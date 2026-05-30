import Foundation

public struct ProjectSerializer: Sendable {
    private static let projectFileName = "project.json"
    private static let sourcesDir      = "Sources"
    private static let resourcesDir    = "Resources"
    private static let theosDir        = "Theos"
    private static let metaDir         = ".spp"

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - Write

    public func write(_ project: SPPProject, to bundleURL: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: bundleURL, withIntermediateDirectories: true)

        let data = try encode(project)
        let projectFile = bundleURL.appendingPathComponent(Self.projectFileName)
        try data.write(to: projectFile, options: .atomic)

        for sub in [Self.sourcesDir, Self.resourcesDir, Self.theosDir, Self.metaDir] {
            let dir = bundleURL.appendingPathComponent(sub)
            if !fm.fileExists(atPath: dir.path) {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }

        SPPLogger.serialization.info("Wrote project '\(project.name)' to \(bundleURL.lastPathComponent)")
    }

    // MARK: - Read

    public func read(from bundleURL: URL) throws -> SPPProject {
        guard FileManager.default.fileExists(atPath: bundleURL.path) else {
            throw SPPError.projectNotFound(bundleURL)
        }
        let projectFile = bundleURL.appendingPathComponent(Self.projectFileName)
        guard FileManager.default.fileExists(atPath: projectFile.path) else {
            throw SPPError.invalidProjectBundle(bundleURL, "Missing \(Self.projectFileName)")
        }
        let data = try readData(from: projectFile, bundleURL: bundleURL)
        return try decode(data, from: bundleURL)
    }

    // MARK: - Helpers

    public func exists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent(Self.projectFileName).path)
    }

    // MARK: - Private

    private func encode(_ project: SPPProject) throws -> Data {
        do {
            return try encoder.encode(project)
        } catch {
            throw SPPError.serializationFailed(error.localizedDescription)
        }
    }

    private func readData(from file: URL, bundleURL: URL) throws -> Data {
        do {
            return try Data(contentsOf: file)
        } catch {
            throw SPPError.fileSystemError("Cannot read \(file.lastPathComponent): \(error.localizedDescription)")
        }
    }

    private func decode(_ data: Data, from bundleURL: URL) throws -> SPPProject {
        do {
            return try decoder.decode(SPPProject.self, from: data)
        } catch {
            throw SPPError.deserializationFailed(error.localizedDescription)
        }
    }
}
