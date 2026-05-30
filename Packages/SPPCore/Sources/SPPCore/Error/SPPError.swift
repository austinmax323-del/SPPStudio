import Foundation

public enum SPPError: LocalizedError, Sendable {
    case projectNotFound(URL)
    case invalidProjectBundle(URL, String)
    case serializationFailed(String)
    case deserializationFailed(String)
    case fileSystemError(String)
    case fileNotFound(String)
    case targetNotFound(String)
    case buildFailed(exitCode: Int, output: String)
    case buildCancelled
    case simulatorError(String)
    case deviceNotFound(String)
    case deviceConnectionFailed(String)
    case exportFailed(String)
    case theosNotFound
    case theosSDKNotFound(String)
    case ipcError(String)
    case pluginError(String, underlying: String?)
    case indexError(String)
    case unsupported(String)

    public var errorDescription: String? {
        switch self {
        case .projectNotFound(let url):
            return "Project not found at: \(url.lastPathComponent)"
        case .invalidProjectBundle(let url, let reason):
            return "Invalid project bundle '\(url.lastPathComponent)': \(reason)"
        case .serializationFailed(let detail):
            return "Failed to serialize project: \(detail)"
        case .deserializationFailed(let detail):
            return "Failed to deserialize project: \(detail)"
        case .fileSystemError(let detail):
            return "File system error: \(detail)"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .targetNotFound(let name):
            return "Target not found: \(name)"
        case .buildFailed(let code, _):
            return "Build failed with exit code \(code)"
        case .buildCancelled:
            return "Build was cancelled"
        case .simulatorError(let detail):
            return "Simulator error: \(detail)"
        case .deviceNotFound(let id):
            return "Device not found: \(id)"
        case .deviceConnectionFailed(let detail):
            return "Device connection failed: \(detail)"
        case .exportFailed(let detail):
            return "Export failed: \(detail)"
        case .theosNotFound:
            return "Theos installation not found. Set $THEOS or install to ~/theos."
        case .theosSDKNotFound(let id):
            return "Theos SDK not found: \(id)"
        case .ipcError(let detail):
            return "IPC error: \(detail)"
        case .pluginError(let id, let underlying):
            let base = "Plugin '\(id)' error"
            return underlying.map { "\(base): \($0)" } ?? base
        case .indexError(let detail):
            return "Source index error: \(detail)"
        case .unsupported(let feature):
            return "Not yet supported: \(feature)"
        }
    }
}
