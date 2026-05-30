import Foundation

// MARK: - ParsedHook

/// The result of parsing a single hook declaration from source text.
public struct ParsedHook: Codable, Sendable {
    /// The node representing the hook itself.
    public var node: HookNode
    /// Edges linking this node to other nodes inferred during parsing.
    public var edges: [HookEdge]

    public init(node: HookNode, edges: [HookEdge] = []) {
        self.node = node
        self.edges = edges
    }
}

// MARK: - HookParser Protocol

/// A type that can parse hook declarations from source text.
///
/// Implementations are expected to be stateless (or actor-isolated); the
/// protocol itself is `Sendable` so parsers can be stored in the actor-isolated
/// `HookParserRegistry` without data-race issues.
public protocol HookParser: Sendable {
    /// File extensions this parser handles (without the leading dot, e.g. `["xm"]`).
    var supportedFileExtensions: [String] { get }

    /// Parse all hook declarations found in `source`.
    ///
    /// - Parameters:
    ///   - source: Full UTF-8 source text of the file.
    ///   - fileID: The `SPPFile.id` of the originating file; embedded in every node.
    /// - Returns: One `ParsedHook` per discovered hook declaration.
    /// - Throws: `HookParseError` on unrecoverable parsing failures.
    func parse(source: String, fileID: UUID) throws -> [ParsedHook]
}

// MARK: - HookParseError

/// Errors thrown by `HookParser` implementations.
public enum HookParseError: LocalizedError, Sendable {
    /// A required regular expression pattern could not be compiled.
    case regexCompilationFailed(pattern: String, reason: String)
    /// The source text is not valid for this parser.
    case invalidSource(String)

    public var errorDescription: String? {
        switch self {
        case .regexCompilationFailed(let pattern, let reason):
            return "Failed to compile regex '\(pattern)': \(reason)"
        case .invalidSource(let detail):
            return "Invalid source: \(detail)"
        }
    }
}

// MARK: - LogosHookParser

/// Parses Logos `.xm` source files and produces `HookNode` values for each
/// discovered hook declaration.
///
/// ## Logos Syntax Recognised
///
/// | Pattern | Produces |
/// |---------|----------|
/// | `%hook ClassName` | `.classHook` node |
/// | `- (ReturnType)selectorName` inside a `%hook` block | `.methodHook` node |
/// | `+ (ReturnType)selectorName` inside a `%hook` block | `.methodHook` node (class method) |
/// | `%new` before a method declaration | `.methodHook` node with metadata `"new": "true"` |
/// | `%ctor` | `.lifecycleHook` node |
/// | `%dtor` | `.lifecycleHook` node |
/// | `%subclass ClassName` | `.classHook` node with metadata `"subclass": "true"` |
///
/// The parser is intentionally permissive: malformed lines are skipped rather
/// than throwing, so partial results are always returned.
public final class LogosHookParser: HookParser {

    // MARK: HookParser Conformance

    public let supportedFileExtensions: [String] = ["xm"]

    public init() {}

    // MARK: Parsing Entry Point

    public func parse(source: String, fileID: UUID) throws -> [ParsedHook] {
        let compiled = CompiledPatterns.shared

        var results: [ParsedHook] = []

        // We parse in two phases:
        //   1. Find all %hook / %subclass / %ctor / %dtor blocks and their line ranges.
        //   2. Within each %hook block find method declarations.

        let lines = source.components(separatedBy: .newlines)

        // Phase 1: Identify top-level Logos directives and their line positions.
        var classHookByStartLine: [Int: ClassHookContext] = [:]
        var lifecycleNodes: [(node: HookNode, line: Int)] = []

        for (lineIndex, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let oneBasedLine = lineIndex + 1

            // %hook ClassName  /  %subclass ClassName
            if let (className, isSubclass) = parseClassDirective(trimmed, patterns: compiled) {
                let node = HookNode(
                    kind: .classHook,
                    label: className,
                    signature: MethodSignature(
                        className: className,
                        selectorName: className,
                        isClassMethod: false,
                        returnType: "void",
                        argumentTypes: []
                    ),
                    sourceFileID: fileID,
                    sourceLine: oneBasedLine,
                    metadata: isSubclass ? ["subclass": "true"] : [:]
                )
                classHookByStartLine[lineIndex] = ClassHookContext(
                    className: className,
                    node: node,
                    startLine: lineIndex
                )
                continue
            }

            // %ctor  /  %dtor
            if let lifecycleNode = parseLifecycleDirective(trimmed, fileID: fileID, line: oneBasedLine) {
                lifecycleNodes.append((node: lifecycleNode, line: lineIndex))
                continue
            }
        }

        // Phase 2: For each class-hook block, collect method nodes within it.
        // Sort contexts by start line so we can find the matching %end.
        let sortedContexts = classHookByStartLine.values.sorted { $0.startLine < $1.startLine }

        for context in sortedContexts {
            // Add the class-hook node itself.
            results.append(ParsedHook(node: context.node))

            // Find the end of this block (%end or next %hook / EOF).
            let blockLines = extractBlockLines(
                lines: lines,
                startLine: context.startLine + 1, // lines inside the block
                patterns: compiled
            )

            // Parse method declarations inside this block.
            var nextLineIsNew = false
            for (offset, bodyLine) in blockLines.enumerated() {
                let trimmed = bodyLine.trimmingCharacters(in: .whitespaces)
                let absoluteLine = context.startLine + 1 + offset + 1 // 1-based

                if trimmed == "%new" || trimmed.hasPrefix("%new(") {
                    nextLineIsNew = true
                    continue
                }

                if let sig = parseMethodDeclaration(trimmed, className: context.className, patterns: compiled) {
                    var meta: [String: String] = [:]
                    if nextLineIsNew { meta["new"] = "true" }
                    let methodNode = HookNode(
                        kind: .methodHook,
                        label: sig.displayName,
                        signature: sig,
                        sourceFileID: fileID,
                        sourceLine: absoluteLine,
                        metadata: meta,
                        groupID: context.node.id
                    )
                    // Add an edge: classHook activates methodHook
                    let activationEdge = HookEdge(
                        sourceID: context.node.id,
                        targetID: methodNode.id,
                        kind: .activates
                    )
                    results.append(ParsedHook(node: methodNode, edges: [activationEdge]))
                    nextLineIsNew = false
                } else {
                    // Non-method line resets the %new flag.
                    if !trimmed.isEmpty { nextLineIsNew = false }
                }
            }
        }

        // Add lifecycle nodes.
        for entry in lifecycleNodes {
            results.append(ParsedHook(node: entry.node))
        }

        return results
    }

    // MARK: Private Parsing Helpers

    /// Returns `(className, isSubclass)` if the line is a `%hook` or `%subclass` directive.
    private func parseClassDirective(
        _ line: String,
        patterns: CompiledPatterns
    ) -> (className: String, isSubclass: Bool)? {
        let nsLine = line as NSString
        let fullRange = NSRange(location: 0, length: nsLine.length)

        // %hook / %subclass
        for (regex, isSubclass) in [(patterns.hookDirective, false), (patterns.subclassDirective, true)] {
            if let match = regex.firstMatch(in: line, options: [], range: fullRange) {
                if match.numberOfRanges > 1 {
                    let nameRange = match.range(at: 1)
                    if nameRange.location != NSNotFound,
                       let swiftRange = Range(nameRange, in: line) {
                        return (String(line[swiftRange]).trimmingCharacters(in: .whitespaces), isSubclass)
                    }
                }
            }
        }
        return nil
    }

    /// Returns a `HookNode` if the line is a `%ctor` or `%dtor` directive.
    private func parseLifecycleDirective(
        _ line: String,
        fileID: UUID,
        line lineNumber: Int
    ) -> HookNode? {
        if line.hasPrefix("%ctor") {
            return HookNode(
                kind: .lifecycleHook,
                label: "%ctor",
                sourceFileID: fileID,
                sourceLine: lineNumber,
                metadata: ["lifecycleType": "constructor"]
            )
        }
        if line.hasPrefix("%dtor") {
            return HookNode(
                kind: .lifecycleHook,
                label: "%dtor",
                sourceFileID: fileID,
                sourceLine: lineNumber,
                metadata: ["lifecycleType": "destructor"]
            )
        }
        return nil
    }

    /// Returns the raw source lines that belong to a `%hook` block body,
    /// stopping at `%end` or the start of the next top-level Logos directive.
    private func extractBlockLines(
        lines: [String],
        startLine: Int,
        patterns: CompiledPatterns
    ) -> [String] {
        var result: [String] = []
        for i in startLine ..< lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed == "%end" { break }
            // Stop at any new top-level directive (%hook, %subclass, %ctor, %dtor).
            if patterns.topLevelDirective.firstMatch(
                in: trimmed,
                options: [],
                range: NSRange(location: 0, length: (trimmed as NSString).length)
            ) != nil { break }
            result.append(lines[i])
        }
        return result
    }

    /// Parses an Objective-C method declaration line and returns a `MethodSignature`,
    /// or `nil` if the line does not match.
    ///
    /// Handles the forms:
    /// ```
    /// - (ReturnType)selectorPart
    /// - (ReturnType)selectorPart:(ArgType)argName ...
    /// + (ReturnType)selectorPart
    /// ```
    private func parseMethodDeclaration(
        _ line: String,
        className: String,
        patterns: CompiledPatterns
    ) -> MethodSignature? {
        let nsLine = line as NSString
        let fullRange = NSRange(location: 0, length: nsLine.length)

        guard let match = patterns.methodDeclaration.firstMatch(in: line, options: [], range: fullRange),
              match.numberOfRanges > 3 else { return nil }

        // Group 1: +/-
        let prefixRange = match.range(at: 1)
        guard prefixRange.location != NSNotFound,
              let swiftPrefixRange = Range(prefixRange, in: line) else { return nil }
        let isClassMethod = line[swiftPrefixRange] == "+"

        // Group 2: return type
        let returnTypeRange = match.range(at: 2)
        let returnType: String
        if returnTypeRange.location != NSNotFound,
           let swiftReturnRange = Range(returnTypeRange, in: line) {
            returnType = String(line[swiftReturnRange]).trimmingCharacters(in: .whitespaces)
        } else {
            returnType = "void"
        }

        // Group 3: remainder of the declaration after "(ReturnType)"
        let remainderRange = match.range(at: 3)
        guard remainderRange.location != NSNotFound,
              let swiftRemainderRange = Range(remainderRange, in: line) else { return nil }
        let remainder = String(line[swiftRemainderRange])

        // Build the selector and argument types from the remainder.
        let (selectorName, argumentTypes) = parseSelectorAndArguments(remainder, patterns: patterns)
        guard !selectorName.isEmpty else { return nil }

        return MethodSignature(
            className: className,
            selectorName: selectorName,
            isClassMethod: isClassMethod,
            returnType: returnType,
            argumentTypes: argumentTypes
        )
    }

    /// Extracts the full selector name and argument types from the part of a
    /// method declaration that follows the return type.
    ///
    /// Examples:
    /// - `"viewDidLoad {"` → `("viewDidLoad", [])`
    /// - `"setFrame:(CGRect)frame {"` → `("setFrame:", ["CGRect"])`
    /// - `"setOrigin:(CGPoint)pt size:(CGSize)sz {"` → `("setOrigin:size:", ["CGPoint","CGSize"])`
    private func parseSelectorAndArguments(
        _ remainder: String,
        patterns: CompiledPatterns
    ) -> (selector: String, argTypes: [String]) {
        let nsRemainder = remainder as NSString

        var selectorParts: [String] = []
        var argTypes: [String] = []
        var searchStart = 0

        // Iteratively match selector-part:(ArgType)argName segments.
        while searchStart < nsRemainder.length {
            let searchRange = NSRange(location: searchStart, length: nsRemainder.length - searchStart)
            guard let segMatch = patterns.selectorSegment.firstMatch(
                in: remainder, options: [], range: searchRange
            ) else { break }

            // Group 1: selector keyword (including the colon when present)
            if segMatch.numberOfRanges > 1 {
                let kwRange = segMatch.range(at: 1)
                if kwRange.location != NSNotFound,
                   let swiftKWRange = Range(kwRange, in: remainder) {
                    selectorParts.append(String(remainder[swiftKWRange]))
                }
            }

            // Group 2: argument type (only present when a colon follows the keyword)
            if segMatch.numberOfRanges > 2 {
                let argTypeRange = segMatch.range(at: 2)
                if argTypeRange.location != NSNotFound,
                   let swiftArgTypeRange = Range(argTypeRange, in: remainder) {
                    argTypes.append(String(remainder[swiftArgTypeRange]).trimmingCharacters(in: .whitespaces))
                }
            }

            let nextStart = segMatch.range.location + segMatch.range.length
            if nextStart <= searchStart { break } // Prevent infinite loop.
            searchStart = nextStart
        }

        if selectorParts.isEmpty {
            // Fallback: treat everything up to a space / '{' as a plain selector.
            let plain = remainder
                .components(separatedBy: CharacterSet(charactersIn: " {"))
                .first ?? ""
            return (plain.trimmingCharacters(in: .whitespaces), [])
        }

        return (selectorParts.joined(), argTypes)
    }

    // MARK: - ClassHookContext

    private struct ClassHookContext {
        let className: String
        let node: HookNode
        let startLine: Int
    }

    // MARK: - CompiledPatterns

    /// Lazily compiled, shared `NSRegularExpression` instances.
    ///
    /// Thread-safety is guaranteed by the `nonisolated(unsafe)` singleton pattern
    /// with a lock-free once initialiser on Swift 5.9+.
    private final class CompiledPatterns: @unchecked Sendable {
        // %hook ClassName  or  %hook ClassName : SuperClass
        let hookDirective: NSRegularExpression
        // %subclass ClassName : SuperClass
        let subclassDirective: NSRegularExpression
        // Any top-level Logos directive: %hook, %subclass, %ctor, %dtor, %end, %group
        let topLevelDirective: NSRegularExpression
        // Method declaration: +/- (ReturnType)rest
        let methodDeclaration: NSRegularExpression
        // One selector segment inside a method declaration
        let selectorSegment: NSRegularExpression

        init() throws {
            // %hook ClassName[optional inheritance / protocols]
            let hookPattern = #"^%hook\s+([A-Za-z_]\w*(?:\s*:\s*[A-Za-z_]\w*)?(?:\s*<[^>]*>)?)"#
            do {
                hookDirective = try NSRegularExpression(pattern: hookPattern, options: [])
            } catch {
                throw HookParseError.regexCompilationFailed(pattern: hookPattern, reason: error.localizedDescription)
            }

            let subclassPattern = #"^%subclass\s+([A-Za-z_]\w*(?:\s*:\s*[A-Za-z_]\w*)?(?:\s*<[^>]*>)?)"#
            do {
                subclassDirective = try NSRegularExpression(pattern: subclassPattern, options: [])
            } catch {
                throw HookParseError.regexCompilationFailed(pattern: subclassPattern, reason: error.localizedDescription)
            }

            let topLevelPattern = #"^%(hook|subclass|ctor|dtor|end|group|ungrouped|config|init|log|c|orig)\b"#
            do {
                topLevelDirective = try NSRegularExpression(pattern: topLevelPattern, options: [])
            } catch {
                throw HookParseError.regexCompilationFailed(pattern: topLevelPattern, reason: error.localizedDescription)
            }

            // Captures: (1) +/-, (2) return type, (3) remainder after closing paren
            let methodPattern = #"^([+\-])\s*\(\s*([^)]*?)\s*\)\s*(.+)"#
            do {
                methodDeclaration = try NSRegularExpression(pattern: methodPattern, options: [])
            } catch {
                throw HookParseError.regexCompilationFailed(pattern: methodPattern, reason: error.localizedDescription)
            }

            // Matches one selector keyword (with optional argument).
            // Group 1: selectorKeyword:  or  plainKeyword (no args)
            // Group 2: argument type inside parens (only when colon present)
            let segmentPattern = #"([A-Za-z_]\w*:)\s*\(\s*([^)]*?)\s*\)\s*[A-Za-z_]\w*\s*|([A-Za-z_]\w*)"#
            do {
                selectorSegment = try NSRegularExpression(pattern: segmentPattern, options: [])
            } catch {
                throw HookParseError.regexCompilationFailed(pattern: segmentPattern, reason: error.localizedDescription)
            }
        }

        // MARK: Singleton

        static let shared: CompiledPatterns = {
            // Force-try is intentional: the patterns above are compile-time constants
            // and have been validated; a failure here is a programming error.
            // swiftlint:disable:next force_try
            return try! CompiledPatterns()
        }()
    }
}

// MARK: - HookParserRegistry

/// An actor-isolated registry that maps file extensions to `HookParser` implementations.
///
/// Usage:
/// ```swift
/// let registry = HookParserRegistry()
/// await registry.register(LogosHookParser())
/// let hooks = try await registry.parse(source: source, fileExtension: "xm", fileID: id)
/// ```
public actor HookParserRegistry {

    // MARK: Storage

    /// Parsers keyed by the file extension they handle (lowercase, without the dot).
    private var parsers: [String: any HookParser] = [:]

    // MARK: Initializer

    public init() {
        // Register the built-in Logos parser by default so callers get out-of-the-box
        // support for `.xm` files without explicit registration.
        let logos = LogosHookParser()
        for ext in logos.supportedFileExtensions {
            parsers[ext.lowercased()] = logos
        }
    }

    // MARK: Registration

    /// Registers `parser` for every file extension it declares.
    ///
    /// If a parser is already registered for a given extension it is replaced.
    public func register(_ parser: any HookParser) {
        for ext in parser.supportedFileExtensions {
            parsers[ext.lowercased()] = parser
        }
    }

    // MARK: Lookup

    /// Returns the parser registered for `ext`, or `nil` if none is registered.
    ///
    /// - Parameter ext: File extension without the leading dot (case-insensitive).
    public func parser(for ext: String) -> (any HookParser)? {
        parsers[ext.lowercased()]
    }

    // MARK: Parse

    /// Parses `source` using the parser registered for `fileExtension`.
    ///
    /// - Parameters:
    ///   - source: Full source text of the file.
    ///   - fileExtension: File extension without the leading dot (case-insensitive).
    ///   - fileID: The `SPPFile.id` of the originating file.
    /// - Returns: All `ParsedHook` values discovered in `source`.
    /// - Throws: `HookParseError.invalidSource` when no parser handles `fileExtension`,
    ///           or whatever error the matched parser throws.
    public func parse(source: String, fileExtension: String, fileID: UUID) throws -> [ParsedHook] {
        let key = fileExtension.lowercased()
        guard let parser = parsers[key] else {
            throw HookParseError.invalidSource(
                "No parser registered for '.\(fileExtension)' files."
            )
        }
        return try parser.parse(source: source, fileID: fileID)
    }
}
