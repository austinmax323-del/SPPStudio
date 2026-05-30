import ArgumentParser
import Foundation
import SPPCore
import SPPTheosKit

// MARK: - BuildCommand

struct BuildCommand: AsyncParsableCommand {

    // MARK: Configuration

    static let configuration = CommandConfiguration(
        commandName: "build",
        abstract: "Build a .sppproject using Theos",
        discussion: """
        Reads the project bundle at PROJECT_PATH, generates a Theos Makefile,
        and invokes `make package`. Build output is streamed to stdout in real
        time; errors and warnings are highlighted with a summary at the end.
        """
    )

    // MARK: Arguments & Options

    @Argument(help: "Path to the .sppproject bundle")
    var projectPath: String

    @Option(name: .shortAndLong, help: "Target name to build (defaults to the first target)")
    var target: String?

    @Flag(name: .shortAndLong, help: "Show verbose output")
    var verbose: Bool = false

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

        if verbose {
            print("[sppctl] Loaded project '\(project.name)' (v\(project.version))")
            print("[sppctl] Bundle ID: \(project.bundleID)")
        }

        // MARK: Step 2 – Resolve target
        let resolvedTarget: SPPTarget
        if let targetName = target {
            guard let found = project.targets.first(where: { $0.name == targetName }) else {
                let available = project.targets.map(\.name).joined(separator: ", ")
                throw ValidationError(
                    "Target '\(targetName)' not found. Available targets: \(available.isEmpty ? "(none)" : available)"
                )
            }
            resolvedTarget = found
        } else {
            guard let first = project.primaryTarget else {
                throw ValidationError("Project '\(project.name)' contains no targets.")
            }
            resolvedTarget = first
        }

        print("[sppctl] Building target '\(resolvedTarget.name)' (\(resolvedTarget.type.rawValue))")

        // MARK: Step 3 – Detect Theos
        guard let theosURL = TheosInstallationDetector.detect() else {
            throw ValidationError(
                "Theos installation not found. Set the $THEOS environment variable or install Theos to ~/theos."
            )
        }

        if verbose {
            print("[sppctl] Using Theos at: \(theosURL.path)")
        }

        do {
            try TheosInstallationDetector.validateInstallation(at: theosURL)
        } catch {
            throw ValidationError("Theos installation at '\(theosURL.path)' appears incomplete: \(error.localizedDescription)")
        }

        // MARK: Step 4 – Create temporary build directory
        let buildDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sppctl-build-\(project.id.uuidString)", isDirectory: true)

        try FileManager.default.createDirectory(at: buildDir, withIntermediateDirectories: true)

        defer {
            // Best-effort cleanup; leave directory on failure so the user can inspect it.
            try? FileManager.default.removeItem(at: buildDir)
        }

        if verbose {
            print("[sppctl] Build directory: \(buildDir.path)")
        }

        // MARK: Step 5 – Write Makefile
        let makefileGenerator = MakefileGenerator()
        let makefileContent = makefileGenerator.generate(
            for: project,
            target: resolvedTarget,
            theosPath: theosURL.path
        )

        let makefileURL = buildDir.appendingPathComponent("Makefile")
        try makefileContent.write(to: makefileURL, atomically: true, encoding: .utf8)

        // Copy source files from the bundle's Sources/ directory into the build dir
        let sourcesInBundle = bundleURL.appendingPathComponent("Sources")
        let sourcesInBuild  = buildDir.appendingPathComponent("Sources")
        if FileManager.default.fileExists(atPath: sourcesInBundle.path) {
            try FileManager.default.copyItem(at: sourcesInBundle, to: sourcesInBuild)
        } else {
            try FileManager.default.createDirectory(at: sourcesInBuild, withIntermediateDirectories: true)
        }

        if verbose {
            print("[sppctl] Makefile written.")
        }

        // MARK: Step 6 – Run make, stream output
        let runner = MakeRunner(theosPath: theosURL.path, workingDirectory: buildDir)
        let parser = BuildOutputParser()

        var errorCount   = 0
        var warningCount = 0

        print("[sppctl] Starting build…")
        print(String(repeating: "─", count: 60))

        do {
            for try await line in await runner.run(target: "package") {
                if let diagnostic = parser.parse(line: line) {
                    switch diagnostic.kind {
                    case .error:
                        errorCount += 1
                        print("  error: \(diagnostic.message)")
                    case .warning:
                        warningCount += 1
                        print("  warning: \(diagnostic.message)")
                    case .note:
                        if verbose { print("  note: \(diagnostic.message)") }
                    }
                } else {
                    print(line)
                }
            }
        } catch SPPError.buildFailed(let exitCode, _) {
            print(String(repeating: "─", count: 60))
            printSummary(success: false, errorCount: errorCount, warningCount: warningCount)
            throw ExitCode(Int32(exitCode))
        }

        // MARK: Step 7 – Success summary
        print(String(repeating: "─", count: 60))
        printSummary(success: true, errorCount: errorCount, warningCount: warningCount)
    }

    // MARK: Private Helpers

    private func printSummary(success: Bool, errorCount: Int, warningCount: Int) {
        let status = success ? "BUILD SUCCEEDED" : "BUILD FAILED"
        let errStr  = errorCount   == 1 ? "1 error"   : "\(errorCount) errors"
        let warnStr = warningCount == 1 ? "1 warning" : "\(warningCount) warnings"
        print("[sppctl] \(status)  ·  \(errStr), \(warnStr)")
    }
}
