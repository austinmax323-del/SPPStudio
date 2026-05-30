import ArgumentParser
import Foundation
import SPPCore
import SPPTheosKit

// MARK: - ValidateCommand

struct ValidateCommand: AsyncParsableCommand {

    // MARK: Configuration

    static let configuration = CommandConfiguration(
        commandName: "validate",
        abstract: "Validate a .sppproject bundle",
        discussion: """
        Performs structural validation on a .sppproject bundle: verifies the
        manifest, enumerates targets, checks that registered source files exist
        on disk, and optionally confirms that a Theos installation is reachable.

        Exits with code 0 on PASS, 1 on FAIL.
        """
    )

    // MARK: Arguments & Flags

    @Argument(help: "Path to the .sppproject bundle")
    var projectPath: String

    @Flag(help: "Also check that a valid Theos installation is accessible")
    var checkTheos: Bool = false

    // MARK: Run

    func run() async throws {
        let bundleURL = URL(fileURLWithPath: projectPath).standardizedFileURL

        var passed = true

        func check(_ label: String, _ status: String, ok: Bool) {
            let icon = ok ? "ok" : "FAIL"
            print("  [\(icon)] \(label): \(status)")
            if !ok { passed = false }
        }

        print("[sppctl] Validating: \(bundleURL.lastPathComponent)")
        print(String(repeating: "─", count: 60))

        // MARK: Step 1 – Read project manifest
        let serializer = ProjectSerializer()
        let project: SPPProject

        do {
            project = try serializer.read(from: bundleURL)
            check("Manifest", "'\(project.name)' v\(project.version) — OK", ok: true)
        } catch {
            check("Manifest", error.localizedDescription, ok: false)
            printResult(passed: false)
            throw ExitCode.failure
        }

        // MARK: Step 2 – Check targets
        let targetCount = project.targets.count
        check(
            "Targets",
            targetCount == 0
                ? "no targets defined"
                : "\(targetCount) target\(targetCount == 1 ? "" : "s"): \(project.targets.map(\.name).joined(separator: ", "))",
            ok: targetCount > 0
        )

        // MARK: Step 3 – Check source files exist on disk
        let sourcesDir = bundleURL.appendingPathComponent("Sources")
        let allFiles = project.files.flatMap { $0.allFiles() }.filter { !$0.isDirectory }

        if allFiles.isEmpty {
            check("Source files", "no files registered in the manifest", ok: false)
        } else {
            var missingPaths: [String] = []
            for file in allFiles {
                let onDisk = sourcesDir.appendingPathComponent(file.relativePath)
                if !FileManager.default.fileExists(atPath: onDisk.path) {
                    missingPaths.append(file.relativePath)
                }
            }

            if missingPaths.isEmpty {
                check("Source files", "\(allFiles.count) file\(allFiles.count == 1 ? "" : "s") present", ok: true)
            } else {
                for missing in missingPaths {
                    check("Source file", "'\(missing)' NOT found on disk", ok: false)
                }
            }
        }

        // MARK: Step 4 – Optionally check Theos
        if checkTheos {
            if let theosURL = TheosInstallationDetector.detect() {
                do {
                    try TheosInstallationDetector.validateInstallation(at: theosURL)
                    check("Theos", theosURL.path, ok: true)
                } catch {
                    check("Theos", "installation at '\(theosURL.path)' is incomplete: \(error.localizedDescription)", ok: false)
                }
            } else {
                check("Theos", "not found (set $THEOS or install to ~/theos)", ok: false)
            }
        }

        // MARK: Step 5 – Print final verdict
        print(String(repeating: "─", count: 60))
        printResult(passed: passed)

        if !passed {
            throw ExitCode.failure
        }
    }

    // MARK: Private Helpers

    private func printResult(passed: Bool) {
        print("[sppctl] \(passed ? "PASS" : "FAIL")")
    }
}
