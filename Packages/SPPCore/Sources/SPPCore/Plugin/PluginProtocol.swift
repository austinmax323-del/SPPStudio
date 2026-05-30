import Foundation

// MARK: - Contribution

public enum PluginContribution: Sendable {
    case exporter(id: String, displayName: String)
    case hookParser(id: String, fileExtension: String)
    case runtimeAnalyzer(id: String, displayName: String)
    case uiComponent(id: String, displayName: String)
    case languageExtension(id: String, fileExtension: String)
    case instrumentationAdapter(id: String, displayName: String)
}

// MARK: - Manifest

public struct PluginManifest: Codable, Sendable {
    public let id: String
    public let displayName: String
    public let version: SPPVersion
    public let minimumStudioVersion: SPPVersion
    public let author: String
    public let description: String

    public init(
        id: String,
        displayName: String,
        version: SPPVersion,
        minimumStudioVersion: SPPVersion = .one,
        author: String = "",
        description: String = ""
    ) {
        self.id = id
        self.displayName = displayName
        self.version = version
        self.minimumStudioVersion = minimumStudioVersion
        self.author = author
        self.description = description
    }
}

// MARK: - Activation context

public struct PluginActivationContext: Sendable {
    public let eventBus: EventBus
    public let logger: SPPLogger

    public init(eventBus: EventBus, logger: SPPLogger) {
        self.eventBus = eventBus
        self.logger = logger
    }
}

// MARK: - Protocol

public protocol SPPPlugin: AnyObject, Sendable {
    var manifest: PluginManifest { get }
    var contributions: [PluginContribution] { get }
    func activate(context: PluginActivationContext) async throws
    func deactivate() async
}
