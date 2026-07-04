import Foundation

// MARK: - InjectionExecutionResult

/// Structured outcome of a single dylib launch-injection attempt.
///
/// NOTE: `succeeded` means the `simctl launch` command exited 0 and reported a
/// launched process. It does NOT prove the dylib's hooks ran — only that the
/// launch was accepted and DYLD_INSERT_LIBRARIES was passed. Hook verification
/// requires runtime evidence (syslog markers / symbol presence), tracked separately.
public struct InjectionExecutionResult: Sendable {

    public let command: String
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32
    public let startedAt: Date
    public let endedAt: Date
    /// Process ID parsed from `simctl launch` stdout (e.g. "com.example.App: 12345"), if present.
    public let launchedPID: Int?

    public var duration: TimeInterval { endedAt.timeIntervalSince(startedAt) }
    public var succeeded: Bool { exitCode == 0 }

    public var summary: String {
        if succeeded {
            let pidPart = launchedPID.map { " (pid \($0))" } ?? ""
            return "Launch injection attempted\(pidPart) — dylib passed via DYLD_INSERT_LIBRARIES. "
                + "Hook execution NOT yet verified."
        } else {
            return "Launch injection FAILED — exit \(exitCode)."
        }
    }
}

// MARK: - InjectionExecutionService

/// Owns execution state for simulator dylib launch injection.
///
/// Separation of concerns:
///   - InjectionPreflightService verifies readiness (does NOT execute).
///   - InjectionExecutionService executes the verified command (does NOT re-verify).
/// The caller is responsible for only invoking `inject` after preflight passes.
@MainActor
public final class InjectionExecutionService: ObservableObject {

    // MARK: - Published State

    @Published public var isExecuting = false
    @Published public var lastResult: InjectionExecutionResult?
    /// Timestamped, human-readable log lines for the simulator panel.
    @Published public var logs: [String] = []

    public init() {}

    // MARK: - Execute

    /// Runs one launch injection.
    ///
    /// Command:
    ///   xcrun simctl launch --terminate-running-process
    ///     --env DYLD_INSERT_LIBRARIES=<dylib> <udid> <bundleID>
    ///
    /// - Returns: the structured result, also stored in `lastResult`.
    @discardableResult
    public func inject(
        target: SimulatorTarget,
        bundleID: String,
        dylibURL: URL
    ) async -> InjectionExecutionResult {
        let arguments = [
            "simctl", "launch", "--terminate-running-process",
            "--env", "DYLD_INSERT_LIBRARIES=\(dylibURL.path)",
            target.udid, bundleID
        ]
        let commandString = "xcrun " + arguments.joined(separator: " ")

        guard !isExecuting else {
            // Defensive: never run two injections at once.
            return InjectionExecutionResult(
                command: commandString, stdout: "",
                stderr: "Injection already in progress.",
                exitCode: -1, startedAt: Date(), endedAt: Date(), launchedPID: nil
            )
        }

        isExecuting = true
        defer { isExecuting = false }

        let startedAt = Date()
        log("─────────────────────────────────────────")
        log("INJECT → \(target.displayName) [\(target.udid)]")
        log("  bundle: \(bundleID)")
        log("  dylib:  \(dylibURL.path)")
        log("  $ \(commandString)")

        let outcome = await ProcessRunner.run(executable: "/usr/bin/xcrun", arguments: arguments)
        let endedAt = Date()

        let pid = parsePID(from: outcome.stdout, bundleID: bundleID)

        let result = InjectionExecutionResult(
            command: commandString,
            stdout: outcome.stdout,
            stderr: outcome.stderr,
            exitCode: outcome.exitCode,
            startedAt: startedAt,
            endedAt: endedAt,
            launchedPID: pid
        )
        lastResult = result

        // Emit captured output
        if !outcome.stdout.isEmpty {
            outcome.stdout.split(separator: "\n").forEach { log("  ⬑ \($0)") }
        }
        if !outcome.stderr.isEmpty {
            outcome.stderr.split(separator: "\n").forEach { log("  ⚠ \($0)") }
        }
        log(String(format: "  exit %d in %.2fs", result.exitCode, result.duration))
        log(result.succeeded ? "✓ \(result.summary)" : "✗ \(result.summary)")
        if result.succeeded {
            log("  NOTE: launch succeeded ≠ hooks active. Verify via syslog markers.")
        }

        return result
    }

    // MARK: - Helpers

    /// `simctl launch` prints "<bundleID>: <pid>" on success.
    private func parsePID(from stdout: String, bundleID: String) -> Int? {
        for line in stdout.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            if parts.count == 2, parts[0] == bundleID, let pid = Int(parts[1]) {
                return pid
            }
        }
        // Fallback: any trailing integer
        if let last = stdout.split(whereSeparator: { $0 == ":" || $0 == " " }).last,
           let pid = Int(last) {
            return pid
        }
        return nil
    }

    private func log(_ message: String) {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        logs.append("[\(f.string(from: Date()))] \(message)")
    }
}
