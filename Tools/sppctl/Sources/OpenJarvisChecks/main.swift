import Foundation
import OpenJarvisCore

enum OpenJarvisCheckError: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message): return message
        }
    }
}

@main
struct OpenJarvisChecksMain {
    static func main() {
        do {
            try runAllChecks()
            print("OpenJarvis checks passed")
        } catch {
            fputs("OpenJarvis checks failed: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func runAllChecks() throws {
        try testTaskCreateShowListAndPrefixLookup()
        try testRetrievalScopeBehavior()
        try testPacketGenerationAndWritebackFlow()
        try testDatabaseReopenPersistence()
        try testInvalidTransitionsAreRejected()
        try testFailedTransitionAuditEventsAreRecorded()
        try testTaskHistoryListsRecentEvents()
        try testReadOnlyStatusFields()
        try testReadOnlyStatusDoesNotCreateMissingDatabase()
    }

    private static func testTaskCreateShowListAndPrefixLookup() throws {
        let dbURL = tempSQLiteURL()
        defer { try? FileManager.default.removeItem(at: dbURL) }

        let store = try OpenJarvisStore(databaseURL: dbURL)
        let taskA = try store.createTask(from: makeDraft(request: "Review architecture docs", worker: .claude, memory: ["architecture"], allowed: ["SPPStudioDocs/20_ArchitectureMemory/"]))
        let taskB = try store.createTask(from: makeDraft(request: "Inspect runtime regression", worker: .codex, memory: ["runtime"], allowed: ["SPPStudioDocs/50_RuntimeOps/"]))

        let exact = try store.fetchTask(id: taskA.id)
        try require(exact?.id == taskA.id, "Expected exact task fetch to work")
        try require(exact?.rawRequest == taskA.rawRequest, "Expected raw request to persist")

        let prefix = try store.resolveTaskID(String(taskA.id.prefix(8)))
        try require(prefix == taskA.id, "Expected unique task prefix to resolve")

        let summaries = try store.listTasks()
        try require(summaries.count == 2, "Expected two tasks in task list")
        try require(summaries.contains(where: { $0.id == taskA.id && $0.objective == taskA.interpretedObjective }), "Expected task A to appear in list")
        try require(summaries.contains(where: { $0.id == taskB.id && $0.worker == .codex }), "Expected task B to appear in list")
    }

    private static func testRetrievalScopeBehavior() throws {
        let vault = tempVaultRoot()
        defer { try? FileManager.default.removeItem(at: vault.deletingLastPathComponent()) }

        let docs = vault
        try FileManager.default.createDirectory(at: docs.appendingPathComponent("20_ArchitectureMemory"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: docs.appendingPathComponent("50_RuntimeOps"), withIntermediateDirectories: true)

        try """
        # Architecture Memory Index
        Tags: #domain/architecture #type/hub
        """.write(to: docs.appendingPathComponent("20_ArchitectureMemory/Architecture Memory Index.md"), atomically: true, encoding: .utf8)

        try """
        # Runtime Issues
        Tags: #domain/runtime #type/hub
        """.write(to: docs.appendingPathComponent("50_RuntimeOps/Runtime Issues.md"), atomically: true, encoding: .utf8)

        let engine = OpenJarvisRetrievalEngine(vaultRoot: docs)
        let architectureHits = try engine.retrieve(OpenJarvisRetrievalRequest(query: "architecture", scopes: [.architecture], limit: 10))
        let runtimeHits = try engine.retrieve(OpenJarvisRetrievalRequest(query: "runtime", scopes: [.runtime], limit: 10))

        try require(architectureHits.contains(where: { $0.path.contains("20_ArchitectureMemory/Architecture Memory Index.md") }), "Expected architecture hub in architecture scope")
        try require(!architectureHits.contains(where: { $0.path.contains("50_RuntimeOps/Runtime Issues.md") }), "Expected runtime notes to stay out of architecture scope")
        try require(runtimeHits.contains(where: { $0.path.contains("50_RuntimeOps/Runtime Issues.md") }), "Expected runtime hub in runtime scope")
        try require(!runtimeHits.contains(where: { $0.path.contains("20_ArchitectureMemory/Architecture Memory Index.md") }), "Expected architecture notes to stay out of runtime scope")
    }

    private static func testPacketGenerationAndWritebackFlow() throws {
        let dbURL = tempSQLiteURL()
        defer { try? FileManager.default.removeItem(at: dbURL) }

        let vault = tempVaultRoot()
        defer { try? FileManager.default.removeItem(at: vault.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: vault.appendingPathComponent("20_ArchitectureMemory"), withIntermediateDirectories: true)
        try """
        # Architecture Memory Index
        Tags: #domain/architecture #type/hub
        Purpose: cluster architecture memory.
        """.write(to: vault.appendingPathComponent("20_ArchitectureMemory/Architecture Memory Index.md"), atomically: true, encoding: .utf8)

        let store = try OpenJarvisStore(databaseURL: dbURL)
        let task = try store.createTask(from: makeDraft(
            request: "Update architecture memory docs",
            worker: .codex,
            memory: ["architecture"],
            allowed: ["SPPStudioDocs/20_ArchitectureMemory/"],
            vaultRoot: vault.path
        ))

        let hits = try store.retrieveContext(for: task.id, query: "architecture memory", scopeHint: [.architecture], limit: 5)
        try require(!hits.isEmpty, "Expected task retrieval to find architecture notes")

        let packet = try store.generatePacket(for: task.id, role: .codex, limit: 3, scopeHint: [.architecture])
        try require(packet.role == .codex, "Expected Codex packet role")
        try require(packet.retrievedContext.count == hits.count, "Expected packet to include retrieved hits")
        try require(packet.markdown.contains("Validation requirements"), "Expected validation section in packet")

        let completed = try store.completeTask(id: task.id, note: "finished")
        try require(completed.stage == .completed, "Expected completion to move stage to completed")
        try require(completed.executionState == .done, "Expected completion to set execution state done")

        let written = try store.writebackTask(id: task.id, note: "memory digest written")
        try require(written.stage == .writeback, "Expected writeback to move stage to writeback")
        try require(written.writebackState == .written, "Expected writeback state to be written")

        let reopened = try OpenJarvisStore(databaseURL: dbURL)
        let persisted = try reopened.fetchTask(id: task.id)
        try require(persisted?.stage == .writeback, "Expected writeback stage to persist after reopen")
        try require(persisted?.writebackState == .written, "Expected writeback state to persist after reopen")
        try require(persisted?.packetText?.contains("OpenJarvis Worker Packet") == true, "Expected packet text to persist after reopen")
    }

    private static func testDatabaseReopenPersistence() throws {
        let dbURL = tempSQLiteURL()
        defer { try? FileManager.default.removeItem(at: dbURL) }

        let store = try OpenJarvisStore(databaseURL: dbURL)
        let task = try store.createTask(from: makeDraft(request: "Document the task lifecycle", worker: .claude, memory: ["lifecycle"]))
        let reopened = try OpenJarvisStore(databaseURL: dbURL)
        let fetched = try reopened.fetchTask(id: task.id)
        try require(fetched?.id == task.id, "Expected task to survive database reopen")
        try require(fetched?.stage == .intake, "Expected initial stage to survive reopen")
    }

    private static func testInvalidTransitionsAreRejected() throws {
        let dbURL = tempSQLiteURL()
        defer { try? FileManager.default.removeItem(at: dbURL) }

        let store = try OpenJarvisStore(databaseURL: dbURL)
        let task = try store.createTask(from: makeDraft(request: "Fix runtime bug", worker: .claude, memory: ["runtime"], allowed: ["SPPStudioDocs/50_RuntimeOps/"]))

        assertThrows({ _ = try store.completeTask(id: task.id) }, message: "Expected completion to fail before packet generation")
        _ = try store.generatePacket(for: task.id, role: .claude, limit: 2, scopeHint: [.runtime])
        _ = try store.completeTask(id: task.id)
        assertThrows({ _ = try store.retrieveContext(for: task.id, query: "runtime bug") }, message: "Expected retrieval to fail after completion")
        let firstWriteback = try store.writebackTask(id: task.id)
        try require(firstWriteback.stage == .writeback, "Expected writeback to move task into writeback stage")
        assertThrows({ _ = try store.writebackTask(id: task.id) }, message: "Expected repeated writeback to fail")
    }

    private static func testFailedTransitionAuditEventsAreRecorded() throws {
        let dbURL = tempSQLiteURL()
        defer { try? FileManager.default.removeItem(at: dbURL) }

        let store = try OpenJarvisStore(databaseURL: dbURL)
        let task = try store.createTask(from: makeDraft(request: "Check blocked transition audit", worker: .claude, memory: ["architecture"]))

        assertThrows({ _ = try store.writebackTask(id: task.id) }, message: "Expected writeback to fail before completion")
        let blockedTransitions = try store.listTaskEvents(taskID: task.id, type: "task.transition_blocked")
        try require(!blockedTransitions.isEmpty, "Expected blocked transition to be recorded")

        _ = try store.generatePacket(for: task.id, role: .claude)
        _ = try store.completeTask(id: task.id)
        assertThrows({ _ = try store.generatePacket(for: task.id, role: .claude) }, message: "Expected packet generation to fail after completion")
        let blockedPackets = try store.listTaskEvents(taskID: task.id, type: "task.packet_blocked")
        try require(!blockedPackets.isEmpty, "Expected blocked packet generation to be recorded")
    }

    private static func testTaskHistoryListsRecentEvents() throws {
        let dbURL = tempSQLiteURL()
        defer { try? FileManager.default.removeItem(at: dbURL) }

        let store = try OpenJarvisStore(databaseURL: dbURL)
        let task = try store.createTask(from: makeDraft(request: "Inspect CLI audit history", worker: .codex, memory: ["audit"]))
        _ = try store.generatePacket(for: task.id, role: .codex)

        let events = try store.listTaskEvents(taskID: task.id, limit: 10)
        try require(events.contains(where: { $0.type == "task.created" }), "Expected history to include task creation")
        try require(events.contains(where: { $0.type == "task.packet_generated" }), "Expected history to include packet generation")

        let packetEvents = try store.listTaskEvents(taskID: task.id, type: "task.packet_generated", limit: 10)
        try require(packetEvents.count == 1, "Expected event type filter to isolate packet generation")
    }

    private static func testReadOnlyStatusFields() throws {
        let dbURL = tempSQLiteURL()
        defer { try? FileManager.default.removeItem(at: dbURL) }

        let store = try OpenJarvisStore(databaseURL: dbURL)
        try require(store.databaseURL == dbURL, "Expected store to expose the selected database URL")
        let emptyCount = try store.countTasks()
        try require(emptyCount == 0, "Expected empty status count before task creation")

        let task = try store.createTask(from: makeDraft(request: "Inspect operator status", worker: .codex, memory: ["status"]))
        let summaries = try store.listTasks()
        let createdCount = try store.countTasks()
        try require(createdCount == 1, "Expected status count after task creation")
        try require(summaries.first?.id == task.id, "Expected latest task summary to match created task")

        let snapshot = try OpenJarvisStatusReader.read(databaseURL: dbURL)
        try require(snapshot.databaseExists, "Expected status reader to detect an existing database")
        try require(snapshot.taskCount == 1, "Expected status reader to report task count")
        try require(snapshot.latestTask?.id == task.id, "Expected status reader to report latest task")
    }

    private static func testReadOnlyStatusDoesNotCreateMissingDatabase() throws {
        let dbURL = tempSQLiteURL()
        defer { try? FileManager.default.removeItem(at: dbURL) }
        try? FileManager.default.removeItem(at: dbURL)

        let snapshot = try OpenJarvisStatusReader.read(databaseURL: dbURL)
        try require(!snapshot.databaseExists, "Expected missing database to stay missing")
        try require(snapshot.taskCount == nil, "Expected missing database task count to be unavailable")
        try require(!FileManager.default.fileExists(atPath: dbURL.path), "Expected status reader not to create the database")
    }

    private static func makeDraft(
        request: String,
        worker: OpenJarvisWorkerKind,
        memory: [String],
        allowed: [String] = [],
        forbidden: [String] = [],
        vaultRoot: String? = nil
    ) -> OpenJarvisTaskDraft {
        OpenJarvisTaskDraft(
            rawRequest: request,
            interpretedObjective: request,
            projectContext: "SPPStudio",
            trustZone: "safe",
            riskLevel: "medium",
            allowedFiles: allowed,
            forbiddenFiles: forbidden,
            targetWorker: worker,
            neededMemory: memory,
            checkpointRequired: true,
            validationRequired: true,
            memoryWritebackRequired: true,
            nextAction: "retrieve context",
            vaultRoot: vaultRoot
        )
    }

    private static func tempSQLiteURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("openjarvis-\(UUID().uuidString).sqlite")
    }

    private static func tempVaultRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("openjarvis-vault-\(UUID().uuidString)/SPPStudioDocs", isDirectory: true)
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() {
            throw OpenJarvisCheckError.failed(message)
        }
    }

    private static func assertThrows(_ body: () throws -> Void, message: String) {
        do {
            try body()
            fatalError(message)
        } catch {
        }
    }
}
