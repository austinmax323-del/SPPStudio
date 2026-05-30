import AppKit
import Foundation
import SPPCore

// MARK: - Runtime Invariant Inspector

@MainActor
enum RuntimeInvariantInspector {
    private final class WeakEditorRef {
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?
        let tabID: UUID
        let fileID: UUID
        let contentType: SPPFile.FileContentType

        init(tabID: UUID, fileID: UUID, contentType: SPPFile.FileContentType, textView: NSTextView, scrollView: NSScrollView) {
            self.tabID = tabID
            self.fileID = fileID
            self.contentType = contentType
            self.textView = textView
            self.scrollView = scrollView
        }
    }

    private struct IdentitySnapshot {
        let tabID: UUID
        let fileID: UUID
        let textViewID: String
        let layoutManagerID: String
        let textStorageID: String
        let undoManagerID: String
        let selection: NSRange
        let isVisible: Bool
    }

    private static var editors: [UUID: WeakEditorRef] = [:]
    private static var activeTabID: UUID?
    private static var activeFileID: UUID?
    private static var activeSelection = NSRange(location: 0, length: 0)
    private static var priorIdentitySnapshots: [UUID: IdentitySnapshot] = [:]
    private static var priorActiveTabID: UUID?
    private static var priorActiveFileID: UUID?
    private static var priorResponderTextViewID = "none"
    private static var registrationWarnings: [String] = []

    static var dumpURL: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base
            .appendingPathComponent("SPPStudio", isDirectory: true)
            .appendingPathComponent("runtime-invariants", isDirectory: true)
            .appendingPathComponent("latest.txt")
    }

    static func register(tabID: UUID, fileID: UUID, contentType: SPPFile.FileContentType, textView: NSTextView, scrollView: NSScrollView) {
        if let existing = editors[tabID], existing.textView != nil, existing.textView !== textView {
            registrationWarnings.append("NSTextView replacement registered for live tab \(tabID.uuidString)")
        }
        editors[tabID] = WeakEditorRef(
            tabID: tabID,
            fileID: fileID,
            contentType: contentType,
            textView: textView,
            scrollView: scrollView
        )
    }

    static func unregister(tabID: UUID) {
        editors.removeValue(forKey: tabID)
        if activeTabID == tabID {
            activeTabID = nil
            activeFileID = nil
        }
    }

    static func updateActive(tabID: UUID, fileID: UUID, selection: NSRange) {
        activeTabID = tabID
        activeFileID = fileID
        activeSelection = selection
    }

    static func recordSelection(tabID: UUID, fileID: UUID, selection: NSRange) {
        guard activeTabID == tabID else { return }
        activeFileID = fileID
        activeSelection = selection
    }

    @discardableResult
    static func writeDump(reason: String) -> URL? {
        do {
            let url = dumpURL
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try dump(reason: reason).write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            NSLog("SPPStudio invariant dump failed: \(error.localizedDescription)")
            return nil
        }
    }

    static func dump(reason: String) -> String {
        let staleRegistrationCount = editors.values.filter { $0.textView == nil || $0.scrollView == nil }.count
        pruneReleasedEditors()

        let activeClaims = editors.values.filter { ref in
            guard ref.tabID == activeTabID else { return false }
            return ref.textView != nil && ref.scrollView?.isHidden == false
        }
        let visibleEditors = editors.values.filter { ref in
            ref.textView != nil && ref.scrollView?.isHidden == false
        }
        let firstResponder = NSApp.keyWindow?.firstResponder
        let firstResponderTextView = firstResponder as? NSTextView
        let responderMatchesActive = firstResponderTextView.map { tv in
            activeClaims.contains { $0.textView === tv }
        }
        let currentSnapshots = makeIdentitySnapshots()
        let continuityWarnings = continuityWarnings(
            currentSnapshots: currentSnapshots,
            activeClaims: activeClaims,
            responderTextViewID: identity(firstResponderTextView),
            responderMatchesActive: responderMatchesActive,
            staleRegistrationCount: staleRegistrationCount
        )

        var lines: [String] = []
        lines.append("SPPStudio Runtime Health Snapshot")
        lines.append("reason: \(reason)")
        lines.append("generated: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("mode: manual")
        lines.append("scope: pooled-editor/responder/diagnostics/completion/runtime-routing/layout")
        lines.append("")
        lines.append("editor-pool")
        lines.append("- pooled-editor-count: \(editors.count)")
        lines.append("- visible-editor-count: \(visibleEditors.count)")
        lines.append("- active-claim-count: \(activeClaims.count)")
        lines.append("- active-tab-id: \(activeTabID?.uuidString ?? "none")")
        lines.append("- active-file-id: \(activeFileID?.uuidString ?? "none")")
        lines.append("- active-selection: \(activeSelection.location):\(activeSelection.length)")
        lines.append("")
        lines.append("lifecycle-transition")
        lines.append("- prior-active-tab-id: \(priorActiveTabID?.uuidString ?? "none")")
        lines.append("- current-active-tab-id: \(activeTabID?.uuidString ?? "none")")
        lines.append("- prior-active-file-id: \(priorActiveFileID?.uuidString ?? "none")")
        lines.append("- current-active-file-id: \(activeFileID?.uuidString ?? "none")")
        lines.append("- prior-responder-text-view-identity: \(priorResponderTextViewID)")
        lines.append("- current-responder-text-view-identity: \(identity(firstResponderTextView))")
        lines.append("")
        lines.append("active-text-view")
        if let active = activeClaims.first, let tv = active.textView {
            let layoutManager = tv.layoutManager
            let textStorage = tv.textStorage
            lines.append("- identity: \(identity(tv))")
            lines.append("- file-id: \(active.fileID.uuidString)")
            lines.append("- content-type: \(active.contentType.rawValue)")
            lines.append("- text-length: \(tv.string.utf16.count)")
            lines.append("- selected-range: \(tv.selectedRange().location):\(tv.selectedRange().length)")
            lines.append("- undo-manager: \(identity(tv.undoManager))")
            lines.append("- layout-manager: \(identity(layoutManager))")
            lines.append("- text-storage: \(identity(textStorage))")
            lines.append("- layout-manager-text-storage-matches: \(relationshipMatches(layoutManager: layoutManager, textStorage: textStorage))")
            lines.append("- text-storage-layout-manager-count: \(textStorage?.layoutManagers.count ?? 0)")
        } else {
            lines.append("- none")
        }
        lines.append("")
        lines.append("responder-chain")
        lines.append("- first-responder: \(firstResponder.map { String(describing: type(of: $0)) } ?? "none")")
        lines.append("- first-responder-text-view-identity: \(identity(firstResponderTextView))")
        lines.append("- responder-matches-active-editor: \(responderMatchesActive.map(String.init(describing:)) ?? "unknown")")
        lines.append("")
        lines.append("ownership-graph")
        lines.append("- BuildService -> structured build/runtime events only")
        lines.append("- FileDiagnosticsStore -> canonical diagnostics ownership")
        lines.append("- EditorCoordinator -> active editor/file routing")
        lines.append("- pooled NSTextViews -> rendering + interaction only")
        lines.append("- NSLayoutManager/TextStorage -> temporary decoration layer only")
        lines.append("- SwiftUI -> shell/container layer only")
        lines.append("")
        lines.append("diagnostics")
        lines.append("- snapshot-owner: FileDiagnosticsStore (expected)")
        lines.append("- editor-owned-diagnostics-state: not present in current editor inspector")
        lines.append("- rendering-owner: NSLayoutManager temporary attributes/layout drawing (expected)")
        lines.append("")
        lines.append("completion")
        lines.append("- context-owner: active document identity + selection range (expected)")
        lines.append("- active-context-file-id: \(activeFileID?.uuidString ?? "none")")
        lines.append("- active-context-selection: \(activeSelection.location):\(activeSelection.length)")
        lines.append("")
        lines.append("runtime-routing")
        lines.append("- route-target-owner: file/document identity (expected)")
        lines.append("- current-target-file-id: \(activeFileID?.uuidString ?? "none")")
        lines.append("")
        lines.append("layout-relationships")
        appendLayoutRelationships(to: &lines, visibleEditors: visibleEditors)
        lines.append("")
        lines.append("identity-continuity")
        appendIdentityContinuity(to: &lines, currentSnapshots: currentSnapshots)
        lines.append("")
        lines.append("continuity-summary")
        lines.append("- prior-tracked-tabs: \(priorIdentitySnapshots.count)")
        lines.append("- current-tracked-tabs: \(currentSnapshots.count)")
        lines.append("- continuity-warning-count: \(continuityWarnings.count)")
        lines.append("- observability-mode: externalized/manual/advisory")
        lines.append("")
        lines.append("view-hierarchy")
        visibleEditors.forEach { ref in
            lines.append("- visible tab=\(ref.tabID.uuidString) file=\(ref.fileID.uuidString) textView=\(identity(ref.textView)) scrollHidden=\(ref.scrollView?.isHidden.description ?? "released")")
        }
        if visibleEditors.isEmpty {
            lines.append("- none")
        }
        lines.append("")
        lines.append("active-drift-indicators")
        appendWarnings(continuityWarnings, to: &lines)
        lines.append("")
        lines.append("drift-warnings")
        appendDriftWarnings(
            to: &lines,
            visibleEditors: visibleEditors,
            activeClaims: activeClaims,
            responderMatchesActive: responderMatchesActive,
            continuityWarnings: continuityWarnings
        )

        priorIdentitySnapshots = currentSnapshots
        priorActiveTabID = activeTabID
        priorActiveFileID = activeFileID
        priorResponderTextViewID = identity(firstResponderTextView)
        registrationWarnings.removeAll(keepingCapacity: true)

        return lines.joined(separator: "\n") + "\n"
    }

    private static func appendDriftWarnings(
        to lines: inout [String],
        visibleEditors: [WeakEditorRef],
        activeClaims: [WeakEditorRef],
        responderMatchesActive: Bool?,
        continuityWarnings: [String]
    ) {
        var warnings = continuityWarnings
        if visibleEditors.count > 1 {
            warnings.append("multiple visible pooled editors; check active/hidden routing")
        }
        if activeClaims.count > 1 {
            warnings.append("multiple active editor ownership claims")
        }
        if activeTabID != nil && activeClaims.isEmpty {
            warnings.append("active tab has no visible NSTextView claim")
        }
        if responderMatchesActive == false {
            warnings.append("first responder does not match active editor")
        }
        if let activeTabID, editors[activeTabID]?.fileID != activeFileID {
            warnings.append("active tab/file identity mismatch")
        }
        for ref in visibleEditors {
            guard let textView = ref.textView else { continue }
            let layoutManager = textView.layoutManager
            let textStorage = textView.textStorage
            if relationshipMatches(layoutManager: layoutManager, textStorage: textStorage) == false {
                warnings.append("layout manager/text storage relationship drift for tab \(ref.tabID.uuidString)")
            }
            if textStorage?.layoutManagers.count != 1 {
                warnings.append("unexpected text storage layout manager count for tab \(ref.tabID.uuidString)")
            }
        }
        if warnings.isEmpty {
            lines.append("- none")
        } else {
            appendWarnings(warnings, to: &lines)
        }
    }

    private static func makeIdentitySnapshots() -> [UUID: IdentitySnapshot] {
        var snapshots: [UUID: IdentitySnapshot] = [:]
        editors.forEach { tabID, ref in
            guard let textView = ref.textView else { return }
            snapshots[tabID] = IdentitySnapshot(
                tabID: tabID,
                fileID: ref.fileID,
                textViewID: identity(textView),
                layoutManagerID: identity(textView.layoutManager),
                textStorageID: identity(textView.textStorage),
                undoManagerID: identity(textView.undoManager),
                selection: textView.selectedRange(),
                isVisible: ref.scrollView?.isHidden == false
            )
        }
        return snapshots
    }

    private static func appendIdentityContinuity(to lines: inout [String], currentSnapshots: [UUID: IdentitySnapshot]) {
        guard !currentSnapshots.isEmpty else {
            lines.append("- none")
            return
        }
        currentSnapshots.values.sorted { $0.tabID.uuidString < $1.tabID.uuidString }.forEach { snapshot in
            let prior = priorIdentitySnapshots[snapshot.tabID]
            lines.append("- tab=\(snapshot.tabID.uuidString) file=\(snapshot.fileID.uuidString) visible=\(snapshot.isVisible) textView=\(continuityStatus(prior?.textViewID, snapshot.textViewID)) layoutManager=\(continuityStatus(prior?.layoutManagerID, snapshot.layoutManagerID)) textStorage=\(continuityStatus(prior?.textStorageID, snapshot.textStorageID)) undoManager=\(continuityStatus(prior?.undoManagerID, snapshot.undoManagerID)) selection=\(selectionStatus(prior?.selection, snapshot.selection))")
        }
    }

    private static func continuityWarnings(
        currentSnapshots: [UUID: IdentitySnapshot],
        activeClaims: [WeakEditorRef],
        responderTextViewID: String,
        responderMatchesActive: Bool?,
        staleRegistrationCount: Int
    ) -> [String] {
        var warnings: [String] = registrationWarnings
        if staleRegistrationCount > 0 {
            warnings.append("stale editor registrations pruned: \(staleRegistrationCount)")
        }

        currentSnapshots.forEach { tabID, snapshot in
            guard let prior = priorIdentitySnapshots[tabID] else { return }
            if prior.fileID != snapshot.fileID {
                warnings.append("tab/file identity continuity drift for tab \(tabID.uuidString)")
            }
            if prior.textViewID != snapshot.textViewID {
                warnings.append("unexpected NSTextView replacement for tab \(tabID.uuidString)")
            }
            if prior.layoutManagerID != snapshot.layoutManagerID {
                warnings.append("layoutManager replacement suspicion for tab \(tabID.uuidString)")
            }
            if prior.textStorageID != snapshot.textStorageID {
                warnings.append("textStorage replacement suspicion for tab \(tabID.uuidString)")
            }
            if prior.undoManagerID != snapshot.undoManagerID {
                warnings.append("UndoManager identity reset suspicion for tab \(tabID.uuidString)")
            }
        }

        if priorActiveTabID != activeTabID, activeTabID != nil, responderMatchesActive == false {
            warnings.append("responder discontinuity after active tab change")
        }
        if activeClaims.count > 1 {
            warnings.append("duplicate active editor ownership during continuity check")
        }
        if responderTextViewID != "none",
           priorResponderTextViewID != "none",
           priorActiveTabID == activeTabID,
           responderTextViewID != priorResponderTextViewID {
            warnings.append("responder identity changed without active tab change")
        }

        return warnings
    }

    private static func pruneReleasedEditors() {
        editors = editors.filter { _, ref in
            ref.textView != nil && ref.scrollView != nil
        }
    }

    private static func appendWarnings(_ warnings: [String], to lines: inout [String]) {
        if warnings.isEmpty {
            lines.append("- none")
        } else {
            warnings.forEach { lines.append("- \($0)") }
        }
    }

    private static func appendLayoutRelationships(to lines: inout [String], visibleEditors: [WeakEditorRef]) {
        guard !visibleEditors.isEmpty else {
            lines.append("- none")
            return
        }
        visibleEditors.forEach { ref in
            guard let textView = ref.textView else {
                lines.append("- tab=\(ref.tabID.uuidString) textView=released")
                return
            }
            let layoutManager = textView.layoutManager
            let textStorage = textView.textStorage
            lines.append(
                "- tab=\(ref.tabID.uuidString) file=\(ref.fileID.uuidString) textView=\(identity(textView)) layoutManager=\(identity(layoutManager)) textStorage=\(identity(textStorage)) relationshipOK=\(relationshipMatches(layoutManager: layoutManager, textStorage: textStorage))"
            )
        }
    }

    private static func identity(_ object: AnyObject?) -> String {
        object.map { String(describing: ObjectIdentifier($0)) } ?? "none"
    }

    private static func continuityStatus(_ prior: String?, _ current: String) -> String {
        guard let prior else { return "new(\(current))" }
        return prior == current ? "stable(\(current))" : "changed(\(prior)->\(current))"
    }

    private static func selectionStatus(_ prior: NSRange?, _ current: NSRange) -> String {
        let currentValue = "\(current.location):\(current.length)"
        guard let prior else { return "new(\(currentValue))" }
        let priorValue = "\(prior.location):\(prior.length)"
        return prior == current ? "stable(\(currentValue))" : "changed(\(priorValue)->\(currentValue))"
    }

    private static func relationshipMatches(layoutManager: NSLayoutManager?, textStorage: NSTextStorage?) -> Bool {
        guard let layoutManager, let textStorage else { return false }
        return layoutManager.textStorage === textStorage
            && textStorage.layoutManagers.contains { $0 === layoutManager }
    }
}
