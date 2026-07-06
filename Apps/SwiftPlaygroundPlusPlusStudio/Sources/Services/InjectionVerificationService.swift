import Foundation
import SPPDeviceKit

// MARK: - InjectionVerificationResult

/// Structured outcome of a runtime-evidence check for an injected dylib.
///
/// Two independent pieces of evidence are collected from syslog:
///   - LOAD: the dylib's `%ctor` ran (image was mapped and executed code).
///   - HOOK: a `%hook` body ran (a real method substitution actually fired).
///
/// These are orthogonal. Load can succeed while hooks silently fail (wrong class,
/// missing substrate, method not present). Only the HOOK marker proves a hook fired.
public struct InjectionVerificationResult: Sendable {

    public enum Status: String, Sendable {
        case hookVerified   // both load + hook markers observed
        case loadOnly       // load observed, hook NOT observed within timeout
        case timedOut       // neither marker observed
        case failed         // log stream could not start
    }

    public let status: Status
    public let loadMarker: String
    public let hookMarker: String
    /// Full syslog line that matched each marker, if seen.
    public let loadLine: String?
    public let hookLine: String?
    public let timeout: TimeInterval
    public let waited: TimeInterval

    public var loadObserved: Bool { loadLine != nil }
    public var hookObserved: Bool { hookLine != nil }

    public var summary: String {
        switch status {
        case .hookVerified:
            return "Dylib loaded AND a hook body fired — injection confirmed end-to-end."
        case .loadOnly:
            return "Dylib loaded, but no hook fired within \(Int(timeout))s. The image mapped "
                + "and ran its constructor, but no `%hook` body executed — the hook may target a "
                + "class/method that never ran, or hooking is unavailable in this simulator."
        case .timedOut:
            return "No evidence — neither '\(loadMarker)' nor '\(hookMarker)' seen within "
                + "\(Int(timeout))s. The dylib may have failed to map, or the tweak emits no markers."
        case .failed:
            return "Verification could not run — log stream failed to start."
        }
    }
}

// MARK: - InjectionImageProbeResult

/// Structured outcome of a read-only image-list probe (`vmmap <pid>`).
///
/// This is independent of, and complementary to, the NSLog markers: it inspects
/// the target process's mapped images directly and does NOT require the dylib to
/// emit anything. It proves the image is *mapped into the address space* — not
/// that any of its code ran.
public struct InjectionImageProbeResult: Sendable {

    public enum Status: String, Sendable {
        case mapped         // dylib found in the process image list
        case notMapped      // probe ran cleanly, dylib NOT present
        case processExited  // PID no longer inspectable — process gone before/at probe
        case unavailable    // no PID available to probe (launch returned none)
        case failed         // vmmap errored for another reason
    }

    public let status: Status
    public let pid: Int?
    public let dylibPath: String
    /// The vmmap line that referenced the dylib, if found.
    public let matchedLine: String?
    /// Raw stderr / error text when status is .failed or .processExited.
    public let rawError: String?
    /// Number of vmmap attempts made before this result was reached.
    public let attempts: Int

    public var summary: String {
        switch status {
        case .mapped:
            return "Image MAPPED — the dylib is present in pid \(pid.map(String.init) ?? "?")'s "
                + "address space (vmmap, attempt \(attempts)). Confirms load without tweak markers."
        case .notMapped:
            return "Image NOT mapped — vmmap for pid \(pid.map(String.init) ?? "?") did not list "
                + "the dylib after \(attempts) attempt\(attempts == 1 ? "" : "s"). dyld likely "
                + "rejected it (wrong arch / unsigned / missing deps)."
        case .processExited:
            return "Process gone — pid \(pid.map(String.init) ?? "?") was not inspectable after "
                + "\(attempts) attempt\(attempts == 1 ? "" : "s"). The app exited before the image "
                + "probe could read it; load could not be confirmed via vmmap."
        case .unavailable:
            return "Image probe skipped — no launched PID was returned, nothing to inspect."
        case .failed:
            return "Image probe failed to run after \(attempts) attempt\(attempts == 1 ? "" : "s"): "
                + "\(rawError ?? "unknown error")."
        }
    }
}

// MARK: - InjectionDiagnosis

/// A plain-language correlation of the two evidence sources (markers + image probe).
/// This does NOT collect evidence — it interprets evidence already collected, so the
/// UI can show one honest sentence instead of three separate signals.
///
/// Crucially: a loaded dylib whose hook marker never fired is reported as a WARNING,
/// not a failure — the image really did load; the hook runtime may simply be absent.
public struct InjectionDiagnosis: Sendable {

    public enum Severity: String, Sendable {
        case ok        // load + hook confirmed
        case warning   // loaded, but hook did not fire (likely no sim hook runtime)
        case info      // mapped / loaded but evidence incomplete (e.g. marker-less)
        case problem   // not loaded / not mapped
    }

    public let severity: Severity
    public let headline: String
    public let detail: String
}

// MARK: - InjectionVerificationService

/// Owns runtime-evidence collection only.
///
/// Separation of concerns:
///   - InjectionExecutionService launches the app (owns execution state).
///   - InjectionVerificationService watches syslog for load + hook markers (owns evidence state).
///   - SimulatorService may stream logs elsewhere, but does not own injection/verification state.
///
/// This service runs its OWN dedicated, marker-scoped log stream so it does not
/// depend on, or interfere with, any syslog stream SimulatorService may be running.
@MainActor
public final class InjectionVerificationService: ObservableObject {

    // MARK: - Markers

    /// Emitted from the tweak's `%ctor` — proves the dylib loaded and ran code.
    public nonisolated static let loadMarker = "SPPSTUDIO_DYLIB_LOADED"

    /// Emitted from inside a `%hook` body — proves a method substitution actually fired.
    public nonisolated static let hookMarker = "SPPSTUDIO_HOOK_FIRED"

    /// Shared prefix used to scope the log stream predicate to just our markers.
    private nonisolated static let markerPrefix = "SPPSTUDIO_"

    // MARK: - Published State

    @Published public var isVerifying = false
    @Published public var lastResult: InjectionVerificationResult?
    @Published public var logs: [String] = []

    // Image-list probe state (independent of marker watch).
    @Published public var isProbingImage = false
    @Published public var lastImageResult: InjectionImageProbeResult?

    public init() {}

    // MARK: - Diagnosis

    /// Correlates the latest marker and image evidence into one honest verdict.
    /// Reactive: recomputes whenever `lastResult` / `lastImageResult` change.
    /// Returns nil until there is at least marker or image evidence to interpret.
    public var diagnosis: InjectionDiagnosis? {
        let markers = lastResult
        let image   = lastImageResult
        guard markers != nil || image != nil else { return nil }

        let load   = markers?.loadObserved ?? false
        let hook   = markers?.hookObserved ?? false
        let mapped = image?.status == .mapped

        // 1. Full success — a hook body actually ran.
        if hook {
            return InjectionDiagnosis(
                severity: .ok,
                headline: "Injection confirmed — dylib loaded and a hook fired.",
                detail: "Load and hook markers both observed"
                    + (mapped ? "; image mapped (vmmap)." : ".")
            )
        }

        // 2. The target case — dylib loaded, but the hook marker never fired.
        //    This is NOT a failure: the image loaded; the hook may simply be inert.
        if load {
            let imgNote = mapped
                ? " The image is mapped — vmmap independently confirms the load."
                : ""
            return InjectionDiagnosis(
                severity: .warning,
                headline: "Dylib loaded, but hook did not fire. The simulator build may "
                    + "not have a working Logos/Substrate hook runtime.",
                detail: "Load marker (\(Self.loadMarker)) observed but hook marker "
                    + "(\(Self.hookMarker)) was not.\(imgNote) iOS simulators ship no Cydia "
                    + "Substrate, so a %hook can stay inert even though the dylib loaded and "
                    + "ran its constructor. This is reported as a warning, not an injection failure."
            )
        }

        // 3. Image mapped but no load marker — the tweak ran no observable marker.
        if mapped {
            return InjectionDiagnosis(
                severity: .info,
                headline: "Image mapped, but no load marker — cannot confirm the tweak ran.",
                detail: "vmmap shows the dylib mapped into the process, but "
                    + "\(Self.loadMarker) was not seen. The tweak may emit no markers, "
                    + "or they were missed within the watch window."
            )
        }

        // 4. No load evidence and the image is explicitly not mapped.
        if image?.status == .notMapped {
            return InjectionDiagnosis(
                severity: .problem,
                headline: "Dylib not loaded — image is not mapped into the process.",
                detail: "Neither markers nor vmmap confirm a load. dyld likely rejected the "
                    + "image (wrong platform/arch or invalid signature)."
            )
        }

        // 5. Inconclusive (probe unavailable / process exited / timed out with nothing).
        return InjectionDiagnosis(
            severity: .info,
            headline: "No load evidence yet — injection result is inconclusive.",
            detail: "No markers observed and the image state could not be confirmed."
        )
    }

    // MARK: - Verify

    /// Watches the simulator's syslog for the load and hook markers for up to `timeout`s.
    ///
    /// Start this BEFORE (or concurrently with) the injection launch so the load-time
    /// `%ctor` marker is captured. Resolves early once BOTH markers are seen; otherwise
    /// resolves at timeout with whatever evidence was collected.
    ///
    /// - Returns: a structured result, also stored in `lastResult`.
    @discardableResult
    public func verify(
        udid: String,
        loadMarker: String = InjectionVerificationService.loadMarker,
        hookMarker: String = InjectionVerificationService.hookMarker,
        timeout: TimeInterval = 10
    ) async -> InjectionVerificationResult {
        guard !isVerifying else {
            return InjectionVerificationResult(
                status: .failed, loadMarker: loadMarker, hookMarker: hookMarker,
                loadLine: nil, hookLine: nil, timeout: timeout, waited: 0
            )
        }
        isVerifying = true
        defer { isVerifying = false }

        let start = Date()
        log("─────────────────────────────────────────")
        log("VERIFY runtime evidence")
        log("  load marker: \"\(loadMarker)\"")
        log("  hook marker: \"\(hookMarker)\"")
        log("  watching syslog for up to \(Int(timeout))s…")

        let outcome = await watchForMarkers(
            udid: udid, loadMarker: loadMarker, hookMarker: hookMarker, timeout: timeout
        )
        let waited = Date().timeIntervalSince(start)

        let status: InjectionVerificationResult.Status
        if outcome.failed {
            status = .failed
        } else if outcome.loadLine != nil && outcome.hookLine != nil {
            status = .hookVerified
        } else if outcome.loadLine != nil {
            status = .loadOnly
        } else {
            status = .timedOut
        }

        let result = InjectionVerificationResult(
            status: status,
            loadMarker: loadMarker,
            hookMarker: hookMarker,
            loadLine: outcome.loadLine,
            hookLine: outcome.hookLine,
            timeout: timeout,
            waited: waited
        )
        lastResult = result

        if let l = outcome.loadLine { log("  ⬑ LOAD: \(l)") }
        if let h = outcome.hookLine { log("  ⬑ HOOK: \(h)") }
        log(String(format: "  waited %.2fs", waited))
        log("  dylib loaded: \(result.loadObserved ? "YES" : "no")  |  hook fired: \(result.hookObserved ? "YES" : "no")")
        log((status == .hookVerified ? "✓ " : "✗ ") + result.summary)

        return result
    }

    // MARK: - Image Probe (vmmap)

    /// Read-only check that the dylib is mapped into the launched process's address
    /// space, using `vmmap <pid>`. Independent of the NSLog markers — works even for
    /// a marker-less dylib.
    ///
    /// Call AFTER injection returns a PID. dyld maps DYLD_INSERT_LIBRARIES images
    /// before `main`, so by the time `simctl launch` reports the PID the image is
    /// already present if it was accepted.
    ///
    /// - Returns: a structured result, also stored in `lastImageResult`.
    @discardableResult
    public func probeImage(
        pid: Int?,
        dylibURL: URL
    ) async -> InjectionImageProbeResult {
        let dylibPath = dylibURL.path
        let dylibName = dylibURL.lastPathComponent

        guard let pid else {
            let r = InjectionImageProbeResult(
                status: .unavailable, pid: nil, dylibPath: dylibPath,
                matchedLine: nil, rawError: nil, attempts: 0
            )
            lastImageResult = r
            log("─────────────────────────────────────────")
            log("IMAGE PROBE skipped — no launched PID")
            log("✗ \(r.summary)")
            return r
        }

        guard !isProbingImage else {
            return InjectionImageProbeResult(
                status: .failed, pid: pid, dylibPath: dylibPath,
                matchedLine: nil, rawError: "Image probe already running.", attempts: 0
            )
        }
        isProbingImage = true
        defer { isProbingImage = false }

        log("─────────────────────────────────────────")
        log("IMAGE PROBE pid \(pid) — vmmap ×\(Self.maxProbeAttempts), searching for \"\(dylibName)\"")

        // Bounded retry to absorb launch-timing jitter: the process may not be
        // inspectable for a few hundred ms right after launch, or vmmap output may
        // be partial. 3 attempts × ~0.5s ≈ under 2s total. Returns immediately on a
        // match. dyld maps inserted libraries before main, so a stable, inspectable
        // process that lacks the image is a genuine notMapped — but we still retry a
        // couple of times to rule out a transient early-launch read.
        var lastOutcome: VmmapOutcome?
        var attemptsUsed = 0
        for attempt in 1...Self.maxProbeAttempts {
            attemptsUsed = attempt
            let outcome = await runVmmap(pid: pid)
            lastOutcome = outcome

            if let line = matchLine(in: outcome.stdout, name: dylibName) {
                let result = InjectionImageProbeResult(
                    status: .mapped, pid: pid, dylibPath: dylibPath,
                    matchedLine: line, rawError: nil, attempts: attempt
                )
                lastImageResult = result
                log("  attempt \(attempt): matched")
                log("  ⬑ \(line)")
                log("✓ \(result.summary)")
                return result
            }

            let classification = classify(outcome)
            log("  attempt \(attempt): \(classification.rawValue)"
                + (outcome.stderr.isEmpty ? "" : " — \(outcome.stderr)"))

            // Wait before the next attempt (not after the last one).
            if attempt < Self.maxProbeAttempts {
                try? await Task.sleep(nanoseconds: Self.probeRetryDelayNanos)
            }
        }

        // Loop exhausted with no match — classify the final outcome.
        let result: InjectionImageProbeResult
        switch lastOutcome.map(classify) ?? .hardFailure {
        case .processGone:
            result = InjectionImageProbeResult(
                status: .processExited, pid: pid, dylibPath: dylibPath,
                matchedLine: nil,
                rawError: lastOutcome?.stderr.nilIfBlank ?? "process not inspectable",
                attempts: attemptsUsed
            )
        case .hardFailure:
            result = InjectionImageProbeResult(
                status: .failed, pid: pid, dylibPath: dylibPath,
                matchedLine: nil,
                rawError: lastOutcome?.stderr.nilIfBlank
                    ?? "vmmap exit \(lastOutcome?.exitCode ?? -1)",
                attempts: attemptsUsed
            )
        case .cleanNoMatch:
            result = InjectionImageProbeResult(
                status: .notMapped, pid: pid, dylibPath: dylibPath,
                matchedLine: nil, rawError: nil, attempts: attemptsUsed
            )
        }
        lastImageResult = result
        if let err = result.rawError { log("  ! \(err)") }
        log("✗ \(result.summary)")
        return result
    }

    // MARK: - vmmap classification

    private enum VmmapClassification: String {
        case cleanNoMatch   // vmmap ran, dylib simply absent
        case processGone    // PID not inspectable — exited / no such process
        case hardFailure    // vmmap couldn't run or produced no usable output
    }

    /// Classifies a vmmap outcome that did NOT contain the dylib.
    private func classify(_ outcome: VmmapOutcome) -> VmmapClassification {
        let err = outcome.stderr.lowercased()
        let exited = err.contains("no process found")
            || err.contains("no such process")
            || err.contains("unable to access task")
            || err.contains("could not")
        if exited { return .processGone }
        // Non-zero exit with no usable stdout = couldn't inspect at all.
        if outcome.exitCode != 0 && outcome.stdout.isEmpty { return .hardFailure }
        return .cleanNoMatch
    }

    // MARK: - vmmap process

    /// 3 attempts, ~0.5s apart → total well under 2s.
    private nonisolated static let maxProbeAttempts = 3
    private nonisolated static let probeRetryDelayNanos: UInt64 = 500_000_000

    private struct VmmapOutcome { let stdout: String; let stderr: String; let exitCode: Int32 }

    private func runVmmap(pid: Int) async -> VmmapOutcome {
        // Read-only inspection of the process's mapped regions.
        let result = await ProcessRunner.run(executable: "/usr/bin/vmmap", arguments: [String(pid)])
        return VmmapOutcome(stdout: result.stdout, stderr: result.stderr, exitCode: result.exitCode)
    }

    /// Finds the first vmmap line referencing the dylib by file name.
    private func matchLine(in output: String, name: String) -> String? {
        for raw in output.components(separatedBy: "\n") {
            if raw.contains(name) {
                return raw.trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    // MARK: - Watch

    /// Accumulates the two marker lines across the streamed log lines and the
    /// concurrent timeout task. Thread-safe so the consumer and the timeout can read
    /// a consistent partial snapshot.
    private final class WatchState: @unchecked Sendable {
        private let lock = NSLock()
        private var _loadLine: String?
        private var _hookLine: String?
        private var _failed = false

        /// Records a line against whichever marker it matches. Returns true once
        /// BOTH markers have been seen (signalling the consumer to finish early).
        func record(line: String, loadMarker: String, hookMarker: String) -> Bool {
            lock.lock(); defer { lock.unlock() }
            if _loadLine == nil, line.contains(loadMarker) { _loadLine = line }
            if _hookLine == nil, line.contains(hookMarker) { _hookLine = line }
            return _loadLine != nil && _hookLine != nil
        }

        func markFailed() {
            lock.lock(); defer { lock.unlock() }
            _failed = true
        }

        func snapshot() -> Outcome {
            lock.lock(); defer { lock.unlock() }
            return Outcome(loadLine: _loadLine, hookLine: _hookLine, failed: _failed)
        }
    }

    private struct Outcome {
        let loadLine: String?
        let hookLine: String?
        let failed: Bool
    }

    /// Spawns a marker-scoped `log stream` inside the simulator and resolves as soon
    /// as BOTH markers appear, or when the timeout elapses (with partial evidence).
    private func watchForMarkers(
        udid: String,
        loadMarker: String,
        hookMarker: String,
        timeout: TimeInterval
    ) async -> Outcome {
        // Scope the stream to our marker family so both markers flow through one stream.
        let runner = StreamingProcessRunner(
            executable: "/usr/bin/xcrun",
            arguments: [
                "simctl", "spawn", udid,
                "log", "stream",
                "--style", "compact",
                "--predicate", "eventMessage CONTAINS \"\(Self.markerPrefix)\""
            ],
            environment: SimulatorToolchain.processEnvironment()
        )
        let state = WatchState()

        return await withTaskGroup(of: Outcome.self) { group in
            // Consumer: read streamed lines until both markers seen or the stream exits.
            group.addTask {
                for await event in runner.start() {
                    switch event {
                    case .stdout(let raw):
                        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !line.isEmpty else { continue }
                        if state.record(line: line, loadMarker: loadMarker, hookMarker: hookMarker) {
                            runner.terminate()
                            return state.snapshot()
                        }
                    case .stderr:
                        continue   // discarded, as before
                    case .exit(let code):
                        // -1 is StreamingProcessRunner's launch-failure signal; any
                        // other code means the stream simply ended.
                        if code == -1 { state.markFailed() }
                        return state.snapshot()
                    }
                }
                return state.snapshot()
            }
            // Timeout: finish with whatever partial evidence we have.
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                runner.terminate()
                return state.snapshot()
            }

            let outcome = await group.next() ?? state.snapshot()
            group.cancelAll()
            runner.terminate()
            return outcome
        }
    }

    // MARK: - Helpers

    private func log(_ message: String) {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        logs.append("[\(f.string(from: Date()))] \(message)")
    }
}

private extension String {
    /// nil when the string is empty (stderr is already whitespace-trimmed upstream).
    var nilIfBlank: String? { isEmpty ? nil : self }
}
