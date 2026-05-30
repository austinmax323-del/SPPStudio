import Foundation

public struct SPPFile: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var relativePath: String
    public var contentType: FileContentType
    public var isDirectory: Bool
    public var children: [SPPFile]

    public init(
        id: UUID = UUID(),
        name: String,
        relativePath: String,
        contentType: FileContentType = .unknown,
        isDirectory: Bool = false,
        children: [SPPFile] = []
    ) {
        self.id = id
        self.name = name
        self.relativePath = relativePath
        self.contentType = contentType
        self.isDirectory = isDirectory
        self.children = children
    }

    public enum FileContentType: String, Codable, Hashable, Sendable, CaseIterable {
        case logosXM       = "logos.xm"
        case orionSwift    = "orion.swift"
        case swift         = "swift"
        case objc          = "objc"
        case objcHeader    = "objc.header"
        case plist         = "plist"
        case makefile      = "makefile"
        case control       = "control"
        case resource      = "resource"
        case sppui         = "sppui"
        case unknown       = "unknown"

        public var systemImageName: String {
            switch self {
            case .logosXM:     return "xmark.seal.fill"
            case .orionSwift:  return "swift"
            case .swift:       return "swift"
            case .objc:        return "c.square.fill"
            case .objcHeader:  return "h.square.fill"
            case .plist:       return "doc.text"
            case .makefile:    return "hammer.fill"
            case .control:     return "doc.badge.gearshape.fill"
            case .resource:    return "photo"
            case .sppui:       return "paintbrush.fill"
            case .unknown:     return "doc"
            }
        }

        public static func infer(from filename: String) -> FileContentType {
            let ext = (filename as NSString).pathExtension.lowercased()
            let base = (filename as NSString).lastPathComponent.lowercased()
            switch ext {
            case "xm":                return .logosXM
            case "swift":             return .swift
            case "m", "mm":           return .objc
            case "h":                 return .objcHeader
            case "plist":             return .plist
            case "sppui":             return .sppui
            default:
                if base == "makefile" { return .makefile }
                if base == "control"  { return .control }
                return .unknown
            }
        }
    }

    public func child(named name: String) -> SPPFile? {
        children.first { $0.name == name }
    }

    public func allFiles() -> [SPPFile] {
        var result = [self]
        for child in children { result.append(contentsOf: child.allFiles()) }
        return result
    }
}
