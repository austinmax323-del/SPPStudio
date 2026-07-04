import Combine
import Foundation
import SPPCore

/// Single source of truth for build / analyzer diagnostics, keyed by file identity.
///
/// **Ownership invariant.** Diagnostics are file / document state, never
/// editor-instance state. The store holds no references to editor views; routing
/// is strictly one-way — `store → file identity → editor`. Editors observe
/// `publisher(for:)` for their own `fileID` and render results as advisory,
/// *temporary* layout attributes (see `CodeEditorView.Coordinator`). Nothing in
/// this file may ever import AppKit or reach back into an editor.
@MainActor
public final class FileDiagnosticsStore: ObservableObject {

    /// Diagnostics grouped by the owning file's id. A file with no diagnostics
    /// has no entry (rather than an empty array) so counts and membership checks
    /// stay simple.
    @Published public private(set) var diagnosticsByFile: [UUID: [Diagnostic]] = [:]

    public init() {}

    // MARK: - Reads

    public func diagnostics(for fileID: UUID) -> [Diagnostic] {
        diagnosticsByFile[fileID] ?? []
    }

    public var isEmpty: Bool { diagnosticsByFile.isEmpty }

    public var totalErrorCount: Int { count(of: .error) }
    public var totalWarningCount: Int { count(of: .warning) }

    private func count(of severity: Diagnostic.Severity) -> Int {
        diagnosticsByFile.values.reduce(0) { total, diags in
            total + diags.lazy.filter { $0.severity == severity }.count
        }
    }

    /// All diagnostics flattened with their owning file id, ordered most-severe
    /// first then by line, for a Problems list. Files are grouped together.
    public var allEntries: [Entry] {
        diagnosticsByFile
            .flatMap { fileID, diags in diags.map { Entry(fileID: fileID, diagnostic: $0) } }
            .sorted { lhs, rhs in
                if lhs.diagnostic.severity != rhs.diagnostic.severity {
                    return lhs.diagnostic.severity > rhs.diagnostic.severity
                }
                if lhs.fileID != rhs.fileID {
                    return lhs.fileID.uuidString < rhs.fileID.uuidString
                }
                return lhs.diagnostic.line < rhs.diagnostic.line
            }
    }

    public struct Entry: Identifiable, Sendable {
        public let fileID: UUID
        public let diagnostic: Diagnostic
        public var id: String { "\(fileID.uuidString)#\(diagnostic.id)" }
    }

    // MARK: - Mutations

    /// Replaces diagnostics for a single file. An empty array removes the entry.
    public func setDiagnostics(_ diagnostics: [Diagnostic], for fileID: UUID) {
        let ordered = diagnostics.sorted(by: Self.ordering)
        if ordered.isEmpty {
            diagnosticsByFile.removeValue(forKey: fileID)
        } else {
            diagnosticsByFile[fileID] = ordered
        }
    }

    /// Atomically replaces the entire diagnostic set. Used after a build so a
    /// single `objectWillChange` fires for the whole update rather than one per
    /// file. Files mapping to empty arrays are dropped.
    public func replaceAll(_ grouped: [UUID: [Diagnostic]]) {
        diagnosticsByFile = grouped
            .filter { !$0.value.isEmpty }
            .mapValues { $0.sorted(by: Self.ordering) }
    }

    /// Clears diagnostics for one file. No-op (no change notification) if the
    /// file had none — this keeps editor edit-invalidation cheap.
    public func clear(fileID: UUID) {
        if diagnosticsByFile[fileID] != nil {
            diagnosticsByFile.removeValue(forKey: fileID)
        }
    }

    public func clearAll() {
        if !diagnosticsByFile.isEmpty { diagnosticsByFile.removeAll() }
    }

    // MARK: - Observation

    /// Per-file publisher for editors to observe their own diagnostics without
    /// waking on unrelated files' changes.
    public func publisher(for fileID: UUID) -> AnyPublisher<[Diagnostic], Never> {
        $diagnosticsByFile
            .map { $0[fileID] ?? [] }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    // MARK: - Ordering

    /// Line ascending, then most-severe first within a line.
    private static func ordering(_ a: Diagnostic, _ b: Diagnostic) -> Bool {
        if a.line != b.line { return a.line < b.line }
        if a.severity != b.severity { return a.severity > b.severity }
        return a.message < b.message
    }
}
