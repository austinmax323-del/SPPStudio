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
                print("Use ask \"...\" to turn pasted notes into a packet.")
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
        let noCopyFlag = tokens.contains("--no-copy")
        let copyFlag = tokens.contains("--copy") || !noCopyFlag
        let requestTokens = tokens.filter { $0 != "--copy" && $0 != "--no-copy" }
        let request = requestTokens.joined(separator: " ")
        guard !request.isEmpty else {
            printSection("Ask")
            print("  ask \"review current retrieval flow for codex\"")
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
        printSection("Created")
        print("  Task     \(task.id.prefix(8))")
        print("  Worker   \(OpenJarvisWorkerKind(rawValue: workerStr)?.displayName ?? workerStr)")
        print("  Context  \(packet.retrievedContext.count) notes")
        if copyFlag {
            try copyToClipboard(packet.markdown)
            print("")
            print("  Copied packet to clipboard.")
        } else {
            print("")
            print("  Next     packet --copy")
        }
    }

    private mutating func handleGo(_ tokens: [String]) throws {
        let request = tokens.joined(separator: " ")
        guard !request.isEmpty else {
            printSection("go")
            print("  ask \"review retrieval architecture for claude\"")
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

    private mutating func handleAuto(_ tokens: [String]) throws {
        let request = tokens.joined(separator: " ")
        guard !request.isEmpty else {
            printSection("auto")
            print("  ask \"review current Jarvis boundary for codex\"")
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
        print("  task: \(task.id.prefix(8))")

        printSection("auto  2/4  retrieving context")
        var queryParts: [String] = [objective]
        let normalizedObjective = objective.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedRequest = request.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedRequest != normalizedObjective { queryParts.append(request) }
        queryParts.append(contentsOf: neededMemory)
        let retrievalQuery = queryParts.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: " ")
        let hits = try store.retrieveContext(for: task.id, query: retrievalQuery, scopeHint: scopes.isEmpty ? nil : scopes, limit: 8)
        print("  hits: \(hits.count)")

        printSection("auto  3/4  generating packet")
        let packet = try store.generatePacket(for: task.id, role: try parseWorker(workerStr), limit: 5, scopeHint: nil)
        print("  context: \(packet.retrievedContext.count) hits")

        printSection("auto  4/4  copying to clipboard")
        try copyToClipboard(packet.markdown)
        try store.recordEvent(taskID: task.id, type: "task.autopilot_launch", payload: [
            "worker": workerStr,
            "hit_count": "\(packet.retrievedContext.count)"
        ])
        print("  done")
        print("")
        printSection("ready")
        print("  task: \(task.id.prefix(8))")
        print("  worker: \(OpenJarvisWorkerKind(rawValue: workerStr)?.displayName ?? workerStr)")
        print("  context hits: \(packet.retrievedContext.count)")
        print("  packet copied to clipboard")
        print("")
        print("  next: paste into \(OpenJarvisWorkerKind(rawValue: workerStr)?.displayName ?? workerStr)")
        print("  then: close \(task.id.prefix(8)) --note \"done\"")
    }

    private mutating func handleResume(_ tokens: [String]) throws {
        let parsed = try parseREPLFlags(tokens)
        let store = try OpenJarvisStore(databaseURL: parsed.databaseURL ?? databaseURL)
        let allTasks = try store.listTasks()
        guard let summary = allTasks.first(where: { $0.completionState == .open }) ?? allTasks.first else {
            printSection("resume")
            print("  no tasks found")
            print("  suggested: auto <your request>")
            return
        }
        currentTaskID = summary.id
        let brief = try store.buildBriefRecoveryContext(for: summary.id)
        let full = try store.buildRecoveryContext(for: summary.id)
        print(brief)
        try copyToClipboard(full)
        print("")
        printSection("full recovery copied to clipboard")
        print("  task: \(summary.id.prefix(8))")
        print("  state: \(visibleLifecycleLabel(for: summary.stage))")
        print("  worker: \(summary.worker?.displayName ?? "unassigned")")
        print("  next: paste into \(summary.worker?.displayName ?? "your worker")")
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
            print("  no open tasks")
            print("  suggested: auto <your request>  or  recover --session")
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
        print("  task: \(taskID.prefix(8))")
        print("  state: \(visibleLifecycleLabel(for: task.stage))")
        print("  worker: \(task.targetWorker?.displayName ?? "unassigned")")
        if mode == "packet" {
            print("  next: paste packet into \(task.targetWorker?.displayName ?? "your worker")")
        } else {
            print("  next: share context with \(task.targetWorker?.displayName ?? "your worker")")
        }
    }

    private mutating func handleSend(_ tokens: [String]) throws {
        let parsed = try parseREPLFlags(tokens)
        guard !tokens.isEmpty else {
            printSection("Send")
            print("  send claude [task]")
            print("  send codex [task]")
            return
        }
        let store = try OpenJarvisStore(databaseURL: parsed.databaseURL ?? databaseURL)

        // First positional may be worker name or task token
        let rawPositionals = parsed.positionals
        var resolvedWorkerStr: String? = parsed.value("worker")
        let taskToken: String?
        if let first = rawPositionals.first, ["claude", "codex"].contains(first.lowercased()) {
            resolvedWorkerStr = resolvedWorkerStr ?? first.lowercased()
            taskToken = rawPositionals.dropFirst().first
        } else {
            taskToken = rawPositionals.first
        }

        // Resolve task
        let taskID: String
        if let token = taskToken {
            taskID = try loadTaskID(store: store, token: token)
        } else if let id = currentTaskID {
            taskID = id
        } else if let latest = try store.listTasks().first(where: { $0.completionState == .open }) {
            taskID = latest.id
        } else {
            throw ValidationError("No open task. Use: ask \"your request\"")
        }
        guard let task = try store.fetchTask(id: taskID) else {
            throw ValidationError("Task '\(taskID)' not found.")
        }

        // Resolve worker
        let workerStr: String
        if let w = resolvedWorkerStr {
            workerStr = w.lowercased()
        } else if let taskWorker = task.targetWorker, taskWorker != .localModel {
            workerStr = taskWorker.rawValue
        } else {
            throw ValidationError("No worker resolved. Use: send claude [TASK]  or  send codex [TASK]")
        }
        guard let worker = OpenJarvisWorkerKind(rawValue: workerStr), worker != .localModel else {
            throw ValidationError("Worker '\(workerStr)' not supported for send. Use: claude or codex")
        }

        // Resolve binary
        let binaryPath = try resolveBinary(workerStr)

        // Get or generate packet
        let packetText: String
        if let existing = task.packetText, !existing.isEmpty {
            packetText = existing
        } else {
            let packet = try store.generatePacket(for: taskID, role: worker, limit: 5, scopeHint: nil)
            packetText = packet.markdown
        }

        // Packet delivered via stdin; workerArgs contain only flags
        let workerArgs: [String]
        switch worker {
        case .claude:
            workerArgs = ["-p", "--no-session-persistence"]
        case .codex:
            workerArgs = ["exec"]
        case .localModel:
            fatalError("unreachable")
        }

        // Resolve working directory: --cwd > git repo root > cwd
        let resolvedCwd: String
        if let cwdOverride = parsed.value("cwd") {
            resolvedCwd = cwdOverride
        } else {
            resolvedCwd = detectRepoRoot() ?? FileManager.default.currentDirectoryPath
        }

        // Resolve vault: --vault > task vaultRoot > auto-detect
        let resolvedVault: String?
        if let vaultOverride = parsed.value("vault") {
            resolvedVault = vaultOverride
        } else if let taskVault = task.vaultRoot, !taskVault.isEmpty {
            resolvedVault = taskVault
        } else {
            resolvedVault = try? OpenJarvisPaths.vaultRoot().path
        }

        // Sanity probes
        guard FileManager.default.fileExists(atPath: resolvedCwd) else {
            throw ValidationError("Working directory does not exist: \(resolvedCwd)")
        }
        if let v = resolvedVault, !FileManager.default.fileExists(atPath: v) {
            throw ValidationError("Vault path does not exist: \(v)")
        }

        // Resolve output artifact path
        let vaultURL: URL
        if let v = resolvedVault {
            vaultURL = URL(fileURLWithPath: v)
        } else {
            vaultURL = try OpenJarvisPaths.vaultRoot()
        }
        let runDir = vaultURL.appendingPathComponent("70_SessionContinuity/WorkerRuns")
        try FileManager.default.createDirectory(at: runDir, withIntermediateDirectories: true)
        let formatter: ISO8601DateFormatter = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f
        }()
        let ts = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        let outputFileName = "\(ts)-\(taskID.prefix(8).lowercased())-\(workerStr).md"
        let outputURL = runDir.appendingPathComponent(outputFileName)

        // Display command summary for confirmation
        let displayCmd: String
        switch worker {
        case .claude:
            displayCmd = "claude -p --no-session-persistence  [\(packetText.count) chars via stdin]"
        case .codex:
            displayCmd = "codex exec  [\(packetText.count) chars via stdin]"
        case .localModel:
            fatalError("unreachable")
        }

        printSection("Send to \(worker.displayName)?")
        print("  Task    \(taskID.prefix(8))")
        print("  Output  WorkerRuns/\(outputFileName)")
        if parsed.hasFlag("verbose") || parsed.hasFlag("dry-run") {
            print("")
            print("  cwd     \(resolvedCwd)")
            if let v = resolvedVault { print("  vault   \(v)") }
            print("  packet  \(packetText.count) chars")
            print("  cmd     \(displayCmd)")
        }

        if parsed.hasFlag("dry-run") {
            print("")
            print("  Dry run only. No worker launched.")
            return
        }

        if !parsed.hasFlag("yes") {
            print("")
            print("  Run? [y/N] ", terminator: "")
            guard let answer = readLine(strippingNewline: true)?.trimmingCharacters(in: .whitespaces).lowercased(),
                  answer == "y" || answer == "yes" else {
                print("  Aborted.")
                return
            }
        }

        try store.recordEvent(taskID: taskID, type: "task.worker_invoked", payload: [
            "worker": workerStr,
            "output_file": outputFileName
        ])
        currentTaskID = taskID

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

        // Save artifact
        var artifact: [String] = []
        artifact.append("# Worker Run: \(task.interpretedObjective)")
        artifact.append("")
        artifact.append("Task: \(task.id)")
        artifact.append("Worker: \(worker.displayName)")
        artifact.append("Command: \(displayCmd)")
        artifact.append("Working Directory: \(resolvedCwd)")
        if let v = resolvedVault { artifact.append("Vault: \(v)") }
        artifact.append("Invoked: \(formatter.string(from: Date()))")
        artifact.append("Exit code: \(exitCode)")
        artifact.append("")
        artifact.append("## Prompt")
        artifact.append("")
        artifact.append(packetText)
        artifact.append("")
        artifact.append("## Response")
        artifact.append("")
        artifact.append(stdout.isEmpty ? "(no output)" : stdout)
        if !stderr.isEmpty {
            artifact.append("")
            artifact.append("## Errors")
            artifact.append("")
            artifact.append(stderr)
        }
        try artifact.joined(separator: "\n").write(to: outputURL, atomically: true, encoding: .utf8)

        try store.recordEvent(taskID: taskID, type: "task.worker_response_saved", payload: [
            "worker": workerStr,
            "exit_code": "\(exitCode)",
            "output_file": outputFileName,
            "response_chars": "\(stdout.count)"
        ])

        print("")
        printSection(exitCode == 0 ? "Saved" : "Worker exited \(exitCode)")
        print("  Exit    \(exitCode)")
        print("  Output  WorkerRuns/\(outputFileName)")
        if !stdout.isEmpty {
            let previewLines = stdout.components(separatedBy: "\n").prefix(6)
            print("")
            for line in previewLines { print("  │ \(line)") }
        }
        print("")
        print("  Next    review, then close \(taskID.prefix(8)) --note \"done\"")
    }

    private func detectRepoRoot() -> String? {
        let git = Process()
        git.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        git.arguments = ["rev-parse", "--show-toplevel"]
        let pipe = Pipe()
        git.standardOutput = pipe
        git.standardError = Pipe()
        guard (try? git.run()) != nil else { return nil }
        git.waitUntilExit()
        guard git.terminationStatus == 0 else { return nil }
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func resolveBinary(_ name: String) throws -> String {
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
            print("  ask \"\(objective)\"")
            print("  Worker  \(OpenJarvisWorkerKind(rawValue: workerStr)?.displayName ?? workerStr)")
            print("  Scope   \(scopeStr)")
        } else {
            print("Unknown command: \(command). Try help.")
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
        print("  Task     \(task.id.prefix(8))")
        print("  Worker   \(workerLabel)")
        print("  Context  \(scopeLabel)")
        print("")
        print("  Next     packet --copy")
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
            print("  Task  \(taskID.prefix(8))")
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
        lines.append(visibleLifecycleLabel(for: task.stage) == "archived" ? "Archived" : "Task")
        lines.append("  ID      \(task.id.prefix(8))")
        lines.append("  State   \(visibleLifecycleLabel(for: task.stage))")
        lines.append("  Worker  \(task.targetWorker?.displayName ?? "unassigned")")
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
        throw ValidationError("No open task. Use: ask \"your request\"")
    }

    private func printAutoSelectionIfNeeded(parsed: REPLParsedArguments, taskID: String) {
        guard parsed.positionals.isEmpty else { return }
        print("Task \(taskID.prefix(8))")
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

    print("Jarvis")
    print("  Active  \(openCount)")
    print("  Vault   \(vaultStatus.resolved ? "ready" : "missing")")
    if recentTasks.isEmpty {
        print("  Latest  none")
    } else {
        let latest = recentTasks[0]
        let obj = latest.objective.count > 48 ? String(latest.objective.prefix(45)) + "..." : latest.objective
        print("  Latest  \(latest.id.prefix(8)) \(visibleLifecycleLabel(for: latest.stage))  \(obj)")
    }
    print("")
    print("  ask | send | status | close | history")
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

func printREPLHelp(_ tokens: [String] = []) {
    if tokens.contains("--advanced") {
        printSection("Advanced")
        print("  retrieve [task] [--scope runtime]")
        print("  packet [task] [--copy]")
        print("  recover [task] [--copy]")
        print("  list | show | open")
        print("  done | writeback")
        print("  new \"task\" --worker codex --memory coordination")
        print("")
        print("  Legacy aliases still work: go, auto, resume, continue, next.")
        return
    }

    printSection("Commands")
    print("  ask \"request\"             create context and copy packet")
    print("  send claude|codex [task]   run worker, save artifact")
    print("  status                     show active work")
    print("  close [task] --note done   archive task")
    print("  history [task]             show audit trail")
    print("")
    print("  help --advanced            show internal utilities")
}

func parseREPLFlags(_ tokens: [String]) throws -> REPLParsedArguments {
    var parsed = REPLParsedArguments()
    var index = 0
    while index < tokens.count {
        let token = tokens[index]
        if token.hasPrefix("--") {
            let key = String(token.dropFirst(2))
            let boolFlags: Set<String> = ["copy", "no-copy", "session", "brief", "yes", "dry-run", "verbose", "advanced"]
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
    print(title)
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
