import Foundation
import SPPCore

// MARK: - Build Diagnostics Collector

/// Accumulates parsed diagnostics across a build, then resolves them to
/// per-file diagnostic groups for `FileDiagnosticsStore`.
///
/// Parsing (`DiagnosticsParser`) and path resolution (`DiagnosticPathResolver`)
/// are pure and live in SPPCore; this type is the stateful build-pipeline glue
/// that AppEnvironment feeds output lines to.
///
/// Not thread-safe by design: it is only ever touched from `AppEnvironment`'s
/// `@MainActor` build loop, where output events are consumed serially.
final class BuildDiagnosticsCollector {

    private var parsed: [ParsedDiagnostic] = []

    func reset() { parsed.removeAll(keepingCapacity: true) }

    /// Feeds one raw output line; ignored unless it parses as a diagnostic.
    func ingest(_ line: String) {
        if let p = DiagnosticsParser.parse(line: line) {
            parsed.append(p)
        }
    }

    /// Groups accumulated diagnostics by file id using `resolve`, de-duplicating
    /// identical diagnostics (Theos frequently re-emits the same error while
    /// compiling multiple slices/arches).
    func grouped(resolve: (String) -> UUID?) -> [UUID: [Diagnostic]] {
        var out: [UUID: [Diagnostic]] = [:]
        var seen: Set<String> = []   // "<fileID>#<diagnostic.id>"
        for item in parsed {
            guard let fileID = resolve(item.path) else { continue }
            let key = "\(fileID.uuidString)#\(item.diagnostic.id)"
            guard seen.insert(key).inserted else { continue }
            out[fileID, default: []].append(item.diagnostic)
        }
        return out
    }
}
