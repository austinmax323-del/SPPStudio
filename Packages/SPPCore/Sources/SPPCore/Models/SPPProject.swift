import Foundation

public struct SPPProject: Identifiable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var displayName: String
    public var version: SPPVersion
    public var bundleID: String
    public var author: String
    public var targets: [SPPTarget]
    public var files: [SPPFile]
    public var createdAt: Date
    public var modifiedAt: Date
    public var theosConfig: TheosConfiguration
    public var collaborationState: CollaborationState

    public init(
        id: UUID = UUID(),
        name: String,
        displayName: String? = nil,
        version: SPPVersion = SPPVersion(major: 1, minor: 0, patch: 0),
        bundleID: String,
        author: String = "",
        targets: [SPPTarget] = [],
        files: [SPPFile] = [],
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        theosConfig: TheosConfiguration = .default,
        collaborationState: CollaborationState = .empty
    ) {
        self.id = id
        self.name = name
        self.displayName = displayName ?? name
        self.version = version
        self.bundleID = bundleID
        self.author = author
        self.targets = targets
        self.files = files
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.theosConfig = theosConfig
        self.collaborationState = collaborationState
    }

    public var primaryTarget: SPPTarget? { targets.first }

    public func file(with id: UUID) -> SPPFile? {
        files.flatMap { $0.allFiles() }.first { $0.id == id }
    }

    public mutating func upsertFile(_ file: SPPFile) {
        if let idx = files.firstIndex(where: { $0.id == file.id }) {
            files[idx] = file
        } else {
            files.append(file)
        }
    }

    public struct TheosConfiguration: Codable, Sendable {
        public var theosPath: String?
        public var packageScheme: PackageScheme
        public var sdkID: String?
        public var nicTemplateName: String

        public enum PackageScheme: String, Codable, CaseIterable, Sendable {
            case rootful
            case rootless
            case rooted
        }

        public init(
            theosPath: String? = nil,
            packageScheme: PackageScheme = .rootless,
            sdkID: String? = nil,
            nicTemplateName: String = "iphone/tweak"
        ) {
            self.theosPath = theosPath
            self.packageScheme = packageScheme
            self.sdkID = sdkID
            self.nicTemplateName = nicTemplateName
        }

        public static let `default` = TheosConfiguration()
    }

    public struct CollaborationState: Codable, Sendable {
        public var comments: [ProjectComment]
        public var todos: [TODOItem]
        public var reviewNotes: [ReviewNote]

        public init(comments: [ProjectComment] = [], todos: [TODOItem] = [], reviewNotes: [ReviewNote] = []) {
            self.comments = comments; self.todos = todos; self.reviewNotes = reviewNotes
        }

        public static let empty = CollaborationState()
    }

    public struct ProjectComment: Identifiable, Codable, Sendable {
        public let id: UUID
        public var author: String
        public var timestamp: Date
        public var fileID: UUID?
        public var lineNumber: Int?
        public var body: String
        public var resolved: Bool

        public init(id: UUID = UUID(), author: String, timestamp: Date = Date(), fileID: UUID? = nil, lineNumber: Int? = nil, body: String, resolved: Bool = false) {
            self.id = id; self.author = author; self.timestamp = timestamp
            self.fileID = fileID; self.lineNumber = lineNumber
            self.body = body; self.resolved = resolved
        }
    }

    public struct TODOItem: Identifiable, Codable, Sendable {
        public let id: UUID
        public var title: String
        public var fileID: UUID?
        public var lineNumber: Int?
        public var completed: Bool

        public init(id: UUID = UUID(), title: String, fileID: UUID? = nil, lineNumber: Int? = nil, completed: Bool = false) {
            self.id = id; self.title = title; self.fileID = fileID
            self.lineNumber = lineNumber; self.completed = completed
        }
    }

    public struct ReviewNote: Identifiable, Codable, Sendable {
        public let id: UUID
        public var author: String
        public var timestamp: Date
        public var body: String
        public var severity: Severity

        public enum Severity: String, Codable, Sendable { case info, warning, blocking }

        public init(id: UUID = UUID(), author: String, timestamp: Date = Date(), body: String, severity: Severity = .info) {
            self.id = id; self.author = author; self.timestamp = timestamp
            self.body = body; self.severity = severity
        }
    }
}
