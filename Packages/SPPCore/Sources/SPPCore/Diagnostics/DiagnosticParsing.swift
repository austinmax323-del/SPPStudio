import Foundation

// MARK: - Parsed Diagnostic

/// A diagnostic parsed from one line of build output, still carrying the raw
/// compiler-reported path. Path → file-identity resolution happens later, once
/// the project file table is available (`DiagnosticPathResolver`).
public struct ParsedDiagnostic: Equatable, Sendable {
    public let path: String
    public let diagnostic: Diagnostic

    public init(path: String, diagnostic: Diagnostic) {
        self.path = path
        self.diagnostic = diagnostic
    }
}

// MARK: - Diagnostics Parser

/// Parses a single line of compiler output into a `ParsedDiagnostic`.
///
/// Handles the standard clang / swiftc / gcc format, which is shared by every
/// tool Theos drives:
///
///     /abs/or/rel/path/File.ext:LINE[:COL]: (error|warning|note): message
///
/// Lines without that shape (progress, linker summaries, `In file included
/// from …`) return `nil`.
public enum DiagnosticsParser {

    /// `path : line [: col] : severity : message`
    private static let regex = try! NSRegularExpression(
        pattern: #"^\s*(.+?):(\d+):(?:(\d+):)?\s*(error|warning|note):\s*(.*\S)\s*$"#,
        options: []
    )

    /// Strips ANSI SGR escape sequences (colour codes) so coloured compiler
    /// output still parses. `\x1B` is the ESC byte in ICU regex syntax (ICU has
    /// no `\u{…}` form — that spelling would fail to compile at runtime).
    private static let ansi = try! NSRegularExpression(
        pattern: #"\x1B\[[0-9;]*[A-Za-z]"#,
        options: []
    )

    public static func parse(line rawLine: String) -> ParsedDiagnostic? {
        let line = stripANSI(rawLine)
        let range = NSRange(line.startIndex..., in: line)
        guard let match = regex.firstMatch(in: line, options: [], range: range),
              match.numberOfRanges == 6,
              let pathR = Range(match.range(at: 1), in: line),
              let lineR = Range(match.range(at: 2), in: line),
              let sevR  = Range(match.range(at: 4), in: line),
              let msgR  = Range(match.range(at: 5), in: line),
              let lineNo = Int(line[lineR])
        else { return nil }

        let column: Int? = {
            let r = match.range(at: 3)
            guard r.location != NSNotFound, let cr = Range(r, in: line) else { return nil }
            return Int(line[cr])
        }()

        guard let severity = severity(from: String(line[sevR])) else { return nil }

        let path = String(line[pathR]).trimmingCharacters(in: .whitespaces)
        // Reject obviously non-path captures (e.g. a stray "note:" mid-sentence).
        guard !path.isEmpty, path.contains("/") || path.contains(".") else { return nil }

        return ParsedDiagnostic(
            path: path,
            diagnostic: Diagnostic(
                line: lineNo,
                column: column,
                severity: severity,
                message: String(line[msgR]),
                source: nil
            )
        )
    }

    private static func severity(from token: String) -> Diagnostic.Severity? {
        switch token {
        case "error":   return .error
        case "warning": return .warning
        case "note":    return .note
        default:        return nil
        }
    }

    private static func stripANSI(_ s: String) -> String {
        let range = NSRange(s.startIndex..., in: s)
        return ansi.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: "")
    }
}

// MARK: - Diagnostic Path Resolver

/// Resolves a compiler-reported path to the id of a project file.
public enum DiagnosticPathResolver {

    /// Compiler paths arrive in several shapes (absolute, project-relative,
    /// `./`-prefixed, or occasionally bare filenames). Resolution tries, in
    /// order: exact standardized absolute match, project-relative suffix match,
    /// then a unique-basename fallback. `leaves` should be the project's
    /// non-directory files.
    public static func resolveFileID(
        forCompilerPath path: String,
        leaves: [SPPFile],
        projectURL: URL
    ) -> UUID? {
        let target = standardizedAbsolutePath(path, projectURL: projectURL)

        // 1. Exact absolute match.
        for file in leaves {
            let abs = projectURL.appendingPathComponent(file.relativePath)
                .standardizedFileURL.path
            if abs == target { return file.id }
        }

        // 2. Project-relative suffix match (handles relative or partial paths).
        let normalizedTarget = "/" + target.drop(while: { $0 == "/" })
        for file in leaves {
            let rel = file.relativePath
            if normalizedTarget.hasSuffix("/" + rel) || target == rel {
                return file.id
            }
        }

        // 3. Unique-basename fallback.
        let base = (path as NSString).lastPathComponent
        let matches = leaves.filter { $0.name == base }
        return matches.count == 1 ? matches[0].id : nil
    }

    private static func standardizedAbsolutePath(_ path: String, projectURL: URL) -> String {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path).standardizedFileURL.path
        }
        return projectURL.appendingPathComponent(path).standardizedFileURL.path
    }
}
