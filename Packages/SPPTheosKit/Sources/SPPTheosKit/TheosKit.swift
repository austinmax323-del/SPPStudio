import Foundation
import SPPCore

// MARK: - TheosSDK

/// Represents a Theos SDK available for building.
public struct TheosSDK: Codable, Hashable, Sendable {
    /// Unique identifier, e.g. "iPhoneOS16.4.sdk"
    public let id: String
    /// Absolute path to the SDK directory
    public let path: String
    /// Platform name derived from the SDK directory, e.g. "iPhoneOS"
    public let platformName: String
    /// Version string, e.g. "16.4"
    public let version: String
    /// Whether this SDK was provided by Apple (versus an open-source toolchain)
    public let isAppleSDK: Bool

    public init(id: String, path: String, platformName: String, version: String, isAppleSDK: Bool) {
        self.id = id
        self.path = path
        self.platformName = platformName
        self.version = version
        self.isAppleSDK = isAppleSDK
    }
}

// MARK: - NICTemplate

/// Represents a NIC (New Instance Creator) project template.
public struct NICTemplate: Codable, Hashable, Sendable {
    /// NIC template identifier, e.g. "iphone/tweak"
    public let id: String
    /// Human-readable name shown in the UI
    public let displayName: String
    /// The target type this template produces
    public let targetType: SPPTarget.TargetType

    public init(id: String, displayName: String, targetType: SPPTarget.TargetType) {
        self.id = id
        self.displayName = displayName
        self.targetType = targetType
    }
}

// MARK: NICTemplate Presets

public extension NICTemplate {
    /// Logos Objective-C tweak template
    static let logosTweak = NICTemplate(
        id: "iphone/tweak",
        displayName: "Logos Tweak",
        targetType: .logos
    )

    /// Orion Swift tweak template
    static let orionTweak = NICTemplate(
        id: "iphone/orion",
        displayName: "Orion Tweak",
        targetType: .orion
    )

    /// Modern preference bundle template
    static let preferenceBundle = NICTemplate(
        id: "iphone/preference_bundle_modern",
        displayName: "Preference Bundle",
        targetType: .preferenceBundle
    )

    /// All built-in templates
    static let allTemplates: [NICTemplate] = [logosTweak, orionTweak, preferenceBundle]
}

// MARK: - TheosInstallationDetector

/// Locates and validates Theos installations on disk.
public struct TheosInstallationDetector: Sendable {

    private static let candidatePaths: [String] = [
        "~/theos",
        "/opt/theos",
        "/var/jb/usr/share/theos"
    ]

    /// Returns the URL of the first valid Theos installation found.
    ///
    /// Search order:
    /// 1. `$THEOS` environment variable
    /// 2. `~/theos`
    /// 3. `/opt/theos`
    /// 4. `/var/jb/usr/share/theos`
    public static func detect() -> URL? {
        let fm = FileManager.default

        // 1. Check $THEOS env var first
        if let envPath = ProcessInfo.processInfo.environment["THEOS"], !envPath.isEmpty {
            let url = URL(fileURLWithPath: envPath)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                return url
            }
        }

        // 2–4. Try well-known paths
        for rawPath in candidatePaths {
            let expanded = (rawPath as NSString).expandingTildeInPath
            let url = URL(fileURLWithPath: expanded)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                return url
            }
        }

        return nil
    }

    /// Returns all SDK descriptors found inside `<theosURL>/sdks/`.
    public static func availableSDKs(at theosURL: URL) -> [TheosSDK] {
        let sdksURL = theosURL.appendingPathComponent("sdks")
        let fm = FileManager.default

        guard let contents = try? fm.contentsOfDirectory(
            at: sdksURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else {
            return []
        }

        return contents.compactMap { url -> TheosSDK? in
            guard url.pathExtension.lowercased() == "sdk" else { return nil }
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return nil }

            let directoryName = url.lastPathComponent          // e.g. "iPhoneOS16.4.sdk"
            let nameWithoutExtension = url.deletingPathExtension().lastPathComponent  // e.g. "iPhoneOS16.4"

            // Split into platform and version components.
            // Typical naming: PlatformNameX.Y  e.g. iPhoneOS16.4 / AppleTVOS17.0
            var platformName = nameWithoutExtension
            var version = ""
            // Find where the numeric version component begins
            if let range = nameWithoutExtension.range(
                of: #"\d"#,
                options: .regularExpression
            ) {
                platformName = String(nameWithoutExtension[nameWithoutExtension.startIndex..<range.lowerBound])
                version = String(nameWithoutExtension[range.lowerBound...])
            }

            // Heuristic: Apple SDKs have recognisable platform names
            let appleSDKPlatforms: Set<String> = [
                "iPhoneOS", "iPhoneSimulator",
                "MacOSX", "AppleTVOS", "AppleTVSimulator",
                "WatchOS", "WatchSimulator", "XROS", "XRSimulator"
            ]
            let isApple = appleSDKPlatforms.contains(platformName)

            return TheosSDK(
                id: directoryName,
                path: url.path,
                platformName: platformName,
                version: version,
                isAppleSDK: isApple
            )
        }
        .sorted { $0.id < $1.id }
    }

    /// Validates that `url` is a functional Theos installation.
    ///
    /// - Throws: `SPPError.theosNotFound` if the installation appears incomplete.
    public static func validateInstallation(at url: URL) throws {
        let fm = FileManager.default

        // vendor/Makefile is the canonical marker for the Theos Makefile system
        let vendorMakefile = url.appendingPathComponent("vendor/Makefile")
        let libDir = url.appendingPathComponent("lib")

        var isDir: ObjCBool = false

        guard fm.fileExists(atPath: vendorMakefile.path) else {
            throw SPPError.theosNotFound
        }

        guard fm.fileExists(atPath: libDir.path, isDirectory: &isDir), isDir.boolValue else {
            throw SPPError.theosNotFound
        }
    }
}

// MARK: - MakefileGenerator

/// Generates a Theos-compatible Makefile for a project target.
public struct MakefileGenerator: Sendable {

    public init() {}

    /// Generates a complete Makefile string for the given project and target.
    ///
    /// - Parameters:
    ///   - project: The `SPPProject` containing metadata and configuration.
    ///   - target:  The `SPPTarget` whose type and build settings drive content.
    ///   - theosPath: Optional override for the `THEOS` variable. Falls back to `$(THEOS)`.
    /// - Returns: A complete, valid Theos Makefile as a string.
    public func generate(for project: SPPProject, target: SPPTarget, theosPath: String?) -> String {
        let resolvedTheosPath = theosPath ?? project.theosConfig.theosPath ?? "$(shell echo $$THEOS)"
        let scheme = project.theosConfig.packageScheme

        let archs = target.buildSettings.architectures
            .map(\.rawValue)
            .joined(separator: " ")

        let targetName = target.name
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()

        let sourceFiles: [String]
        if target.type == .logos || target.type == .orion {
            // Gather source files from the project; fall back to a conventional name
            let sources = project.files
                .flatMap { $0.allFiles() }
                .filter { !$0.isDirectory }
                .filter { file in
                    switch file.contentType {
                    case .logosXM, .orionSwift, .swift, .objc: return true
                    default: return false
                    }
                }
                .map(\.relativePath)
            sourceFiles = sources.isEmpty ? [targetName + ".xm"] : sources
        } else {
            sourceFiles = []
        }

        let sourceFilesLine = sourceFiles.isEmpty
            ? ""
            : "\(targetName)_FILES = \(sourceFiles.joined(separator: " "))\n"

        let extraCFlags = target.buildSettings.extraCFlags.isEmpty
            ? ""
            : "\(targetName)_CFLAGS = \(target.buildSettings.extraCFlags.joined(separator: " "))\n"

        let frameworks: [String] = target.buildSettings.frameworks
        let frameworksLine = frameworks.isEmpty
            ? ""
            : "\(targetName)_FRAMEWORKS = \(frameworks.joined(separator: " "))\n"

        let privateFrameworks = target.buildSettings.privateFrameworks
        let privateFrameworksLine = privateFrameworks.isEmpty
            ? ""
            : "\(targetName)_PRIVATE_FRAMEWORKS = \(privateFrameworks.joined(separator: " "))\n"

        let includeMk: String
        switch target.type {
        case .logos, .orion:
            includeMk = "tweak.mk"
        case .preferenceBundle:
            includeMk = "preferenceBundle.mk"
        case .swiftUIOverlay, .uikitOverlay:
            includeMk = "tweak.mk"
        }

        var lines: [String] = []

        lines.append("# Generated by SPP Studio — do not edit manually")
        lines.append("")
        lines.append("export THEOS := \(resolvedTheosPath)")
        lines.append("TARGET := iphone:clang:\(target.buildSettings.minOSVersion)")
        lines.append("ARCHS = \(archs)")
        lines.append("THEOS_PACKAGE_SCHEME = \(scheme.rawValue)")
        lines.append("")
        lines.append("include $(THEOS)/makefiles/common.mk")
        lines.append("")
        lines.append("\(makeVariableName(for: target.type)) = \(targetName)")
        if !sourceFilesLine.isEmpty { lines.append(sourceFilesLine.trimmingCharacters(in: .newlines)) }
        if !extraCFlags.isEmpty     { lines.append(extraCFlags.trimmingCharacters(in: .newlines)) }
        if !frameworksLine.isEmpty  { lines.append(frameworksLine.trimmingCharacters(in: .newlines)) }
        if !privateFrameworksLine.isEmpty { lines.append(privateFrameworksLine.trimmingCharacters(in: .newlines)) }
        lines.append("")
        lines.append("before-all::")
        lines.append("\t@echo \"[SPP] Building \(project.displayName) ($(THEOS_PACKAGE_SCHEME))\"")
        lines.append("")
        lines.append("include $(THEOS_MAKE_PATH)/\(includeMk)")

        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: Private Helpers

    private func makeVariableName(for type: SPPTarget.TargetType) -> String {
        switch type {
        case .logos, .orion, .swiftUIOverlay, .uikitOverlay:
            return "TWEAK_NAME"
        case .preferenceBundle:
            return "BUNDLE_NAME"
        }
    }
}

// MARK: - ControlFileGenerator

/// Generates a Debian `control` file for a Theos project.
public struct ControlFileGenerator: Sendable {

    public init() {}

    /// Generates a complete Debian control file string for the given project.
    public func generate(for project: SPPProject) -> String {
        let packageID = project.bundleID.isEmpty
            ? "com.example.\(project.name.lowercased().replacingOccurrences(of: " ", with: ""))"
            : project.bundleID

        let author = project.author.isEmpty ? "Unknown Author" : project.author

        // Standard Theos/dpkg depends
        let target = project.primaryTarget
        var depends = "mobilesubstrate"
        if let targetType = target?.type {
            switch targetType {
            case .orion:
                depends = "eu.cristianszpisjak.orion"
            case .preferenceBundle:
                depends = "preferenceloader, mobilesubstrate"
            default:
                depends = "mobilesubstrate"
            }
        }

        // Rootless packages need `firmware (>= 16.0)` or similar
        let scheme = project.theosConfig.packageScheme
        if scheme == .rootless {
            depends += ", firmware (>= 15.0)"
        }

        let versionString = project.version.description

        var lines: [String] = []
        lines.append("Package: \(packageID)")
        lines.append("Name: \(project.displayName)")
        lines.append("Depends: \(depends)")
        lines.append("Version: \(versionString)")
        lines.append("Architecture: iphoneos-arm64")
        lines.append("Description: \(project.displayName)")
        lines.append("Maintainer: \(author)")
        lines.append("Author: \(author)")
        lines.append("Section: Tweaks")

        return lines.joined(separator: "\n") + "\n"
    }
}

// MARK: - BuildDiagnostic

/// A single compiler or build system diagnostic (error, warning, or note).
public struct BuildDiagnostic: Identifiable, Sendable {
    public let id: UUID
    public let kind: DiagnosticKind
    public let message: String
    public let file: String?
    public let line: Int?
    public let column: Int?

    public init(
        id: UUID = UUID(),
        kind: DiagnosticKind,
        message: String,
        file: String? = nil,
        line: Int? = nil,
        column: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.message = message
        self.file = file
        self.line = line
        self.column = column
    }

    // MARK: DiagnosticKind

    /// Severity level of a build diagnostic.
    public enum DiagnosticKind: String, Sendable {
        case error
        case warning
        case note
    }
}

// MARK: - BuildOutputParser

/// Parses raw make / clang output lines into structured `BuildDiagnostic` values.
public struct BuildOutputParser: Sendable {

    // Patterns:
    // 1. Clang:  file.m:10:5: error: some message
    // 2. Make:   Makefile:3: *** some message. Stop.  (no column)
    private static let clangPattern: NSRegularExpression = {
        // group 1: file, 2: line, 3: column, 4: kind, 5: message
        let pattern = #"^(.+?):(\d+):(\d+):\s*(error|warning|note):\s*(.+)$"#
        return try! NSRegularExpression(pattern: pattern, options: [])
    }()

    private static let makePattern: NSRegularExpression = {
        // group 1: file, 2: line, 3: message
        let pattern = #"^(.+?):(\d+):\s*\*{3}\s*(.+?)\.*\s*(Stop\.)?$"#
        return try! NSRegularExpression(pattern: pattern, options: [])
    }()

    public init() {}

    /// Parses a single output line.
    /// - Returns: A `BuildDiagnostic` if the line matches a known diagnostic format; `nil` otherwise.
    public func parse(line: String) -> BuildDiagnostic? {
        let nsLine = line as NSString
        let range = NSRange(location: 0, length: nsLine.length)

        // Try clang-style first (more specific — has column)
        if let match = Self.clangPattern.firstMatch(in: line, options: [], range: range),
           match.numberOfRanges == 6 {
            let file    = nsLine.substring(with: match.range(at: 1))
            let lineNum = Int(nsLine.substring(with: match.range(at: 2)))
            let col     = Int(nsLine.substring(with: match.range(at: 3)))
            let kindStr = nsLine.substring(with: match.range(at: 4))
            let msg     = nsLine.substring(with: match.range(at: 5))

            let kind: BuildDiagnostic.DiagnosticKind
            switch kindStr {
            case "error":   kind = .error
            case "warning": kind = .warning
            default:        kind = .note
            }

            return BuildDiagnostic(kind: kind, message: msg, file: file, line: lineNum, column: col)
        }

        // Try make-style (file:line: *** message)
        if let match = Self.makePattern.firstMatch(in: line, options: [], range: range),
           match.numberOfRanges >= 4 {
            let file    = nsLine.substring(with: match.range(at: 1))
            let lineNum = Int(nsLine.substring(with: match.range(at: 2)))
            let msg     = nsLine.substring(with: match.range(at: 3))
            return BuildDiagnostic(kind: .error, message: msg, file: file, line: lineNum, column: nil)
        }

        return nil
    }
}

// MARK: - MakeRunner

/// Runs `make` inside a Theos project directory and streams output lines.
public actor MakeRunner {

    public let theosPath: String
    public let workingDirectory: URL

    public init(theosPath: String, workingDirectory: URL) {
        self.theosPath = theosPath
        self.workingDirectory = workingDirectory
    }

    /// Launches `make` and returns an `AsyncThrowingStream` of raw output lines.
    ///
    /// Both stdout and stderr are captured and interleaved in arrival order.
    /// The stream terminates when the process exits. If the process exits with a
    /// non-zero status code the stream throws `SPPError.buildFailed`.
    ///
    /// - Parameters:
    ///   - target:      The make target to build (default: `"package"`).
    ///   - environment: Additional environment variables to pass to the child process.
    public func run(
        target: String = "package",
        environment: [String: String] = [:]
    ) -> AsyncThrowingStream<String, Error> {
        let theosPath = self.theosPath
        let workingDirectory = self.workingDirectory

        return AsyncThrowingStream { continuation in
            Task.detached {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/make")
                process.arguments = [target]
                process.currentDirectoryURL = workingDirectory

                // Build the child environment
                var env = ProcessInfo.processInfo.environment
                env["THEOS"] = theosPath
                env["THEOS_MAKE_PATH"] = "\(theosPath)/makefiles"
                for (key, value) in environment {
                    env[key] = value
                }
                process.environment = env

                // A single pipe captures both stdout and stderr so lines arrive
                // in the order the process writes them.
                let outputPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError  = outputPipe

                do {
                    try process.run()
                } catch {
                    continuation.finish(throwing: error)
                    return
                }

                // Read output line by line
                let handle = outputPipe.fileHandleForReading
                var buffer = Data()

                while true {
                    let chunk = handle.availableData
                    if chunk.isEmpty {
                        // No more data — flush any remaining partial line
                        if !buffer.isEmpty, let partial = String(data: buffer, encoding: .utf8) {
                            continuation.yield(partial)
                        }
                        break
                    }
                    buffer.append(chunk)

                    // Emit complete lines
                    while let newlineRange = buffer.range(of: Data([0x0A])) {
                        let lineData = buffer[buffer.startIndex..<newlineRange.lowerBound]
                        if let lineString = String(data: lineData, encoding: .utf8) {
                            continuation.yield(lineString)
                        }
                        buffer = buffer[newlineRange.upperBound...]
                    }
                }

                process.waitUntilExit()

                let exitCode = Int(process.terminationStatus)
                if exitCode != 0 {
                    continuation.finish(throwing: SPPError.buildFailed(exitCode: exitCode, output: ""))
                } else {
                    continuation.finish()
                }
            }
        }
    }
}
