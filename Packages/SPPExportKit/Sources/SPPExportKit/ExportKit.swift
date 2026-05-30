import Foundation
import SPPCore
import SPPHookKit
import SPPTheosKit
import SPPUIBuilderKit

// MARK: - WarningSeverity

/// Describes how critical an export warning is.
public enum WarningSeverity: String, Codable, Hashable, Sendable, CaseIterable {
    /// Informational — the export will succeed without any degradation.
    case info
    /// Advisory — the export will proceed, but the output may be sub-optimal.
    case caution
    /// Fatal — the export cannot succeed until this issue is resolved.
    case blocking
}

// MARK: - ExportWarning

/// A single diagnostic produced during export validation or execution.
public struct ExportWarning: Identifiable, Sendable {
    public let id: UUID
    public let message: String
    public let severity: WarningSeverity

    public init(id: UUID = UUID(), message: String, severity: WarningSeverity) {
        self.id = id
        self.message = message
        self.severity = severity
    }
}

// MARK: - ExportResult

/// The outcome of a successful export pipeline run.
public struct ExportResult: Sendable {
    /// URL of the primary output artifact (file or directory).
    public let outputURL: URL
    /// All warnings collected during validation and execution.
    public let warnings: [ExportWarning]
    /// Wall-clock duration of the export in seconds.
    public let duration: TimeInterval

    public init(outputURL: URL, warnings: [ExportWarning], duration: TimeInterval) {
        self.outputURL = outputURL
        self.warnings = warnings
        self.duration = duration
    }

    /// `true` when at least one warning has `.blocking` severity.
    public var hasBlockingWarnings: Bool {
        warnings.contains { $0.severity == .blocking }
    }
}

// MARK: - ExportContext

/// All inputs required by an `ExportPipeline` to produce its output.
public struct ExportContext: Sendable {
    /// The project being exported.
    public let project: SPPProject
    /// The specific target within the project to export.
    public let target: SPPTarget
    /// Directory where all output artifacts will be written.
    public let outputDirectory: URL
    /// Optional override for the `$THEOS` path used during packaging.
    public let theosPath: String?
    /// Arbitrary string metadata passed through to the pipeline.
    public let additionalMetadata: [String: String]

    public init(
        project: SPPProject,
        target: SPPTarget,
        outputDirectory: URL,
        theosPath: String? = nil,
        additionalMetadata: [String: String] = [:]
    ) {
        self.project = project
        self.target = target
        self.outputDirectory = outputDirectory
        self.theosPath = theosPath
        self.additionalMetadata = additionalMetadata
    }
}

// MARK: - ExportPipeline

/// A self-contained export strategy capable of turning a project context into
/// one or more output artifacts.
public protocol ExportPipeline: Sendable {
    /// Stable, reverse-DNS-style identifier (e.g. `"theos.debian"`).
    var id: String { get }
    /// Human-readable label for display in the UI.
    var displayName: String { get }
    /// Target types this pipeline is capable of handling.
    var supportedTargetTypes: [SPPTarget.TargetType] { get }

    /// Performs the full export and returns the result.
    func export(context: ExportContext) async throws -> ExportResult

    /// Returns any warnings about `context` without performing the export.
    /// Blocking warnings indicate that `export` would definitely fail.
    func validate(context: ExportContext) -> [ExportWarning]
}

// MARK: - TheosDebianPackageExporter

/// Builds a Debian `.deb` package using the Theos build system.
public final class TheosDebianPackageExporter: ExportPipeline, @unchecked Sendable {

    public let id = "theos.debian"
    public let displayName = "Theos Debian Package"
    public let supportedTargetTypes: [SPPTarget.TargetType] = [.logos, .orion, .preferenceBundle]

    public init() {}

    // MARK: Validation

    public func validate(context: ExportContext) -> [ExportWarning] {
        var warnings: [ExportWarning] = []

        // 1. Theos path must be resolvable
        let resolvedTheosPath = context.theosPath
            ?? context.project.theosConfig.theosPath
            ?? ProcessInfo.processInfo.environment["THEOS"]

        if resolvedTheosPath == nil || resolvedTheosPath!.isEmpty {
            warnings.append(ExportWarning(
                message: "No Theos installation path is configured. Set $THEOS or provide a theosPath.",
                severity: .blocking
            ))
        } else if let path = resolvedTheosPath {
            let theosURL = URL(fileURLWithPath: path)
            if (try? TheosInstallationDetector.validateInstallation(at: theosURL)) == nil {
                warnings.append(ExportWarning(
                    message: "Theos installation at '\(path)' appears incomplete (missing vendor/Makefile or lib/).",
                    severity: .blocking
                ))
            }
        }

        // 2. Target must have at least one source file
        let allFiles = context.project.files.flatMap { $0.allFiles() }.filter { !$0.isDirectory }
        if allFiles.isEmpty {
            warnings.append(ExportWarning(
                message: "Target '\(context.target.name)' has no source files. Add at least one source file before exporting.",
                severity: .blocking
            ))
        }

        // 3. Bundle ID should be set
        if context.project.bundleID.isEmpty {
            warnings.append(ExportWarning(
                message: "Project bundle ID is empty. A placeholder will be used in the control file.",
                severity: .caution
            ))
        }

        // 4. Author should be set
        if context.project.author.isEmpty {
            warnings.append(ExportWarning(
                message: "Project author is not set. The control file will use 'Unknown Author'.",
                severity: .info
            ))
        }

        return warnings
    }

    // MARK: Export

    public func export(context: ExportContext) async throws -> ExportResult {
        let startDate = Date()
        var collectedWarnings = validate(context: context)

        // Reject immediately on any blocking warning
        if collectedWarnings.contains(where: { $0.severity == .blocking }) {
            throw SPPError.exportFailed(
                collectedWarnings
                    .filter { $0.severity == .blocking }
                    .map(\.message)
                    .joined(separator: "; ")
            )
        }

        let fm = FileManager.default
        let outputDir = context.outputDirectory

        // 1. Create output directory hierarchy
        try fm.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let sourcesDir = outputDir.appendingPathComponent("Sources")
        try fm.createDirectory(at: sourcesDir, withIntermediateDirectories: true)

        // 2. Write Makefile
        let makefileGenerator = MakefileGenerator()
        let resolvedTheosPath = context.theosPath ?? context.project.theosConfig.theosPath
        let makefileContent = makefileGenerator.generate(
            for: context.project,
            target: context.target,
            theosPath: resolvedTheosPath
        )
        let makefileURL = outputDir.appendingPathComponent("Makefile")
        try makefileContent.write(to: makefileURL, atomically: true, encoding: .utf8)

        // 3. Write control file
        let controlGenerator = ControlFileGenerator()
        let controlContent = controlGenerator.generate(for: context.project)
        let layoutDir = outputDir.appendingPathComponent("layout/DEBIAN")
        try fm.createDirectory(at: layoutDir, withIntermediateDirectories: true)
        let controlURL = layoutDir.appendingPathComponent("control")
        try controlContent.write(to: controlURL, atomically: true, encoding: .utf8)

        // 4. Copy / link source files into Sources/
        let allSourceFiles = context.project.files
            .flatMap { $0.allFiles() }
            .filter { !$0.isDirectory }

        for file in allSourceFiles {
            let destURL = sourcesDir.appendingPathComponent(file.relativePath)
            let destParent = destURL.deletingLastPathComponent()
            if !fm.fileExists(atPath: destParent.path) {
                try fm.createDirectory(at: destParent, withIntermediateDirectories: true)
            }
            // Produce a placeholder stub for each source file so make can resolve paths.
            // In a live workspace the caller should pass real file URLs via additionalMetadata.
            if let sourceBasePath = context.additionalMetadata["sourceBasePath"] {
                let sourceURL = URL(fileURLWithPath: sourceBasePath)
                    .appendingPathComponent(file.relativePath)
                if fm.fileExists(atPath: sourceURL.path), !fm.fileExists(atPath: destURL.path) {
                    try fm.copyItem(at: sourceURL, to: destURL)
                }
            }
        }

        // 5. Run `make package` via MakeRunner
        guard let theosPathResolved = resolvedTheosPath ?? ProcessInfo.processInfo.environment["THEOS"],
              !theosPathResolved.isEmpty else {
            throw SPPError.theosNotFound
        }

        let runner = MakeRunner(theosPath: theosPathResolved, workingDirectory: outputDir)
        var outputLines: [String] = []
        let parser = BuildOutputParser()

        for try await line in await runner.run(target: "package") {
            outputLines.append(line)
            if let diagnostic = parser.parse(line: line) {
                switch diagnostic.kind {
                case .error:
                    collectedWarnings.append(ExportWarning(
                        message: diagnostic.message,
                        severity: .blocking
                    ))
                case .warning:
                    collectedWarnings.append(ExportWarning(
                        message: diagnostic.message,
                        severity: .caution
                    ))
                case .note:
                    collectedWarnings.append(ExportWarning(
                        message: diagnostic.message,
                        severity: .info
                    ))
                }
            }
        }

        // 6. Locate the produced .deb inside packages/
        let packagesDir = outputDir.appendingPathComponent("packages")
        var debURL: URL = outputDir

        if let contents = try? fm.contentsOfDirectory(
            at: packagesDir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ), let deb = contents.first(where: { $0.pathExtension == "deb" }) {
            debURL = deb
        }

        let duration = Date().timeIntervalSince(startDate)
        return ExportResult(outputURL: debURL, warnings: collectedWarnings, duration: duration)
    }
}

// MARK: - RawSourceExporter

/// Copies all project source files into a structured directory and writes a
/// `project.json` manifest. Supports every target type.
public final class RawSourceExporter: ExportPipeline, @unchecked Sendable {

    public let id = "source.raw"
    public let displayName = "Raw Source Archive"
    public let supportedTargetTypes: [SPPTarget.TargetType] = SPPTarget.TargetType.allCases

    public init() {}

    // MARK: Validation

    public func validate(context: ExportContext) -> [ExportWarning] {
        var warnings: [ExportWarning] = []

        let allFiles = context.project.files.flatMap { $0.allFiles() }.filter { !$0.isDirectory }
        if allFiles.isEmpty {
            warnings.append(ExportWarning(
                message: "Project has no source files to archive.",
                severity: .caution
            ))
        }

        return warnings
    }

    // MARK: Export

    public func export(context: ExportContext) async throws -> ExportResult {
        let startDate = Date()
        let warnings = validate(context: context)

        let fm = FileManager.default
        let outputDir = context.outputDirectory
        try fm.createDirectory(at: outputDir, withIntermediateDirectories: true)

        // 1. Create Sources/ sub-directory
        let sourcesDir = outputDir.appendingPathComponent("Sources")
        try fm.createDirectory(at: sourcesDir, withIntermediateDirectories: true)

        // 2. Copy source files
        let allSourceFiles = context.project.files
            .flatMap { $0.allFiles() }
            .filter { !$0.isDirectory }

        if let sourceBasePath = context.additionalMetadata["sourceBasePath"] {
            let baseURL = URL(fileURLWithPath: sourceBasePath)
            for file in allSourceFiles {
                let sourceURL = baseURL.appendingPathComponent(file.relativePath)
                let destURL = sourcesDir.appendingPathComponent(file.relativePath)
                let destParent = destURL.deletingLastPathComponent()
                if !fm.fileExists(atPath: destParent.path) {
                    try fm.createDirectory(at: destParent, withIntermediateDirectories: true)
                }
                if fm.fileExists(atPath: sourceURL.path), !fm.fileExists(atPath: destURL.path) {
                    try fm.copyItem(at: sourceURL, to: destURL)
                }
            }
        }

        // 3. Write project.json manifest
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let projectData = try encoder.encode(context.project)
        let projectJSONURL = outputDir.appendingPathComponent("project.json")
        try projectData.write(to: projectJSONURL, options: .atomicWrite)

        // 4. Create zip archive via /usr/bin/zip
        let archiveName = "\(context.project.name)-source.zip"
        let archiveURL = outputDir.appendingPathComponent(archiveName)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-r", archiveURL.path, "Sources", "project.json"]
        process.currentDirectoryURL = outputDir
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        let outputURL: URL
        if fm.fileExists(atPath: archiveURL.path) {
            outputURL = archiveURL
        } else {
            // Fallback to directory if zip is unavailable
            outputURL = outputDir
        }

        let duration = Date().timeIntervalSince(startDate)
        return ExportResult(outputURL: outputURL, warnings: warnings, duration: duration)
    }
}

// MARK: - ExportPipelineRegistry

/// Thread-safe registry that maps pipeline identifiers to `ExportPipeline` instances.
public actor ExportPipelineRegistry {

    private var pipelines: [String: any ExportPipeline] = [:]

    /// Creates a registry pre-populated with the built-in pipelines.
    public init() {
        let theos = TheosDebianPackageExporter()
        let raw = RawSourceExporter()
        pipelines[theos.id] = theos
        pipelines[raw.id] = raw
    }

    // MARK: Registration

    /// Adds or replaces a pipeline in the registry.
    public func register(_ pipeline: any ExportPipeline) {
        pipelines[pipeline.id] = pipeline
    }

    // MARK: Lookup

    /// Returns the pipeline registered under `id`, or `nil` if not found.
    public func pipeline(id: String) -> (any ExportPipeline)? {
        pipelines[id]
    }

    /// Returns all pipelines that support the given target type.
    public func pipelines(for targetType: SPPTarget.TargetType) -> [any ExportPipeline] {
        pipelines.values.filter { $0.supportedTargetTypes.contains(targetType) }
    }

    /// Returns all registered pipelines.
    public func allPipelines() -> [any ExportPipeline] {
        Array(pipelines.values)
    }
}
