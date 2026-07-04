import Foundation

/// A single compiler / analyzer diagnostic anchored to a source location.
///
/// A `Diagnostic` is a value type owned by *file / document identity*, never by
/// an editor instance. This is what lets the same diagnostic be routed to
/// whichever editor happens to be showing the file, and rendered as advisory,
/// non-destructive layout state (temporary layout-manager attributes) rather
/// than baked into text storage.
///
/// Identity is derived from the diagnostic's content, so re-parsing the same
/// build output yields equal (and therefore de-duplicated) diagnostics.
public struct Diagnostic: Identifiable, Hashable, Sendable {

    /// Ordered by increasing severity so `max()` yields the most severe
    /// diagnostic on a line (used to pick a single gutter marker colour).
    public enum Severity: Int, Comparable, Sendable, CaseIterable {
        case note = 0
        case warning = 1
        case error = 2

        public static func < (lhs: Severity, rhs: Severity) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    /// 1-based line number as reported by the compiler.
    public let line: Int
    /// 1-based column, or `nil` when the compiler did not report one.
    public let column: Int?
    public let severity: Severity
    public let message: String
    /// Emitting tool (e.g. `"clang"`, `"swiftc"`). Advisory only.
    public let source: String?

    /// Content-derived stable identity — two diagnostics describing the same
    /// problem at the same location compare equal across builds.
    public var id: String { "\(line):\(column ?? 0):\(severity.rawValue):\(message)" }

    public init(
        line: Int,
        column: Int? = nil,
        severity: Severity,
        message: String,
        source: String? = nil
    ) {
        self.line = max(1, line)
        self.column = column.map { max(1, $0) }
        self.severity = severity
        self.message = message
        self.source = source
    }
}
