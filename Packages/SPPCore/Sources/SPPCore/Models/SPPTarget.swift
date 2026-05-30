import Foundation

public struct SPPTarget: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var type: TargetType
    public var entryFileID: UUID?
    public var dependencies: [String]
    public var filterConfig: FilterPlistConfig
    public var buildSettings: BuildSettings

    public init(
        id: UUID = UUID(),
        name: String,
        type: TargetType,
        entryFileID: UUID? = nil,
        dependencies: [String] = [],
        filterConfig: FilterPlistConfig = .empty,
        buildSettings: BuildSettings = .default
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.entryFileID = entryFileID
        self.dependencies = dependencies
        self.filterConfig = filterConfig
        self.buildSettings = buildSettings
    }

    public enum TargetType: String, Codable, CaseIterable, Sendable {
        case logos
        case orion
        case swiftUIOverlay
        case uikitOverlay
        case preferenceBundle
    }

    public struct BuildSettings: Codable, Hashable, Sendable {
        public var minOSVersion: String
        public var architectures: [Architecture]
        public var extraCFlags: [String]
        public var extraSwiftFlags: [String]
        public var frameworks: [String]
        public var privateFrameworks: [String]

        public init(
            minOSVersion: String = "15.0",
            architectures: [Architecture] = [.arm64],
            extraCFlags: [String] = [],
            extraSwiftFlags: [String] = [],
            frameworks: [String] = [],
            privateFrameworks: [String] = []
        ) {
            self.minOSVersion = minOSVersion
            self.architectures = architectures
            self.extraCFlags = extraCFlags
            self.extraSwiftFlags = extraSwiftFlags
            self.frameworks = frameworks
            self.privateFrameworks = privateFrameworks
        }

        public static let `default` = BuildSettings()
    }

    public struct FilterPlistConfig: Codable, Hashable, Sendable {
        public var bundles: [String]
        public var classes: [String]
        public var executables: [String]

        public init(bundles: [String] = [], classes: [String] = [], executables: [String] = []) {
            self.bundles = bundles; self.classes = classes; self.executables = executables
        }

        public static let empty = FilterPlistConfig()
        public static func springBoard() -> FilterPlistConfig {
            FilterPlistConfig(bundles: ["com.apple.springboard"])
        }
    }
}

public extension SPPTarget {
    static func defaultLogosTarget(name: String = "Tweak") -> SPPTarget {
        SPPTarget(
            name: name,
            type: .logos,
            filterConfig: .springBoard(),
            buildSettings: .default
        )
    }

    static func defaultOrionTarget(name: String = "OrionTweak") -> SPPTarget {
        SPPTarget(
            name: name,
            type: .orion,
            filterConfig: .springBoard(),
            buildSettings: .default
        )
    }
}
