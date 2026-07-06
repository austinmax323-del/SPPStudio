import ArgumentParser
import Foundation
import OpenJarvisCore
#if canImport(Darwin)
import Darwin
#endif

@_silgen_name("readline")
private func cReadline(_ prompt: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>?

@_silgen_name("add_history")
private func cAddHistory(_ line: UnsafePointer<CChar>)

struct OpenJarvisREPL {
    var databaseURL: URL?
    private var sessionHistory: [String] = []
    private var currentTaskID: String?
    private var pasteBlockActive: Bool = false

    init(databaseURL: URL?) {
        self.databaseURL = databaseURL
    }

    mutating func run() throws {
        try printStartupDashboard(databaseURL: databaseURL)
        while true {
            guard let line = readPrompt("jarvis> ") else {
                print("")
                return
            }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            sessionHistory.append(trimmed)
            addShellHistory(trimmed)

            do {
                if try handle(trimmed) {
                    return
                }
            } catch {
                printSection("error")
                print(kv("State", "[err] failed"))
                print(kv("Detail", error.localizedDescription))
                if let hint = lifecycleGuidance(for: error) {
                    print(kv("Hint", hint))
                }
            }
        }
    }

    private mutating func handle(_ line: String) throws -> Bool {
        // Paste protection: detect common paste patterns before tokenizing
        if isPasteNoise(line) {
            if !pasteBlockActive {
                pasteBlockActive = true
                printSection("Paste Detected")
                print(kv("Try", "ask \"...\" to turn pasted notes into a packet"))
            }
            return false
        }
        pasteBlockActive = false

        var tokens = try tokenize(line)
        guard !tokens.isEmpty else { return false }
        let command = tokens.removeFirst().lowercased()

        switch command {
        case "exit", "quit", "q":
            printSection("goodbye")
            return true
        case "help", "?":
            printREPLHelp(tokens)
        case "status", "s":
            try printStatus(databaseURL: databaseURL)
        case "list", "ls":
            try printList(tokens)
        case "next", "n":
            try printNext(databaseURL: databaseURL)
        case "new":
            try createTask(tokens)
        case "auto":
            try handleAsk(tokens + ["--copy"])
        case "ask":
            try handleAsk(tokens)
        case "go":
            try handleAsk(tokens + ["--copy"])
        case "resume", "res":
            try handleResume(tokens)
        case "continue", "cont":
            try handleContinue(tokens)
        case "send":
            try handleSend(tokens)
        case "approve", "ap":
            try approve(tokens)
        case "reject", "rej":
            try reject(tokens)
        case "edit":
            try edit(tokens)
        case "recover", "rec":
            try recover(tokens)
        case "retrieve", "r":
            try retrieve(tokens)
        case "packet", "p":
            try packet(tokens)
        case "close", "c":
            try closeTask(tokens)
        case "done", "d":
            try complete(tokens)
        case "history", "h":
            try history(tokens)
        case "show":
            try show(tokens)
        case "writeback", "rb", "w":
            try writeback(tokens)
        case "open":
            try openTask(tokens)
        case "clear":
            print("\u{001B}[2J\u{001B}[H", terminator: "")
        case "repl-history":
            printSessionHistory()
        default:
            handleUnknownInput(command: command, fullLine: line)
        }
        return false
    }

    // MARK: - Natural Language Intent

    private func isPasteNoise(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return false }
        if t.hasPrefix("#") { return true }
        if t.hasPrefix("- ") || t == "-" { return true }
        if t.hasPrefix("* ") || t == "*" { return true }
        if t.hasPrefix("+ ") || t == "+" { return true }
        if t.hasPrefix("---") { return true }
        if t.range(of: #"^\d+[.)]\s"#, options: .regularExpression) != nil { return true }
        // Label pattern: "Goal:", "Required behavior:", "Tasks:" — ends with colon, only alphanum+spaces before it
        if t.hasSuffix(":") {
            let label = String(t.dropLast())
            if !label.isEmpty && label.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.union(.whitespaces).contains($0) }) {
                return true
            }
        }
        return false
    }

    private func inferWorker(from text: String) -> String? {
        let lower = text.lowercased()
        if lower.contains("codex") { return "codex" }
        if lower.contains("claude") { return "claude" }
        return nil
    }

    private mutating func handleAsk(_ tokens: [String]) throws {
        let requestTokens = tokens.filter { $0 != "--copy" && $0 != "--no-copy" }
        let request = requestTokens.joined(separator: " ")
        guard !request.isEmpty else {
            printSection("Ask")
            print(kv("Try", "ask \"review current retrieval flow for codex\""))
            return
        }
        let workerStr = inferWorker(from: request) ?? "codex"
        let scopes = inferOpenJarvisScopes(from: request)
        let neededMemory = scopes.isEmpty ? ["coordination"] : scopes.map(\.rawValue)
        let objective = request.prefix(1).uppercased() + request.dropFirst()
        let store = try OpenJarvisStore(databaseURL: databaseURL)
        let task = try store.createTask(
            from: OpenJarvisTaskDraft(
                rawRequest: request,
                interpretedObjective: objective,
                projectContext: nil,
                trustZone: "safe",
                riskLevel: "medium",
                allowedFiles: [],
                forbiddenFiles: [],
                targetWorker: try parseWorker(workerStr),
                neededMemory: neededMemory,
                checkpointRequired: true,
                validationRequired: true,
                memoryWritebackRequired: true,
                nextAction: nil,
                vaultRoot: nil
            )
        )
        currentTaskID = task.id
        let packet = try store.generatePacket(
            for: task.id,
            role: try parseWorker(workerStr),
            limit: 5,
            scopeHint: scopes.isEmpty ? nil : scopes
        )
        try recordApprovalRequested(store: store, taskID: task.id, packetText: packet.markdown)
        let storedTask = try store.fetchTask(id: task.id) ?? task
        print(renderApprovalReview(task: storedTask, packetText: packet.markdown, approval: .pending))
    }

    private mutating func handleGo(_ tokens: [String]) throws {
        let request = tokens.joined(separator: " ")
        guard !request.isEmpty else {
            printSection("go")
            print(kv("Try", "ask \"review retrieval architecture for claude\""))
            return
        }
        let workerStr = inferWorker(from: request) ?? "codex"
        let scopes = inferOpenJarvisScopes(from: request)
        let neededMemory = scopes.isEmpty ? ["coordination"] : scopes.map(\.rawValue)
        let scopeLabel = scopes.first?.rawValue ?? "coordination"
        let objective = request.prefix(1).uppercased() + request.dropFirst()
        let store = try OpenJarvisStore(databaseURL: databaseURL)
        let task = try store.createTask(
            from: OpenJarvisTaskDraft(
                rawRequest: request,
                interpretedObjective: objective,
                projectContext: nil,
                trustZone: "safe",
                riskLevel: "medium",
                allowedFiles: [],
                forbiddenFiles: [],
                targetWorker: try parseWorker(workerStr),
                neededMemory: neededMemory,
                checkpointRequired: true,
                validationRequired: true,
                memoryWritebackRequired: true,
                nextAction: nil,
                vaultRoot: nil
            )
        )
        currentTaskID = task.id
        let packet = try store.generatePacket(
            for: task.id,
            role: try parseWorker(workerStr),
            limit: 5,
            scopeHint: scopes.isEmpty ? nil : scopes
        )
        try copyToClipboard(packet.markdown)
        printSection("task ready")
        print(kv("Task", String(task.id.prefix(8))))
        print(kv("Worker", workerStr))
        print(kv("Scope", scopeLabel))
        print(kv("Context", "\(packet.retrievedContext.count) hits"))
        print(kv("Packet", "[ok] copied to clipboard"))
    }

    private mutating func handleAuto(_ tokens: [String]) throws {
        let request = tokens.joined(separator: " ")
        guard !request.isEmpty else {
            printSection("auto")
            print(kv("Try", "ask \"review current Jarvis boundary for codex\""))
            return
        }
        let workerStr = inferWorker(from: request) ?? "codex"
        let scopes = inferOpenJarvisScopes(from: request)
        let neededMemory = scopes.isEmpty ? ["coordination"] : scopes.map(\.rawValue)
        let objective = request.prefix(1).uppercased() + request.dropFirst()
        let store = try OpenJarvisStore(databaseURL: databaseURL)

        printSection("auto  1/4  creating task")
        let task = try store.createTask(
            from: OpenJarvisTaskDraft(
                rawRequest: request,
                interpretedObjective: objective,
                projectContext: nil,
                trustZone: "safe",
                riskLevel: "medium",
                allowedFiles: [],
                forbiddenFiles: [],
                targetWorker: try parseWorker(workerStr),
                neededMemory: neededMemory,
                checkpointRequired: true,
                validationRequired: true,
                memoryWritebackRequired: true,
                nextAction: nil,
                vaultRoot: nil
            )
        )
        currentTaskID = task.id
        print(kv("Task", String(task.id.prefix(8))))

        printSection("auto  2/4  retrieving context")
        var queryParts: [String] = [objective]
        let normalizedObjective = objective.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedRequest = request.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedRequest != normalizedObjective { queryParts.append(request) }
        queryParts.append(contentsOf: neededMemory)
        let retrievalQuery = queryParts.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: " ")
        let hits = try store.retrieveContext(for: task.id, query: retrievalQuery, scopeHint: scopes.isEmpty ? nil : scopes, limit: 8)
        print(kv("Hits", "\(hits.count)"))

        printSection("auto  3/4  generating packet")
        let packet = try store.generatePacket(for: task.id, role: try parseWorker(workerStr), limit: 5, scopeHint: nil)
        print(kv("Context", "\(packet.retrievedContext.count) hits"))

        printSection("auto  4/4  copying to clipboard")
        try copyToClipboard(packet.markdown)
        try store.recordEvent(taskID: task.id, type: "task.autopilot_launch", payload: [
            "worker": workerStr,
            "hit_count": "\(packet.retrievedContext.count)"
        ])
        print(kv("Packet", "[ok] copied to clipboard"))
        print("")
        printSection("ready")
        print(kv("Task", String(task.id.prefix(8))))
        print(kv("Worker", OpenJarvisWorkerKind(rawValue: workerStr)?.displayName ?? workerStr))
        print(kv("Context", "\(packet.retrievedContext.count) hits"))
        print(kv("Packet", "[ok] copied to clipboard"))
        print("")
        print(kv("Next", "paste into \(OpenJarvisWorkerKind(rawValue: workerStr)?.displayName ?? workerStr)"))
        print(kv("Then", "close \(task.id.prefix(8)) --note \"done\""))
    }

    private mutating func handleResume(_ tokens: [String]) throws {
        let parsed = try parseREPLFlags(tokens)
        let store = try OpenJarvisStore(databaseURL: parsed.databaseURL ?? databaseURL)
        let allTasks = try store.listTasks()
        guard let summary = allTasks.first(where: { $0.completionState == .open }) ?? allTasks.first else {
            printSection("resume")
            print(emptyState("no tasks found"))
            print(kv("Try", "ask \"your request\""))
            return
        }
        currentTaskID = summary.id
        let brief = try store.buildBriefRecoveryContext(for: summary.id)
        let full = try store.buildRecoveryContext(for: summary.id)
        print(brief)
        try copyToClipboard(full)
        print("")
        printSection("full recovery copied to clipboard")
        print(kv("Task", String(summary.id.prefix(8))))
        print(kv("State", visibleLifecycleLabel(for: summary.stage)))
        print(kv("Worker", summary.worker?.displayName ?? "unassigned"))
        print(kv("Next", "paste into \(summary.worker?.displayName ?? "your worker")"))
    }

    private mutating func handleContinue(_ tokens: [String]) throws {
        let parsed = try parseREPLFlags(tokens)
        let store = try OpenJarvisStore(databaseURL: parsed.databaseURL ?? databaseURL)
        let taskID: String
        if let token = parsed.positionals.first {
            taskID = try loadTaskID(store: store, token: token)
        } else if let id = currentTaskID {
            taskID = id
        } else if let latest = try store.listTasks().first(where: { $0.completionState == .open }) {
            taskID = latest.id
        } else {
            printSection("continue")
            print(emptyState("no open tasks"))
            print(kv("Try", "ask \"your request\"  or  recover --session"))
            return
        }
        guard let task = try store.fetchTask(id: taskID) else {
            throw ValidationError("Task '\(taskID)' not found.")
        }
        currentTaskID = taskID
        let isTerminal = task.stage == .completed || task.stage == .writeback
        let content: String
        let mode: String
        if isTerminal || task.packetText != nil && task.stage == .executionReady {
            content = try store.buildBriefRecoveryContext(for: taskID)
            mode = "brief recovery"
        } else {
            let packet = try store.generatePacket(for: taskID, role: task.targetWorker, limit: 5, scopeHint: nil)
            content = packet.markdown
            mode = "packet"
        }
        print(content)
        try copyToClipboard(content)
        print("")
        printSection("copied \(mode) to clipboard")
        print(kv("Task", String(taskID.prefix(8))))
        print(kv("State", visibleLifecycleLabel(for: task.stage)))
        print(kv("Worker", task.targetWorker?.displayName ?? "unassigned"))
        if mode == "packet" {
            print(kv("Next", "paste packet into \(task.targetWorker?.displayName ?? "your worker")"))
        } else {
            print(kv("Next", "share context with \(task.targetWorker?.displayName ?? "your worker")"))
        }
    }

    private mutating func handleSend(_ tokens: [String]) throws {
        let parsed = try parseREPLFlags(tokens)
        guard !tokens.isEmpty else {
            printSection("Send")
            print(kv("Try", "send claude [task]"))
            print(kv("Try", "send codex [task]"))
            return
        }
        let rawPositionals = parsed.positionals
        var workerName = parsed.value("worker")
        let taskToken: String?
        if let first = rawPositionals.first, ["claude", "codex"].contains(first.lowercased()) {
            workerName = workerName ?? first.lowercased()
            taskToken = rawPositionals.dropFirst().first
        } else {
            taskToken = rawPositionals.first
        }
        let result = try performWorkerSend(
            databaseURL: parsed.databaseURL ?? databaseURL,
            currentTaskID: currentTaskID,
            workerName: workerName,
            taskToken: taskToken,
            dryRun: parsed.hasFlag("dry-run"),
            assumeYes: parsed.hasFlag("yes"),
            cwdOverride: parsed.value("cwd"),
            vaultOverride: parsed.value("vault"),
            verbose: parsed.hasFlag("verbose"),
            artifactVerbose: parsed.hasFlag("artifact-verbose")
        )
        currentTaskID = result.taskID
    }

    private func lifecycleGuidance(for error: Error) -> String? {
        let msg = error.localizedDescription
        guard msg.contains("Invalid transition from") else { return nil }
        let preReady = ["intake", "retrieve", "assemble", "assign_worker", "validate_scope", "checkpoint_requirement"]
        for stage in preReady where msg.contains("from \(stage)") {
            return "try: ask \"...\""
        }
        if msg.contains("from execution_ready") { return "hint: close --note \"done\"" }
        if msg.contains("from completed") { return "hint: close --note \"done\"" }
        if msg.contains("from writeback") { return "task is archived" }
        return nil
    }

    private func handleUnknownInput(command: String, fullLine: String) {
        let wordCount = fullLine.split(separator: " ").count
        if wordCount >= 3 {
            let workerStr = inferWorker(from: fullLine) ?? "codex"
            let scopes = inferOpenJarvisScopes(from: fullLine)
            let scopeStr = scopes.first?.rawValue ?? "coordination"
            let objective = fullLine.prefix(1).uppercased() + fullLine.dropFirst()
            printSection("Looks like a request")
            print(kv("Try", "ask \"\(objective)\""))
            print(kv("Worker", OpenJarvisWorkerKind(rawValue: workerStr)?.displayName ?? workerStr))
            print(kv("Scope", scopeStr))
        } else {
            printSection("Unknown Command")
            print(kv("Input", command))
            print(kv("Try", "help"))
        }
    }

    private func printList(_ tokens: [String]) throws {
        let options = try parseREPLFlags(tokens)
        let store = try OpenJarvisStore(databaseURL: options.databaseURL ?? databaseURL)
        let stage = try parseStage(options.value("stage"))
        print(renderTaskList(try store.listTasks(stage: stage), label: "tasks", emptyMessage: "no tasks"))
    }

    private mutating func createTask(_ tokens: [String]) throws {
        let parsed = try parseREPLFlags(tokens)
        guard let request = parsed.positionals.first else {
            throw ValidationError("Usage: new \"task\" [--context SPPStudio] [--worker codex] [--memory coordination]")
        }
        let store = try OpenJarvisStore(databaseURL: parsed.databaseURL ?? databaseURL)
        let task = try store.createTask(
            from: OpenJarvisTaskDraft(
                rawRequest: request,
                interpretedObjective: parsed.value("objective") ?? request,
                projectContext: parsed.value("context"),
                trustZone: parsed.value("trust-zone") ?? "safe",
                riskLevel: parsed.value("risk-level") ?? "medium",
                allowedFiles: parsed.values("allowed-file"),
                forbiddenFiles: parsed.values("forbidden-file"),
                targetWorker: try parseWorker(parsed.value("worker")),
                neededMemory: parsed.values("memory"),
                checkpointRequired: try parsePolicy(parsed.value("checkpoint") ?? "required", name: "checkpoint"),
                validationRequired: try parsePolicy(parsed.value("validation") ?? "required", name: "validation"),
                memoryWritebackRequired: try parsePolicy(parsed.value("writeback") ?? "required", name: "writeback"),
                nextAction: parsed.value("next-action"),
                vaultRoot: parsed.value("vault")
            )
        )
        currentTaskID = task.id
        let workerLabel = task.targetWorker?.rawValue ?? "unassigned"
        let scopeLabel = task.neededMemory.first ?? "none"
        printSection("Created")
        print(kv("Task", String(task.id.prefix(8))))
        print(kv("Worker", workerLabel))
        print(kv("Context", scopeLabel))
        print("")
        print(kv("Next", "packet --copy"))
    }

    private mutating func retrieve(_ tokens: [String]) throws {
        let parsed = try parseREPLFlags(tokens)
        let store = try OpenJarvisStore(databaseURL: parsed.databaseURL ?? databaseURL)
        let limit = try parsed.intValue("limit") ?? 8
        let scopes = try parseScopes(parsed.values("scope"))
        if parsed.positionals.first != nil || parsed.value("query") == nil {
            let taskID = try selectedTaskID(store: store, parsed: parsed, action: "retrieve")
            guard let task = try store.fetchTask(id: taskID) else {
                throw ValidationError("Task '\(taskID)' not found.")
            }
            let queryText = parsed.value("query") ?? [task.interpretedObjective, task.rawRequest, task.neededMemory.joined(separator: " ")].joined(separator: " ")
            printAutoSelectionIfNeeded(parsed: parsed, taskID: taskID)
            let hits = try store.retrieveContext(for: taskID, query: queryText, scopeHint: scopes, limit: limit)
            currentTaskID = taskID
            print(renderRetrieval(taskID: taskID, query: queryText, hits: hits))
        } else if let queryText = parsed.value("query") {
            let vault = try OpenJarvisPaths.vaultRoot()
            let engine = OpenJarvisRetrievalEngine(vaultRoot: vault)
            let hits = try engine.retrieve(OpenJarvisRetrievalRequest(query: queryText, scopes: scopes ?? inferOpenJarvisScopes(from: queryText), limit: limit))
            try store.recordEvent(taskID: nil, type: "retrieval.preview", payload: [
                "query": queryText,
                "hit_count": "\(hits.count)"
            ])
            print(renderRetrieval(taskID: nil, query: queryText, hits: hits))
        } else {
            throw ValidationError("Usage: retrieve TASK [--scope coordination] or retrieve --query \"text\"")
        }
    }

    private mutating func packet(_ tokens: [String]) throws {
        let parsed = try parseREPLFlags(tokens)
        let store = try OpenJarvisStore(databaseURL: parsed.databaseURL ?? databaseURL)
        let taskID = try selectedTaskID(store: store, parsed: parsed, action: "packet")
        printAutoSelectionIfNeeded(parsed: parsed, taskID: taskID)
        let packet = try store.generatePacket(
            for: taskID,
            role: parsed.value("role").flatMap(OpenJarvisWorkerKind.init(rawValue:)),
            limit: try parsed.intValue("limit") ?? 5,
            scopeHint: try parseScopes(parsed.values("scope"))
        )
        currentTaskID = taskID
        print(packet.markdown)
        if parsed.hasFlag("copy") {
            try copyToClipboard(packet.markdown)
            print("")
            printSection("copied packet to clipboard")
        }
    }

    private mutating func complete(_ tokens: [String]) throws {
        let parsed = try parseREPLFlags(tokens)
        let store = try OpenJarvisStore(databaseURL: parsed.databaseURL ?? databaseURL)
        let taskID = try selectedTaskID(store: store, parsed: parsed, action: "done")
        printAutoSelectionIfNeeded(parsed: parsed, taskID: taskID)
        let task = try store.completeTask(id: taskID, note: parsed.value("note"))
        currentTaskID = task.id
        print(renderTaskBrief(task))
    }

    private mutating func writeback(_ tokens: [String]) throws {
        let parsed = try parseREPLFlags(tokens)
        let store = try OpenJarvisStore(databaseURL: parsed.databaseURL ?? databaseURL)
        let taskID = try selectedTaskID(store: store, parsed: parsed, action: "writeback")
        printAutoSelectionIfNeeded(parsed: parsed, taskID: taskID)
        let task = try store.writebackTask(id: taskID, note: parsed.value("note"))
        currentTaskID = task.id
        print(renderTaskBrief(task))
    }

    private mutating func closeTask(_ tokens: [String]) throws {
        let parsed = try parseREPLFlags(tokens)
        let store = try OpenJarvisStore(databaseURL: parsed.databaseURL ?? databaseURL)
        let taskID = try selectedTaskID(store: store, parsed: parsed, action: "close")
        printAutoSelectionIfNeeded(parsed: parsed, taskID: taskID)
        let note = parsed.value("note") ?? "closed"
        guard let task = try store.fetchTask(id: taskID) else {
            throw ValidationError("Task '\(taskID)' not found.")
        }
        switch task.stage {
        case .writeback:
            printSection("Archived")
            print(kv("Task", String(taskID.prefix(8))))
        case .completed:
            let final = try store.writebackTask(id: taskID, note: note)
            currentTaskID = final.id
            print(renderTaskBrief(final))
        default:
            _ = try store.completeTask(id: taskID, note: note)
            let final = try store.writebackTask(id: taskID, note: note)
            currentTaskID = final.id
            print(renderTaskBrief(final))
        }
    }

    private mutating func recover(_ tokens: [String]) throws {
        let parsed = try parseREPLFlags(tokens)
        let store = try OpenJarvisStore(databaseURL: parsed.databaseURL ?? databaseURL)

        if parsed.hasFlag("session") {
            let context = try store.buildSessionRecoveryContext()
            print(context)
            if parsed.hasFlag("copy") {
                try copyToClipboard(context)
                print("")
                printSection("copied session recovery to clipboard")
            }
            return
        }

        let taskID: String
        if let token = parsed.positionals.first {
            taskID = try loadTaskID(store: store, token: token)
        } else if let id = currentTaskID {
            taskID = id
        } else if let latest = try store.listTasks().first {
            taskID = latest.id
        } else {
            throw ValidationError("No tasks found. Use: ask \"your request\"")
        }
        printAutoSelectionIfNeeded(parsed: parsed, taskID: taskID)

        let context: String
        if parsed.hasFlag("brief") {
            context = try store.buildBriefRecoveryContext(for: taskID)
        } else {
            context = try store.buildRecoveryContext(for: taskID)
        }
        currentTaskID = taskID
        print(context)
        if parsed.hasFlag("copy") {
            try copyToClipboard(context)
            print("")
            printSection("copied recovery context to clipboard")
        }
    }

    private func renderTaskBrief(_ task: OpenJarvisTask) -> String {
        var lines: [String] = []
        lines.append(sectionTitle(visibleLifecycleLabel(for: task.stage) == "archived" ? "Archived" : "Task"))
        lines.append(kv("ID", String(task.id.prefix(8))))
        lines.append(kv("State", visibleLifecycleLabel(for: task.stage)))
        lines.append(kv("Worker", task.targetWorker?.displayName ?? "unassigned"))
        return lines.joined(separator: "\n")
    }

    private mutating func history(_ tokens: [String]) throws {
        let parsed = try parseREPLFlags(tokens)
        let limit = try parsed.intValue("limit") ?? 20
        guard limit > 0 else {
            throw ValidationError("History limit must be greater than 0.")
        }
        let store = try OpenJarvisStore(databaseURL: parsed.databaseURL ?? databaseURL)
        let taskID = try selectedTaskID(store: store, parsed: parsed, action: "history")
        printAutoSelectionIfNeeded(parsed: parsed, taskID: taskID)
        let events = try store.listTaskEvents(taskID: taskID, type: parsed.value("type"), limit: limit)
        currentTaskID = taskID
        print(renderHistory(taskID: taskID, events: events, type: parsed.value("type"), limit: limit))
    }

    private mutating func show(_ tokens: [String]) throws {
        let parsed = try parseREPLFlags(tokens)
        let store = try OpenJarvisStore(databaseURL: parsed.databaseURL ?? databaseURL)
        let taskID = try selectedTaskID(store: store, parsed: parsed, action: "show")
        printAutoSelectionIfNeeded(parsed: parsed, taskID: taskID)
        let task = try loadTask(store: store, token: taskID)
        currentTaskID = task.id
        if let packetText = task.packetText, !packetText.isEmpty {
            let approval = try approvalState(store: store, taskID: task.id)
            print(renderApprovalReview(task: task, packetText: packetText, approval: approval))
        } else {
            print(render(task: task))
        }
    }

    private mutating func approve(_ tokens: [String]) throws {
        let parsed = try parseREPLFlags(tokens)
        let store = try OpenJarvisStore(databaseURL: parsed.databaseURL ?? databaseURL)
        let taskID = try selectedTaskID(store: store, parsed: parsed, action: "approve")
        printAutoSelectionIfNeeded(parsed: parsed, taskID: taskID)
        let task = try approveTask(store: store, token: taskID, copy: !parsed.hasFlag("no-copy"))
        currentTaskID = task.id
        print(renderApprovalDecision(task: task, state: .approved, copied: !parsed.hasFlag("no-copy")))
    }

    private mutating func reject(_ tokens: [String]) throws {
        let parsed = try parseREPLFlags(tokens)
        let store = try OpenJarvisStore(databaseURL: parsed.databaseURL ?? databaseURL)
        let taskID = try selectedTaskID(store: store, parsed: parsed, action: "reject")
        printAutoSelectionIfNeeded(parsed: parsed, taskID: taskID)
        let task = try rejectTask(store: store, token: taskID, note: parsed.value("note"))
        currentTaskID = task.id
        print(renderApprovalDecision(task: task, state: .rejected, copied: false))
    }

    private mutating func edit(_ tokens: [String]) throws {
        let parsed = try parseREPLFlags(tokens)
        let store = try OpenJarvisStore(databaseURL: parsed.databaseURL ?? databaseURL)
        let taskID = try selectedTaskID(store: store, parsed: parsed, action: "edit")
        printAutoSelectionIfNeeded(parsed: parsed, taskID: taskID)
        let task = try editTaskPacket(store: store, token: taskID)
        currentTaskID = task.id
        let approval = try approvalState(store: store, taskID: task.id)
        print(renderApprovalReview(task: task, packetText: task.packetText ?? "", approval: approval))
    }

    private mutating func openTask(_ tokens: [String]) throws {
        let parsed = try parseREPLFlags(tokens)
        let store = try OpenJarvisStore(databaseURL: parsed.databaseURL ?? databaseURL)
        let taskID = try selectedTaskID(store: store, parsed: parsed, action: "open")
        printAutoSelectionIfNeeded(parsed: parsed, taskID: taskID)
        let task = try loadTask(store: store, token: taskID)
        let vault = try OpenJarvisPaths.vaultRoot()
        let candidates = task.retrievedContext.map(\.path) + task.allowedFiles
        guard let path = candidates.first else {
            throw ValidationError("Task has no retrieved context or allowed files to open.")
        }
        let target = path.hasPrefix("/") ? URL(fileURLWithPath: path) : vault.appendingPathComponent(path)
        try openURL(target)
        printSection("opened")
        print(kv("Path", target.path))
    }

    private func selectedTaskID(store: OpenJarvisStore, parsed: REPLParsedArguments, action: String) throws -> String {
        if let token = parsed.positionals.first {
            return try loadTaskID(store: store, token: token)
        }
        if let currentTaskID {
            return currentTaskID
        }
        if let latestOpen = try store.listTasks().first(where: { $0.completionState == .open }) {
            return latestOpen.id
        }
        throw ValidationError("No open task. Use: ask \"your request\"")
    }

    private func printAutoSelectionIfNeeded(parsed: REPLParsedArguments, taskID: String) {
        guard parsed.positionals.isEmpty else { return }
        print(kv("Task", "\(taskID.prefix(8)) selected"))
    }

    private func printSessionHistory() {
        printSection("repl history")
        for (index, item) in sessionHistory.enumerated() {
            print("  \(index + 1). \(item)")
        }
    }
}

struct REPLParsedArguments {
    var positionals: [String] = []
    var options: [String: [String]] = [:]
    var flags: Set<String> = []

    var databaseURL: URL? {
        value("database").map { URL(fileURLWithPath: $0).standardizedFileURL }
    }

    func value(_ key: String) -> String? {
        options[key]?.last
    }

    func values(_ key: String) -> [String] {
        options[key] ?? []
    }

    func hasFlag(_ key: String) -> Bool {
        flags.contains(key)
    }

    func intValue(_ key: String) throws -> Int? {
        guard let raw = value(key) else { return nil }
        guard let value = Int(raw) else {
            throw ValidationError("--\(key) must be an integer.")
        }
        return value
    }
}

func printStartupDashboard(databaseURL: URL?) throws {
    let snapshot = try OpenJarvisStatusReader.read(databaseURL: databaseURL)
    let vaultStatus = resolveVaultStatus()
    var openCount = 0
    var recentTasks: [OpenJarvisTaskSummary] = []
    if snapshot.databaseExists {
        let allTasks = try OpenJarvisStore(databaseURL: databaseURL).listTasks()
        openCount = allTasks.filter { $0.completionState == .open }.count
        recentTasks = Array(allTasks.prefix(3))
    }

    print(sectionTitle("Jarvis Command Center"))
    print(kv("Store", "\(statusBadge(snapshot.databaseExists)) \(snapshot.databaseExists ? "ready" : "not created")"))
    print(kv("Vault", "\(statusBadge(vaultStatus.resolved)) \(vaultStatus.resolved ? "ready" : "missing")"))
    print(kv("Active", "\(openCount) open tasks"))
    if recentTasks.isEmpty {
        print(kv("Latest", "none"))
    } else {
        let latest = recentTasks[0]
        let obj = clipped(latest.objective, limit: 48)
        print(kv("Latest", "\(latest.id.prefix(8))  \(visibleLifecycleLabel(for: latest.stage))  \(obj)"))
    }
    print("")
    print("  Commands  ask | send | status | close | history")
    print("  Help      help --advanced")
}

func printStatus(databaseURL: URL?) throws {
    print(renderStatus(snapshot: try OpenJarvisStatusReader.read(databaseURL: databaseURL), vaultStatus: resolveVaultStatus()))
}

func printNext(databaseURL: URL?) throws {
    let snapshot = try OpenJarvisStatusReader.read(databaseURL: databaseURL)
    guard snapshot.databaseExists else {
        printSection("next")
        print(emptyState("database does not exist yet"))
        print(kv("Try", "ask \"your task\""))
        return
    }

    let store = try OpenJarvisStore(databaseURL: databaseURL)
    guard let task = try store.listTasks().first(where: { $0.completionState == .open }) else {
        printSection("next")
        print(emptyState("no open tasks"))
        print(kv("Try", "ask \"your request\"  or  recover --session"))
        return
    }

    let suggested: String
    if task.stage == .writeback {
        suggested = "recover \(task.id.prefix(8))"
    } else {
        suggested = suggestedCommand(for: task).replacingOccurrences(of: "jarvis ", with: "")
    }
    printSection("next")
    print(kv("Task", String(task.id.prefix(8))))
    print(kv("Goal", clipped(task.objective, limit: 72)))
    print(kv("State", userFacingStage(task.stage)))
    print(kv("Worker", task.worker?.displayName ?? "unassigned"))
    print(kv("Next", suggested))
}

func printREPLHelp(_ tokens: [String] = []) {
    if tokens.contains("--advanced") {
        printSection("Advanced")
        print(kv("Context", "retrieve [task] [--scope runtime]"))
        print(kv("Packet", "packet [task] [--copy]"))
        print(kv("Recover", "recover [task] [--copy]"))
        print(kv("Inspect", "list | show | open"))
        print(kv("Archive", "done | writeback"))
        print(kv("Create", "new \"task\" --worker codex --memory coordination"))
        print("")
        print(kv("Aliases", "go, auto, resume, continue, next"))
        return
    }

    printSection("Commands")
    print(kv("ask", "\"request\"             create review packet"))
    print(kv("show", "[task]                inspect generated prompt"))
    print(kv("approve", "[task]              approve and copy packet"))
    print(kv("send", "claude|codex [task]   run approved worker"))
    print(kv("status", "show active work"))
    print(kv("close", "[task] --note done   archive task"))
    print(kv("history", "[task]             show audit trail"))
    print("")
    print(kv("More", "help --advanced"))
}

struct WorkerSendResult {
    let taskID: String
    let outputFileName: String?
}

private struct GitSnapshot {
    let isRepo: Bool
    let statusShort: String
    let diffNameStatus: String
    let diffStat: String
    let error: String?
}

func performWorkerSend(
    databaseURL: URL?,
    currentTaskID: String?,
    workerName: String?,
    taskToken: String?,
    dryRun: Bool,
    assumeYes: Bool,
    cwdOverride: String?,
    vaultOverride: String?,
    verbose: Bool,
    artifactVerbose: Bool
) throws -> WorkerSendResult {
    let store = try OpenJarvisStore(databaseURL: databaseURL)

    let taskID: String
    if let token = taskToken {
        taskID = try loadTaskID(store: store, token: token)
    } else if let currentTaskID {
        taskID = currentTaskID
    } else if let latest = try store.listTasks().first(where: { $0.completionState == .open }) {
        taskID = latest.id
    } else {
        throw ValidationError("No open task. Use: ask \"your request\"")
    }
    guard let task = try store.fetchTask(id: taskID) else {
        throw ValidationError("Task '\(taskID)' not found.")
    }

    let workerStr: String
    if let workerName {
        workerStr = workerName.lowercased()
    } else if let taskWorker = task.targetWorker, taskWorker != .localModel {
        workerStr = taskWorker.rawValue
    } else {
        throw ValidationError("No worker resolved. Use: send claude [TASK]  or  send codex [TASK]")
    }
    guard let worker = OpenJarvisWorkerKind(rawValue: workerStr), worker != .localModel else {
        throw ValidationError("Worker '\(workerStr)' not supported for send. Use: claude or codex")
    }

    let binaryPath = try resolveWorkerBinary(workerStr)
    let packetText: String
    if let existing = task.packetText, !existing.isEmpty {
        packetText = existing
    } else {
        let packet = try store.generatePacket(for: taskID, role: worker, limit: 5, scopeHint: nil)
        packetText = packet.markdown
        try recordApprovalRequested(store: store, taskID: taskID, packetText: packetText)
    }

    if !dryRun {
        try requireApprovalForSend(store: store, taskID: taskID)
    }

    let workerArgs: [String]
    switch worker {
    case .claude:
        workerArgs = ["-p", "--no-session-persistence"]
    case .codex:
        workerArgs = ["exec"]
    case .localModel:
        fatalError("unreachable")
    }

    let resolvedCwd = cwdOverride ?? detectGitRepoRoot() ?? FileManager.default.currentDirectoryPath
    guard FileManager.default.fileExists(atPath: resolvedCwd) else {
        throw ValidationError("Working directory does not exist: \(resolvedCwd)")
    }

    let resolvedVault: String?
    if let vaultOverride {
        resolvedVault = vaultOverride
    } else if let taskVault = task.vaultRoot, !taskVault.isEmpty {
        resolvedVault = taskVault
    } else {
        resolvedVault = try? OpenJarvisPaths.vaultRoot().path
    }
    if let v = resolvedVault, !FileManager.default.fileExists(atPath: v) {
        throw ValidationError("Vault path does not exist: \(v)")
    }

    let vaultURL = try resolvedVault.map { URL(fileURLWithPath: $0) } ?? OpenJarvisPaths.vaultRoot()
    let runDir = vaultURL.appendingPathComponent("70_SessionContinuity/WorkerRuns")
    try FileManager.default.createDirectory(at: runDir, withIntermediateDirectories: true)

    let formatter = workerArtifactDateFormatter()
    let ts = formatter.string(from: Date())
        .replacingOccurrences(of: ":", with: "-")
        .replacingOccurrences(of: ".", with: "-")
    let outputFileName = "\(ts)-\(taskID.prefix(8).lowercased())-\(workerStr).md"
    let outputURL = runDir.appendingPathComponent(outputFileName)

    let displayCmd: String
    switch worker {
    case .claude:
        displayCmd = "claude -p --no-session-persistence  [\(packetText.count) chars via stdin]"
    case .codex:
        displayCmd = "codex exec  [\(packetText.count) chars via stdin]"
    case .localModel:
        fatalError("unreachable")
    }

    let beforeGit = captureGitSnapshot(cwd: resolvedCwd)

    printSection("Send to \(worker.displayName)?")
    print(kv("Task", String(taskID.prefix(8))))
    print(kv("Output", "WorkerRuns/\(outputFileName)"))
    if verbose || dryRun {
        print("")
        print(kv("CWD", resolvedCwd))
        if let v = resolvedVault { print(kv("Vault", v)) }
        print(kv("Packet", "\(packetText.count) chars"))
        print(kv("Command", displayCmd))
        print(kv("Git", beforeGit.isRepo ? "repo" : "not a repo"))
    }

    if dryRun {
        print("")
        print(kv("State", "[ok] dry run only; no worker launched"))
        return WorkerSendResult(taskID: taskID, outputFileName: nil)
    }

    if !assumeYes {
        print("")
        print("  Run? [y/N] ", terminator: "")
        guard let answer = readLine(strippingNewline: true)?.trimmingCharacters(in: .whitespaces).lowercased(),
              answer == "y" || answer == "yes" else {
            print(kv("State", "[warn] aborted"))
            return WorkerSendResult(taskID: taskID, outputFileName: nil)
        }
    }

    try store.recordEvent(taskID: taskID, type: "task.worker_invoked", payload: [
        "worker": workerStr,
        "output_file": outputFileName
    ])

    printSection("Running \(worker.displayName)")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: binaryPath)
    process.arguments = workerArgs
    process.currentDirectoryURL = URL(fileURLWithPath: resolvedCwd)
    var workerEnv = ProcessInfo.processInfo.environment
    if let v = resolvedVault { workerEnv["OPENJARVIS_VAULT"] = v }
    process.environment = workerEnv
    let stdinPipe = Pipe()
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardInput = stdinPipe
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe
    try process.run()
    DispatchQueue.global().async {
        stdinPipe.fileHandleForWriting.write(Data(packetText.utf8))
        try? stdinPipe.fileHandleForWriting.close()
    }
    let stdout = String(decoding: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    let stderr = String(decoding: stderrPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    process.waitUntilExit()
    let exitCode = Int(process.terminationStatus)
    let afterGit = captureGitSnapshot(cwd: resolvedCwd)
    let invokedAt = formatter.string(from: Date())

    let artifact = renderWorkerRunArtifact(
        task: task,
        worker: worker,
        displayCommand: displayCmd,
        resolvedCwd: resolvedCwd,
        resolvedVault: resolvedVault,
        invokedAt: invokedAt,
        exitCode: exitCode,
        beforeGit: beforeGit,
        afterGit: afterGit,
        stdout: stdout,
        stderr: stderr,
        artifactVerbose: artifactVerbose
    )
    try artifact.write(to: outputURL, atomically: true, encoding: .utf8)

    try store.recordEvent(taskID: taskID, type: "task.worker_response_saved", payload: [
        "worker": workerStr,
        "exit_code": "\(exitCode)",
        "output_file": outputFileName,
        "response_chars": "\(stdout.count)"
    ])

    print("")
    printSection(exitCode == 0 ? "Saved" : "Worker exited \(exitCode)")
    print(kv("Exit", exitCode == 0 ? "[ok] 0" : "[err] \(exitCode)"))
    print(kv("Output", "WorkerRuns/\(outputFileName)"))
    if !stdout.isEmpty {
        let previewLines = usefulPreview(stdout).components(separatedBy: "\n").prefix(6)
        print("")
        for line in previewLines { print("  │ \(line)") }
    }
    print("")
    print(kv("Next", "review diff, then close \(taskID.prefix(8)) --note \"done\""))
    return WorkerSendResult(taskID: taskID, outputFileName: outputFileName)
}

private func renderWorkerRunArtifact(
    task: OpenJarvisTask,
    worker: OpenJarvisWorkerKind,
    displayCommand: String,
    resolvedCwd: String,
    resolvedVault: String?,
    invokedAt: String,
    exitCode: Int,
    beforeGit: GitSnapshot,
    afterGit: GitSnapshot,
    stdout: String,
    stderr: String,
    artifactVerbose: Bool
) -> String {
    var lines: [String] = []
    lines.append("# Worker Run")
    lines.append("")
    lines.append("## Summary")
    lines.append("- Task: \(task.interpretedObjective)")
    lines.append("- Worker: \(worker.displayName)")
    lines.append("- Exit: \(exitCode)")
    lines.append("- Time: \(invokedAt)")
    lines.append("- CWD: \(resolvedCwd)")
    lines.append("- Vault: \(resolvedVault ?? "(unresolved)")")
    lines.append("")
    lines.append("## Review First")
    appendReviewFirst(afterGit, to: &lines)
    lines.append("")
    lines.append("## Changed Files")
    appendGitNameStatus(afterGit, to: &lines)
    lines.append("")
    lines.append("## Diff Stat")
    appendGitDiffStat(afterGit, to: &lines)
    lines.append("")
    lines.append("## Review Checklist")
    lines.append("- Build/test result: Not determined by Jarvis. Review worker output and run verification.")
    lines.append("- Files to inspect: \(filesToInspect(from: afterGit))")
    lines.append("- Risk: Manual review required. Jarvis does not infer risk from worker text.")
    lines.append("- Follow-up: Review diff, run tests, then close task when validated.")
    if artifactVerbose {
        lines.append("")
        lines.append("## Git Snapshot Before")
        appendGitSnapshot(beforeGit, to: &lines)
        lines.append("")
        lines.append("## Git Snapshot After")
        appendGitSnapshot(afterGit, to: &lines)
    }
    lines.append("")
    lines.append("## Worker Response Preview")
    lines.append("")
    lines.append(usefulPreview(stdout))
    lines.append("")
    lines.append("## Full Transcript")
    lines.append("")
    lines.append("Command: \(displayCommand)")
    lines.append("")
    lines.append("### stdout")
    lines.append("")
    lines.append(fencedText(stdout.isEmpty ? "(no stdout)" : stdout))
    lines.append("")
    lines.append("### stderr")
    lines.append("")
    lines.append(fencedText(stderr.isEmpty ? "(no stderr)" : stderr))
    return lines.joined(separator: "\n")
}

private func appendGitNameStatus(_ snapshot: GitSnapshot, to lines: inout [String]) {
    guard snapshot.isRepo else {
        lines.append("- Not a git repository at CWD.")
        if let error = snapshot.error { lines.append("- Git error: \(error)") }
        return
    }
    let value = snapshot.diffNameStatus.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.isEmpty {
        lines.append("- No working tree changes detected by git diff --name-status.")
        return
    }
    for line in value.components(separatedBy: "\n") where !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        lines.append("- \(line)")
    }
}

private func appendReviewFirst(_ snapshot: GitSnapshot, to lines: inout [String]) {
    guard snapshot.isRepo else {
        lines.append("Not a git repository at CWD.")
        return
    }
    let files = changedFiles(from: snapshot)
    guard !files.isEmpty else {
        lines.append("No changed files detected.")
        return
    }
    lines.append("- Inspect:")
    for file in files {
        lines.append("  - \(file)")
    }
    lines.append("- Command:")
    for file in files {
        lines.append("  - git diff -- \(shellQuoted(file))")
    }
}

private func appendGitDiffStat(_ snapshot: GitSnapshot, to lines: inout [String]) {
    guard snapshot.isRepo else {
        lines.append("Not a git repository at CWD.")
        return
    }
    let value = snapshot.diffStat.trimmingCharacters(in: .whitespacesAndNewlines)
    lines.append(value.isEmpty ? "No diff stat." : fencedText(value))
}

private func appendGitSnapshot(_ snapshot: GitSnapshot, to lines: inout [String]) {
    guard snapshot.isRepo else {
        lines.append("Not a git repository at CWD.")
        if let error = snapshot.error { lines.append("Git error: \(error)") }
        return
    }
    lines.append("### git status --short")
    lines.append(fencedText(snapshot.statusShort.isEmpty ? "(clean)" : snapshot.statusShort))
    lines.append("")
    lines.append("### git diff --name-status")
    lines.append(fencedText(snapshot.diffNameStatus.isEmpty ? "(empty)" : snapshot.diffNameStatus))
    lines.append("")
    lines.append("### git diff --stat")
    lines.append(fencedText(snapshot.diffStat.isEmpty ? "(empty)" : snapshot.diffStat))
}

private func filesToInspect(from snapshot: GitSnapshot) -> String {
    guard snapshot.isRepo else { return "CWD is not a git repository" }
    let files = changedFiles(from: snapshot)
    guard !files.isEmpty else { return "None from git diff --name-status" }
    return files.joined(separator: ", ")
}

private func changedFiles(from snapshot: GitSnapshot) -> [String] {
    guard snapshot.isRepo else { return [] }
    return snapshot.diffNameStatus
        .components(separatedBy: "\n")
        .compactMap { line -> String? in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard let path = fields.last.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !path.isEmpty
            else { return nil }
            return path
        }
}

private func usefulPreview(_ stdout: String) -> String {
    let trimmedLines = stdout
        .components(separatedBy: "\n")
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    let preview = trimmedLines.prefix(10).joined(separator: "\n")
    if preview.isEmpty { return "(no stdout)" }
    if preview.count <= 1200 { return preview }
    let index = preview.index(preview.startIndex, offsetBy: 1200)
    return String(preview[..<index]) + "\n... truncated ..."
}

private func fencedText(_ text: String) -> String {
    "````text\n\(text)\n````"
}

private func shellQuoted(_ value: String) -> String {
    guard !value.isEmpty else { return "''" }
    let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "/._-"))
    if value.unicodeScalars.allSatisfy({ safe.contains($0) }) {
        return value
    }
    return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

private func captureGitSnapshot(cwd: String) -> GitSnapshot {
    let inside = runGit(["rev-parse", "--is-inside-work-tree"], cwd: cwd)
    guard inside.exitCode == 0, inside.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "true" else {
        return GitSnapshot(isRepo: false, statusShort: "", diffNameStatus: "", diffStat: "", error: inside.stderr.trimmedOrNil)
    }
    return GitSnapshot(
        isRepo: true,
        statusShort: runGit(["status", "--short"], cwd: cwd).stdout.trimmingCharacters(in: .whitespacesAndNewlines),
        diffNameStatus: runGit(["diff", "--name-status"], cwd: cwd).stdout.trimmingCharacters(in: .whitespacesAndNewlines),
        diffStat: runGit(["diff", "--stat"], cwd: cwd).stdout.trimmingCharacters(in: .whitespacesAndNewlines),
        error: nil
    )
}

private func runGit(_ args: [String], cwd: String) -> (exitCode: Int, stdout: String, stderr: String) {
    runProcess("/usr/bin/git", arguments: ["-C", cwd] + args, cwd: nil, stdin: nil)
}

private func runProcess(_ executable: String, arguments: [String], cwd: String?, stdin: String?) -> (exitCode: Int, stdout: String, stderr: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    if let cwd { process.currentDirectoryURL = URL(fileURLWithPath: cwd) }
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe
    if let stdin {
        let stdinPipe = Pipe()
        process.standardInput = stdinPipe
        do {
            try process.run()
            stdinPipe.fileHandleForWriting.write(Data(stdin.utf8))
            try? stdinPipe.fileHandleForWriting.close()
        } catch {
            return (127, "", String(describing: error))
        }
    } else {
        do {
            try process.run()
        } catch {
            return (127, "", String(describing: error))
        }
    }
    let stdout = String(decoding: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    let stderr = String(decoding: stderrPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    process.waitUntilExit()
    return (Int(process.terminationStatus), stdout, stderr)
}

private func detectGitRepoRoot() -> String? {
    let result = runProcess("/usr/bin/git", arguments: ["rev-parse", "--show-toplevel"], cwd: nil, stdin: nil)
    guard result.exitCode == 0 else { return nil }
    let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func resolveWorkerBinary(_ name: String) throws -> String {
    let candidates = [
        "/opt/homebrew/bin/\(name)",
        "/usr/local/bin/\(name)",
        "/usr/bin/\(name)"
    ]
    for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
        return path
    }
    throw ValidationError("\(name) not found. Ensure it is installed in /opt/homebrew/bin or /usr/local/bin.")
}

private func workerArtifactDateFormatter() -> ISO8601DateFormatter {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}

private extension String {
    var trimmedOrNil: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

func parseREPLFlags(_ tokens: [String]) throws -> REPLParsedArguments {
    var parsed = REPLParsedArguments()
    var index = 0
    while index < tokens.count {
        let token = tokens[index]
        if token.hasPrefix("--") {
            let key = String(token.dropFirst(2))
            let boolFlags: Set<String> = ["copy", "no-copy", "session", "brief", "yes", "dry-run", "verbose", "advanced", "artifact-verbose"]
            if boolFlags.contains(key) {
                parsed.flags.insert(key)
                index += 1
            } else {
                guard index + 1 < tokens.count else {
                    throw ValidationError("Missing value for --\(key).")
                }
                parsed.options[key, default: []].append(tokens[index + 1])
                index += 2
            }
        } else {
            parsed.positionals.append(token)
            index += 1
        }
    }
    return parsed
}

func tokenize(_ line: String) throws -> [String] {
    var tokens: [String] = []
    var current = ""
    var quote: Character?
    var escaping = false

    for character in line {
        if escaping {
            current.append(character)
            escaping = false
            continue
        }
        if character == "\\" {
            escaping = true
            continue
        }
        if let activeQuote = quote {
            if character == activeQuote {
                quote = nil
            } else {
                current.append(character)
            }
            continue
        }
        if character == "\"" || character == "'" {
            quote = character
        } else if character.isWhitespace {
            if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
        } else {
            current.append(character)
        }
    }

    if quote != nil {
        throw ValidationError("Unclosed quote.")
    }
    if escaping {
        current.append("\\")
    }
    if !current.isEmpty {
        tokens.append(current)
    }
    return tokens
}

func copyToClipboard(_ text: String) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/pbcopy")
    let pipe = Pipe()
    process.standardInput = pipe
    try process.run()
    pipe.fileHandleForWriting.write(Data(text.utf8))
    try pipe.fileHandleForWriting.close()
    process.waitUntilExit()
    if process.terminationStatus != 0 {
        throw ValidationError("pbcopy failed with status \(process.terminationStatus).")
    }
}

func openURL(_ url: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = [url.path]
    try process.run()
    process.waitUntilExit()
    if process.terminationStatus != 0 {
        throw ValidationError("open failed with status \(process.terminationStatus).")
    }
}

func printSection(_ title: String) {
    print(sectionTitle(title))
}

private func readPrompt(_ prompt: String) -> String? {
    #if canImport(Darwin)
    if isatty(STDIN_FILENO) == 1, let line = cReadline(prompt) {
        defer { free(line) }
        return String(cString: line)
    }
    #endif
    print(prompt, terminator: "")
    return readLine(strippingNewline: true)
}

private func addShellHistory(_ line: String) {
    #if canImport(Darwin)
    if isatty(STDIN_FILENO) == 1 {
        line.withCString { cAddHistory($0) }
    }
    #endif
}
