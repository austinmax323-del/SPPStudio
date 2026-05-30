import ArgumentParser
import Foundation
import SPPCore

// MARK: - NewCommand

struct NewCommand: AsyncParsableCommand {

    // MARK: Configuration

    static let configuration = CommandConfiguration(
        commandName: "new",
        abstract: "Create a new .sppproject",
        discussion: """
        Scaffolds a new .sppproject bundle at OUTPUT/NAME.sppproject (or the
        current directory when --output is omitted).  Choose a template to
        pre-populate an appropriate source file and target configuration:

          logos       Logos Objective-C tweak  (Tweak.xm)   [default]
          orion       Orion Swift tweak         (Tweak.swift)
          preference  Preference bundle         (RootListController.m)
        """
    )

    // MARK: Arguments & Options

    @Argument(help: "Project name (also used as the bundle directory name)")
    var name: String

    @Option(name: .shortAndLong, help: "Bundle identifier (e.g. com.example.mytweak)")
    var bundleID: String?

    @Option(name: .shortAndLong, help: "Output directory (defaults to the current working directory)")
    var output: String?

    @Option(name: .shortAndLong, help: "Template to use: logos | orion | preference  (default: logos)")
    var template: String = "logos"

    // MARK: Run

    func run() async throws {
        // MARK: Step 1 – Resolve output URL
        let baseURL: URL
        if let outputPath = output {
            baseURL = URL(fileURLWithPath: outputPath).standardizedFileURL
        } else {
            baseURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        }

        let sanitizedName = sanitize(name)
        let bundleURL = baseURL.appendingPathComponent("\(sanitizedName).sppproject", isDirectory: true)

        guard !FileManager.default.fileExists(atPath: bundleURL.path) else {
            throw ValidationError("A project already exists at '\(bundleURL.path)'. Choose a different name or output directory.")
        }

        // MARK: Step 2 – Resolve template
        let resolvedTemplate = TemplateKind(rawValue: template.lowercased()) ?? .logos
        if TemplateKind(rawValue: template.lowercased()) == nil {
            print("[sppctl] Warning: unknown template '\(template)'; defaulting to 'logos'.")
        }

        // MARK: Step 3 – Build project model
        let resolvedBundleID = bundleID ?? "com.example.\(sanitizedName.lowercased())"

        let target   = resolvedTemplate.makeTarget(projectName: sanitizedName)
        let file     = resolvedTemplate.makeSourceFile()

        var project = SPPProject(
            name: sanitizedName,
            displayName: name,
            bundleID: resolvedBundleID,
            targets: [target],
            files: [file]
        )

        // Associate entry file with the target
        if var first = project.targets.first {
            first.entryFileID = file.id
            project.targets[0] = first
        }

        // MARK: Step 4 – Write bundle
        let serializer = ProjectSerializer()
        try serializer.write(project, to: bundleURL)

        // Write the default source file content into Sources/
        let sourcesDir = bundleURL.appendingPathComponent("Sources")
        let sourceFileURL = sourcesDir.appendingPathComponent(file.relativePath)
        let sourceFileDir = sourceFileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: sourceFileDir.path) {
            try FileManager.default.createDirectory(at: sourceFileDir, withIntermediateDirectories: true)
        }
        try resolvedTemplate.defaultSourceContent(projectName: name, bundleID: resolvedBundleID)
            .write(to: sourceFileURL, atomically: true, encoding: .utf8)

        // MARK: Step 5 – Success message
        print("[sppctl] Created '\(name)' at:")
        print("         \(bundleURL.path)")
        print("[sppctl] Template : \(resolvedTemplate.displayName)")
        print("[sppctl] Bundle ID: \(resolvedBundleID)")
        print("[sppctl] Target   : \(target.name) (\(target.type.rawValue))")
        print("[sppctl] Entry    : Sources/\(file.relativePath)")
    }

    // MARK: Private Helpers

    /// Replaces whitespace and non-alphanumeric characters so the name can be
    /// used safely as a file-system component.
    private func sanitize(_ raw: String) -> String {
        let stripped = raw
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
        // Keep alphanumerics, hyphens, underscores, and dots; replace the rest.
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "-_."))
        return String(stripped.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
    }
}

// MARK: - TemplateKind

private enum TemplateKind: String {
    case logos
    case orion
    case preference

    var displayName: String {
        switch self {
        case .logos:      return "Logos Tweak"
        case .orion:      return "Orion Tweak"
        case .preference: return "Preference Bundle"
        }
    }

    func makeTarget(projectName: String) -> SPPTarget {
        switch self {
        case .logos:
            return SPPTarget.defaultLogosTarget(name: projectName)
        case .orion:
            return SPPTarget.defaultOrionTarget(name: projectName)
        case .preference:
            return SPPTarget(
                name: projectName,
                type: .preferenceBundle,
                filterConfig: .empty,
                buildSettings: .default
            )
        }
    }

    func makeSourceFile() -> SPPFile {
        switch self {
        case .logos:
            return SPPFile(
                name: "Tweak.xm",
                relativePath: "Tweak.xm",
                contentType: .logosXM
            )
        case .orion:
            return SPPFile(
                name: "Tweak.swift",
                relativePath: "Tweak.swift",
                contentType: .orionSwift
            )
        case .preference:
            return SPPFile(
                name: "RootListController.m",
                relativePath: "RootListController.m",
                contentType: .objc
            )
        }
    }

    func defaultSourceContent(projectName: String, bundleID: String) -> String {
        switch self {
        case .logos:
            return """
            // \(projectName) — Logos Tweak
            // Generated by sppctl

            %hook SpringBoard

            - (void)applicationDidFinishLaunching:(id)application {
                %orig;
                // TODO: add your hook here
            }

            %end
            """

        case .orion:
            return """
            // \(projectName) — Orion Tweak
            // Generated by sppctl

            import Orion
            import SpringBoardKit

            class SpringBoardHook: ClassHook<SpringBoard> {

                func applicationDidFinishLaunching(_ application: AnyObject) {
                    orig.applicationDidFinishLaunching(application)
                    // TODO: add your hook here
                }
            }
            """

        case .preference:
            return """
            // \(projectName) — Preference Bundle
            // Generated by sppctl

            #import <Preferences/PSListController.h>

            @interface \(projectName.replacingOccurrences(of: "-", with: ""))RootListController : PSListController
            @end

            @implementation \(projectName.replacingOccurrences(of: "-", with: ""))RootListController

            - (NSArray *)specifiers {
                if (!_specifiers) {
                    _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
                }
                return _specifiers;
            }

            @end
            """
        }
    }
}
