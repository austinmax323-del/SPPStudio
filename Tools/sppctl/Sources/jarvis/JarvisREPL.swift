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
                print("  \(error.localizedDescription)")
                if let hint = lifecycleGuidance(for: error) {
                    print("  \(hint)")
                }
            }
        }
    }

    private mutating func handle(_ line: String) throws -> Bool {
        // Paste protection: detect common paste patterns before tokenizing
        if isPasteNoise(line) {
            if !pasteBlockActive {
                pasteBlockActive = true
                print("That looks like pasted notes or a prompt. Use ask ... to turn it into a Jarvis task, or help for commands.")
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
            printREPLHelp()
        case "status", "s":
            try printStatus(databaseURL: databaseURL)
        case "list", "ls":
            try printList(tokens)
        case "next", "n":
            try printNext(databaseURL: databaseURL)
        case "new":
            try createTask(tokens)
        case "ask":
            try handleAsk(tokens)
        case "go":
            try handleGo(tokens)
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
        let copyFlag = tokens.contains("--copy")
        let requestTokens = tokens.filter { $0 != "--copy" }
        let request = requestTokens.joined(separator: " ")
        guard !request.isEmpty else {
            printSection("ask")
            print("  Usage: ask <request>  [--copy]")
            print("  Example: ask review current OpenJarvis UX for codex")
            print("  Tip: plain 3+ word input shows a suggested task without creating it.")
            print("  Tip: go <request>  creates task, generates packet, and copies in one step.")
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
        printSection("task ready")
        print("  task: \(task.id.prefix(8))")
        print("  worker: \(workerStr)")
        print("  scope: \(scopeLabel)")
        print("  context: \(packet.retrievedContext.count) hits")
        if copyFlag {
            try copyToClipboard(packet.markdown)
            print("  packet copied to clipboard")
        } else {
            print("  suggested: p --copy")
        }
    }

    private mutating func handleGo(_ tokens: [String]) throws {
        let request = tokens.joined(separator: " ")
        guard !request.isEmpty else {
            printSection("go")
            print("  Usage: go <request>")
            print("  Example: go review retrieval architecture for claude")
            print("  Creates task, generates packet, and copies to clipboard.")
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
        print("  task: \(task.id.prefix(8))")
        print("  worker: \(workerStr)")
        print("  scope: \(scopeLabel)")
        print("  context: \(packet.retrievedContext.count) hits")
        print("  packet copied to clipboard")
    }

    private func lifecycleGuidance(for error: Error) -> String? {
        let msg = error.localizedDescription
        guard msg.contains("Invalid transition from") else { return nil }
        let preReady = ["intake", "retrieve", "assemble", "assign_worker", "validate_scope", "checkpoint_requirement"]
        for stage in preReady where msg.contains("from \(stage)") {
            return "hint: p --copy"
        }
        if msg.contains("from execution_ready") { return "hint: close --note \"done\"" }
        if msg.contains("from completed") { return "hint: w --note \"memory updated\"" }
        if msg.contains("from writeback") { return "hint: task is archived — use: new or go" }
        return nil
    }

    private func handleUnknownInput(command: String, fullLine: String) {
        let wordCount = fullLine.split(separator: " ").count
        if wordCount >= 3 {
            let workerStr = inferWorker(from: fullLine) ?? "codex"
            let scopes = inferOpenJarvisScopes(from: fullLine)
            let scopeStr = scopes.first?.rawValue ?? "coordination"
            let objective = fullLine.prefix(1).uppercased() + fullLine.dropFirst()
            printSection("interpreted request")
            print("  Create task: \(objective)")
            print("  Suggested worker: \(workerStr)")
            print("  Suggested scope: \(scopeStr)")
            print("  Run: go \(fullLine)")
            print("  Or:  new \"\(objective)\" --worker \(workerStr) --memory \(scopeStr)")
        } else {
            print("Unknown command: \(command). Try: help")
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
        printSection("task created")
        print("  task: \(task.id.prefix(8))")
        print("  worker: \(workerLabel)")
        print("  scope: \(scopeLabel)")
        print("  suggested: p --copy")
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
            printSection("task")
            print("  id: \(taskID.prefix(8))")
            print("  status: archived")
            print("  already archived")
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
            throw ValidationError("No tasks found. Use: go <request>")
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
        lines.append("[jarvis] task")
        lines.append("  id: \(task.id.prefix(8))")
        lines.append("  status: \(userFacingStage(task.stage))")
        lines.append("  worker: \(task.targetWorker?.displayName ?? "unassigned")")
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
        print(render(task: task))
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
        print("  \(target.path)")
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
        throw ValidationError("No open task. Use: go <request>")
    }

    private func printAutoSelectionIfNeeded(parsed: REPLParsedArguments, taskID: String) {
        guard parsed.positionals.isEmpty else { return }
        printSection("selected task")
        print("  \(taskID.prefix(8))")
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

    print("OpenJarvis manual-first mode enabled")
    print("No autonomous execution. No background workers. No hidden execution.")
    print("")
    print("Database: \(snapshot.databaseExists ? "connected" : "not created")")
    print("Vault: \(vaultStatus.resolved ? "resolved" : "unresolved")")
    print("Open tasks: \(openCount)")
    if recentTasks.isEmpty {
        print("Recent tasks: none")
    } else {
        print("Recent tasks:")
        for task in recentTasks {
            let age = relativeAge(from: task.updatedAt)
            let obj = task.objective.count > 60 ? String(task.objective.prefix(57)) + "..." : task.objective
            print("  \(task.id.prefix(8))  \(task.stage.displayLabel)  \(age)  \(obj)")
        }
    }
    print("")
    print("Type 'help' for commands.")
}

func printStatus(databaseURL: URL?) throws {
    print(renderStatus(snapshot: try OpenJarvisStatusReader.read(databaseURL: databaseURL), vaultStatus: resolveVaultStatus()))
}

func printNext(databaseURL: URL?) throws {
    let snapshot = try OpenJarvisStatusReader.read(databaseURL: databaseURL)
    guard snapshot.databaseExists else {
        printSection("next")
        print("  database does not exist yet")
        print("  suggested: new \"your task\"")
        return
    }

    let store = try OpenJarvisStore(databaseURL: databaseURL)
    guard let task = try store.listTasks().first(where: { $0.completionState == .open }) else {
        printSection("next")
        print("  no open tasks")
        print("  suggested: go <your request>  or  recover --session")
        return
    }

    let suggested: String
    if task.stage == .writeback {
        suggested = "recover \(task.id.prefix(8))"
    } else {
        suggested = suggestedCommand(for: task).replacingOccurrences(of: "jarvis ", with: "")
    }
    printSection("next")
    print("  task: \(task.id.prefix(8))")
    print("  objective: \(task.objective)")
    print("  status: \(userFacingStage(task.stage))")
    print("  worker: \(task.worker?.displayName ?? "unassigned")")
    print("  suggested: \(suggested)")
}

func printREPLHelp() {
    printSection("commands")
    print("  Daily flow: go <request>  →  paste into Codex/Claude  →  close --note \"done\"  →  h  →  q")
    print("")
    print("  go <request>                     create task, generate packet, copy to clipboard")
    print("  ask <request> [--copy]           create task + packet (infers worker/scope)")
    print("  close | c [TASK] --note \"done\"   complete + writeback in one step (default note: closed)")
    print("  recover | rec [TASK] [--copy]    assemble recovery context (read-only)")
    print("  recover --session [--copy]       recent session overview across tasks")
    print("  recover --brief [TASK] [--copy]  compact per-task brief (no packet body)")
    print("  status | s                       show database/vault status")
    print("  list | ls                        list tasks")
    print("  next | n                         show latest open task and suggested command")
    print("  new \"task\"                      create a manual task with explicit flags")
    print("  show [TASK]                      inspect current/latest task")
    print("  retrieve | r [TASK]              retrieve context for a task")
    print("  packet | p [TASK] [--copy]       generate worker packet, optionally copy")
    print("  done | d [TASK] --note \"done\"    mark current/latest task complete")
    print("  writeback | rb | w [TASK]        mark writeback complete")
    print("  history | h [TASK]               show task audit events")
    print("  open TASK                        open first related note/file")
    print("  clear                            clear the screen")
    print("  exit | q                         leave the shell")
    print("")
    print("Natural language: type 3+ words to get a suggested go command (no task created).")
    print("Scopes: architecture, runtime, coordination, validation, continuity, memory_digests, active_tasks, failures, decisions")
}

func parseREPLFlags(_ tokens: [String]) throws -> REPLParsedArguments {
    var parsed = REPLParsedArguments()
    var index = 0
    while index < tokens.count {
        let token = tokens[index]
        if token.hasPrefix("--") {
            let key = String(token.dropFirst(2))
            let boolFlags: Set<String> = ["copy", "session", "brief"]
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
    print("[jarvis] \(title)")
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
