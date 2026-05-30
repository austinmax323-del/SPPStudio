import ArgumentParser
import Foundation
import SPPCore
import SPPExportKit
import SPPTheosKit

// MARK: - ExportCommand

struct ExportCommand: AsyncParsableCommand {

    // MARK: Configuration

    static let configuration = CommandConfiguration(
        commandName: "export",
        abstract: "Export a .sppproject",
        discussion: """
        Runs the named export pipeline against a .sppproject bundle and writes
        the output artifact to the specified directory (or a timestamped
        subdirectory of the current working directory when --output is omitted).

        Built-in pipeline IDs:
          theos.debian   Build a Debian .deb package via Theos  [default]
          source.raw     Archive all source files as a .zip
        """
    )

    // MARK: Arguments & Options

    @Argument(help: "Path to the .sppproject bundle")
    var projectPath: String

    @Option(name: .shortAndLong, help: "Export pipeline ID (default: theos.debian)")
    var pipeline: String = "theos.debian"

    @Option(name: .shortAndLong, help: "Directory to place the exported artifact (defaults to ./exports/<name>-<timestamp>)")
    var output: String?

    // MARK: Run

    func run() async throws {
        let bundleURL = URL(fileURLWithPath: projectPath).standardizedFileURL

        // MARK: Step 1 – Load project
        let serializer = ProjectSerializer()
        let project: SPPProject
        do {
            project = try serializer.read(from: bundleURL)
        } catch {
            throw ValidationError("Could not read project at '\(projectPath)': \(error.localizedDescription)")
        }

        print("[sppctl] Exporting '\(project.name)' v\(project.version)")

        // MARK: Step 2 – Resolve primary target
        guard let resolvedTarget = project.primaryTarget else {
            throw ValidationError("Project '\(project.name)' contains no targets.")
        }

        print("[sppctl] Target  : \(resolvedTarget.name) (\(resolvedTarget.type.rawValue))")

        // MARK: Step 3 – Locate pipeline
        let registry = ExportPipelineRegistry()
        guard let exportPipeline = await registry.pipeline(id: pipeline) else {
            let available = await registry.allPipelines().map(\.id).sorted().joined(separator: ", ")
            throw ValidationError(
                "Unknown pipeline '\(pipeline)'. Available pipelines: \(available.isEmpty ? "(none)" : available)"
            )
        }

        print("[sppctl] Pipeline: \(exportPipeline.displayName) (\(exportPipeline.id))")

        // Warn if the pipeline does not support this target type
        guard exportPipeline.supportedTargetTypes.contains(resolvedTarget.type) else {
            let supported = exportPipeline.supportedTargetTypes.map(\.rawValue).joined(separator: ", ")
            throw ValidationError(
                "Pipeline '\(exportPipeline.id)' does not support target type '\(resolvedTarget.type.rawValue)'. "
                + "Supported types: \(supported)"
            )
        }

        // MARK: Step 4 – Build ExportContext
        let outputDir = resolveOutputDirectory(projectName: project.name)

        // Detect Theos path for pipelines that need it (best-effort; pipelines validate themselves)
        let theosPath = TheosInstallationDetector.detect()?.path
            ?? project.theosConfig.theosPath

        let sourcesDir = bundleURL.appendingPathComponent("Sources")
        var metadata: [String: String] = [:]
        if FileManager.default.fileExists(atPath: sourcesDir.path) {
            metadata["sourceBasePath"] = sourcesDir.path
        }

        let context = ExportContext(
            project: project,
            target: resolvedTarget,
            outputDirectory: outputDir,
            theosPath: theosPath,
            additionalMetadata: metadata
        )

        // Run pre-export validation and surface any warnings before starting
        let preflightWarnings = exportPipeline.validate(context: context)
        if !preflightWarnings.isEmpty {
            print("[sppctl] Pre-flight warnings:")
            for warning in preflightWarnings {
                let severityLabel: String
                switch warning.severity {
                case .blocking: severityLabel = "BLOCKING"
                case .caution:  severityLabel = "caution"
                case .info:     severityLabel = "info"
                }
                print("  [\(severityLabel)] \(warning.message)")
            }
            if preflightWarnings.contains(where: { $0.severity == .blocking }) {
                print("[sppctl] Export aborted due to blocking warnings.")
                throw ExitCode.failure
            }
        }

        // MARK: Step 5 – Run pipeline
        print(String(repeating: "─", count: 60))
        print("[sppctl] Starting export…")

        let result: ExportResult
        do {
            result = try await exportPipeline.export(context: context)
        } catch {
            print(String(repeating: "─", count: 60))
            print("[sppctl] EXPORT FAILED: \(error.localizedDescription)")
            throw ExitCode.failure
        }

        // MARK: Step 6 – Print result
        print(String(repeating: "─", count: 60))
        print("[sppctl] EXPORT SUCCEEDED")
        print("[sppctl] Output  : \(result.outputURL.path)")
        print(String(format: "[sppctl] Duration: %.1f seconds", result.duration))

        if !result.warnings.isEmpty {
            print("[sppctl] Warnings (\(result.warnings.count)):")
            for warning in result.warnings {
                let label: String
                switch warning.severity {
                case .blocking: label = "blocking"
                case .caution:  label = "caution"
                case .info:     label = "info"
                }
                print("  [\(label)] \(warning.message)")
            }
        }
    }

    // MARK: Private Helpers

    /// Returns the resolved output directory URL.
    /// If `--output` was provided it is used as-is; otherwise a timestamped
    /// subdirectory is created under `./exports/`.
    private func resolveOutputDirectory(projectName: String) -> URL {
        if let outputPath = output {
            return URL(fileURLWithPath: outputPath).standardizedFileURL
        }

        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        let dirName = "\(projectName)-\(timestamp)"
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("exports", isDirectory: true)
            .appendingPathComponent(dirName, isDirectory: true)
    }
}
