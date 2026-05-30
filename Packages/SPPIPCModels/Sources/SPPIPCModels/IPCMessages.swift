import Foundation

// MARK: - Version

public enum IPCMessageVersion: String, Codable, Sendable {
    case v1 = "1"
}

// MARK: - Envelope

public struct IPCEnvelope<Payload: Codable & Sendable>: Codable, Sendable {
    public let version: IPCMessageVersion
    public let id: UUID
    public let timestamp: Date
    public let payload: Payload

    public init(payload: Payload) {
        self.version = .v1
        self.id = UUID()
        self.timestamp = Date()
        self.payload = payload
    }
}

// MARK: - Commands

public enum IPCCommand: Codable, Sendable {
    case ping
    case getStatus
    case launchComponent(componentID: UUID)
    case updateDocument(document: BuilderDocumentTransfer)
    case applyTheme(theme: ThemeTransfer)
    case captureSnapshot
    case setOrientation(orientation: IPCDeviceOrientation)
    case runReplay(sessionID: UUID)
    case stopReplay

    private enum CodingKeys: String, CodingKey {
        case type
        case componentID
        case document
        case theme
        case orientation
        case sessionID
    }

    private enum CommandType: String, Codable {
        case ping
        case getStatus
        case launchComponent
        case updateDocument
        case applyTheme
        case captureSnapshot
        case setOrientation
        case runReplay
        case stopReplay
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(CommandType.self, forKey: .type)
        switch type {
        case .ping:
            self = .ping
        case .getStatus:
            self = .getStatus
        case .launchComponent:
            let componentID = try container.decode(UUID.self, forKey: .componentID)
            self = .launchComponent(componentID: componentID)
        case .updateDocument:
            let document = try container.decode(BuilderDocumentTransfer.self, forKey: .document)
            self = .updateDocument(document: document)
        case .applyTheme:
            let theme = try container.decode(ThemeTransfer.self, forKey: .theme)
            self = .applyTheme(theme: theme)
        case .captureSnapshot:
            self = .captureSnapshot
        case .setOrientation:
            let orientation = try container.decode(IPCDeviceOrientation.self, forKey: .orientation)
            self = .setOrientation(orientation: orientation)
        case .runReplay:
            let sessionID = try container.decode(UUID.self, forKey: .sessionID)
            self = .runReplay(sessionID: sessionID)
        case .stopReplay:
            self = .stopReplay
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .ping:
            try container.encode(CommandType.ping, forKey: .type)
        case .getStatus:
            try container.encode(CommandType.getStatus, forKey: .type)
        case .launchComponent(let componentID):
            try container.encode(CommandType.launchComponent, forKey: .type)
            try container.encode(componentID, forKey: .componentID)
        case .updateDocument(let document):
            try container.encode(CommandType.updateDocument, forKey: .type)
            try container.encode(document, forKey: .document)
        case .applyTheme(let theme):
            try container.encode(CommandType.applyTheme, forKey: .type)
            try container.encode(theme, forKey: .theme)
        case .captureSnapshot:
            try container.encode(CommandType.captureSnapshot, forKey: .type)
        case .setOrientation(let orientation):
            try container.encode(CommandType.setOrientation, forKey: .type)
            try container.encode(orientation, forKey: .orientation)
        case .runReplay(let sessionID):
            try container.encode(CommandType.runReplay, forKey: .type)
            try container.encode(sessionID, forKey: .sessionID)
        case .stopReplay:
            try container.encode(CommandType.stopReplay, forKey: .type)
        }
    }
}

// MARK: - Responses

public enum IPCResponse: Codable, Sendable {
    case pong(timestamp: Date)
    case status(state: CompanionStateTransfer)
    case snapshotCaptured(imageData: Data, format: IPCImageFormat)
    case acknowledgement(commandID: UUID)
    case error(code: String, message: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case timestamp
        case state
        case imageData
        case format
        case commandID
        case code
        case message
    }

    private enum ResponseType: String, Codable {
        case pong
        case status
        case snapshotCaptured
        case acknowledgement
        case error
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ResponseType.self, forKey: .type)
        switch type {
        case .pong:
            let timestamp = try container.decode(Date.self, forKey: .timestamp)
            self = .pong(timestamp: timestamp)
        case .status:
            let state = try container.decode(CompanionStateTransfer.self, forKey: .state)
            self = .status(state: state)
        case .snapshotCaptured:
            let imageData = try container.decode(Data.self, forKey: .imageData)
            let format = try container.decode(IPCImageFormat.self, forKey: .format)
            self = .snapshotCaptured(imageData: imageData, format: format)
        case .acknowledgement:
            let commandID = try container.decode(UUID.self, forKey: .commandID)
            self = .acknowledgement(commandID: commandID)
        case .error:
            let code = try container.decode(String.self, forKey: .code)
            let message = try container.decode(String.self, forKey: .message)
            self = .error(code: code, message: message)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .pong(let timestamp):
            try container.encode(ResponseType.pong, forKey: .type)
            try container.encode(timestamp, forKey: .timestamp)
        case .status(let state):
            try container.encode(ResponseType.status, forKey: .type)
            try container.encode(state, forKey: .state)
        case .snapshotCaptured(let imageData, let format):
            try container.encode(ResponseType.snapshotCaptured, forKey: .type)
            try container.encode(imageData, forKey: .imageData)
            try container.encode(format, forKey: .format)
        case .acknowledgement(let commandID):
            try container.encode(ResponseType.acknowledgement, forKey: .type)
            try container.encode(commandID, forKey: .commandID)
        case .error(let code, let message):
            try container.encode(ResponseType.error, forKey: .type)
            try container.encode(code, forKey: .code)
            try container.encode(message, forKey: .message)
        }
    }
}

// MARK: - Events

public enum IPCEvent: Codable, Sendable {
    case companionReady(info: CompanionReadyInfo)
    case componentTapped(componentID: UUID, point: IPCPoint)
    case runtimeLog(message: String, level: String)
    case hookTriggered(hookID: String, timestamp: Date)
    case replayFrameAdvanced(frame: Int, timestamp: Date)

    private enum CodingKeys: String, CodingKey {
        case type
        case info
        case componentID
        case point
        case message
        case level
        case hookID
        case timestamp
        case frame
    }

    private enum EventType: String, Codable {
        case companionReady
        case componentTapped
        case runtimeLog
        case hookTriggered
        case replayFrameAdvanced
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(EventType.self, forKey: .type)
        switch type {
        case .companionReady:
            let info = try container.decode(CompanionReadyInfo.self, forKey: .info)
            self = .companionReady(info: info)
        case .componentTapped:
            let componentID = try container.decode(UUID.self, forKey: .componentID)
            let point = try container.decode(IPCPoint.self, forKey: .point)
            self = .componentTapped(componentID: componentID, point: point)
        case .runtimeLog:
            let message = try container.decode(String.self, forKey: .message)
            let level = try container.decode(String.self, forKey: .level)
            self = .runtimeLog(message: message, level: level)
        case .hookTriggered:
            let hookID = try container.decode(String.self, forKey: .hookID)
            let timestamp = try container.decode(Date.self, forKey: .timestamp)
            self = .hookTriggered(hookID: hookID, timestamp: timestamp)
        case .replayFrameAdvanced:
            let frame = try container.decode(Int.self, forKey: .frame)
            let timestamp = try container.decode(Date.self, forKey: .timestamp)
            self = .replayFrameAdvanced(frame: frame, timestamp: timestamp)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .companionReady(let info):
            try container.encode(EventType.companionReady, forKey: .type)
            try container.encode(info, forKey: .info)
        case .componentTapped(let componentID, let point):
            try container.encode(EventType.componentTapped, forKey: .type)
            try container.encode(componentID, forKey: .componentID)
            try container.encode(point, forKey: .point)
        case .runtimeLog(let message, let level):
            try container.encode(EventType.runtimeLog, forKey: .type)
            try container.encode(message, forKey: .message)
            try container.encode(level, forKey: .level)
        case .hookTriggered(let hookID, let timestamp):
            try container.encode(EventType.hookTriggered, forKey: .type)
            try container.encode(hookID, forKey: .hookID)
            try container.encode(timestamp, forKey: .timestamp)
        case .replayFrameAdvanced(let frame, let timestamp):
            try container.encode(EventType.replayFrameAdvanced, forKey: .type)
            try container.encode(frame, forKey: .frame)
            try container.encode(timestamp, forKey: .timestamp)
        }
    }
}

// MARK: - Device Orientation

public enum IPCDeviceOrientation: String, Codable, Sendable {
    case portrait
    case landscapeLeft
    case landscapeRight
    case portraitUpsideDown
}

// MARK: - Image Format

public enum IPCImageFormat: String, Codable, Sendable {
    case png
    case jpeg
}

// MARK: - Geometry

public struct IPCPoint: Codable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = IPCPoint(x: 0, y: 0)
}

public struct IPCRect: Codable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public static let zero = IPCRect(x: 0, y: 0, width: 0, height: 0)

    public var origin: IPCPoint { IPCPoint(x: x, y: y) }
}

// MARK: - Companion Info

public struct CompanionReadyInfo: Codable, Sendable {
    public let deviceID: String
    public let systemVersion: String
    public let appVersion: String

    public init(deviceID: String, systemVersion: String, appVersion: String) {
        self.deviceID = deviceID
        self.systemVersion = systemVersion
        self.appVersion = appVersion
    }
}

// MARK: - Companion State

public struct CompanionStateTransfer: Codable, Sendable {
    public let isConnected: Bool
    public let deviceID: String
    public let currentComponentID: UUID?
    public let orientation: IPCDeviceOrientation

    public init(
        isConnected: Bool,
        deviceID: String,
        currentComponentID: UUID? = nil,
        orientation: IPCDeviceOrientation = .portrait
    ) {
        self.isConnected = isConnected
        self.deviceID = deviceID
        self.currentComponentID = currentComponentID
        self.orientation = orientation
    }
}

// MARK: - Document Transfer

public struct BuilderDocumentTransfer: Codable, Sendable {
    public let documentID: UUID
    public let schemaVersion: Int
    /// Raw JSON blob of the component tree.
    public let componentsJSON: Data

    public init(documentID: UUID = UUID(), schemaVersion: Int, componentsJSON: Data) {
        self.documentID = documentID
        self.schemaVersion = schemaVersion
        self.componentsJSON = componentsJSON
    }
}

// MARK: - Theme Transfer

public struct ThemeTransfer: Codable, Sendable {
    public let themeID: String
    public let colorScheme: String
    public let accentColorHex: String

    public init(themeID: String, colorScheme: String, accentColorHex: String) {
        self.themeID = themeID
        self.colorScheme = colorScheme
        self.accentColorHex = accentColorHex
    }
}
