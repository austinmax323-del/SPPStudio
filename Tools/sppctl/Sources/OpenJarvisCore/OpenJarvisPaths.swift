import Foundation

public enum OpenJarvisPaths {
    public static func databaseURL(fileManager: FileManager = .default, createDirectory: Bool = true) throws -> URL {
        let base = try appSupportBase(fileManager: fileManager)
        let url = base.appendingPathComponent("SPPStudio/OpenJarvis/openjarvis.sqlite", isDirectory: false)
        if createDirectory {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        return url
    }

    public static func vaultRoot(startingAt start: URL? = nil, fileManager: FileManager = .default) throws -> URL {
        let current = (start ?? URL(fileURLWithPath: fileManager.currentDirectoryPath)).standardizedFileURL
        var cursor = current
        while true {
            let candidate = cursor.appendingPathComponent("SPPStudioDocs", isDirectory: true)
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            let parent = cursor.deletingLastPathComponent()
            if parent.path == cursor.path {
                break
            }
            cursor = parent
        }
        throw NSError(domain: "OpenJarvisPaths", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not locate SPPStudioDocs from \(current.path)"])
    }

    private static func appSupportBase(fileManager: FileManager) throws -> URL {
        let urls = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        guard let url = urls.first else {
            throw NSError(domain: "OpenJarvisPaths", code: 2, userInfo: [NSLocalizedDescriptionKey: "Application Support directory unavailable"])
        }
        return url.appendingPathComponent("SPPStudio", isDirectory: true)
    }
}
