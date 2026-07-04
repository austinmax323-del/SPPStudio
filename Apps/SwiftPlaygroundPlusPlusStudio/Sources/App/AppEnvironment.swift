import AppKit
import Combine
import Foundation
import SPPCore

// MARK: - AppEnvironment

/// Root application environment object. Bootstraps services, wires the event
/// bus, and vends domain objects to the SwiftUI view hierarchy via
/// `.environmentObject`.
@MainActor
public final class AppEnvironment: ObservableObject {

    // MARK: - Published State

    @Published public var projectService: ProjectService
    @Published public var currentProject: SPPProject?
    @Published public var buildLog: [BuildLogEntry] = []
    @Published public var isBootstrapped: Bool = false
    @Published public var isBuilding: Bool = false
    @Published public var lastBuiltPackageURL: URL?
    /// Device (iphoneos / platform 2) .dylib from .theos/obj/<name>.dylib.
    /// This is the device build product — it will NOT map into a simulator.
    @Published public var lastBuiltDylibURL: URL?
    /// Simulator (iphonesimulator / platform 7) .dylib from
    /// .theos/obj/iphone_simulator/<config>/<name>.dylib. This is the artifact that
    /// can actually be DYLD-injected into a booted simulator. Set only on a
    /// successful simulator build; nil otherwise.
    @Published public var lastBuiltSimulatorDylibURL: URL?

    // MARK: - Simulator / Injection

    public let simulatorService          = SimulatorService()
    public let injectionPreflightService = InjectionPreflightService()
    public let injectionExecutionService = InjectionExecutionService()
    public let injectionVerificationService = InjectionVerificationService()
    /// Orchestrates the Run-in-Simulator pipeline by sequencing the services above.
    /// Lazy so it can hold a back-reference to this environment without an init cycle.
    public private(set) lazy var simulatorRunCoordinator = SimulatorRunCoordinator(appEnv: self)

    // MARK: - Stable References

    public let logger: SPPLogger = .ide
    public let eventBus: EventBus

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()
    /// Cancellation handle for the in-flight build (device or simulator). Backed by a
    /// raw `Process` (runBuild) or a `StreamingProcessRunner` (buildSimulatorDylib);
    /// `stopBuild` cancels via the `BuildCancellable` contract (SIGINT) without caring which.
    private var buildCancellable: (any BuildCancellable)?

    // MARK: - Initialisation

    public init() {
        let bus = EventBus()
        self.eventBus = bus
        self.projectService = ProjectService(eventBus: bus)
    }

    // MARK: - Bootstrap

    /// Call once on first appear. Idempotent.
    public func bootstrap() async {
        guard !isBootstrapped else { return }

        logger.info("Bootstrapping SPPStudio app environment")

        wireProjectState()
        subscribeToBuildOutput()

        isBootstrapped = true
        logger.info("Bootstrap complete")
    }

    // MARK: - Private

    // MARK: - Build

    public func buildCurrentProject() {
        Task { await buildAndWait() }
    }

    /// Awaitable build. Same setup as `buildCurrentProject()` but returns whether the
    /// build succeeded, so orchestration flows (Run in Simulator) can sequence on it.
    /// Reuses the existing `runBuild` — no duplicated build logic.
    @discardableResult
    public func buildAndWait() async -> Bool {
        guard !isBuilding else { return false }
        guard let project = currentProject,
              let projectURL = projectService.currentProjectURL else {
            emit("No project open.", isError: true)
            return false
        }
        isBuilding = true
        buildLog.removeAll()
        lastBuiltPackageURL = nil
        lastBuiltDylibURL   = nil
        return await runBuild(project: project, at: projectURL)
    }

    /// Builds a SEPARATE iphonesimulator (platform 7) dylib so the image can be
    /// DYLD-injected into a booted simulator. This does NOT touch the device
    /// `make package` flow, its artifacts, or `lastBuiltDylibURL` — the two builds
    /// are namespaced by Theos (`.theos/obj/` vs `.theos/obj/iphone_simulator/`).
    ///
    /// Returns true and sets `lastBuiltSimulatorDylibURL` on success.
    @discardableResult
    public func buildSimulatorDylib() async -> Bool {
        guard !isBuilding else { return false }
        guard let project = currentProject,
              let projectURL = projectService.currentProjectURL else {
            emit("No project open.", isError: true)
            return false
        }
        isBuilding = true
        lastBuiltSimulatorDylibURL = nil
        defer { Task { @MainActor in self.isBuilding = false; self.buildCancellable = nil } }

        let start = Date()
        try? projectService.ensureBuildFiles()

        guard let developerDir = await xcodeDeveloperDir() else {
            emit("=== SIMULATOR BUILD FAILED ===", isError: true)
            emit("  Full Xcode not found. The iphonesimulator SDK requires Xcode.app "
                + "(Command Line Tools alone cannot build for the simulator).", isError: true)
            return false
        }

        let theosPath = theosInstallPath()
        let arch = hostSimulatorArch()
        emit("=== SIMULATOR BUILD STARTED: \(project.name) ===", isError: false)
        emit("  DEVELOPER_DIR: \(developerDir)", isError: false)
        emit("  TARGET: simulator:clang:latest:\(Self.simulatorDeploymentMin)  ARCHS: \(arch)", isError: false)

        var env = ProcessInfo.processInfo.environment
        env["THEOS"]           = theosPath
        env["THEOS_MAKE_PATH"] = "\(theosPath)/makefiles"
        env["DEVELOPER_DIR"]   = developerDir   // critical: points xcrun at full Xcode
        env["TERM"]            = "dumb"
        env["COLUMNS"]         = "120"
        let existingPath = env["PATH"] ?? "/usr/bin:/bin"
        env["PATH"]            = "/opt/homebrew/bin:/usr/local/bin:\(existingPath)"

        // Build the dylib only (no packaging). Ad-hoc sign so it loads on the
        // macOS-hosted simulator without an Apple Development identity.
        let runner = StreamingProcessRunner(
            executable: "/usr/bin/make",
            arguments: [
                "TARGET=simulator:clang:latest:\(Self.simulatorDeploymentMin)",
                "ARCHS=\(arch)",
                "TARGET_CODESIGN_FLAGS=--sign -"
            ],
            environment: env,
            workingDirectory: projectURL
        )
        buildCancellable = runner   // so stopBuild can SIGINT this build; cleared in defer

        var exitCode: Int32 = -1
        for await event in runner.start() {
            switch event {
            case .stdout(let line):
                if !line.isEmpty { emit(line, isError: false) }
            case .stderr(let line):
                if !line.isEmpty { emit(line, isError: line.lowercased().contains("error:")) }
            case .exit(let code):
                exitCode = code
            }
        }

        let elapsed = String(format: "%.2fs", Date().timeIntervalSince(start))
        let success = exitCode == 0
        let resolved = success ? builtSimulatorDylib(in: projectURL, projectName: project.name) : nil

        if let dylib = resolved {
            await MainActor.run { lastBuiltSimulatorDylibURL = dylib }
            emit("  Simulator dylib: \(dylib.path)", isError: false)
            emit("=== SIMULATOR BUILD SUCCEEDED (\(elapsed)) ===", isError: false)
            return true
        } else {
            emit(success
                ? "  Simulator dylib not found under .theos/obj/iphone_simulator/ after build."
                : "=== SIMULATOR BUILD FAILED — exit \(exitCode) (\(elapsed)) ===",
                 isError: true)
            return false
        }
    }

    public func stopBuild() {
        buildCancellable?.cancelBuild()
        buildCancellable = nil
    }

    public func revealLastPackage() {
        guard let url = lastBuiltPackageURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @discardableResult
    private func runBuild(project: SPPProject, at projectURL: URL) async -> Bool {
        let start = Date()

        // Ensure Makefile + control exist for legacy projects
        try? projectService.ensureBuildFiles()

        let theosPath = theosInstallPath()
        emit("=== BUILD STARTED: \(project.name) ===", isError: false)
        emit("  Theos: \(theosPath)", isError: false)
        emit("  Directory: \(projectURL.path)", isError: false)

        var env = ProcessInfo.processInfo.environment
        env["THEOS"]           = theosPath
        env["THEOS_MAKE_PATH"] = "\(theosPath)/makefiles"
        env["TERM"]            = "dumb"
        env["COLUMNS"]         = "120"
        // Prepend Homebrew bin so ldid is found
        let existingPath = env["PATH"] ?? "/usr/bin:/bin"
        env["PATH"]            = "/opt/homebrew/bin:/usr/local/bin:\(existingPath)"

        let runner = StreamingProcessRunner(
            executable: "/usr/bin/make",
            arguments: ["package", "FINALPACKAGE=1"],
            environment: env,
            workingDirectory: projectURL
        )
        buildCancellable = runner   // so stopBuild can SIGINT this build; cleared below

        var exitCode: Int32 = -1
        for await event in runner.start() {
            switch event {
            case .stdout(let line):
                if !line.isEmpty { emit(line, isError: false) }
            case .stderr(let line):
                if !line.isEmpty { emit(line, isError: line.lowercased().contains("error:")) }
            case .exit(let code):
                exitCode = code
            }
        }

        let elapsed = String(format: "%.2fs", Date().timeIntervalSince(start))
        let code = exitCode
        let success = code == 0

        if success {
            let packageURL = latestDebPackage(in: projectURL)
            let dylibURL   = builtDylib(in: projectURL, projectName: project.name)
            await MainActor.run {
                lastBuiltPackageURL = packageURL
                lastBuiltDylibURL   = dylibURL
            }
            if let d = dylibURL {
                emit("  Dylib: \(d.path)", isError: false)
            } else {
                emit("  Dylib: not found in .theos/obj/ — preflight injection check will fail", isError: false)
            }
        }

        emit(success
            ? "=== BUILD SUCCEEDED (\(elapsed)) ==="
            : "=== BUILD FAILED — exit \(code) (\(elapsed)) ===",
             isError: !success)

        await MainActor.run { isBuilding = false; buildCancellable = nil }
        return success
    }

    private func emit(_ line: String, isError: Bool) {
        Task { @MainActor [weak self] in
            self?.eventBus.publish(BuildOutputLineEvent(line: line, isError: isError))
        }
    }

    /// Resolves the raw .dylib produced by a Theos build.
    ///
    /// Theos writes the fat (multi-arch) dylib to:
    ///   <project>/.theos/obj/<name>.dylib        ← primary
    ///   <project>/.theos/_/Library/MobileSubstrate/DynamicLibraries/<name>.dylib  ← staged
    ///
    /// The primary path is deterministic: <name> is always `project.name` as set in
    /// the Theos Makefile TWEAK_NAME variable (which SPPStudio sets from SPPProject.name).
    private func builtDylib(in projectURL: URL, projectName: String) -> URL? {
        let fm = FileManager.default

        // Primary: .theos/obj/<name>.dylib — fat binary linking all built arches
        let primary = projectURL
            .appendingPathComponent(".theos/obj/\(projectName).dylib")
        if fm.fileExists(atPath: primary.path) { return primary }

        // Fallback: staged copy used to build the .deb package
        let staged = projectURL
            .appendingPathComponent(".theos/_/Library/MobileSubstrate/DynamicLibraries/\(projectName).dylib")
        if fm.fileExists(atPath: staged.path) { return staged }

        return nil
    }

    // MARK: - Simulator build helpers

    /// Minimum iOS deployment version for the simulator build. A lower min is always
    /// loadable on a higher-OS simulator, so this is intentionally conservative.
    private static let simulatorDeploymentMin = "14.0"

    /// Resolves the iphonesimulator dylib. Theos namespaces simulator output under
    /// `.theos/obj/iphone_simulator/<config>/<name>.dylib` (config defaults to `debug`),
    /// so it never collides with the device build at `.theos/obj/<name>.dylib`.
    private func builtSimulatorDylib(in projectURL: URL, projectName: String) -> URL? {
        let fm = FileManager.default
        let simRoot = projectURL.appendingPathComponent(".theos/obj/iphone_simulator")

        // Preferred deterministic locations first.
        for config in ["debug", "release"] {
            let candidate = simRoot.appendingPathComponent("\(config)/\(projectName).dylib")
            if fm.fileExists(atPath: candidate.path) { return candidate }
        }
        // Fallback: search the simulator obj tree for <name>.dylib (skip dSYM bundles).
        if let enumerator = fm.enumerator(at: simRoot, includingPropertiesForKeys: nil) {
            for case let url as URL in enumerator
            where url.lastPathComponent == "\(projectName).dylib" && !url.path.contains(".dSYM") {
                return url
            }
        }
        return nil
    }

    /// The host architecture to build the simulator slice for (arm64 on Apple Silicon,
    /// x86_64 on Intel). The booted simulator runs natively as a host process.
    private func hostSimulatorArch() -> String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }

    /// Locates a full Xcode developer dir (required for the iphonesimulator SDK).
    /// Command Line Tools alone cannot build for the simulator. Returns nil if no
    /// Xcode with an iPhoneSimulator platform is found.
    private func xcodeDeveloperDir() async -> String? {
        let fm = FileManager.default
        func hasSimulatorPlatform(_ dir: String) -> Bool {
            fm.fileExists(atPath: dir + "/Platforms/iPhoneSimulator.platform")
        }
        // 1. Respect xcode-select if it already points at a real Xcode.
        //    ProcessRunner already returns trimmed stdout (empty on launch failure).
        let selected = await ProcessRunner.run(
            executable: "/usr/bin/xcode-select", arguments: ["-p"]
        ).stdout
        if !selected.isEmpty, hasSimulatorPlatform(selected) {
            return selected
        }
        // 2. Fall back to the conventional Xcode.app location.
        let conventional = "/Applications/Xcode.app/Contents/Developer"
        if hasSimulatorPlatform(conventional) { return conventional }
        return nil
    }

    private func latestDebPackage(in projectURL: URL) -> URL? {
        let packagesDir = projectURL.appendingPathComponent("packages")
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: packagesDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return nil }
        return items
            .filter { $0.pathExtension == "deb" }
            .max {
                let d1 = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let d2 = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return d1 < d2
            }
    }

    private func theosInstallPath() -> String {
        // Check common install locations
        let candidates = [
            ProcessInfo.processInfo.environment["THEOS"],
            "\(NSHomeDirectory())/theos",
            "/opt/theos",
            "/var/theos"
        ]
        return candidates.compactMap { $0 }
            .first { FileManager.default.fileExists(atPath: $0 + "/makefiles/common.mk") }
            ?? "\(NSHomeDirectory())/theos"
    }

    private func wireProjectState() {
        projectService.$currentProject
            .receive(on: RunLoop.main)
            .assign(to: &$currentProject)
    }

    private func subscribeToBuildOutput() {
        eventBus
            .publisher(for: BuildOutputLineEvent.self)
            .receive(on: RunLoop.main)
            .sink { [weak self] event in
                guard let self else { return }
                let entry = BuildLogEntry(
                    text: event.line,
                    isError: event.isError
                )
                self.buildLog.append(entry)
                // Trim the in-memory log to a sane ceiling to avoid unbounded growth.
                if self.buildLog.count > 10_000 {
                    self.buildLog.removeFirst(self.buildLog.count - 10_000)
                }
            }
            .store(in: &cancellables)
    }
}

// MARK: - BuildLogEntry

extension AppEnvironment {

    /// A single line emitted from a build process.
    public struct BuildLogEntry: Identifiable, Sendable {

        public let id: UUID
        public let text: String
        public let isError: Bool
        public let timestamp: Date

        public init(
            id: UUID = UUID(),
            text: String,
            isError: Bool = false,
            timestamp: Date = Date()
        ) {
            self.id = id
            self.text = text
            self.isError = isError
            self.timestamp = timestamp
        }
    }
}
