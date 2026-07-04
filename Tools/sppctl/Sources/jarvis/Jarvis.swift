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
        abstract: "Quiet local continuity utilities for Claude Code and Codex",
        discussion: """
        jarvis prepares context, preserves task continuity, and records worker
        artifacts behind Claude Code and Codex.

        Examples:
          jarvis
          jarvis status
          jarvis shell
          jarvis history <task-id>
        """,
        subcommands: [
            ShellCommand.self,
            AskCommand.self,
            SendCommand.self,
            StatusCommand.self,
            CloseCommand.self,
            HistoryCommand.self,
            OverviewCommand.self,
            NewCommand.self,
            ListCommand.self,
            NextCommand.self,
            DoneCommand.self,
            ShowCommand.self,
            ApproveCommand.self,
            RejectCommand.self,
            EditCommand.self,
            WritebackCommand.self,
            OpenCommand.self,
            TaskCommand.self,
            RetrieveCommand.self,
            PacketCommand.self
        ]
    )

    @OptionGroup var options: OpenJarvisCLIOptions

    func run() throws {
        var repl = OpenJarvisREPL(databaseURL: options.databaseURL())
        try repl.run()
    }
}

struct SendCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "send",
        abstract: "Run a Claude/Codex worker and save a review artifact"
    )

    @Argument(help: "Worker: claude | codex")
    var worker: String

    @Argument(help: "Optional task ID")
    var task: String?

    @Flag(name: .long, help: "Show command and git context without launching worker")
    var dryRun: Bool = false

    @Flag(name: .long, help: "Skip confirmation prompt")
    var yes: Bool = false

    @Flag(name: .long, help: "Show command details")
    var verbose: Bool = false

    @Flag(name: .long, help: "Include before/after git snapshots in artifact")
    var artifactVerbose: Bool = false

    @Option(name: .long, help: "Working directory for worker subprocess")
    var cwd: String?

    @Option(name: .long, help: "Vault root path for artifact output")
    var vault: String?

    @OptionGroup var options: OpenJarvisCLIOptions

    func run() throws {
        _ = try performWorkerSend(
            databaseURL: options.databaseURL(),
            currentTaskID: nil,
            workerName: worker,
            taskToken: task,
            dryRun: dryRun,
            assumeYes: yes,
            cwdOverride: cwd,
            vaultOverride: vault,
            verbose: verbose,
            artifactVerbose: artifactVerbose
        )
    }
}

struct AskCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ask",
        abstract: "Create a reviewable worker packet"
    )

    @OptionGroup var options: OpenJarvisCLIOptions

    @Argument(help: "Request to package")
    var request: String

    @Option(name: .long, help: "Target worker: claude | codex")
    var worker: String?

    @Flag(name: .long, help: "Deprecated; ask always prints the packet for approval")
    var noCopy: Bool = false

    func run() throws {
        let workerKind = try parseWorker(worker) ?? inferWorker(from: request)
        let scopes = inferOpenJarvisScopes(from: request)
        let neededMemory = scopes.isEmpty ? ["coordination"] : scopes.map(\.rawValue)
        let objective = request.prefix(1).uppercased() + request.dropFirst()
        let store = try OpenJarvisStore(databaseURL: options.databaseURL())
        let task = try store.createTask(
            from: OpenJarvisTaskDraft(
                rawRequest: request,
                interpretedObjective: objective,
                projectContext: nil,
                trustZone: "safe",
                riskLevel: "medium",
                allowedFiles: [],
                forbiddenFiles: [],
                targetWorker: workerKind,
                neededMemory: neededMemory,
                checkpointRequired: true,
                validationRequired: true,
                memoryWritebackRequired: true,
                nextAction: nil,
                vaultRoot: nil
            )
        )
        let packet = try store.generatePacket(for: task.id, role: workerKind, limit: 5, scopeHint: scopes.isEmpty ? nil : scopes)
        try recordApprovalRequested(store: store, taskID: task.id, packetText: packet.markdown)
        let storedTask = try store.fetchTask(id: task.id) ?? task
        print(renderApprovalReview(task: storedTask, packetText: packet.markdown, approval: .pending))
    }
}

struct ApproveCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "approve",
        abstract: "Approve a worker packet after inspection"
    )

    @Argument(help: "Task ID")
    var id: String

    @Flag(name: .long, help: "Do not copy the approved packet to the clipboard")
    var noCopy: Bool = false

    @OptionGroup var options: OpenJarvisCLIOptions

    func run() throws {
        let store = try OpenJarvisStore(databaseURL: options.databaseURL())
        let task = try approveTask(store: store, token: id, copy: !noCopy)
        print(renderApprovalDecision(task: task, state: .approved, copied: !noCopy))
    }
}

struct RejectCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reject",
        abstract: "Reject a worker packet"
    )

    @Argument(help: "Task ID")
    var id: String

    @Option(name: .long, help: "Reason for rejection")
    var note: String?

    @OptionGroup var options: OpenJarvisCLIOptions

    func run() throws {
        let store = try OpenJarvisStore(databaseURL: options.databaseURL())
        let task = try rejectTask(store: store, token: id, note: note)
        print(renderApprovalDecision(task: task, state: .rejected, copied: false))
    }
}

struct EditCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "edit",
        abstract: "Edit a stored worker packet before approval"
    )

    @Argument(help: "Task ID")
    var id: String

    @OptionGroup var options: OpenJarvisCLIOptions

    func run() throws {
        let store = try OpenJarvisStore(databaseURL: options.databaseURL())
        let task = try editTaskPacket(store: store, token: id)
        let approval = try approvalState(store: store, taskID: task.id)
        print(renderApprovalReview(task: task, packetText: task.packetText ?? "", approval: approval))
    }
}

struct CloseCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "close",
        abstract: "Archive a task"
    )

    @Argument(help: "Task ID")
    var id: String

    @Option(name: .long, help: "Closure note")
    var note: String?

    @OptionGroup var options: OpenJarvisCLIOptions

    func run() throws {
        let store = try OpenJarvisStore(databaseURL: options.databaseURL())
        let taskID = try loadTaskID(store: store, token: id)
        let closeNote = note ?? "closed"
        guard let task = try store.fetchTask(id: taskID) else {
            throw ValidationError("Task '\(taskID)' not found.")
        }
        let final: OpenJarvisTask
        switch task.stage {
        case .writeback:
            final = task
        case .completed:
            final = try store.writebackTask(id: taskID, note: closeNote)
        default:
            _ = try store.completeTask(id: taskID, note: closeNote)
            final = try store.writebackTask(id: taskID, note: closeNote)
        }
        print(sectionTitle("Archived"))
        print(kv("Task", String(final.id.prefix(8))))
    }
}

struct ShellCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "shell",
        abstract: "Start the interactive manual-first OpenJarvis shell"
    )

    @OptionGroup var options: OpenJarvisCLIOptions

    func run() throws {
        var repl = OpenJarvisREPL(databaseURL: options.databaseURL())
        try repl.run()
    }
}

struct OverviewCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "overview",
        abstract: "Show status, open tasks, and common manual commands",
        shouldDisplay: false
    )

    @OptionGroup var options: OpenJarvisCLIOptions

    func run() throws {
        let snapshot = try OpenJarvisStatusReader.read(databaseURL: options.databaseURL())
        let vaultStatus = resolveVaultStatus()
        print(renderStatus(snapshot: snapshot, vaultStatus: vaultStatus))
        print("")

        guard snapshot.databaseExists else {
            print(sectionTitle("Open Tasks"))
            print(emptyState("database does not exist yet"))
            print("")
            printCommonCommands()
            return
        }

        let store = try OpenJarvisStore(databaseURL: options.databaseURL())
        let openTasks = try store.listTasks().filter { $0.completionState == .open }
        print(renderTaskList(openTasks, label: "open tasks", emptyMessage: "no open tasks"))
        print("")
        printCommonCommands()
    }
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

struct NewCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "new",
        abstract: "Create a new manual OpenJarvis task",
        discussion: "Alias for: jarvis task create",
        shouldDisplay: false
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

struct ListCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List OpenJarvis tasks",
        discussion: "Alias for: jarvis task list",
        shouldDisplay: false
    )

    @Option(name: .long, help: "Filter by stage")
    var stage: String?

    @OptionGroup var options: OpenJarvisCLIOptions

    func run() throws {
        let store = try OpenJarvisStore(databaseURL: options.databaseURL())
        let stageFilter = try parseStage(stage)
        let tasks = try store.listTasks(stage: stageFilter)
        print(renderTaskList(tasks, label: "tasks", emptyMessage: "no tasks"))
    }
}

struct NextCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "next",
        abstract: "Show the latest open task and suggested next command",
        discussion: "Read-only. Does not advance task state.",
        shouldDisplay: false
    )

    @OptionGroup var options: OpenJarvisCLIOptions

    func run() throws {
        let snapshot = try OpenJarvisStatusReader.read(databaseURL: options.databaseURL())
        guard snapshot.databaseExists else {
            print(sectionTitle("Next"))
            print(emptyState("database does not exist yet"))
            print(kv("Try", "jarvis ask \"your task\""))
            return
        }

        let store = try OpenJarvisStore(databaseURL: options.databaseURL())
        guard let task = try store.listTasks().first(where: { $0.completionState == .open }) else {
            print(sectionTitle("Next"))
            print(emptyState("no open tasks"))
            print(kv("Try", "jarvis ask \"your task\""))
            return
        }

        print(sectionTitle("Next"))
        print(kv("Task", String(task.id.prefix(8))))
        print(kv("Goal", clipped(task.objective, limit: 72)))
        print(kv("State", userFacingStage(task.stage)))
        print(kv("Worker", task.worker?.displayName ?? "unassigned"))
        print(kv("Next", suggestedCommand(for: task)))
    }
}

struct DoneCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "done",
        abstract: "Mark a task complete",
        discussion: "Alias for: jarvis task complete",
        shouldDisplay: false
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

struct HistoryCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "history",
        abstract: "Show recent audit events for a task",
        discussion: "Alias for: jarvis task history"
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

struct ShowCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Show a task",
        discussion: "Alias for: jarvis task show",
        shouldDisplay: false
    )

    @Argument(help: "Task ID")
    var id: String

    @OptionGroup var options: OpenJarvisCLIOptions

    func run() throws {
        let store = try OpenJarvisStore(databaseURL: options.databaseURL())
        let task = try loadTask(store: store, token: id)
        if let packetText = task.packetText, !packetText.isEmpty {
            let approval = try approvalState(store: store, taskID: task.id)
            print(renderApprovalReview(task: task, packetText: packetText, approval: approval))
        } else {
            print(render(task: task))
        }
    }
}

struct WritebackCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "writeback",
        abstract: "Mark a task's memory writeback complete",
        discussion: "Alias for: jarvis task writeback",
        shouldDisplay: false
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

struct OpenCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "open",
        abstract: "Open the first related Obsidian note or allowed file for a task",
        shouldDisplay: false
    )

    @Argument(help: "Task ID")
    var id: String

    @OptionGroup var options: OpenJarvisCLIOptions

    func run() throws {
        let store = try OpenJarvisStore(databaseURL: options.databaseURL())
        let task = try loadTask(store: store, token: id)
        let vault = try OpenJarvisPaths.vaultRoot()
        let candidates = task.retrievedContext.map(\.path) + task.allowedFiles
        guard let path = candidates.first else {
            throw ValidationError("Task has no retrieved context or allowed files to open.")
        }
        let target = path.hasPrefix("/") ? URL(fileURLWithPath: path) : vault.appendingPathComponent(path)
        try openURL(target)
        print("Opened")
        print("  \(target.path)")
    }
}

struct TaskCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "task",
        abstract: "Create and manage OpenJarvis tasks",
        shouldDisplay: false,
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
            print(renderTaskList(tasks, label: "tasks", emptyMessage: "no tasks"))
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
        discussion: "Use --task to attach the retrieval to a stored task, or --query for a one-off read-only lookup.",
        shouldDisplay: false
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
        abstract: "Generate a Claude/Codex worker packet",
        shouldDisplay: false
    )

    @Argument(help: "Task ID")
    var taskID: String

    @Option(name: .long, help: "Worker role: claude | codex")
    var role: String?

    @Option(name: .long, help: "Optional retrieval scope override")
    var scope: [String] = []

    @Option(name: .long, help: "Candidate limit")
    var limit: Int = 5

    @Flag(name: .long, help: "Copy the generated packet to the macOS clipboard")
    var copy: Bool = false

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
        if copy {
            try copyToClipboard(packet.markdown)
            print("")
            print(sectionTitle("Copied"))
            print(kv("Packet", "[ok] copied to clipboard"))
        }
    }
}

// MARK: - Rendering Helpers

func sectionTitle(_ title: String) -> String {
    "== \(title.uppercased()) =="
}

func kv(_ label: String, _ value: String) -> String {
    let padded = label.padding(toLength: 8, withPad: " ", startingAt: 0)
    return "  \(padded) \(value)"
}

func emptyState(_ message: String) -> String {
    "  \(message)"
}

func clipped(_ text: String, limit: Int) -> String {
    guard text.count > limit, limit > 3 else { return text }
    return String(text.prefix(limit - 3)) + "..."
}

func statusBadge(_ ok: Bool) -> String {
    ok ? "[ok]" : "[warn]"
}

func shellQuote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

enum JarvisApprovalState: String {
    case pending
    case approved
    case rejected

    var displayLabel: String {
        switch self {
        case .pending: return "[wait] pending"
        case .approved: return "[ok] approved"
        case .rejected: return "[err] rejected"
        }
    }
}

func approvalState(store: OpenJarvisStore, taskID: String) throws -> JarvisApprovalState {
    let events = try store.listTaskEvents(taskID: taskID, limit: 100)
    for event in events {
        switch event.type {
        case "task.approved":
            return .approved
        case "task.rejected":
            return .rejected
        case "task.packet_generated", "task.packet_edited", "task.approval_requested":
            return .pending
        default:
            continue
        }
    }
    return .pending
}

func estimatedTokens(for text: String) -> Int {
    max(1, Int(ceil(Double(text.count) / 4.0)))
}

func packetSizeLabel(_ text: String) -> String {
    "\(text.count) chars, ~\(estimatedTokens(for: text)) tokens"
}

func recordApprovalRequested(store: OpenJarvisStore, taskID: String, packetText: String) throws {
    try store.recordEvent(taskID: taskID, type: "task.approval_requested", payload: [
        "chars": "\(packetText.count)",
        "estimated_tokens": "\(estimatedTokens(for: packetText))"
    ])
}

func approveTask(store: OpenJarvisStore, token: String, copy: Bool) throws -> OpenJarvisTask {
    let taskID = try loadTaskID(store: store, token: token)
    guard let task = try store.fetchTask(id: taskID) else {
        throw ValidationError("Task '\(taskID)' not found.")
    }
    guard let packetText = task.packetText, !packetText.isEmpty else {
        throw ValidationError("Task \(taskID.prefix(8)) has no stored packet. Use: jarvis ask \"...\"")
    }
    try store.recordEvent(taskID: taskID, type: "task.approved", payload: [
        "chars": "\(packetText.count)",
        "estimated_tokens": "\(estimatedTokens(for: packetText))",
        "worker": task.targetWorker?.rawValue ?? ""
    ])
    if copy {
        try copyToClipboard(packetText)
    }
    return try store.fetchTask(id: taskID) ?? task
}

func rejectTask(store: OpenJarvisStore, token: String, note: String?) throws -> OpenJarvisTask {
    let taskID = try loadTaskID(store: store, token: token)
    guard let task = try store.fetchTask(id: taskID) else {
        throw ValidationError("Task '\(taskID)' not found.")
    }
    try store.recordEvent(taskID: taskID, type: "task.rejected", payload: [
        "note": note ?? "",
        "worker": task.targetWorker?.rawValue ?? ""
    ])
    return try store.fetchTask(id: taskID) ?? task
}

func editTaskPacket(store: OpenJarvisStore, token: String) throws -> OpenJarvisTask {
    let taskID = try loadTaskID(store: store, token: token)
    guard let task = try store.fetchTask(id: taskID) else {
        throw ValidationError("Task '\(taskID)' not found.")
    }
    guard let packetText = task.packetText, !packetText.isEmpty else {
        throw ValidationError("Task \(taskID.prefix(8)) has no stored packet. Use: jarvis ask \"...\"")
    }
    let editor = ProcessInfo.processInfo.environment["VISUAL"]
        ?? ProcessInfo.processInfo.environment["EDITOR"]
        ?? "vi"
    let tempURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("openjarvis-\(taskID.prefix(8))-packet.md")
    try packetText.write(to: tempURL, atomically: true, encoding: .utf8)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-lc", "\(shellQuote(editor)) \(shellQuote(tempURL.path))"]
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw ValidationError("Editor exited with status \(process.terminationStatus). Packet was not changed.")
    }
    let edited = try String(contentsOf: tempURL, encoding: .utf8)
    guard !edited.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw ValidationError("Edited packet is empty. Packet was not changed.")
    }
    return try store.updatePacketText(taskID: taskID, packetText: edited, note: "manual edit")
}

func requireApprovalForSend(store: OpenJarvisStore, taskID: String) throws {
    let state = try approvalState(store: store, taskID: taskID)
    guard state == .approved else {
        try? store.recordEvent(taskID: taskID, type: "task.approval_required", payload: [
            "state": state.rawValue
        ])
        throw ValidationError("Task \(taskID.prefix(8)) is \(state.rawValue). Review with: jarvis show \(taskID.prefix(8)); approve with: jarvis approve \(taskID.prefix(8))")
    }
}

func renderContextSources(_ hits: [OpenJarvisRetrievalHit]) -> [String] {
    guard !hits.isEmpty else { return [emptyState("no retrieved context sources")] }
    return hits.enumerated().map { index, hit in
        let rank = String(format: "%2d", index + 1)
        return "  \(rank). [\(hit.score)] \(clipped(hit.path, limit: 72))"
    }
}

func renderApprovalReview(task: OpenJarvisTask, packetText: String, approval: JarvisApprovalState) -> String {
    var lines: [String] = []
    let worker = task.targetWorker?.displayName ?? "unassigned"
    lines.append(sectionTitle("Approval Required"))
    lines.append(kv("Task", String(task.id.prefix(8))))
    lines.append(kv("Worker", worker))
    lines.append(kv("State", approval.displayLabel))
    lines.append(kv("Context", "\(task.retrievedContext.count) sources"))
    lines.append(kv("Size", packetSizeLabel(packetText)))
    lines.append("")
    lines.append(sectionTitle("Context Sources"))
    lines.append(contentsOf: renderContextSources(task.retrievedContext))
    lines.append("")
    lines.append(sectionTitle("Generated Prompt"))
    if packetText.isEmpty {
        lines.append(emptyState("no packet stored"))
    } else {
        lines.append(packetText)
    }
    lines.append("")
    lines.append(sectionTitle("Next"))
    lines.append(kv("Inspect", "jarvis show \(task.id.prefix(8))"))
    lines.append(kv("Approve", "jarvis approve \(task.id.prefix(8))"))
    lines.append(kv("Reject", "jarvis reject \(task.id.prefix(8))"))
    lines.append(kv("Edit", "jarvis edit \(task.id.prefix(8))"))
    return lines.joined(separator: "\n")
}

func renderApprovalDecision(task: OpenJarvisTask, state: JarvisApprovalState, copied: Bool) -> String {
    var lines: [String] = []
    lines.append(sectionTitle(state == .approved ? "Approved" : "Rejected"))
    lines.append(kv("Task", String(task.id.prefix(8))))
    lines.append(kv("Worker", task.targetWorker?.displayName ?? "unassigned"))
    lines.append(kv("State", state.displayLabel))
    if let packetText = task.packetText {
        lines.append(kv("Size", packetSizeLabel(packetText)))
    }
    if state == .approved {
        lines.append(kv("Packet", copied ? "[ok] copied to clipboard" : "not copied"))
        lines.append(kv("Next", "jarvis send \(task.targetWorker?.rawValue ?? "codex") \(task.id.prefix(8))"))
    } else {
        lines.append(kv("Next", "jarvis edit \(task.id.prefix(8))"))
    }
    return lines.joined(separator: "\n")
}

func render(task: OpenJarvisTask) -> String {
    var lines: [String] = []
    lines.append(sectionTitle("Task"))
    lines.append(kv("ID", String(task.id.prefix(8))))
    lines.append(kv("State", visibleLifecycleLabel(for: task.stage)))
    lines.append(kv("Worker", task.targetWorker?.displayName ?? "unassigned"))
    lines.append(kv("Goal", clipped(task.interpretedObjective, limit: 72)))
    if let context = task.projectContext {
        lines.append(kv("Project", context))
    }
    if !task.neededMemory.isEmpty {
        lines.append(kv("Memory", task.neededMemory.joined(separator: ", ")))
    }
    if let nextAction = task.nextAction {
        lines.append(kv("Next", clipped(nextAction, limit: 72)))
    }
    if let packetText = task.packetText {
        lines.append(kv("Packet", packetSizeLabel(packetText)))
        lines.append("")
        lines.append(sectionTitle("Context Sources"))
        lines.append(contentsOf: renderContextSources(task.retrievedContext))
        lines.append("")
        lines.append(sectionTitle("Generated Prompt"))
        lines.append(packetText)
    }
    return lines.joined(separator: "\n")
}

func renderRetrieval(taskID: String?, query: String, hits: [OpenJarvisRetrievalHit]) -> String {
    var lines: [String] = []
    lines.append(sectionTitle("Context"))
    if let taskID { lines.append(kv("Task", String(taskID.prefix(8)))) }
    lines.append(kv("Query", clipped(query, limit: 72)))
    lines.append(kv("Hits", "\(hits.count)"))
    guard !hits.isEmpty else {
        lines.append(emptyState("no context hits"))
        return lines.joined(separator: "\n")
    }
    lines.append("")
    for (index, hit) in hits.enumerated() {
        let rank = String(format: "%2d", index + 1)
        lines.append("  \(rank). [\(hit.score)] \(clipped(hit.path, limit: 68))")
        lines.append("      title   \(clipped(hit.title, limit: 64))")
        if !hit.reasons.isEmpty {
            lines.append("      reason  \(hit.reasons.joined(separator: ", "))")
        }
        if !hit.excerpt.isEmpty {
            lines.append("      note    \(clipped(hit.excerpt, limit: 78))")
        }
    }
    return lines.joined(separator: "\n")
}

func renderHistory(taskID: String, events: [OpenJarvisTaskEvent], type: String?, limit: Int) -> String {
    var lines: [String] = []
    lines.append(sectionTitle("History"))
    lines.append(kv("Task", String(taskID.prefix(8))))
    if let type {
        lines.append(kv("Type", type))
    }
    lines.append(kv("Events", "\(events.count)"))
    guard !events.isEmpty else {
        lines.append(emptyState("no events"))
        return lines.joined(separator: "\n")
    }
    lines.append("")
    let landmarks: Set<String> = ["task.packet_generated", "task.completed", "task.writeback", "task.session_closed"]
    for event in events {
        if landmarks.contains(event.type) {
            lines.append("")
        }
        let age = relativeAge(from: event.createdAt)
        lines.append("  \(event.id). \(age.padding(toLength: 8, withPad: " ", startingAt: 0)) \(humanEventLabel(event.type))")
    }
    return lines.joined(separator: "\n")
}

func renderStatus(snapshot: OpenJarvisStatusSnapshot, vaultStatus: (resolved: Bool, detail: String)) -> String {
    var lines: [String] = []
    lines.append(sectionTitle("Status"))
    lines.append(kv("Store", "\(statusBadge(snapshot.databaseExists)) \(snapshot.databaseExists ? "ready" : "not created")"))
    lines.append(kv("Vault", "\(statusBadge(vaultStatus.resolved)) \(vaultStatus.resolved ? "ready" : "missing")"))
    lines.append(kv("Tasks", snapshot.taskCount.map { "\($0) total" } ?? "unavailable"))
    if let latestTask = snapshot.latestTask {
        let latest = "\(latestTask.id.prefix(8))  \(visibleLifecycleLabel(for: latestTask.stage))  \(clipped(latestTask.objective, limit: 48))"
        lines.append(kv("Latest", latest))
        lines.append(kv("Updated", relativeAge(from: latestTask.updatedAt)))
    } else {
        lines.append(kv("Latest", "none"))
    }
    return lines.joined(separator: "\n")
}

func userFacingStage(_ stage: OpenJarvisStage) -> String {
    return visibleLifecycleLabel(for: stage)
}

func visibleLifecycleLabel(for stage: OpenJarvisStage) -> String {
    switch stage {
    case .intake, .retrieve, .assemble, .assignWorker, .validateScope, .checkpointRequirement:
        return "active"
    case .executionReady, .completed:
        return "ready"
    case .writeback:
        return "archived"
    }
}

func humanEventLabel(_ type: String) -> String {
    switch type {
    case "task.created": return "created"
    case "task.retrieved": return "context retrieved"
    case "task.packet_generated": return "packet generated"
    case "task.approval_requested": return "approval requested"
    case "task.approved": return "approved"
    case "task.rejected": return "rejected"
    case "task.packet_edited": return "packet edited"
    case "task.approval_required": return "approval required"
    case "task.autopilot_launch": return "packet copied"
    case "task.worker_invoked": return "worker invoked"
    case "task.worker_response_saved": return "response saved"
    case "task.completed": return "closed"
    case "task.writeback": return "archived"
    case "task.session_closed": return "archived"
    case "task.transition_blocked": return "transition blocked"
    case "task.packet_blocked": return "packet blocked"
    default: return type
    }
}

func renderTaskList(_ tasks: [OpenJarvisTaskSummary], label: String, emptyMessage: String) -> String {
    var lines: [String] = []
    lines.append(sectionTitle(String(label.prefix(1).uppercased() + label.dropFirst())))
    guard !tasks.isEmpty else {
        lines.append(emptyState(emptyMessage))
        return lines.joined(separator: "\n")
    }
    lines.append("  ID        State     Worker    Objective")
    lines.append("  --------  --------  --------  --------------------------------")
    for task in tasks {
        let state = userFacingStage(task.stage).padding(toLength: 8, withPad: " ", startingAt: 0)
        let worker = (task.worker?.displayName ?? "none").padding(toLength: 8, withPad: " ", startingAt: 0)
        let objective = clipped(task.objective, limit: 44)
        lines.append("  \(task.id.prefix(8))  \(state)  \(worker)  \(objective)")
    }
    return lines.joined(separator: "\n")
}

func printCommonCommands() {
    print(sectionTitle("Commands"))
    print("  jarvis ask \"request\"")
    print("  jarvis show TASK")
    print("  jarvis approve TASK")
    print("  jarvis send claude|codex TASK")
    print("  jarvis status")
    print("  jarvis close TASK --note \"done\"")
    print("  jarvis history TASK")
}

func suggestedCommand(for task: OpenJarvisTaskSummary) -> String {
    switch task.stage {
    case .intake, .retrieve, .assemble, .assignWorker, .validateScope, .checkpointRequirement:
        return "jarvis ask \"...\""
    case .executionReady:
        return "jarvis show \(task.id.prefix(8))"
    case .completed:
        return "jarvis close \(task.id.prefix(8)) --note \"done\""
    case .writeback:
        return "jarvis h \(task.id.prefix(8))"
    }
}

func resolveVaultStatus() -> (resolved: Bool, detail: String) {
    do {
        return (true, try OpenJarvisPaths.vaultRoot().path)
    } catch {
        return (false, String(describing: error))
    }
}

func parseScopes(_ raw: [String]) throws -> [OpenJarvisRetrievalScope]? {
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

func parseStage(_ raw: String?) throws -> OpenJarvisStage? {
    guard let raw else { return nil }
    guard let stage = OpenJarvisStage(rawValue: raw.lowercased()) else {
        throw ValidationError("Unknown stage '\(raw)'.")
    }
    return stage
}

func parseWorker(_ raw: String?) throws -> OpenJarvisWorkerKind? {
    guard let raw else { return nil }
    guard let worker = OpenJarvisWorkerKind(rawValue: raw.lowercased()) else {
        throw ValidationError("Unknown worker '\(raw)'. Use claude or codex.")
    }
    return worker
}

func inferWorker(from text: String) -> OpenJarvisWorkerKind {
    let lower = text.lowercased()
    if lower.contains("claude") { return .claude }
    return .codex
}

func parsePolicy(_ raw: String, name: String) throws -> Bool {
    switch raw.lowercased() {
    case "required":
        return true
    case "optional":
        return false
    default:
        throw ValidationError("Unknown \(name) policy '\(raw)'. Use required or optional.")
    }
}

func loadTaskID(store: OpenJarvisStore, token: String) throws -> String {
    do {
        return try store.resolveTaskID(token)
    } catch let error as NSError {
        if error.code == 409 {
            let prefix = token.uppercased()
            let matches = try store.listTasks()
                .filter { $0.id.uppercased().hasPrefix(prefix) }
                .prefix(8)
            if !matches.isEmpty {
                let details = matches.map { "\($0.id.prefix(8)) \($0.stage.rawValue) \($0.objective)" }.joined(separator: "\n  ")
                throw ValidationError("Task prefix '\(token)' is ambiguous. Matching tasks:\n  \(details)")
            }
        }
        throw ValidationError(error.localizedDescription)
    }
}

func loadTask(store: OpenJarvisStore, token: String) throws -> OpenJarvisTask {
    let taskID = try loadTaskID(store: store, token: token)
    guard let task = try store.fetchTask(id: taskID) else {
        throw ValidationError("Task '\(token)' not found.")
    }
    return task
}

func taskSummary(_ task: OpenJarvisTask, label: String) -> String {
    var lines: [String] = []
    lines.append(sectionTitle(String(label.prefix(1).uppercased() + label.dropFirst())))
    lines.append(kv("Task", String(task.id.prefix(8))))
    lines.append(kv("State", visibleLifecycleLabel(for: task.stage)))
    lines.append(kv("Worker", task.targetWorker?.displayName ?? "unassigned"))
    return lines.joined(separator: "\n")
}
