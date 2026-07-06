import Foundation
import SPPCore

// MARK: - Code Completion Provider

/// Supplies completion candidates for the editor's NSTextView-native completion
/// (`complete:`, ⌥⎋ / F5). Candidates are a union of a curated per-language
/// vocabulary and identifiers harvested from the current document, filtered by
/// the partial word the user has typed.
///
/// This is intentionally a plain, pure value-producing type: no editor state, no
/// AppKit. The editor coordinator adapts it to the `NSTextViewDelegate`
/// completion callback.
enum CodeCompletionProvider {

    /// Ordered, de-duplicated completions for `partial`. Empty when nothing
    /// sensible matches (the caller then falls back to the system list).
    static func completions(
        forPartialWord partial: String,
        in text: String,
        contentType: SPPFile.FileContentType
    ) -> [String] {
        guard partial.count >= 1 else { return [] }
        let lowerPartial = partial.lowercased()

        var candidates = Set<String>()
        candidates.formUnion(vocabulary(for: contentType))
        candidates.formUnion(documentIdentifiers(in: text))

        let matches = candidates.filter { word in
            let lower = word.lowercased()
            return lower != lowerPartial && lower.hasPrefix(lowerPartial)
        }

        return matches.sorted { a, b in
            // Case-sensitive prefix matches rank above case-insensitive ones.
            let aExact = a.hasPrefix(partial)
            let bExact = b.hasPrefix(partial)
            if aExact != bExact { return aExact }
            if a.count != b.count { return a.count < b.count }
            return a < b
        }
    }

    // MARK: - Document identifiers

    private static let identifierRegex = try! NSRegularExpression(
        pattern: #"[A-Za-z_][A-Za-z0-9_]{2,}"#
    )

    /// Distinct identifiers (≥ 3 chars) appearing in the document, so completion
    /// learns names the user has already written (types, methods, locals).
    private static func documentIdentifiers(in text: String) -> Set<String> {
        let ns = text as NSString
        var out = Set<String>()
        identifierRegex.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let r = match?.range else { return }
            out.insert(ns.substring(with: r))
        }
        return out
    }

    // MARK: - Per-language vocabulary

    private static func vocabulary(for contentType: SPPFile.FileContentType) -> [String] {
        switch contentType {
        case .swift, .orionSwift:      return swift
        case .objc, .objcHeader:       return objc
        case .logosXM:                 return objc + logos
        case .makefile:                return makefile
        default:                       return []
        }
    }

    private static let swift: [String] = [
        // Keywords
        "func", "let", "var", "if", "else", "guard", "for", "while", "switch",
        "case", "default", "return", "class", "struct", "enum", "protocol",
        "extension", "import", "init", "deinit", "self", "super", "static",
        "public", "private", "internal", "fileprivate", "open", "final", "lazy",
        "weak", "unowned", "override", "throws", "rethrows", "try", "catch",
        "throw", "defer", "do", "where", "as", "is", "nil", "true", "false",
        "async", "await", "actor", "some", "any", "typealias", "associatedtype",
        "subscript", "inout", "mutating", "nonmutating", "convenience",
        "required", "indirect", "repeat", "fallthrough", "break", "continue",
        // Common types
        "String", "Int", "Double", "Float", "Bool", "Character", "Array",
        "Dictionary", "Set", "Optional", "Void", "Any", "AnyObject", "Result",
        "Data", "Date", "URL", "UUID", "NSObject", "NSString", "CGFloat",
        "CGRect", "CGPoint", "CGSize",
    ]

    private static let objc: [String] = [
        // Keywords
        "if", "else", "for", "while", "do", "switch", "case", "default",
        "return", "break", "continue", "typedef", "struct", "enum", "union",
        "static", "extern", "const", "void", "int", "long", "short", "char",
        "float", "double", "unsigned", "signed", "inline", "sizeof", "nil",
        "NULL", "YES", "NO", "self", "super", "id", "BOOL", "SEL", "IMP",
        "Class", "instancetype",
        // @-directives
        "@interface", "@implementation", "@end", "@property", "@synthesize",
        "@dynamic", "@protocol", "@optional", "@required", "@class",
        "@selector", "@encode", "@autoreleasepool", "@import",
        // Common types
        "NSObject", "NSString", "NSArray", "NSDictionary", "NSMutableArray",
        "NSMutableDictionary", "NSNumber", "NSData", "NSError", "NSInteger",
        "NSUInteger", "CGFloat", "CGRect", "CGPoint", "UIView",
        "UIViewController", "UIColor", "UILabel", "UIButton", "UIImage",
    ]

    private static let logos: [String] = [
        "%hook", "%end", "%orig", "%new", "%group", "%init", "%ctor", "%dtor",
        "%subclass", "%property", "%log", "%c", "%hookf", "%config",
    ]

    private static let makefile: [String] = [
        "TARGET", "ARCHS", "THEOS", "THEOS_DEVICE_IP", "THEOS_PACKAGE_SCHEME",
        "INSTALL_TARGET_PROCESSES", "TWEAK_NAME", "SUBPROJECTS", "include",
        "after-install", "before-package",
    ]
}
