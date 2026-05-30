import AppKit
import Combine
import Foundation
import SPPCore

// MARK: - ProjectService

/// Manages the lifecycle of SPP projects: create, open, save, and close.
/// All mutating operations are performed on the `@MainActor` and errors are
/// surfaced through `lastError` as well as thrown to the caller.
@MainActor
public final class ProjectService: ObservableObject {

    // MARK: - Published State

    @Published public var currentProject: SPPProject?
    @Published public private(set) var recentProjectURLs: [URL]
    @Published public private(set) var isSaving: Bool = false
    @Published public private(set) var lastError: SPPError?

    // MARK: - Private State

    public private(set) var currentProjectURL: URL?

    // MARK: - Dependencies

    private let serializer = ProjectSerializer()
    private let eventBus: EventBus
    private let logger: SPPLogger = .ide

    // MARK: - UserDefaults Key

    private static let recentsKey = "spp.recentProjects"
    private static let maxRecentProjects = 20

    // MARK: - Init

    public init(eventBus: EventBus) {
        self.eventBus = eventBus
        self.recentProjectURLs = Self.loadRecents()
        logger.info("ProjectService initialised with \(self.recentProjectURLs.count) recent project(s)")
    }

    // MARK: - Create

    /// Creates a new `.sppproject` bundle at `outputDirectory/name.sppproject`,
    /// pre-populated with a default Logos target and a `Tweak.xm` source file.
    public func createProject(
        name: String,
        bundleID: String,
        outputDirectory: URL
    ) async throws -> SPPProject {
        logger.info("Creating project '\(name)' at \(outputDirectory.path)")

        let bundleURL = outputDirectory
            .appendingPathComponent("\(name).sppproject", isDirectory: true)

        // Build default Logos target
        let defaultTarget = SPPTarget.defaultLogosTarget(name: "Tweak")

        // Build a default Tweak.xm source file
        let tweakFile = SPPFile(
            name: "Tweak.xm",
            relativePath: "Sources/Tweak.xm",
            contentType: .logosXM,
            isDirectory: false
        )

        var project = SPPProject(
            name: name,
            displayName: name,
            bundleID: bundleID,
            targets: [defaultTarget],
            files: [tweakFile]
        )

        do {
            try serializer.write(project, to: bundleURL)
        } catch let sppErr as SPPError {
            lastError = sppErr
            logger.error(sppErr)
            throw sppErr
        } catch {
            let sppErr = SPPError.fileSystemError(error.localizedDescription)
            lastError = sppErr
            logger.error(sppErr)
            throw sppErr
        }

        // Write source scaffold
        let sourcesDir = bundleURL.appendingPathComponent("Sources", isDirectory: true)
        let tweakFileURL = sourcesDir.appendingPathComponent("Tweak.xm")
        if !FileManager.default.fileExists(atPath: tweakFileURL.path) {
            try defaultTweakXMScaffold(projectName: name, bundleID: bundleID)
                .write(to: tweakFileURL, atomically: true, encoding: .utf8)
        }

        // Write Theos build files
        let makefileURL = bundleURL.appendingPathComponent("Makefile")
        if !FileManager.default.fileExists(atPath: makefileURL.path) {
            try theosMakefile(projectName: name, bundleID: bundleID)
                .write(to: makefileURL, atomically: true, encoding: .utf8)
        }
        let controlURL = bundleURL.appendingPathComponent("control")
        if !FileManager.default.fileExists(atPath: controlURL.path) {
            try theosControl(projectName: name, bundleID: bundleID)
                .write(to: controlURL, atomically: true, encoding: .utf8)
        }
        let filterPlistURL = bundleURL.appendingPathComponent("\(safeTweakName(name)).plist")
        // (safeTweakName defined below)
        if !FileManager.default.fileExists(atPath: filterPlistURL.path) {
            try theosFilterPlist(bundleID: bundleID)
                .write(to: filterPlistURL, atomically: true, encoding: .utf8)
        }

        currentProject = project
        currentProjectURL = bundleURL
        appendRecent(bundleURL)

        eventBus.publish(ProjectOpenedEvent(projectID: project.id))
        logger.info("Created and opened project '\(name)' (id: \(project.id))")

        return project
    }

    // MARK: - Open

    /// Reads a `.sppproject` bundle from `url` and sets it as the current project.
    public func openProject(at url: URL) async throws {
        logger.info("Opening project at \(url.lastPathComponent)")

        let project: SPPProject
        do {
            project = try serializer.read(from: url)
        } catch let sppErr as SPPError {
            lastError = sppErr
            logger.error(sppErr)
            throw sppErr
        } catch {
            let sppErr = SPPError.fileSystemError(error.localizedDescription)
            lastError = sppErr
            logger.error(sppErr)
            throw sppErr
        }

        currentProject = project
        currentProjectURL = url
        appendRecent(url)

        eventBus.publish(ProjectOpenedEvent(projectID: project.id))
        logger.info("Opened project '\(project.name)' (id: \(project.id))")
    }

    // MARK: - Save

    /// Persists the current project to its on-disk bundle. No-op if there is
    /// no current project. Sets `isSaving` around the write operation.
    public func saveCurrentProject() async throws {
        guard let project = currentProject else {
            logger.warning("saveCurrentProject called with no current project")
            return
        }
        guard let url = currentProjectURL else {
            let err = SPPError.fileSystemError("No bundle URL recorded for current project '\(project.name)'")
            lastError = err
            throw err
        }

        logger.info("Saving project '\(project.name)'")
        isSaving = true
        defer { isSaving = false }

        do {
            try serializer.write(project, to: url)
        } catch let sppErr as SPPError {
            lastError = sppErr
            logger.error(sppErr)
            throw sppErr
        } catch {
            let sppErr = SPPError.fileSystemError(error.localizedDescription)
            lastError = sppErr
            logger.error(sppErr)
            throw sppErr
        }

        eventBus.publish(ProjectSavedEvent(projectID: project.id))
        logger.info("Saved project '\(project.name)'")
    }

    // MARK: - Close

    /// Clears the current project from memory and publishes a close event.
    public func closeProject() {
        guard let project = currentProject else { return }
        logger.info("Closing project '\(project.name)'")
        currentProject = nil
        currentProjectURL = nil
        eventBus.publish(ProjectClosedEvent(projectID: project.id))
    }

    // MARK: - Recents Helpers

    private func appendRecent(_ url: URL) {
        // De-duplicate (keep latest position at front)
        var updated = recentProjectURLs.filter { $0 != url }
        updated.insert(url, at: 0)
        if updated.count > Self.maxRecentProjects {
            updated = Array(updated.prefix(Self.maxRecentProjects))
        }
        recentProjectURLs = updated
        Self.persistRecents(updated)
    }

    private static func loadRecents() -> [URL] {
        guard let bookmarks = UserDefaults.standard.array(forKey: recentsKey) as? [Data] else {
            return []
        }
        return bookmarks.compactMap { data -> URL? in
            var stale = false
            return try? URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
        }
    }

    private static func persistRecents(_ urls: [URL]) {
        let bookmarks: [Data] = urls.compactMap { url in
            try? url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
        UserDefaults.standard.set(bookmarks, forKey: recentsKey)
    }

    // MARK: - File I/O

    public func fileURL(for file: SPPFile) -> URL? {
        currentProjectURL?.appendingPathComponent(file.relativePath)
    }

    public func loadFileContents(_ file: SPPFile) throws -> String {
        guard let url = fileURL(for: file) else {
            throw SPPError.fileSystemError("No project open")
        }
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw SPPError.fileSystemError("Cannot read \(file.name): \(error.localizedDescription)")
        }
    }

    public func saveFileContents(_ contents: String, to file: SPPFile) throws {
        guard let url = fileURL(for: file) else {
            throw SPPError.fileSystemError("No project open")
        }
        do {
            try contents.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw SPPError.fileSystemError("Cannot save \(file.name): \(error.localizedDescription)")
        }
    }

    // MARK: - File Operations

    /// Creates a new file on disk and registers it in the project model.
    @discardableResult
    public func createFile(name: String, contentType: SPPFile.FileContentType, scaffold: String = "") throws -> SPPFile {
        guard let projectURL = currentProjectURL else {
            throw SPPError.fileSystemError("No project open")
        }
        let relativePath = "Sources/\(name)"
        let fileURL = projectURL.appendingPathComponent(relativePath)

        // Ensure Sources dir exists
        let sourcesDir = projectURL.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sourcesDir, withIntermediateDirectories: true)

        guard !FileManager.default.fileExists(atPath: fileURL.path) else {
            throw SPPError.fileSystemError("A file named '\(name)' already exists.")
        }
        try scaffold.write(to: fileURL, atomically: true, encoding: .utf8)

        let newFile = SPPFile(name: name, relativePath: relativePath, contentType: contentType)
        currentProject?.upsertFile(newFile)
        try? serializer.write(currentProject!, to: projectURL)
        logger.info("Created file '\(name)'")
        return newFile
    }

    /// Creates a new file inside a specific directory in the project.
    @discardableResult
    public func createFile(name: String, in parent: SPPFile, contentType: SPPFile.FileContentType, scaffold: String = "") throws -> SPPFile {
        guard let projectURL = currentProjectURL else {
            throw SPPError.fileSystemError("No project open")
        }
        guard parent.isDirectory else {
            throw SPPError.fileSystemError("Parent must be a directory.")
        }
        let relativePath = "\(parent.relativePath)/\(name)"
        let fileURL = projectURL.appendingPathComponent(relativePath)
        let parentURL = projectURL.appendingPathComponent(parent.relativePath, isDirectory: true)
        try FileManager.default.createDirectory(at: parentURL, withIntermediateDirectories: true)
        guard !FileManager.default.fileExists(atPath: fileURL.path) else {
            throw SPPError.fileSystemError("A file named '\(name)' already exists.")
        }
        try scaffold.write(to: fileURL, atomically: true, encoding: .utf8)
        let newFile = SPPFile(name: name, relativePath: relativePath, contentType: contentType)
        currentProject?.upsertFile(newFile)
        try? serializer.write(currentProject!, to: projectURL)
        logger.info("Created file '\(name)' in '\(parent.name)'")
        return newFile
    }

    /// Creates a new subdirectory inside a specific directory in the project.
    @discardableResult
    public func createFolder(name: String, in parent: SPPFile) throws -> SPPFile {
        guard let projectURL = currentProjectURL else {
            throw SPPError.fileSystemError("No project open")
        }
        let relativePath = "\(parent.relativePath)/\(name)"
        let folderURL = projectURL.appendingPathComponent(relativePath)
        guard !FileManager.default.fileExists(atPath: folderURL.path) else {
            throw SPPError.fileSystemError("A folder named '\(name)' already exists.")
        }
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let newFolder = SPPFile(name: name, relativePath: relativePath, isDirectory: true, children: [])
        currentProject?.upsertFile(newFolder)
        try? serializer.write(currentProject!, to: projectURL)
        logger.info("Created folder '\(name)' in '\(parent.name)'")
        return newFolder
    }

    /// Renames a file on disk and updates the project model.
    public func renameFile(_ file: SPPFile, to newName: String) throws {
        guard let projectURL = currentProjectURL else {
            throw SPPError.fileSystemError("No project open")
        }
        let oldURL = projectURL.appendingPathComponent(file.relativePath)
        let newRelative = (file.relativePath as NSString).deletingLastPathComponent + "/\(newName)"
        let newURL = projectURL.appendingPathComponent(newRelative)

        try FileManager.default.moveItem(at: oldURL, to: newURL)

        // Rebuild updated file node
        let updated = SPPFile(
            id: file.id,
            name: newName,
            relativePath: newRelative,
            contentType: SPPFile.FileContentType.infer(from: newName),
            isDirectory: file.isDirectory,
            children: file.children
        )
        currentProject?.upsertFile(updated)
        try? serializer.write(currentProject!, to: projectURL)
        logger.info("Renamed '\(file.name)' → '\(newName)'")
    }

    /// Deletes a file from disk and removes it from the project model.
    public func deleteFile(_ file: SPPFile) throws {
        guard let projectURL = currentProjectURL else {
            throw SPPError.fileSystemError("No project open")
        }
        let url = projectURL.appendingPathComponent(file.relativePath)
        try FileManager.default.removeItem(at: url)

        removeFileFromModel(id: file.id)
        try? serializer.write(currentProject!, to: projectURL)
        logger.info("Deleted '\(file.name)'")
    }

    public func revealInFinder(_ file: SPPFile) {
        guard let url = fileURL(for: file) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func removeFileFromModel(id: UUID) {
        guard var project = currentProject else { return }
        project.files = project.files
            .compactMap { removeFromTree($0, id: id) }
        currentProject = project
    }

    private func removeFromTree(_ node: SPPFile, id: UUID) -> SPPFile? {
        if node.id == id { return nil }
        var updated = node
        updated.children = node.children.compactMap { removeFromTree($0, id: id) }
        return updated
    }

    // MARK: - Scaffolding

    private func theosMakefile(projectName: String, bundleID: String) -> String {
        let safeName = projectName
            .components(separatedBy: .alphanumerics.inverted)
            .joined()
            .nilIfEmpty ?? "Tweak"
        return """
        TARGET := iphone:clang:16.5:14.0
        ARCHS = arm64 arm64e

        include $(THEOS)/makefiles/common.mk

        TWEAK_NAME = \(safeName)
        \(safeName)_FILES = Sources/Tweak.xm
        \(safeName)_CFLAGS = -fobjc-arc

        include $(THEOS_MAKE_PATH)/tweak.mk
        """
    }

    private func theosFilterPlist(bundleID: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Filter</key>
            <dict>
                <key>Bundles</key>
                <array>
                    <string>com.apple.UIKit</string>
                </array>
            </dict>
        </dict>
        </plist>
        """
    }

    private func theosControl(projectName: String, bundleID: String) -> String {
        """
        Package: \(bundleID)
        Name: \(projectName)
        Depends: mobilesubstrate
        Version: 0.0.1
        Architecture: iphoneos-arm
        Description: A Logos tweak created with Swift Playground++ Studio
        Maintainer: Developer
        Author: Developer
        Section: Tweaks
        """
    }

    /// Also writes Makefile+control for existing projects that predate scaffolding.
    public func ensureBuildFiles() throws {
        guard let url = currentProjectURL, let project = currentProject else { return }
        let fm = FileManager.default
        let name = project.name
        let bundleID = project.bundleID
        let makefileURL = url.appendingPathComponent("Makefile")
        if !fm.fileExists(atPath: makefileURL.path) {
            try theosMakefile(projectName: name, bundleID: bundleID)
                .write(to: makefileURL, atomically: true, encoding: .utf8)
        }
        let controlURL = url.appendingPathComponent("control")
        if !fm.fileExists(atPath: controlURL.path) {
            try theosControl(projectName: name, bundleID: bundleID)
                .write(to: controlURL, atomically: true, encoding: .utf8)
        }
        let filterURL = url.appendingPathComponent("\(safeTweakName(name)).plist")
        if !fm.fileExists(atPath: filterURL.path) {
            try theosFilterPlist(bundleID: bundleID)
                .write(to: filterURL, atomically: true, encoding: .utf8)
        }
    }

    private func safeTweakName(_ name: String) -> String {
        name.components(separatedBy: .alphanumerics.inverted).joined().nilIfEmpty ?? "Tweak"
    }

    private func defaultTweakXMScaffold(projectName: String, bundleID: String) -> String {
        """
        // \(projectName) — Tweak.xm
        // Generated by SwiftPlayground++ Studio
        // Bundle target: \(bundleID)

        #import <UIKit/UIKit.h>

        %hook SomeClass

        - (void)someMethod {
            %orig;
        }

        %end
        """
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
