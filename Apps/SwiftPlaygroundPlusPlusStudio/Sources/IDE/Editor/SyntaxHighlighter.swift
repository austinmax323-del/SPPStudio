import AppKit
import SPPCore

// MARK: - Syntax Highlighter

final class SyntaxHighlighter {

    private static let tabParagraphStyle: NSParagraphStyle = {
        let font   = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
        let spaceW = (" " as NSString).size(withAttributes: [.font: font]).width
        let style  = NSMutableParagraphStyle()
        style.defaultTabInterval = spaceW * 4
        style.tabStops           = []
        return style
    }()

    static func apply(to storage: NSTextStorage, contentType: SPPFile.FileContentType) {
        let source = storage.string
        storage.beginEditing()

        let full = NSRange(location: 0, length: storage.length)
        storage.addAttribute(.font,            value: Palette.font,  range: full)
        storage.addAttribute(.foregroundColor, value: Palette.plain, range: full)
        storage.addAttribute(.paragraphStyle,  value: tabParagraphStyle, range: full)

        switch contentType {
        case .swift, .orionSwift:  Lang.swift(storage, source)
        case .objc, .objcHeader:   Lang.objc(storage, source)
        case .logosXM:             Lang.logos(storage, source)
        case .makefile:            Lang.makefile(storage, source)
        case .plist:               Lang.plist(storage, source)
        default: break
        }

        storage.endEditing()
    }

    // MARK: - Color Palette

    enum Palette {
        static let font         = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
        static let plain        = NSColor(white: 0.82, alpha: 1)
        static let keyword      = NSColor(red: 0.83, green: 0.52, blue: 0.88, alpha: 1)
        static let type         = NSColor(red: 0.44, green: 0.78, blue: 0.96, alpha: 1)
        static let string       = NSColor(red: 0.90, green: 0.62, blue: 0.44, alpha: 1)
        static let comment      = NSColor(red: 0.44, green: 0.56, blue: 0.44, alpha: 1)
        static let number       = NSColor(red: 0.78, green: 0.88, blue: 0.56, alpha: 1)
        static let preprocessor = NSColor(red: 0.92, green: 0.78, blue: 0.46, alpha: 1)
        static let logos        = NSColor(red: 0.72, green: 0.52, blue: 1.00, alpha: 1)
        static let makeVar      = NSColor(red: 0.68, green: 0.88, blue: 0.76, alpha: 1)
        static let xmlTag       = NSColor(red: 0.58, green: 0.76, blue: 0.92, alpha: 1)
    }

    // MARK: - Languages

    private enum Lang {

        // MARK: Swift

        static let swiftKeywords: [String] = [
            "as", "associatedtype", "break", "case", "catch", "class", "continue",
            "default", "defer", "deinit", "do", "else", "enum", "extension",
            "fallthrough", "false", "fileprivate", "for", "func", "guard", "if",
            "import", "in", "init", "inout", "internal", "is", "let", "nil",
            "open", "operator", "override", "package", "private", "protocol",
            "public", "repeat", "rethrows", "return", "self", "Self", "static",
            "struct", "subscript", "super", "switch", "throw", "throws", "true",
            "try", "typealias", "var", "where", "while",
            "async", "await", "actor", "nonisolated", "isolated", "some", "any",
            "consuming", "borrowing",
        ]

        static let swiftAttr: [String] = [
            "@MainActor", "@globalActor", "@Published", "@State", "@Binding",
            "@StateObject", "@ObservedObject", "@EnvironmentObject", "@Environment",
            "@Observable", "@objc", "@objcMembers", "@available", "@discardableResult",
            "@escaping", "@autoclosure", "@frozen", "@inline", "@nonobjc",
            "@NSManaged", "@propertyWrapper", "@resultBuilder", "@Sendable",
            "@preconcurrency", "@unchecked",
        ]

        static func swift(_ s: NSTextStorage, _ src: String) {
            re("/\\*[\\s\\S]*?\\*/",                     Palette.comment,      s, src)
            re("//[^\n]*",                               Palette.comment,      s, src)
            re("\"\"\"[\\s\\S]*?\"\"\"",                 Palette.string,       s, src)
            re("\"(?:[^\"\\\\]|\\\\.)*\"",               Palette.string,       s, src)
            words(swiftKeywords,                          Palette.keyword,      s, src)
            exact(swiftAttr,                              Palette.keyword,      s, src)
            re("\\b[A-Z][A-Za-z0-9_]*\\b",              Palette.type,         s, src)
            re("\\b\\d+[_0-9]*(?:\\.\\d+)?(?:[eE][+-]?\\d+)?[fFdD]?\\b|0x[0-9A-Fa-f_]+", Palette.number, s, src)
        }

        // MARK: ObjC

        static let objcKeywords: [String] = [
            "nil", "YES", "NO", "NULL", "self", "super",
            "void", "int", "long", "short", "char", "float", "double", "BOOL", "id", "SEL", "IMP", "Class",
            "if", "else", "for", "while", "do", "switch", "case", "break", "default",
            "return", "continue", "typedef", "struct", "enum",
            "static", "extern", "const", "unsigned", "signed", "inline",
        ]

        static let objcAt: [String] = [
            "@interface", "@implementation", "@end", "@property", "@synthesize",
            "@dynamic", "@protocol", "@optional", "@required", "@class",
            "@selector", "@encode", "@throw", "@try", "@catch", "@finally",
            "@autoreleasepool", "@import",
        ]

        static func objc(_ s: NSTextStorage, _ src: String) {
            re("/\\*[\\s\\S]*?\\*/",                                   Palette.comment,      s, src)
            re("//[^\n]*",                                             Palette.comment,      s, src)
            re("#\\s*(?:import|include|define|undef|pragma|ifdef|ifndef|if|elif|else|endif)[^\n]*",
                                                                        Palette.preprocessor, s, src, [.anchorsMatchLines])
            re("@\"(?:[^\"\\\\]|\\\\.)*\"",                            Palette.string,       s, src)
            re("\"(?:[^\"\\\\]|\\\\.)*\"",                             Palette.string,       s, src)
            words(objcKeywords,                                         Palette.keyword,      s, src)
            exact(objcAt,                                               Palette.keyword,      s, src)
            re("\\b[A-Z][A-Za-z0-9_]*\\b",                            Palette.type,         s, src)
            re("\\b\\d+[_0-9]*(?:\\.\\d+)?[fFlLuU]*\\b",             Palette.number,       s, src)
        }

        // MARK: Logos

        static let logosDirectives: [String] = [
            "%hook", "%end", "%orig", "%new", "%group", "%init", "%ctor", "%dtor",
            "%subclass", "%property", "%log", "%c", "%hookf", "%config",
        ]

        static func logos(_ s: NSTextStorage, _ src: String) {
            objc(s, src)
            for d in logosDirectives {
                re(NSRegularExpression.escapedPattern(for: d) + "\\b", Palette.logos, s, src)
            }
        }

        // MARK: Makefile

        static func makefile(_ s: NSTextStorage, _ src: String) {
            re("^#[^\n]*",                                 Palette.comment,      s, src, [.anchorsMatchLines])
            re("^[A-Za-z_][A-Za-z0-9_]*\\s*[:?!+]?=",   Palette.makeVar,      s, src, [.anchorsMatchLines])
            re("\\$\\([A-Za-z0-9_]+\\)",                  Palette.type,         s, src)
            re("^include\\b[^\n]*",                        Palette.keyword,      s, src, [.anchorsMatchLines])
            re("^[A-Za-z0-9_.%-]+:\\s",                   Palette.preprocessor, s, src, [.anchorsMatchLines])
            re("\"[^\"]*\"",                               Palette.string,       s, src)
        }

        // MARK: Plist

        static func plist(_ s: NSTextStorage, _ src: String) {
            re("<!--[\\s\\S]*?-->",     Palette.comment,      s, src)
            re("<!DOCTYPE[^>]*>",       Palette.preprocessor, s, src)
            re("</?[a-zA-Z][^>]*>",     Palette.xmlTag,       s, src)
            re("\"[^\"<>]*\"",          Palette.string,       s, src)
        }

        // MARK: Primitives

        private static func re(
            _ pattern: String, _ color: NSColor,
            _ storage: NSTextStorage, _ source: String,
            _ opts: NSRegularExpression.Options = []
        ) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: opts) else { return }
            let ns = source as NSString
            regex.enumerateMatches(in: source, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
                guard let r = m?.range else { return }
                storage.addAttribute(.foregroundColor, value: color, range: r)
            }
        }

        private static func words(_ list: [String], _ color: NSColor, _ storage: NSTextStorage, _ source: String) {
            for w in list {
                re("\\b\(NSRegularExpression.escapedPattern(for: w))\\b", color, storage, source)
            }
        }

        private static func exact(_ list: [String], _ color: NSColor, _ storage: NSTextStorage, _ source: String) {
            for w in list {
                re(NSRegularExpression.escapedPattern(for: w) + "(?=\\b|\\s|$)", color, storage, source)
            }
        }
    }
}
