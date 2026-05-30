// SourceIndexKit.swift
// SPPSourceIndexKit
//
// macOS only. Depends on SPPCore, SPPHookKit.
// NOTE: This package must NOT be imported by EditorService.
//       It is consumed exclusively by IndexService.

import Foundation

// MARK: - SymbolKind

public enum SymbolKind: String, Codable, Hashable, Sendable, CaseIterable {
    case hookClass
    case hookMethod
    case swiftClass
    case swiftStruct
    case swiftEnum
    case swiftFunction
    case objcClass
    case objcMethod
    case typedef
    case macro
}

// MARK: - SymbolIndexEntry

public struct SymbolIndexEntry: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var qualifiedName: String
    public var kind: SymbolKind
    public var fileID: UUID
    public var line: Int
    public var column: Int
    public var projectID: UUID
    public var documentation: String?

    public init(
        id: UUID = UUID(),
        name: String,
        qualifiedName: String,
        kind: SymbolKind,
        fileID: UUID,
        line: Int,
        column: Int,
        projectID: UUID,
        documentation: String? = nil
    ) {
        self.id = id
        self.name = name
        self.qualifiedName = qualifiedName
        self.kind = kind
        self.fileID = fileID
        self.line = line
        self.column = column
        self.projectID = projectID
        self.documentation = documentation
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: SymbolIndexEntry, rhs: SymbolIndexEntry) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - HookRefKind

public enum HookRefKind: String, Codable, Hashable, Sendable {
    case definition
    case invocation
    case override
}

// MARK: - HookReference

public struct HookReference: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var hookNodeID: UUID
    public var targetSymbolName: String
    public var fileID: UUID
    public var line: Int
    public var kind: HookRefKind

    public init(
        id: UUID = UUID(),
        hookNodeID: UUID,
        targetSymbolName: String,
        fileID: UUID,
        line: Int,
        kind: HookRefKind
    ) {
        self.id = id
        self.hookNodeID = hookNodeID
        self.targetSymbolName = targetSymbolName
        self.fileID = fileID
        self.line = line
        self.kind = kind
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: HookReference, rhs: HookReference) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - IndexQuery

public struct IndexQuery: Sendable {
    public var text: String
    public var kinds: Set<SymbolKind>
    public var projectID: UUID?
    public var fileID: UUID?
    public var maxResults: Int
    public var caseSensitive: Bool

    public init(
        text: String,
        kinds: Set<SymbolKind> = [],
        projectID: UUID? = nil,
        fileID: UUID? = nil,
        maxResults: Int = 100,
        caseSensitive: Bool = false
    ) {
        self.text = text
        self.kinds = kinds
        self.projectID = projectID
        self.fileID = fileID
        self.maxResults = maxResults
        self.caseSensitive = caseSensitive
    }
}

// MARK: - IndexQueryResult

public struct IndexQueryResult: Sendable {
    public var entries: [SymbolIndexEntry]
    public var hookReferences: [HookReference]
    public var totalCount: Int
    public var truncated: Bool

    public init(
        entries: [SymbolIndexEntry],
        hookReferences: [HookReference],
        totalCount: Int,
        truncated: Bool
    ) {
        self.entries = entries
        self.hookReferences = hookReferences
        self.totalCount = totalCount
        self.truncated = truncated
    }

    public static let empty = IndexQueryResult(
        entries: [],
        hookReferences: [],
        totalCount: 0,
        truncated: false
    )
}

// MARK: - SourceIndex

public actor SourceIndex {

    private var entries: [UUID: SymbolIndexEntry] = [:]
    private var hookRefs: [UUID: HookReference] = [:]
    /// fileID → entry IDs
    private var fileIndex: [UUID: [UUID]] = [:]
    /// projectID → entry IDs
    private var projectIndex: [UUID: [UUID]] = [:]

    public init() {}

    // MARK: Indexing

    public func index(_ entry: SymbolIndexEntry) {
        entries[entry.id] = entry

        fileIndex[entry.fileID, default: []].removeAll { $0 == entry.id }
        fileIndex[entry.fileID, default: []].append(entry.id)

        projectIndex[entry.projectID, default: []].removeAll { $0 == entry.id }
        projectIndex[entry.projectID, default: []].append(entry.id)
    }

    public func indexHookReference(_ ref: HookReference) {
        hookRefs[ref.id] = ref
    }

    public func removeEntries(forFile fileID: UUID) {
        guard let ids = fileIndex[fileID] else { return }
        for id in ids {
            if let entry = entries.removeValue(forKey: id) {
                projectIndex[entry.projectID]?.removeAll { $0 == id }
            }
        }
        fileIndex.removeValue(forKey: fileID)
        // Remove hook refs that belong to this file
        hookRefs = hookRefs.filter { $0.value.fileID != fileID }
    }

    public func removeEntries(forProject projectID: UUID) {
        guard let ids = projectIndex[projectID] else { return }
        for id in ids {
            if let entry = entries.removeValue(forKey: id) {
                fileIndex[entry.fileID]?.removeAll { $0 == id }
            }
        }
        projectIndex.removeValue(forKey: projectID)
    }

    // MARK: Search

    public func search(_ query: IndexQuery) -> IndexQueryResult {
        // Determine candidate entry IDs
        var candidateIDs: [UUID]

        if let fileID = query.fileID {
            candidateIDs = fileIndex[fileID] ?? []
        } else if let projectID = query.projectID {
            candidateIDs = projectIndex[projectID] ?? []
        } else {
            candidateIDs = Array(entries.keys)
        }

        // Collect matching entries
        var matched: [SymbolIndexEntry] = []
        for id in candidateIDs {
            guard let entry = entries[id] else { continue }

            // Filter by kind if specified
            if !query.kinds.isEmpty, !query.kinds.contains(entry.kind) {
                continue
            }

            // Text match
            if !query.text.isEmpty {
                let haystack = query.caseSensitive ? entry.qualifiedName : entry.qualifiedName.lowercased()
                let needle   = query.caseSensitive ? query.text : query.text.lowercased()
                guard haystack.contains(needle) else { continue }
            }

            matched.append(entry)
        }

        // Collect matching hook references for the query text
        var matchedHooks: [HookReference] = []
        if !query.text.isEmpty {
            for ref in hookRefs.values {
                // Honour fileID / projectID scope for hook refs
                if let fileID = query.fileID, ref.fileID != fileID { continue }
                // (hook refs don't carry projectID; project scoping handled at WorkspaceIndex level)

                let haystack = query.caseSensitive ? ref.targetSymbolName : ref.targetSymbolName.lowercased()
                let needle   = query.caseSensitive ? query.text : query.text.lowercased()
                if haystack.contains(needle) {
                    matchedHooks.append(ref)
                }
            }
        }

        let totalCount = matched.count
        let truncated = totalCount > query.maxResults
        let trimmed = truncated ? Array(matched.prefix(query.maxResults)) : matched

        return IndexQueryResult(
            entries: trimmed,
            hookReferences: matchedHooks,
            totalCount: totalCount,
            truncated: truncated
        )
    }

    // MARK: Lookup

    public func hookReferences(for symbolName: String) -> [HookReference] {
        hookRefs.values.filter { $0.targetSymbolName == symbolName }
    }

    public func symbolsInFile(_ fileID: UUID) -> [SymbolIndexEntry] {
        (fileIndex[fileID] ?? []).compactMap { entries[$0] }
    }

    // MARK: Clear

    public func clear() {
        entries.removeAll()
        hookRefs.removeAll()
        fileIndex.removeAll()
        projectIndex.removeAll()
    }
}

// MARK: - WorkspaceIndex

public actor WorkspaceIndex {

    private var perProjectIndices: [UUID: SourceIndex] = [:]

    public init() {}

    // MARK: Project management

    public func index(for projectID: UUID) -> SourceIndex {
        if let existing = perProjectIndices[projectID] {
            return existing
        }
        let newIndex = SourceIndex()
        perProjectIndices[projectID] = newIndex
        return newIndex
    }

    public func removeProject(id: UUID) {
        perProjectIndices.removeValue(forKey: id)
    }

    public func clearAll() {
        perProjectIndices.removeAll()
    }

    // MARK: Search

    public func search(_ query: IndexQuery) async -> IndexQueryResult {
        if let projectID = query.projectID {
            // Delegate directly to that project's index
            guard let projectIndex = perProjectIndices[projectID] else {
                return .empty
            }
            return await projectIndex.search(query)
        }

        // Merge results across all projects up to maxResults
        var allEntries: [SymbolIndexEntry] = []
        var allHookRefs: [HookReference] = []
        var totalCount = 0
        var truncated = false

        for projectIndex in perProjectIndices.values {
            let result = await projectIndex.search(query)
            totalCount += result.totalCount
            allEntries.append(contentsOf: result.entries)
            allHookRefs.append(contentsOf: result.hookReferences)
        }

        if allEntries.count > query.maxResults {
            truncated = true
            allEntries = Array(allEntries.prefix(query.maxResults))
        }

        return IndexQueryResult(
            entries: allEntries,
            hookReferences: allHookRefs,
            totalCount: totalCount,
            truncated: truncated
        )
    }
}

// MARK: - RenameChange

public struct RenameChange: Sendable {
    public var fileID: UUID
    public var line: Int
    public var column: Int
    public var length: Int
    public var replacementText: String

    public init(
        fileID: UUID,
        line: Int,
        column: Int,
        length: Int,
        replacementText: String
    ) {
        self.fileID = fileID
        self.line = line
        self.column = column
        self.length = length
        self.replacementText = replacementText
    }
}

// MARK: - RenameProposal

public struct RenameProposal: Sendable {
    public var originalName: String
    public var newName: String
    public var affectedFiles: [UUID]
    public var changes: [RenameChange]

    public init(
        originalName: String,
        newName: String,
        affectedFiles: [UUID],
        changes: [RenameChange]
    ) {
        self.originalName = originalName
        self.newName = newName
        self.affectedFiles = affectedFiles
        self.changes = changes
    }
}

// MARK: - RenameEngine

public actor RenameEngine {

    public let workspaceIndex: WorkspaceIndex

    public init(workspaceIndex: WorkspaceIndex) {
        self.workspaceIndex = workspaceIndex
    }

    /// Searches the workspace index for all occurrences of `symbolName` (including
    /// hook references), builds a `RenameChange` for each, and returns a
    /// `RenameProposal` ready to be applied.
    public func proposedRename(
        of symbolName: String,
        to newName: String,
        in projectID: UUID
    ) async -> RenameProposal {
        let query = IndexQuery(
            text: symbolName,
            kinds: [],
            projectID: projectID,
            fileID: nil,
            maxResults: Int.max,
            caseSensitive: true
        )

        let result = await workspaceIndex.search(query)

        var changes: [RenameChange] = []

        // Build changes from symbol entries where the name matches exactly
        for entry in result.entries {
            guard entry.name == symbolName || entry.qualifiedName == symbolName ||
                  entry.qualifiedName.hasSuffix(".\(symbolName)") else { continue }

            let change = RenameChange(
                fileID: entry.fileID,
                line: entry.line,
                column: entry.column,
                length: entry.name.utf8.count,
                replacementText: newName
            )
            changes.append(change)
        }

        // Build changes from hook references where the target matches exactly
        for hookRef in result.hookReferences {
            guard hookRef.targetSymbolName == symbolName else { continue }

            // For hook references, column is not stored, use 0 as a sentinel.
            // Consumers may perform a text search within the line to locate the
            // exact column before applying.
            let change = RenameChange(
                fileID: hookRef.fileID,
                line: hookRef.line,
                column: 0,
                length: symbolName.utf8.count,
                replacementText: newName
            )
            changes.append(change)
        }

        // Deduplicate affected file IDs
        let affectedFiles: [UUID] = Array(
            Set(changes.map(\.fileID))
        ).sorted { $0.uuidString < $1.uuidString }

        return RenameProposal(
            originalName: symbolName,
            newName: newName,
            affectedFiles: affectedFiles,
            changes: changes
        )
    }
}
