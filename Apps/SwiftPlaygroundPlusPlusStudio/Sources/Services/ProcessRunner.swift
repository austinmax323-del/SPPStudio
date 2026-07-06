import Foundation

// MARK: - ProcessResult

/// Structured outcome of a single external process run.
///
/// Exit code is data, not an error: a non-zero `exitCode` is returned normally,
/// never thrown. Callers decide what a given exit code means for their domain.
public struct ProcessResult: Sendable {

    /// The full command line as executed (executable + arguments), for logging.
    public let command: String
    public let stdout: String
    public let stderr: String
    /// Process termination status. -1 when the process could not be launched.
    public let exitCode: Int32
    /// True when the run exceeded its timeout and the process was terminated.
    public let timedOut: Bool

    /// Convenience: launched and exited cleanly within the time budget.
    public var succeeded: Bool { exitCode == 0 && !timedOut }

    public init(
        command: String,
        stdout: String,
        stderr: String,
        exitCode: Int32,
        timedOut: Bool
    ) {
        self.command = command
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
        self.timedOut = timedOut
    }
}

// MARK: - ProcessRunner

/// Shared, read-agnostic helper for spawning external processes off the main actor
/// and capturing their output as a structured `ProcessResult`.
///
/// This consolidates the `Process` + `Pipe` + `waitUntilExit` boilerplate currently
/// duplicated across the runtime services. It is intentionally behavior-only plumbing:
/// it owns no injection, build, verification, or simulator state.
///
/// Usage:
/// ```
/// let result = await ProcessRunner.run(
///     executable: "/usr/bin/xcrun",
///     arguments: ["simctl", "list", "devices", "--json"]
/// )
/// if result.succeeded { parse(result.stdout) }
/// ```
public enum ProcessRunner {

    /// Runs an external process to completion (or until `timeout`) and returns its
    /// captured output. Never throws — launch failures and non-zero exits are
    /// reported in the returned `ProcessResult`.
    ///
    /// - Parameters:
    ///   - executable:       Absolute path to the executable (e.g. "/usr/bin/xcrun").
    ///   - arguments:        Argument vector (not including the executable).
    ///   - environment:      Full environment for the child. `nil` inherits the
    ///                       current process environment.
    ///   - workingDirectory: Working directory for the child, or `nil` to inherit.
    ///   - timeout:          Optional wall-clock budget in seconds. When exceeded the
    ///                       process is terminated and `timedOut` is set. `nil` waits
    ///                       indefinitely.
    public static func run(
        executable: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        timeout: TimeInterval? = nil
    ) async -> ProcessResult {
        let command = ([executable] + arguments).joined(separator: " ")

        return await withCheckedContinuation { (continuation: CheckedContinuation<ProcessResult, Never>) in
            // Hand the whole run to a detached task so the blocking reads/waits never
            // touch the calling actor.
            Task.detached {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                if let environment { process.environment = environment }
                if let workingDirectory { process.currentDirectoryURL = workingDirectory }

                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe

                // Latch so the timeout watchdog and normal completion resume once.
                let state = RunState()

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: ProcessResult(
                        command: command,
                        stdout: "",
                        stderr: "Failed to launch \(executable): \(error.localizedDescription)",
                        exitCode: -1,
                        timedOut: false
                    ))
                    return
                }

                // Optional timeout watchdog: terminate the process if it overruns.
                if let timeout {
                    let watchdog = DispatchQueue(label: "ProcessRunner.timeout")
                    watchdog.asyncAfter(deadline: .now() + timeout) {
                        if state.markTimedOut(), process.isRunning {
                            process.terminate()
                        }
                    }
                }

                // Drain both pipes before waiting to avoid deadlock on large output.
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                let timedOut = state.didTimeOut
                continuation.resume(returning: ProcessResult(
                    command: command,
                    stdout: String(data: outData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                    stderr: String(data: errData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                    exitCode: process.terminationStatus,
                    timedOut: timedOut
                ))
            }
        }
    }

    // MARK: - Internal

    /// Thread-safe one-shot latch for the timeout watchdog.
    private final class RunState: @unchecked Sendable {
        private let lock = NSLock()
        private var _timedOut = false

        /// Returns true exactly once, for the first caller (the watchdog) to fire.
        func markTimedOut() -> Bool {
            lock.lock(); defer { lock.unlock() }
            if _timedOut { return false }
            _timedOut = true
            return true
        }

        var didTimeOut: Bool {
            lock.lock(); defer { lock.unlock() }
            return _timedOut
        }
    }
}
