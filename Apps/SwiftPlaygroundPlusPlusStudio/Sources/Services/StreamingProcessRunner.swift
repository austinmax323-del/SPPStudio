import Foundation

// MARK: - BuildCancellable

/// A build's cancellation handle. Lets `stopBuild` cancel a running build without
/// knowing whether it is backed by a raw `Process` or a `StreamingProcessRunner`.
/// `cancelBuild()` maps to SIGINT for both backends (Ctrl-C semantics), preserving
/// the existing device-build stop behavior.
public protocol BuildCancellable: AnyObject {
    func cancelBuild()
}

extension Process: BuildCancellable {
    public func cancelBuild() { interrupt() }
}

extension StreamingProcessRunner: BuildCancellable {
    public func cancelBuild() { interrupt() }
}

// MARK: - StreamingProcessRunner

/// Spawns an external process and streams its output **line by line** as it is
/// produced, ending with an exit event. This is the streaming counterpart to
/// `ProcessRunner` (which is batch: it waits for completion and returns one result).
///
/// It exists for the three live-output process sites that `ProcessRunner` cannot
/// serve because they need incremental output and/or early termination:
///   - `AppEnvironment.runBuild`            (live `make` console output)
///   - `AppEnvironment.buildSimulatorDylib` (live `make` console output)
///   - `InjectionVerificationService.watchForMarkers` (`log stream`, stop on first match)
///
/// Behavior-only plumbing: it owns no build, injection, or verification state.
/// One instance drives one process — call `start()` exactly once.
///
/// Usage — drain to completion (build):
/// ```
/// let runner = StreamingProcessRunner(executable: "/usr/bin/make", arguments: ["package"])
/// for await event in runner.start() {
///     switch event {
///     case .stdout(let line): console.append(line, isError: false)
///     case .stderr(let line): console.append(line, isError: true)
///     case .exit(let code):   finish(code)
///     }
/// }
/// ```
///
/// Usage — stop early on a match (marker watcher):
/// ```
/// for await event in runner.start() {
///     if case .stdout(let line) = event, line.contains(marker) {
///         runner.terminate()   // or simply `break` — see cancellation model
///         break
///     }
/// }
/// ```
public final class StreamingProcessRunner: @unchecked Sendable {

    /// One streamed output line, or the terminal exit status.
    /// The stream yields zero or more `.stdout`/`.stderr` events, then exactly one
    /// `.exit`, then finishes. On a launch failure it yields a single `.stderr`
    /// describing the error followed by `.exit(-1)`.
    public enum Event: Sendable {
        case stdout(String)
        case stderr(String)
        case exit(Int32)
    }

    // MARK: - Configuration

    private let executable: String
    private let arguments: [String]
    private let environment: [String: String]?
    private let workingDirectory: URL?

    // MARK: - State

    private let lock = NSLock()
    private var process: Process?
    private var started = false

    public init(
        executable: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil
    ) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
    }

    // MARK: - Start

    /// Launches the process and returns an `AsyncStream` of line events. Call once.
    /// Lines are reassembled across read chunks (a line split between two reads is
    /// emitted whole), and any unterminated trailing text is flushed as a final
    /// line just before `.exit`. Empty lines are passed through; callers filter as
    /// needed.
    public func start() -> AsyncStream<Event> {
        AsyncStream { continuation in
            lock.lock()
            let alreadyStarted = started
            started = true
            lock.unlock()

            guard !alreadyStarted else {
                continuation.yield(.stderr("StreamingProcessRunner.start() called more than once."))
                continuation.yield(.exit(-1))
                continuation.finish()
                return
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            if let environment { process.environment = environment }
            if let workingDirectory { process.currentDirectoryURL = workingDirectory }

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            // Each pipe has its own buffer; the two readability handlers run on
            // independent queues but never touch the same buffer.
            let outBuffer = LineBuffer()
            let errBuffer = LineBuffer()

            outPipe.fileHandleForReading.readabilityHandler = { fh in
                let data = fh.availableData
                guard !data.isEmpty else { return }
                for line in outBuffer.append(data) { continuation.yield(.stdout(line)) }
            }
            errPipe.fileHandleForReading.readabilityHandler = { fh in
                let data = fh.availableData
                guard !data.isEmpty else { return }
                for line in errBuffer.append(data) { continuation.yield(.stderr(line)) }
            }

            process.terminationHandler = { proc in
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                // Flush any unterminated trailing text as a final line.
                for line in outBuffer.flush() { continuation.yield(.stdout(line)) }
                for line in errBuffer.flush() { continuation.yield(.stderr(line)) }
                continuation.yield(.exit(proc.terminationStatus))
                continuation.finish()
            }

            lock.lock(); self.process = process; lock.unlock()

            do {
                try process.run()
            } catch {
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                continuation.yield(.stderr("Failed to launch \(executable): \(error.localizedDescription)"))
                continuation.yield(.exit(-1))
                continuation.finish()
                return
            }

            // Caller-driven cancellation: if the consuming task is cancelled, or the
            // consumer breaks out of the for-await loop, the stream terminates and
            // this fires — so we kill the process. This is what makes `break` enough
            // for the early-stop (marker) case.
            continuation.onTermination = { [weak self] _ in
                self?.terminate()
            }
        }
    }

    // MARK: - Terminate

    /// Sends SIGTERM to the running process. Safe to call repeatedly and after the
    /// process has already exited (no-op in those cases). Used for explicit stops
    /// (e.g. a Stop Build button) in addition to the automatic `onTermination` path.
    public func terminate() {
        lock.lock()
        let proc = process
        lock.unlock()
        if let proc, proc.isRunning { proc.terminate() }
    }

    /// Sends SIGINT (Ctrl-C semantics) to the running process. Distinct from
    /// `terminate()` (SIGTERM): SIGINT is the conventional "stop the build" signal
    /// and propagates to a build tool's child processes (e.g. `make` → compilers).
    /// Same lock / `isRunning` safety as `terminate()`; idempotent and a no-op once
    /// the process has exited.
    public func interrupt() {
        lock.lock()
        let proc = process
        lock.unlock()
        if let proc, proc.isRunning { proc.interrupt() }
    }
}

// MARK: - LineBuffer

/// Accumulates raw bytes and yields complete (newline-delimited) lines, retaining
/// any unterminated remainder until more data arrives or `flush()` is called.
/// Internally locked so a late readability callback and the termination flush can
/// never corrupt the buffer.
private final class LineBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()

    /// Appends new bytes and returns every complete line now available (without the
    /// trailing newline). The text after the last newline is retained as remainder.
    func append(_ data: Data) -> [String] {
        lock.lock(); defer { lock.unlock() }
        buffer.append(data)
        guard buffer.contains(0x0A) else { return [] }
        var parts = buffer.split(separator: 0x0A, omittingEmptySubsequences: false)
        let remainder = parts.removeLast()          // text after the final newline
        buffer = Data(remainder)
        return parts.map { String(decoding: $0, as: UTF8.self) }
    }

    /// Returns the retained remainder (if any) as a single final line and clears it.
    func flush() -> [String] {
        lock.lock(); defer { lock.unlock() }
        guard !buffer.isEmpty else { return [] }
        let line = String(decoding: buffer, as: UTF8.self)
        buffer.removeAll()
        return [line]
    }
}
