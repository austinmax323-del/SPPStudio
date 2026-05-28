import Foundation
import SQLite3

public final class OpenJarvisStore {
    private let database: OpenJarvisSQLiteDatabase
    public let databaseURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(databaseURL: URL? = nil) throws {
        let url = try databaseURL ?? OpenJarvisPaths.databaseURL()
        self.databaseURL = url
        self.database = try OpenJarvisSQLiteDatabase(url: url)
        try createSchema()
    }

    public func createTask(from draft: OpenJarvisTaskDraft) throws -> OpenJarvisTask {
        let task = OpenJarvisTask(
            rawRequest: draft.rawRequest,
            interpretedObjective: draft.interpretedObjective,
            projectContext: draft.projectContext,
            trustZone: draft.trustZone,
            riskLevel: draft.riskLevel,
            allowedFiles: draft.allowedFiles,
            forbiddenFiles: draft.forbiddenFiles,
            targetWorker: draft.targetWorker,
            neededMemory: draft.neededMemory,
            checkpointRequired: draft.checkpointRequired,
            validationRequired: draft.validationRequired,
            memoryWritebackRequired: draft.memoryWritebackRequired,
            nextAction: draft.nextAction,
            vaultRoot: draft.vaultRoot
        )
        try insert(task)
        try recordEvent(taskID: task.id, type: "task.created", payload: [
            "request": task.rawRequest,
            "objective": task.interpretedObjective
        ])
        return task
    }

    public func fetchTask(id: String) throws -> OpenJarvisTask? {
        let decoder = self.decoder
        return try database.queryOne("""
        SELECT id, raw_request, interpreted_objective, project_context, trust_zone, risk_level,
               allowed_files_json, forbidden_files_json, target_worker, needed_memory_json,
               checkpoint_required, validation_required, memory_writeback_required, next_action,
               vault_root, stage, execution_state, completion_state, writeback_state,
               retrieved_context_json, packet_text, created_at, updated_at, completed_at, written_back_at
        FROM tasks WHERE id = ?
        """, bindings: [.text(id)], map: { row in
            try Self.decodeTaskRow(row, decoder: decoder)
        })
    }

    public func resolveTaskID(_ token: String) throws -> String {
        if let task = try fetchTask(id: token) {
            return task.id
        }

        let matches = try database.query("""
        SELECT id FROM tasks
        WHERE id LIKE ?
        ORDER BY updated_at DESC
        LIMIT 2
        """, bindings: [.text("\(token)%")]) { row in
            String(cString: sqlite3_column_text(row, 0))
        }

        switch matches.count {
        case 1:
            return matches[0]
        case 0:
            throw NSError(domain: "OpenJarvisStore", code: 404, userInfo: [NSLocalizedDescriptionKey: "Task '\(token)' not found."])
        default:
            throw NSError(domain: "OpenJarvisStore", code: 409, userInfo: [NSLocalizedDescriptionKey: "Task '\(token)' is ambiguous. Use a longer prefix or the full task ID."])
        }
    }

    public func listTasks(stage: OpenJarvisStage? = nil) throws -> [OpenJarvisTaskSummary] {
        let sql = """
        SELECT id, interpreted_objective, stage, execution_state, completion_state, writeback_state,
               target_worker, updated_at
        FROM tasks
        \(stage == nil ? "" : "WHERE stage = ?")
        ORDER BY updated_at DESC
        """
        return try database.query(sql, bindings: stage.map { [.text($0.rawValue)] } ?? []) { row in
            OpenJarvisTaskSummary(
                id: String(cString: sqlite3_column_text(row, 0)),
                stage: OpenJarvisStage(rawValue: String(cString: sqlite3_column_text(row, 2))) ?? .intake,
                executionState: OpenJarvisExecutionState(rawValue: String(cString: sqlite3_column_text(row, 3))) ?? .pending,
                completionState: OpenJarvisCompletionState(rawValue: String(cString: sqlite3_column_text(row, 4))) ?? .open,
                writebackState: OpenJarvisWritebackState(rawValue: String(cString: sqlite3_column_text(row, 5))) ?? .pending,
                worker: sqlite3_column_type(row, 6) == SQLITE_NULL ? nil : OpenJarvisWorkerKind(rawValue: String(cString: sqlite3_column_text(row, 6))),
                objective: String(cString: sqlite3_column_text(row, 1)),
                updatedAt: String(cString: sqlite3_column_text(row, 7))
            )
        }
    }

    public func countTasks() throws -> Int {
        try database.queryOne("SELECT COUNT(*) FROM tasks") { row in
            Int(sqlite3_column_int64(row, 0))
        } ?? 0
    }

    public func retrieveContext(for taskID: String, query: String, scopeHint: [OpenJarvisRetrievalScope]? = nil, limit: Int = 8) throws -> [OpenJarvisRetrievalHit] {
        guard let task = try fetchTask(id: taskID) else {
            throw NSError(domain: "OpenJarvisStore", code: 404, userInfo: [NSLocalizedDescriptionKey: "Task \(taskID) not found"])
        }
        let vaultRoot = try resolveVaultRoot(task: task)
        let engine = OpenJarvisRetrievalEngine(vaultRoot: vaultRoot)
        let request = OpenJarvisRetrievalRequest(query: query, scopes: scopeHint ?? inferOpenJarvisScopes(from: query), limit: limit)
        let hits = try engine.retrieve(request)
        try saveRetrievedHits(taskID: taskID, query: query, hits: hits, vaultRoot: vaultRoot.path)
        try advance(taskID: taskID, to: .retrieve, executionState: .pending)
        try recordEvent(taskID: taskID, type: "task.retrieved", payload: [
            "query": query,
            "hit_count": "\(hits.count)"
        ])
        return hits
    }

    public func generatePacket(for taskID: String, role: OpenJarvisWorkerKind? = nil, limit: Int = 5, scopeHint: [OpenJarvisRetrievalScope]? = nil) throws -> OpenJarvisWorkerPacket {
        guard let task = try fetchTask(id: taskID) else {
            throw NSError(domain: "OpenJarvisStore", code: 404, userInfo: [NSLocalizedDescriptionKey: "Task \(taskID) not found"])
        }
        guard task.stage != .completed, task.stage != .writeback else {
            try? recordEvent(taskID: taskID, type: "task.packet_blocked", payload: [
                "stage": task.stage.rawValue
            ])
            throw NSError(domain: "OpenJarvisStore", code: 409, userInfo: [NSLocalizedDescriptionKey: "Cannot generate a packet after task completion."])
        }
        let vaultRoot = try resolveVaultRoot(task: task)
        let packet: OpenJarvisWorkerPacket
        if scopeHint == nil, !task.retrievedContext.isEmpty {
            let effectiveRole = role ?? task.targetWorker ?? .codex
            packet = OpenJarvisWorkerPacket(
                taskID: task.id,
                role: effectiveRole,
                task: task.interpretedObjective,
                allowedScope: task.allowedFiles,
                forbiddenScope: task.forbiddenFiles,
                retrievedContext: task.retrievedContext
            )
        } else {
            let engine = OpenJarvisRetrievalEngine(vaultRoot: vaultRoot)
            let assembler = OpenJarvisPacketAssembler(retrievalEngine: engine)
            packet = try assembler.assemble(task: task, role: role, limit: limit, scopeOverride: scopeHint)
        }
        try savePacket(taskID: taskID, packet: packet, vaultRoot: vaultRoot.path)
        if task.stage != .executionReady {
            try advance(taskID: taskID, to: .executionReady, executionState: .ready)
        }
        try recordEvent(taskID: taskID, type: "task.packet_generated", payload: [
            "role": packet.role.rawValue,
            "hit_count": "\(packet.retrievedContext.count)"
        ])
        return packet
    }

    public func completeTask(id: String, note: String? = nil) throws -> OpenJarvisTask {
        try advance(taskID: id, to: .completed, executionState: .done, completionState: .completed)
        try updateCompletionTime(taskID: id)
        try recordEvent(taskID: id, type: "task.completed", payload: [
            "note": note ?? ""
        ])
        guard let task = try fetchTask(id: id) else {
            throw NSError(domain: "OpenJarvisStore", code: 500, userInfo: [NSLocalizedDescriptionKey: "Task \(id) disappeared after completion"])
        }
        return task
    }

    public func writebackTask(id: String, note: String? = nil) throws -> OpenJarvisTask {
        try advance(taskID: id, to: .writeback)
        try updateWritebackTime(taskID: id)
        try recordEvent(taskID: id, type: "task.writeback", payload: [
            "note": note ?? ""
        ])
        guard let task = try fetchTask(id: id) else {
            throw NSError(domain: "OpenJarvisStore", code: 500, userInfo: [NSLocalizedDescriptionKey: "Task \(id) disappeared after writeback"])
        }
        try recordEvent(taskID: id, type: "task.session_closed", payload: [
            "objective": task.interpretedObjective,
            "worker": task.targetWorker?.rawValue ?? "",
            "status": "archived",
            "note": note ?? "",
            "closed_at": task.writtenBackAt ?? now()
        ])
        return task
    }

    public func buildRecoveryContext(for taskID: String) throws -> String {
        guard let task = try fetchTask(id: taskID) else {
            throw NSError(domain: "OpenJarvisStore", code: 404, userInfo: [NSLocalizedDescriptionKey: "Task '\(taskID)' not found."])
        }
        let events = try listTaskEvents(taskID: taskID, limit: 10)
        var lines: [String] = []
        lines.append("# OpenJarvis Recovery Context")
        lines.append("")
        lines.append("Task: \(task.interpretedObjective)")
        lines.append("ID: \(task.id.prefix(8))")
        lines.append("Worker: \(task.targetWorker?.displayName ?? "unassigned")")
        lines.append("Status: \(task.stage.displayLabel)")
        lines.append("Updated: \(relativeAge(from: task.updatedAt))")
        lines.append("")
        lines.append("## Last Packet")
        if let packetText = task.packetText, !packetText.isEmpty {
            lines.append(packetText)
        } else {
            lines.append("(no packet generated)")
        }
        lines.append("")
        lines.append("## Recent Events")
        let recent = Array(events.prefix(5))
        if recent.isEmpty {
            lines.append("(no events)")
        } else {
            for event in recent {
                lines.append("- \(relativeAge(from: event.createdAt))  \(eventLabel(event.type))")
                if let data = event.payloadJSON.data(using: .utf8),
                   let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                    for key in ["note", "query", "objective"] {
                        if let val = dict[key], !val.isEmpty {
                            lines.append("  \(key): \(val)")
                        }
                    }
                }
            }
        }
        let closedNote: String? = events.first(where: { $0.type == "task.session_closed" }).flatMap { event in
            guard let data = event.payloadJSON.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                  let note = dict["note"], !note.isEmpty else { return nil }
            return note
        }
        if let note = closedNote {
            lines.append("")
            lines.append("## Writeback Note")
            lines.append(note)
        }
        return lines.joined(separator: "\n")
    }

    public func buildSessionRecoveryContext(limit: Int = 5) throws -> String {
        let tasks = try listTasks()
        let recent = Array(tasks.prefix(limit))
        var lines: [String] = []
        lines.append("# OpenJarvis Session Recovery")
        lines.append("")
        if recent.isEmpty {
            lines.append("No tasks found. Use: go <request>")
            return lines.joined(separator: "\n")
        }
        lines.append("Recent tasks (newest first):")
        for task in recent {
            let age = relativeAge(from: task.updatedAt)
            let obj = task.objective.count > 60 ? String(task.objective.prefix(57)) + "..." : task.objective
            let worker = task.worker?.displayName ?? "unassigned"
            lines.append("")
            lines.append("## \(task.id.prefix(8))  \(task.stage.displayLabel)  \(age)")
            lines.append("   \(obj)")
            lines.append("   worker: \(worker)")
            let events = try listTaskEvents(taskID: task.id, limit: 5)
            let note: String? = events.first(where: {
                $0.type == "task.session_closed" || $0.type == "task.writeback" || $0.type == "task.completed"
            }).flatMap { event in
                guard let data = event.payloadJSON.data(using: .utf8),
                      let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                      let n = dict["note"], !n.isEmpty else { return nil }
                return n
            }
            if let note { lines.append("   note: \(note)") }
        }
        return lines.joined(separator: "\n")
    }

    public func buildBriefRecoveryContext(for taskID: String) throws -> String {
        guard let task = try fetchTask(id: taskID) else {
            throw NSError(domain: "OpenJarvisStore", code: 404, userInfo: [NSLocalizedDescriptionKey: "Task '\(taskID)' not found."])
        }
        let events = try listTaskEvents(taskID: taskID, limit: 10)
        var lines: [String] = []
        lines.append("# OpenJarvis Recovery (Brief)")
        lines.append("")
        lines.append("Task: \(task.interpretedObjective)")
        lines.append("ID: \(task.id.prefix(8))")
        lines.append("Worker: \(task.targetWorker?.displayName ?? "unassigned")")
        lines.append("Status: \(task.stage.displayLabel)")
        lines.append("Updated: \(relativeAge(from: task.updatedAt))")
        if !task.retrievedContext.isEmpty {
            lines.append("")
            lines.append("## Top Context")
            for hit in task.retrievedContext.prefix(3) {
                lines.append("- [\(hit.score)] \(hit.title) — \(hit.path)")
            }
        }
        lines.append("")
        lines.append("## Recent Events")
        for event in events.prefix(5) {
            lines.append("- \(relativeAge(from: event.createdAt))  \(eventLabel(event.type))")
            if let data = event.payloadJSON.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String],
               let note = dict["note"], !note.isEmpty {
                lines.append("  note: \(note)")
            }
        }
        let closedNote: String? = events.first(where: { $0.type == "task.session_closed" }).flatMap { event in
            guard let data = event.payloadJSON.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                  let note = dict["note"], !note.isEmpty else { return nil }
            return note
        }
        if let note = closedNote {
            lines.append("")
            lines.append("## Note")
            lines.append(note)
        }
        return lines.joined(separator: "\n")
    }

    private func eventLabel(_ type: String) -> String {
        switch type {
        case "task.created": return "created"
        case "task.retrieved": return "context retrieved"
        case "task.packet_generated": return "packet generated"
        case "task.completed": return "completed"
        case "task.writeback": return "writeback"
        case "task.session_closed": return "session closed"
        case "task.transition_blocked": return "transition blocked"
        case "task.packet_blocked": return "packet blocked"
        default: return type
        }
    }

    public func recordEvent(taskID: String?, type: String, payload: [String: String]) throws {
        let payloadData = try JSONSerialization.data(withJSONObject: payload, options: [])
        let payloadString = String(decoding: payloadData, as: UTF8.self)
        try database.execute(
            "INSERT INTO task_events(task_id, event_type, payload_json, created_at) VALUES (?, ?, ?, ?)",
            bindings: [
                taskID.map(OpenJarvisSQLiteValue.text) ?? .null,
                .text(type),
                .text(payloadString),
                .text(now())
            ]
        )
    }

    private func insert(_ task: OpenJarvisTask) throws {
        try database.execute("""
        INSERT INTO tasks(
            id, raw_request, interpreted_objective, project_context, trust_zone, risk_level,
            allowed_files_json, forbidden_files_json, target_worker, needed_memory_json,
            checkpoint_required, validation_required, memory_writeback_required, next_action,
            vault_root, stage, execution_state, completion_state, writeback_state,
            retrieved_context_json, packet_text, created_at, updated_at, completed_at, written_back_at
        ) VALUES (
            ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
        )
        """, bindings: taskBindings(task))
    }

    private func advance(taskID: String, to newStage: OpenJarvisStage, executionState: OpenJarvisExecutionState? = nil, completionState: OpenJarvisCompletionState? = nil, writebackState: OpenJarvisWritebackState? = nil) throws {
        guard var task = try fetchTask(id: taskID) else {
            throw NSError(domain: "OpenJarvisStore", code: 404, userInfo: [NSLocalizedDescriptionKey: "Task \(taskID) not found"])
        }
        guard allowedTransitions[task.stage, default: []].contains(newStage) else {
            try? recordEvent(taskID: taskID, type: "task.transition_blocked", payload: [
                "from": task.stage.rawValue,
                "to": newStage.rawValue
            ])
            throw NSError(domain: "OpenJarvisStore", code: 409, userInfo: [NSLocalizedDescriptionKey: "Invalid transition from \(task.stage.rawValue) to \(newStage.rawValue)"])
        }
        task.stage = newStage
        if let executionState { task.executionState = executionState }
        if let completionState { task.completionState = completionState }
        if let writebackState { task.writebackState = writebackState }
        task.updatedAt = now()
        try update(task)
    }

    private func updateCompletionTime(taskID: String) throws {
        try database.execute("UPDATE tasks SET completed_at = ?, updated_at = ? WHERE id = ?", bindings: [.text(now()), .text(now()), .text(taskID)])
    }

    private func updateWritebackTime(taskID: String) throws {
        try database.execute("UPDATE tasks SET written_back_at = ?, writeback_state = ?, updated_at = ? WHERE id = ?", bindings: [.text(now()), .text(OpenJarvisWritebackState.written.rawValue), .text(now()), .text(taskID)])
    }

    private func update(_ task: OpenJarvisTask) throws {
        try database.execute("""
        UPDATE tasks SET
            raw_request = ?,
            interpreted_objective = ?,
            project_context = ?,
            trust_zone = ?,
            risk_level = ?,
            allowed_files_json = ?,
            forbidden_files_json = ?,
            target_worker = ?,
            needed_memory_json = ?,
            checkpoint_required = ?,
            validation_required = ?,
            memory_writeback_required = ?,
            next_action = ?,
            vault_root = ?,
            stage = ?,
            execution_state = ?,
            completion_state = ?,
            writeback_state = ?,
            retrieved_context_json = ?,
            packet_text = ?,
            created_at = ?,
            updated_at = ?,
            completed_at = ?,
            written_back_at = ?
        WHERE id = ?
        """, bindings: updateBindings(task))
    }

    private func saveRetrievedHits(taskID: String, query: String, hits: [OpenJarvisRetrievalHit], vaultRoot: String) throws {
        guard var task = try fetchTask(id: taskID) else { return }
        task.retrievedContext = hits
        task.vaultRoot = vaultRoot
        task.updatedAt = now()
        try update(task)
    }

    private func savePacket(taskID: String, packet: OpenJarvisWorkerPacket, vaultRoot: String) throws {
        guard var task = try fetchTask(id: taskID) else { return }
        task.targetWorker = packet.role
        task.packetText = packet.markdown
        task.retrievedContext = packet.retrievedContext
        task.vaultRoot = vaultRoot
        task.updatedAt = now()
        try update(task)
    }

    private func resolveVaultRoot(task: OpenJarvisTask) throws -> URL {
        if let root = task.vaultRoot {
            let url = URL(fileURLWithPath: root)
            if fileExists(url) { return url }
        }
        return try OpenJarvisPaths.vaultRoot()
    }

    private func fileExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    private func createSchema() throws {
        try database.execute("""
        CREATE TABLE IF NOT EXISTS tasks (
            id TEXT PRIMARY KEY,
            raw_request TEXT NOT NULL,
            interpreted_objective TEXT NOT NULL,
            project_context TEXT,
            trust_zone TEXT NOT NULL,
            risk_level TEXT NOT NULL,
            allowed_files_json TEXT NOT NULL,
            forbidden_files_json TEXT NOT NULL,
            target_worker TEXT,
            needed_memory_json TEXT NOT NULL,
            checkpoint_required INTEGER NOT NULL,
            validation_required INTEGER NOT NULL,
            memory_writeback_required INTEGER NOT NULL,
            next_action TEXT,
            vault_root TEXT,
            stage TEXT NOT NULL,
            execution_state TEXT NOT NULL,
            completion_state TEXT NOT NULL,
            writeback_state TEXT NOT NULL,
            retrieved_context_json TEXT NOT NULL,
            packet_text TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            completed_at TEXT,
            written_back_at TEXT
        );
        """)
        try database.execute("""
        CREATE TABLE IF NOT EXISTS task_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            task_id TEXT,
            event_type TEXT NOT NULL,
            payload_json TEXT NOT NULL,
            created_at TEXT NOT NULL
        );
        """)
        try database.execute("CREATE INDEX IF NOT EXISTS idx_task_events_task_id ON task_events(task_id);")
        try database.execute("CREATE INDEX IF NOT EXISTS idx_tasks_stage ON tasks(stage);")
        try database.execute("CREATE INDEX IF NOT EXISTS idx_tasks_updated ON tasks(updated_at);")
    }

    private func taskBindings(_ task: OpenJarvisTask) throws -> [OpenJarvisSQLiteValue] {
        [
            .text(task.id),
            .text(task.rawRequest),
            .text(task.interpretedObjective),
            task.projectContext.map(OpenJarvisSQLiteValue.text) ?? .null,
            .text(task.trustZone),
            .text(task.riskLevel),
            .text(try json(task.allowedFiles)),
            .text(try json(task.forbiddenFiles)),
            task.targetWorker.map { .text($0.rawValue) } ?? .null,
            .text(try json(task.neededMemory)),
            .int(task.checkpointRequired ? 1 : 0),
            .int(task.validationRequired ? 1 : 0),
            .int(task.memoryWritebackRequired ? 1 : 0),
            task.nextAction.map(OpenJarvisSQLiteValue.text) ?? .null,
            task.vaultRoot.map(OpenJarvisSQLiteValue.text) ?? .null,
            .text(task.stage.rawValue),
            .text(task.executionState.rawValue),
            .text(task.completionState.rawValue),
            .text(task.writebackState.rawValue),
            .text(try json(task.retrievedContext)),
            task.packetText.map(OpenJarvisSQLiteValue.text) ?? .null,
            .text(task.createdAt),
            .text(task.updatedAt),
            task.completedAt.map(OpenJarvisSQLiteValue.text) ?? .null,
            task.writtenBackAt.map(OpenJarvisSQLiteValue.text) ?? .null
        ]
    }

    private func updateBindings(_ task: OpenJarvisTask) throws -> [OpenJarvisSQLiteValue] {
        [
            .text(task.rawRequest),
            .text(task.interpretedObjective),
            task.projectContext.map(OpenJarvisSQLiteValue.text) ?? .null,
            .text(task.trustZone),
            .text(task.riskLevel),
            .text(try json(task.allowedFiles)),
            .text(try json(task.forbiddenFiles)),
            task.targetWorker.map { .text($0.rawValue) } ?? .null,
            .text(try json(task.neededMemory)),
            .int(task.checkpointRequired ? 1 : 0),
            .int(task.validationRequired ? 1 : 0),
            .int(task.memoryWritebackRequired ? 1 : 0),
            task.nextAction.map(OpenJarvisSQLiteValue.text) ?? .null,
            task.vaultRoot.map(OpenJarvisSQLiteValue.text) ?? .null,
            .text(task.stage.rawValue),
            .text(task.executionState.rawValue),
            .text(task.completionState.rawValue),
            .text(task.writebackState.rawValue),
            .text(try json(task.retrievedContext)),
            task.packetText.map(OpenJarvisSQLiteValue.text) ?? .null,
            .text(task.createdAt),
            .text(task.updatedAt),
            task.completedAt.map(OpenJarvisSQLiteValue.text) ?? .null,
            task.writtenBackAt.map(OpenJarvisSQLiteValue.text) ?? .null,
            .text(task.id)
        ]
    }

    private func json<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    private static func decodeTaskRow(_ row: OpaquePointer, decoder: JSONDecoder) throws -> OpenJarvisTask {
        func text(_ index: Int32) -> String {
            String(cString: sqlite3_column_text(row, index))
        }
        func nullableText(_ index: Int32) -> String? {
            sqlite3_column_type(row, index) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(row, index))
        }
        func bool(_ index: Int32) -> Bool {
            sqlite3_column_int(row, index) != 0
        }
        let allowedFiles: [String] = try decoder.decode([String].self, from: Data(text(6).utf8))
        let forbiddenFiles: [String] = try decoder.decode([String].self, from: Data(text(7).utf8))
        let neededMemory: [String] = try decoder.decode([String].self, from: Data(text(9).utf8))
        let retrievedContext: [OpenJarvisRetrievalHit] = try decoder.decode([OpenJarvisRetrievalHit].self, from: Data(text(19).utf8))

        return OpenJarvisTask(
            id: text(0),
            rawRequest: text(1),
            interpretedObjective: text(2),
            projectContext: nullableText(3),
            trustZone: text(4),
            riskLevel: text(5),
            allowedFiles: allowedFiles,
            forbiddenFiles: forbiddenFiles,
            targetWorker: nullableText(8).flatMap(OpenJarvisWorkerKind.init(rawValue:)),
            neededMemory: neededMemory,
            checkpointRequired: bool(10),
            validationRequired: bool(11),
            memoryWritebackRequired: bool(12),
            nextAction: nullableText(13),
            vaultRoot: nullableText(14),
            stage: OpenJarvisStage(rawValue: text(15)) ?? .intake,
            executionState: OpenJarvisExecutionState(rawValue: text(16)) ?? .pending,
            completionState: OpenJarvisCompletionState(rawValue: text(17)) ?? .open,
            writebackState: OpenJarvisWritebackState(rawValue: text(18)) ?? .pending,
            retrievedContext: retrievedContext,
            packetText: nullableText(20),
            createdAt: text(21),
            updatedAt: text(22),
            completedAt: nullableText(23),
            writtenBackAt: nullableText(24)
        )
    }

    private let allowedTransitions: [OpenJarvisStage: [OpenJarvisStage]] = [
        .intake: [.retrieve, .executionReady],
        .retrieve: [.assemble, .executionReady],
        .assemble: [.assignWorker, .executionReady],
        .assignWorker: [.validateScope, .executionReady],
        .validateScope: [.checkpointRequirement, .executionReady],
        .checkpointRequirement: [.executionReady],
        .executionReady: [.completed],
        .completed: [.writeback],
        .writeback: []
    ]

    public func listTaskEvents(taskID: String, type: String? = nil, limit: Int = 20) throws -> [OpenJarvisTaskEvent] {
        let sql = """
        SELECT id, task_id, event_type, payload_json, created_at
        FROM task_events
        WHERE task_id = ?
        \(type == nil ? "" : "AND event_type = ?")
        ORDER BY id DESC
        LIMIT ?
        """
        let bindings: [OpenJarvisSQLiteValue] = type.map {
            [.text(taskID), .text($0), .int(Int64(limit))]
        } ?? [.text(taskID), .int(Int64(limit))]
        return try database.query(sql, bindings: bindings) { row in
            OpenJarvisTaskEvent(
                id: Int(sqlite3_column_int(row, 0)),
                taskID: sqlite3_column_type(row, 1) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(row, 1)),
                type: String(cString: sqlite3_column_text(row, 2)),
                payloadJSON: String(cString: sqlite3_column_text(row, 3)),
                createdAt: String(cString: sqlite3_column_text(row, 4))
            )
        }
    }

    private func now() -> String {
        ISO8601DateFormatter.openJarvis.string(from: Date())
    }
}
