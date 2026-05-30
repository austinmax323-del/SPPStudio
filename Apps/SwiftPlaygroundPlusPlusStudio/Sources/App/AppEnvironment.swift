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

    // MARK: - Simulator

    public let simulatorService = SimulatorService()

    // MARK: - Stable References

    public let logger: SPPLogger = .ide
    public let eventBus: EventBus

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()
    private var buildProcess: Process?

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
        guard !isBuilding else { return }
        guard let project = currentProject,
              let projectURL = projectService.currentProjectURL else {
            emit("No project open.", isError: true)
            return
        }
        isBuilding = true
        buildLog.removeAll()
        Task { await runBuild(project: project, at: projectURL) }
    }

    public func stopBuild() {
        buildProcess?.interrupt()
        buildProcess = nil
    }

    public func revealLastPackage() {
        guard let url = lastBuiltPackageURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func runBuild(project: SPPProject, at projectURL: URL) async {
        let start = Date()

        // Ensure Makefile + control exist for legacy projects
        try? projectService.ensureBuildFiles()

        let theosPath = theosInstallPath()
        emit("=== BUILD STARTED: \(project.name) ===", isError: false)
        emit("  Theos: \(theosPath)", isError: false)
        emit("  Directory: \(projectURL.path)", isError: false)

        let process = Process()
        buildProcess = process
        let outPipe = Pipe()
        let errPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/make")
        process.arguments = ["package", "FINALPACKAGE=1"]
        process.currentDirectoryURL = projectURL
        process.standardOutput = outPipe
        process.standardError  = errPipe

        var env = ProcessInfo.processInfo.environment
        env["THEOS"]           = theosPath
        env["THEOS_MAKE_PATH"] = "\(theosPath)/makefiles"
        env["TERM"]            = "dumb"
        env["COLUMNS"]         = "120"
        // Prepend Homebrew bin so ldid is found
        let existingPath = env["PATH"] ?? "/usr/bin:/bin"
        env["PATH"]            = "/opt/homebrew/bin:/usr/local/bin:\(existingPath)"
        process.environment    = env

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] fh in
            guard let text = String(data: fh.availableData, encoding: .utf8),
                  !text.isEmpty else { return }
            let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
            Task { @MainActor [weak self] in
                lines.forEach { self?.emit($0, isError: false) }
            }
        }
        errPipe.fileHandleForReading.readabilityHandler = { [weak self] fh in
            guard let text = String(data: fh.availableData, encoding: .utf8),
                  !text.isEmpty else { return }
            let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
            Task { @MainActor [weak self] in
                lines.forEach { self?.emit($0, isError: $0.lowercased().contains("error:")) }
            }
        }

        do {
            try process.run()
        } catch {
            emit("Failed to launch make: \(error.localizedDescription)", isError: true)
            await MainActor.run { isBuilding = false; buildProcess = nil }
            return
        }

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in cont.resume() }
        }

        outPipe.fileHandleForReading.readabilityHandler = nil
        errPipe.fileHandleForReading.readabilityHandler = nil

        let elapsed = String(format: "%.2fs", Date().timeIntervalSince(start))
        let code = process.terminationStatus
        let success = code == 0

        if success {
            let packageURL = latestDebPackage(in: projectURL)
            await MainActor.run { lastBuiltPackageURL = packageURL }
        }

        emit(success
            ? "=== BUILD SUCCEEDED (\(elapsed)) ==="
            : "=== BUILD FAILED — exit \(code) (\(elapsed)) ===",
             isError: !success)

        await MainActor.run { isBuilding = false; buildProcess = nil }
    }

    private func emit(_ line: String, isError: Bool) {
        Task { @MainActor [weak self] in
            self?.eventBus.publish(BuildOutputLineEvent(line: line, isError: isError))
        }
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
