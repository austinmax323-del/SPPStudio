import Foundation

// MARK: - SimulatorRunCoordinator

/// Orchestrates the one-click "Run in Simulator" pipeline by SEQUENCING the existing
/// services. It owns the pipeline progression and stop-on-failure policy — and nothing
/// else. It contains no build, preflight, injection, or verification logic of its own;
/// every step is delegated to its owner:
///   - AppEnvironment                  → simulator dylib build + artifact URLs
///   - InjectionPreflightService       → readiness checks
///   - InjectionExecutionService       → DYLD launch
///   - InjectionVerificationService    → marker verification + vmmap image probe
///
/// This exists so SimulatorPanelView stops being the de-facto pipeline owner: the View
/// collects inputs, calls `run`, and renders `stages` / `isRunning`.
@MainActor
public final class SimulatorRunCoordinator: ObservableObject {

    /// One row in the end-to-end pipeline readout. Records a step's outcome; it does
    /// not perform the step.
    public struct RunStage: Identifiable {
        public enum Outcome { case pending, running, passed, failed, warn }
        public let id = UUID()
        public let key: String
        public let label: String
        public var outcome: Outcome = .pending
        public var detail: String = ""
    }

    // MARK: - Published State

    @Published public private(set) var stages: [RunStage] = []
    @Published public private(set) var isRunning = false

    // MARK: - Dependencies

    /// The environment owns this coordinator, so the back-reference is `unowned`.
    private unowned let appEnv: AppEnvironment

    public init(appEnv: AppEnvironment) {
        self.appEnv = appEnv
    }

    /// Clears the readout (used by the View's dismiss control).
    public func reset() {
        stages = []
    }

    // MARK: - Orchestration

    /// Runs the full pipeline for an already-selected, booted simulator target.
    /// Stops at the first hard failure (build / preflight / launch); the evidence
    /// stages are observational and all collected.
    public func run(target: SimulatorTarget, bundleID: String) async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        let preflight    = appEnv.injectionPreflightService
        let injection    = appEnv.injectionExecutionService
        let verification = appEnv.injectionVerificationService

        stages = [
            RunStage(key: "build",     label: "Sim dylib build"),
            RunStage(key: "preflight", label: "Preflight"),
            RunStage(key: "launch",    label: "Launch"),
            RunStage(key: "dylib",     label: "Dylib loaded"),
            RunStage(key: "hook",      label: "Hook fired"),
            RunStage(key: "image",     label: "Image mapped")
        ]

        // ── Stage 1: Simulator dylib build (owned by AppEnvironment) ──────────
        // Simulator preview ONLY needs the iphonesimulator dylib (platform 7).
        // The device .deb/package build is intentionally NOT run here — it stays
        // available through the normal Build/package action. lastBuiltPackageURL
        // is therefore only optional package info downstream (preflight warns, not
        // fails, when it is absent).
        setStage("build", .running)
        let simBuilt = await appEnv.buildSimulatorDylib()   // the only build step
        guard simBuilt, let dylib = appEnv.lastBuiltSimulatorDylibURL,
              FileManager.default.fileExists(atPath: dylib.path) else {
            setStage("build", .failed, "simulator dylib build failed — see Build console")
            return
        }
        setStage("build", .passed, dylib.lastPathComponent)

        // ── Stage 2: Preflight (owned by InjectionPreflightService) ───────────
        setStage("preflight", .running)
        await preflight.run(
            target: target, bundleID: bundleID,
            packageURL: appEnv.lastBuiltPackageURL, dylibURL: dylib
        )
        guard preflight.result?.passed == true else {
            setStage("preflight", .failed, preflight.result?.summary ?? "preflight failed")
            return
        }
        setStage("preflight", .passed, preflight.result?.summary ?? "")

        // ── Stage 3: Launch (owned by InjectionExecutionService) ──────────────
        // Start the marker watcher before launch so the %ctor marker is captured.
        setStage("launch", .running)
        let udid = target.udid
        let verifyTask = Task { await verification.verify(udid: udid, timeout: 10) }
        try? await Task.sleep(nanoseconds: 600_000_000)
        let exec = await injection.inject(target: target, bundleID: bundleID, dylibURL: dylib)
        guard exec.succeeded else {
            setStage("launch", .failed, "exit \(exec.exitCode)")
            _ = await verifyTask.value   // let the watcher finish/timeout cleanly
            return
        }
        setStage("launch", .passed, exec.launchedPID.map { "pid \($0)" } ?? "launched")

        // ── Evidence stages (owned by InjectionVerificationService) ───────────
        // Observational: collect ALL of them; do not abort on a single miss.
        await verification.probeImage(pid: exec.launchedPID, dylibURL: dylib)
        let v = await verifyTask.value

        setStage("dylib", v.loadObserved ? .passed : .failed,
                 v.loadObserved ? "marker seen" : "marker not seen")
        setStage("hook", v.hookObserved ? .passed : .warn,
                 v.hookObserved ? "hook fired" : "not observed")

        switch verification.lastImageResult?.status {
        case .mapped:        setStage("image", .passed, "mapped")
        case .notMapped:     setStage("image", .failed, "not mapped")
        case .processExited: setStage("image", .warn, "process exited")
        case .failed:        setStage("image", .warn, "probe failed")
        case .unavailable:   setStage("image", .warn, "no pid")
        case .none:          setStage("image", .warn, "n/a")
        }
    }

    // MARK: - Inject-only orchestration

    /// Runs the standalone Inject sequence: marker watcher → launch → image probe →
    /// await markers. No build, no preflight, no stage readout — this backs the
    /// panel's Inject button. Orchestration only; every step is delegated to its
    /// owning service.
    public func runInjectOnly(
        target: SimulatorTarget,
        bundleID: String,
        dylibURL: URL
    ) async {
        let injection    = appEnv.injectionExecutionService
        let verification = appEnv.injectionVerificationService

        // Start the load-marker watcher BEFORE launching so the dylib's load-time
        // constructor marker is captured. The watcher owns its own log stream;
        // injection owns the launch. Give the stream a brief head-start to attach,
        // then inject. Await both.
        let udid = target.udid
        // 10s window: load fires immediately at %ctor; the hook (viewDidLoad) fires
        // a beat later once the first view controller loads.
        let verifyTask = Task { await verification.verify(udid: udid, timeout: 10) }
        try? await Task.sleep(nanoseconds: 600_000_000) // 0.6s for log stream to attach
        let exec = await injection.inject(target: target, bundleID: bundleID, dylibURL: dylibURL)

        // Image-list probe: independent of markers. dyld maps the inserted library
        // before main, so the launched PID's address space already contains it (if
        // accepted). Read-only — vmmap only inspects, never modifies.
        await verification.probeImage(pid: exec.launchedPID, dylibURL: dylibURL)

        _ = await verifyTask.value
    }

    // MARK: - Preflight-only orchestration

    /// Runs the standalone Preflight check, backing the panel's Preflight button.
    /// `target` is optional — InjectionPreflightService reports "no simulator
    /// selected" itself when it is nil. Orchestration only; the readiness logic and
    /// all wording live in the preflight service.
    public func runPreflightOnly(
        target: SimulatorTarget?,
        bundleID: String?,
        packageURL: URL?,
        dylibURL: URL?
    ) async {
        await appEnv.injectionPreflightService.run(
            target: target,
            bundleID: bundleID,
            packageURL: packageURL,
            dylibURL: dylibURL
        )
    }

    // MARK: - Stage mutation

    private func setStage(_ key: String, _ outcome: RunStage.Outcome, _ detail: String = "") {
        guard let i = stages.firstIndex(where: { $0.key == key }) else { return }
        stages[i].outcome = outcome
        if !detail.isEmpty { stages[i].detail = detail }
    }
}
