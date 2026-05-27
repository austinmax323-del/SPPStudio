import ArgumentParser
import Foundation
import OpenJarvisCore

struct OpenJarvisCLIOptions: ParsableArguments {
    @Option(name: .long, help: "Optional SQLite database path override")
    var database: String?

    func databaseURL() -> URL? {
        database.map { URL(fileURLWithPath: $0).standardizedFileURL }
    }
}

@main
struct Jarvis: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "jarvis",
        abstract: "OpenJarvis manual-first orchestration CLI",
        discussion: """
        jarvis turns a raw request into a structured task, retrieves Obsidian
        context, assembles a worker packet, and records explicit state changes.
        It does not execute shell commands or run unattended automation.

        Examples:
          jarvis task create "review the runtime ops notes" --context SPPStudio --allowed-file SPPStudioDocs/50_RuntimeOps/
          jarvis retrieve --query "architecture memory" --scope architecture
          jarvis packet <task-id> --role codex
        """,
        subcommands: [
            StatusCommand.self,
            TaskCommand.self,
            RetrieveCommand.self,
            PacketCommand.self
        ]
    )
}

struct StatusCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show read-only OpenJarvis operator status"
    )

    @OptionGroup var options: OpenJarvisCLIOptions

    func run() throws {
        let snapshot = try OpenJarvisStatusReader.read(databaseURL: options.databaseURL())
        let vaultStatus = resolveVaultStatus()
        print(renderStatus(snapshot: snapshot, vaultStatus: vaultStatus))
    }
}

struct TaskCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "task",
        abstract: "Create and manage OpenJarvis tasks",
        subcommands: [
            Create.self,
            Show.self,
            List.self,
            Complete.self,
            Writeback.self,
            History.self
        ]
    )
}

extension TaskCommand {
    struct Create: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "create",
            abstract: "Create a new OpenJarvis task",
            discussion: "The raw request is required. All other fields default to manual-first safe values."
        )

        @OptionGroup var options: OpenJarvisCLIOptions

        @Argument(help: "Raw user request")
        var rawRequest: String

        @Option(name: .long, help: "Interpreted objective (defaults to the raw request)")
        var objective: String?

        @Option(name: .long, help: "Project or context hint")
        var context: String?

        @Option(name: .long, help: "Trust zone label")
        var trustZone: String = "safe"

        @Option(name: .long, help: "Risk label")
        var riskLevel: String = "medium"

        @Option(name: .long, help: "Allowed files or paths")
        var allowedFile: [String] = []

        @Option(name: .long, help: "Forbidden files or paths")
        var forbiddenFile: [String] = []

        @Option(name: .long, help: "Target worker: claude | codex")
        var worker: String?

        @Option(name: .long, help: "Needed memory tags or retrieval hints")
        var memory: [String] = []

        @Option(name: .long, help: "Next safe action")
        var nextAction: String?

        @Option(name: .long, help: "Vault root path if different from auto-discovery")
        var vault: String?

        @Option(name: .long, help: "Checkpoint policy: required | optional")
        var checkpoint: String = "required"

        @Option(name: .long, help: "Validation policy: required | optional")
        var validation: String = "required"

        @Option(name: .long, help: "Writeback policy: required | optional")
        var writeback: String = "required"

        func run() throws {
            let store = try OpenJarvisStore(databaseURL: options.databaseURL())
            let targetWorker = try parseWorker(worker)
            let checkpointRequired = try parsePolicy(checkpoint, name: "checkpoint")
            let validationRequired = try parsePolicy(validation, name: "validation")
            let writebackRequired = try parsePolicy(writeback, name: "writeback")
            let task = try store.createTask(
                from: OpenJarvisTaskDraft(
                    rawRequest: rawRequest,
                    interpretedObjective: objective ?? rawRequest,
                    projectContext: context,
                    trustZone: trustZone,
                    riskLevel: riskLevel,
                    allowedFiles: allowedFile,
                    forbiddenFiles: forbiddenFile,
                    targetWorker: targetWorker,
                    neededMemory: memory,
                    checkpointRequired: checkpointRequired,
                    validationRequired: validationRequired,
                    memoryWritebackRequired: writebackRequired,
                    nextAction: nextAction,
                    vaultRoot: vault
                )
            )

            print(taskSummary(task, label: "created"))
        }
    }

    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "show",
            abstract: "Show a task",
            discussion: "Accepts the full task ID or a unique prefix."
        )

        @Argument(help: "Task ID")
        var id: String

        @OptionGroup var options: OpenJarvisCLIOptions

        func run() throws {
            let store = try OpenJarvisStore(databaseURL: options.databaseURL())
            let task = try loadTask(store: store, token: id)
            print(render(task: task))
        }
    }

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List tasks",
            discussion: "Use --stage execution_ready to focus on a workflow slice."
        )

        @Option(name: .long, help: "Filter by stage")
        var stage: String?

        @OptionGroup var options: OpenJarvisCLIOptions

        func run() throws {
            let store = try OpenJarvisStore(databaseURL: options.databaseURL())
            let stageFilter = try parseStage(stage)
            let tasks = try store.listTasks(stage: stageFilter)
            if tasks.isEmpty {
                print("[jarvis] no tasks")
                return
            }
            print("[jarvis] tasks")
            for task in tasks {
                let worker = task.worker?.displayName ?? "unassigned"
                print("  \(task.id.prefix(8))  \(task.stage.rawValue)  \(task.executionState.rawValue)  \(task.completionState.rawValue)  \(task.writebackState.rawValue)  \(worker)  \(task.objective)")
            }
        }
    }

    struct Complete: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "complete",
            abstract: "Mark a task complete",
            discussion: "Requires the task to already be at execution_ready."
        )

        @Argument(help: "Task ID")
        var id: String

        @Option(name: .long, help: "Completion note")
        var note: String?

        @OptionGroup var options: OpenJarvisCLIOptions

        func run() throws {
            let store = try OpenJarvisStore(databaseURL: options.databaseURL())
            let task = try store.completeTask(id: try loadTaskID(store: store, token: id), note: note)
            print(render(task: task))
        }
    }

    struct Writeback: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "writeback",
            abstract: "Mark a task's memory writeback complete",
            discussion: "Requires the task to already be completed."
        )

        @Argument(help: "Task ID")
        var id: String

        @Option(name: .long, help: "Writeback note")
        var note: String?

        @OptionGroup var options: OpenJarvisCLIOptions

        func run() throws {
            let store = try OpenJarvisStore(databaseURL: options.databaseURL())
            let task = try store.writebackTask(id: try loadTaskID(store: store, token: id), note: note)
            print(render(task: task))
        }
    }

    struct History: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "history",
            abstract: "Show recent audit events for a task",
            discussion: "Read-only. Accepts the full task ID or a unique prefix."
        )

        @Argument(help: "Task ID")
        var id: String

        @Option(name: .long, help: "Optional event type filter")
        var type: String?

        @Option(name: .long, help: "Maximum events to show")
        var limit: Int = 20

        @OptionGroup var options: OpenJarvisCLIOptions

        func run() throws {
            guard limit > 0 else {
                throw ValidationError("History limit must be greater than 0.")
            }
            let store = try OpenJarvisStore(databaseURL: options.databaseURL())
            let taskID = try loadTaskID(store: store, token: id)
            let events = try store.listTaskEvents(taskID: taskID, type: type, limit: limit)
            print(renderHistory(taskID: taskID, events: events, type: type, limit: limit))
        }
    }
}

struct RetrieveCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "retrieve",
        abstract: "Read-only context retrieval from the Obsidian vault",
        discussion: "Use --task to attach the retrieval to a stored task, or --query for a one-off read-only lookup."
    )

    @Option(name: .long, help: "Task ID to retrieve for")
    var task: String?

    @Option(name: .long, help: "Query string to search the vault")
    var query: String?

    @Option(name: .long, help: "Optional retrieval scope")
    var scope: [String] = []

    @Option(name: .long, help: "Candidate limit")
    var limit: Int = 8

    @OptionGroup var options: OpenJarvisCLIOptions

    func run() throws {
        let store = try OpenJarvisStore(databaseURL: options.databaseURL())
        if let task {
            let taskID = try loadTaskID(store: store, token: task)
            guard let taskRecord = try store.fetchTask(id: taskID) else {
                throw ValidationError("Task '\(task)' not found.")
            }
            let queryText = query ?? [taskRecord.interpretedObjective, taskRecord.rawRequest, taskRecord.neededMemory.joined(separator: " ")].joined(separator: " ")
            let hits = try store.retrieveContext(for: taskID, query: queryText, scopeHint: parseScopes(scope), limit: limit)
            print(renderRetrieval(taskID: taskID, query: queryText, hits: hits))
        } else {
            let queryText = query ?? ""
            guard !queryText.isEmpty else {
                throw ValidationError("Provide either --task or --query.")
            }
            let vault = try OpenJarvisPaths.vaultRoot()
            let engine = OpenJarvisRetrievalEngine(vaultRoot: vault)
            let request = OpenJarvisRetrievalRequest(query: queryText, scopes: try parseScopes(scope) ?? inferOpenJarvisScopes(from: queryText), limit: limit)
            let hits = try engine.retrieve(request)
            try store.recordEvent(taskID: nil, type: "retrieval.preview", payload: [
                "query": queryText,
                "hit_count": "\(hits.count)"
            ])
            print(renderRetrieval(taskID: nil, query: queryText, hits: hits))
        }
    }
}

struct PacketCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "packet",
        abstract: "Generate a Claude/Codex worker packet"
    )

    @Argument(help: "Task ID")
    var taskID: String

    @Option(name: .long, help: "Worker role: claude | codex")
    var role: String?

    @Option(name: .long, help: "Optional retrieval scope override")
    var scope: [String] = []

    @Option(name: .long, help: "Candidate limit")
    var limit: Int = 5

    @OptionGroup var options: OpenJarvisCLIOptions

    func run() throws {
        let store = try OpenJarvisStore(databaseURL: options.databaseURL())
        let resolvedTaskID = try loadTaskID(store: store, token: taskID)
        let packet = try store.generatePacket(
            for: resolvedTaskID,
            role: role.flatMap(OpenJarvisWorkerKind.init(rawValue:)),
            limit: limit,
            scopeHint: try parseScopes(scope)
        )
        print(packet.markdown)
    }
}

// MARK: - Rendering Helpers

private func render(task: OpenJarvisTask) -> String {
    var lines: [String] = []
    lines.append("[jarvis] task")
    lines.append("  id: \(task.id)")
    lines.append("  short id: \(task.id.prefix(8))")
    lines.append("  objective: \(task.interpretedObjective)")
    if let context = task.projectContext {
        lines.append("  context: \(context)")
    }
    if !task.allowedFiles.isEmpty {
        lines.append("  allowed: \(task.allowedFiles.joined(separator: ", "))")
    }
    if !task.forbiddenFiles.isEmpty {
        lines.append("  forbidden: \(task.forbiddenFiles.joined(separator: ", "))")
    }
    if !task.neededMemory.isEmpty {
        lines.append("  memory: \(task.neededMemory.joined(separator: ", "))")
    }
    if let nextAction = task.nextAction {
        lines.append("  next action: \(nextAction)")
    }
    lines.append("  stage: \(task.stage.rawValue)")
    lines.append("  execution: \(task.executionState.rawValue)")
    lines.append("  completion: \(task.completionState.rawValue)")
    lines.append("  writeback: \(task.writebackState.rawValue)")
    lines.append("  worker: \(task.targetWorker?.displayName ?? "unassigned")")
    lines.append("  updated: \(task.updatedAt)")
    lines.append("  created: \(task.createdAt)")
    if let completedAt = task.completedAt {
        lines.append("  completed: \(completedAt)")
    }
    if let writtenBackAt = task.writtenBackAt {
        lines.append("  written back: \(writtenBackAt)")
    }
    if let packetText = task.packetText {
        lines.append("")
        lines.append(packetText)
    }
    return lines.joined(separator: "\n")
}

private func renderRetrieval(taskID: String?, query: String, hits: [OpenJarvisRetrievalHit]) -> String {
    var lines: [String] = []
    lines.append("[jarvis] retrieval")
    if let taskID { lines.append("  task: \(taskID)") }
    lines.append("  query: \(query)")
    lines.append("  hits: \(hits.count)")
    for (index, hit) in hits.enumerated() {
        lines.append("  \(index + 1). [\(hit.score)] \(hit.path)")
        lines.append("     title: \(hit.title)")
        if !hit.reasons.isEmpty {
            lines.append("     reasons: \(hit.reasons.joined(separator: ", "))")
        }
        if !hit.excerpt.isEmpty {
            lines.append("     excerpt: \(hit.excerpt)")
        }
    }
    return lines.joined(separator: "\n")
}

private func renderHistory(taskID: String, events: [OpenJarvisTaskEvent], type: String?, limit: Int) -> String {
    var lines: [String] = []
    lines.append("[jarvis] task history")
    lines.append("  task: \(taskID)")
    if let type {
        lines.append("  type: \(type)")
    }
    lines.append("  limit: \(limit)")
    lines.append("  events: \(events.count)")
    for event in events {
        lines.append("  \(event.id). \(event.createdAt) \(event.type)")
        if !event.payloadJSON.isEmpty && event.payloadJSON != "{}" {
            lines.append("     payload: \(event.payloadJSON)")
        }
    }
    return lines.joined(separator: "\n")
}

private func renderStatus(snapshot: OpenJarvisStatusSnapshot, vaultStatus: (resolved: Bool, detail: String)) -> String {
    var lines: [String] = []
    lines.append("[jarvis] status")
    lines.append("  database: \(snapshot.databaseURL.path)")
    lines.append("  database exists: \(snapshot.databaseExists ? "yes" : "no")")
    lines.append("  task count: \(snapshot.taskCount.map(String.init) ?? "unavailable")")
    if let latestTask = snapshot.latestTask {
        lines.append("  latest task: \(latestTask.id.prefix(8)) \(latestTask.stage.rawValue) \(latestTask.objective)")
        lines.append("  latest updated: \(latestTask.updatedAt)")
    } else {
        lines.append("  latest task: none")
    }
    lines.append("  vault root: \(vaultStatus.resolved ? "resolved" : "unresolved")")
    lines.append("  vault detail: \(vaultStatus.detail)")
    lines.append("  mode: manual-first, read-only status")
    return lines.joined(separator: "\n")
}

private func resolveVaultStatus() -> (resolved: Bool, detail: String) {
    do {
        return (true, try OpenJarvisPaths.vaultRoot().path)
    } catch {
        return (false, String(describing: error))
    }
}

private func parseScopes(_ raw: [String]) throws -> [OpenJarvisRetrievalScope]? {
    guard !raw.isEmpty else { return nil }
    var scopes: [OpenJarvisRetrievalScope] = []
    for value in raw {
        guard let scope = OpenJarvisRetrievalScope(rawValue: value.lowercased()) else {
            throw ValidationError("Unknown retrieval scope '\(value)'.")
        }
        scopes.append(scope)
    }
    return scopes
}

private func parseStage(_ raw: String?) throws -> OpenJarvisStage? {
    guard let raw else { return nil }
    guard let stage = OpenJarvisStage(rawValue: raw.lowercased()) else {
        throw ValidationError("Unknown stage '\(raw)'.")
    }
    return stage
}

private func parseWorker(_ raw: String?) throws -> OpenJarvisWorkerKind? {
    guard let raw else { return nil }
    guard let worker = OpenJarvisWorkerKind(rawValue: raw.lowercased()) else {
        throw ValidationError("Unknown worker '\(raw)'. Use claude or codex.")
    }
    return worker
}

private func parsePolicy(_ raw: String, name: String) throws -> Bool {
    switch raw.lowercased() {
    case "required":
        return true
    case "optional":
        return false
    default:
        throw ValidationError("Unknown \(name) policy '\(raw)'. Use required or optional.")
    }
}

private func loadTaskID(store: OpenJarvisStore, token: String) throws -> String {
    do {
        return try store.resolveTaskID(token)
    } catch let error as NSError {
        throw ValidationError(error.localizedDescription)
    }
}

private func loadTask(store: OpenJarvisStore, token: String) throws -> OpenJarvisTask {
    let taskID = try loadTaskID(store: store, token: token)
    guard let task = try store.fetchTask(id: taskID) else {
        throw ValidationError("Task '\(token)' not found.")
    }
    return task
}

private func taskSummary(_ task: OpenJarvisTask, label: String) -> String {
    var lines: [String] = []
    lines.append("[jarvis] task \(label)")
    lines.append("  id: \(task.id)")
    lines.append("  short id: \(task.id.prefix(8))")
    lines.append("  objective: \(task.interpretedObjective)")
    lines.append("  stage: \(task.stage.rawValue)")
    lines.append("  execution: \(task.executionState.rawValue)")
    lines.append("  completion: \(task.completionState.rawValue)")
    lines.append("  writeback: \(task.writebackState.rawValue)")
    return lines.joined(separator: "\n")
}
