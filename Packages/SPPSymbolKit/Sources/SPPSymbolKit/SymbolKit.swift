import Foundation
import SPPCore

// MARK: - ObjCMethodDescriptor

/// Describes a single Objective-C method (instance or class).
public struct ObjCMethodDescriptor: Codable, Hashable, Sendable {
    /// The Objective-C selector string, e.g. `"initWithFrame:"`.
    public let selector: String

    /// The raw Objective-C type encoding string, e.g. `"v16@0:8"`.
    public let typeEncoding: String

    /// `true` when this is a `+` (class) method; `false` for `-` (instance) methods.
    public let isClassMethod: Bool

    /// Human-readable return type derived from the type encoding, e.g. `"void"`.
    public let returnType: String

    /// Human-readable argument types (excluding the implicit `self` and `_cmd`).
    public let argumentTypes: [String]

    public init(
        selector: String,
        typeEncoding: String,
        isClassMethod: Bool,
        returnType: String,
        argumentTypes: [String]
    ) {
        self.selector = selector
        self.typeEncoding = typeEncoding
        self.isClassMethod = isClassMethod
        self.returnType = returnType
        self.argumentTypes = argumentTypes
    }
}

// MARK: - ObjCClassDescriptor

/// Describes an Objective-C class as discovered in a dyld image.
public struct ObjCClassDescriptor: Codable, Hashable, Sendable {
    /// The class name, e.g. `"NSObject"`.
    public let name: String

    /// The superclass name, if any. `nil` for root classes.
    public let superclassName: String?

    /// Names of protocols the class conforms to.
    public let protocols: [String]

    /// Instance methods declared on the class.
    public let instanceMethods: [ObjCMethodDescriptor]

    /// Class methods (`+` methods) declared on the class.
    public let classMethods: [ObjCMethodDescriptor]

    /// Names of instance variables declared directly on the class.
    public let instanceVariables: [String]

    /// Filesystem path of the image (dylib / framework) that contains this class.
    public let imagePath: String?

    public init(
        name: String,
        superclassName: String? = nil,
        protocols: [String] = [],
        instanceMethods: [ObjCMethodDescriptor] = [],
        classMethods: [ObjCMethodDescriptor] = [],
        instanceVariables: [String] = [],
        imagePath: String? = nil
    ) {
        self.name = name
        self.superclassName = superclassName
        self.protocols = protocols
        self.instanceMethods = instanceMethods
        self.classMethods = classMethods
        self.instanceVariables = instanceVariables
        self.imagePath = imagePath
    }
}

// MARK: - DyldImageDescriptor

/// Describes a loaded dyld image (dylib, framework, or executable).
public struct DyldImageDescriptor: Codable, Hashable, Sendable {
    /// Short display name of the image, e.g. `"UIKit"`.
    public let name: String

    /// Full filesystem path of the image.
    public let path: String

    /// The load address of the image in the current process.
    public let loadAddress: UInt64

    /// The Mach-O build UUID, if available.
    public let uuid: UUID?

    /// `true` when the image lives under a system prefix such as `/usr` or `/System`.
    public let isSystem: Bool

    public init(
        name: String,
        path: String,
        loadAddress: UInt64,
        uuid: UUID? = nil,
        isSystem: Bool
    ) {
        self.name = name
        self.path = path
        self.loadAddress = loadAddress
        self.uuid = uuid
        self.isSystem = isSystem
    }
}

// MARK: - SwiftTypeKind

/// The broad category of a Swift type.
public enum SwiftTypeKind: String, Codable, Hashable, Sendable, CaseIterable {
    case class_    = "class"
    case struct_   = "struct"
    case enum_     = "enum"
    case protocol_ = "protocol"
}

// MARK: - SwiftTypeDescriptor

/// Describes a Swift type as recovered from a dyld image's reflection metadata.
public struct SwiftTypeDescriptor: Codable, Hashable, Sendable {
    /// The unqualified type name, e.g. `"MyViewController"`.
    public let name: String

    /// The mangled type name, e.g. `"$s9MyModule18MyViewControllerC"`.
    public let mangledName: String

    /// Whether this is a class, struct, enum, or protocol.
    public let kind: SwiftTypeKind

    /// The Swift module that defines this type.
    public let moduleName: String

    /// The superclass name, if any (relevant only for `class_` types).
    public let superclassName: String?

    /// Names of protocols this type conforms to.
    public let conformances: [String]

    public init(
        name: String,
        mangledName: String,
        kind: SwiftTypeKind,
        moduleName: String,
        superclassName: String? = nil,
        conformances: [String] = []
    ) {
        self.name = name
        self.mangledName = mangledName
        self.kind = kind
        self.moduleName = moduleName
        self.superclassName = superclassName
        self.conformances = conformances
    }
}

// MARK: - SymbolSearchQuery

/// Parameters that drive a search against a `SymbolIndex`.
public struct SymbolSearchQuery: Sendable {
    /// The substring to match against (case-insensitive).
    public let text: String

    /// Whether to include Objective-C class results. Defaults to `true`.
    public let includeObjC: Bool

    /// Whether to include Swift type results. Defaults to `true`.
    public let includeSwift: Bool

    /// Whether to include dyld image results. Defaults to `false`.
    public let includeImages: Bool

    /// Maximum number of results to return. Defaults to `50`.
    public let maxResults: Int

    public init(
        text: String,
        includeObjC: Bool = true,
        includeSwift: Bool = true,
        includeImages: Bool = false,
        maxResults: Int = 50
    ) {
        self.text = text
        self.includeObjC = includeObjC
        self.includeSwift = includeSwift
        self.includeImages = includeImages
        self.maxResults = maxResults
    }
}

// MARK: - SymbolSearchResult

/// A single result returned from `SymbolIndex.search(_:)`.
public enum SymbolSearchResult: Sendable {
    case objcClass(ObjCClassDescriptor)
    case swiftType(SwiftTypeDescriptor)
    case image(DyldImageDescriptor)

    /// The primary display name of the wrapped value.
    public var displayName: String {
        switch self {
        case .objcClass(let descriptor):
            return descriptor.name
        case .swiftType(let descriptor):
            return descriptor.name
        case .image(let descriptor):
            return descriptor.name
        }
    }
}

// MARK: - SymbolIndex

/// An actor that maintains in-memory indexes of ObjC classes, Swift types, and dyld images
/// and provides efficient search across them.
public actor SymbolIndex {

    // MARK: Storage

    private var objcClasses: [String: ObjCClassDescriptor] = [:]
    private var swiftTypes: [String: SwiftTypeDescriptor] = [:]
    private var images: [String: DyldImageDescriptor] = [:]

    public init() {}

    // MARK: Ingestion

    /// Merges the supplied Objective-C class descriptors into the index, keyed by class name.
    /// Duplicate keys are overwritten with the newest value.
    public func ingest(classes: [ObjCClassDescriptor]) {
        for descriptor in classes {
            objcClasses[descriptor.name] = descriptor
        }
    }

    /// Merges the supplied Swift type descriptors into the index, keyed by mangled name.
    /// Duplicate keys are overwritten with the newest value.
    public func ingest(types: [SwiftTypeDescriptor]) {
        for descriptor in types {
            swiftTypes[descriptor.mangledName] = descriptor
        }
    }

    /// Merges the supplied dyld image descriptors into the index, keyed by path.
    /// Duplicate keys are overwritten with the newest value.
    public func ingest(images newImages: [DyldImageDescriptor]) {
        for descriptor in newImages {
            images[descriptor.path] = descriptor
        }
    }

    // MARK: Search

    /// Searches the index using the provided query.
    ///
    /// Results are ordered: ObjC classes first, then Swift types, then images.
    /// The total number of results is capped at `query.maxResults`.
    public func search(_ query: SymbolSearchQuery) -> [SymbolSearchResult] {
        let needle = query.text.lowercased()
        var results: [SymbolSearchResult] = []
        results.reserveCapacity(min(query.maxResults, objcClasses.count + swiftTypes.count + images.count))

        if query.includeObjC {
            for descriptor in objcClasses.values {
                guard results.count < query.maxResults else { break }
                if descriptor.name.lowercased().contains(needle) {
                    results.append(.objcClass(descriptor))
                }
            }
        }

        if query.includeSwift {
            for descriptor in swiftTypes.values {
                guard results.count < query.maxResults else { break }
                if descriptor.name.lowercased().contains(needle) {
                    results.append(.swiftType(descriptor))
                }
            }
        }

        if query.includeImages {
            for descriptor in images.values {
                guard results.count < query.maxResults else { break }
                if descriptor.name.lowercased().contains(needle) {
                    results.append(.image(descriptor))
                }
            }
        }

        return results
    }

    // MARK: Point Lookups

    /// Returns the ObjC class descriptor for the given class name, or `nil` if not indexed.
    public func objcClass(named name: String) -> ObjCClassDescriptor? {
        objcClasses[name]
    }

    /// Returns the Swift type descriptor for the given mangled name, or `nil` if not indexed.
    public func swiftType(mangledName: String) -> SwiftTypeDescriptor? {
        swiftTypes[mangledName]
    }

    // MARK: Maintenance

    /// Removes all entries from the index.
    public func clear() {
        objcClasses.removeAll()
        swiftTypes.removeAll()
        images.removeAll()
    }
}

// MARK: - SymbolProvider

/// A type that can asynchronously load symbol data for ingestion into a `SymbolIndex`.
public protocol SymbolProvider: Sendable {
    /// Loads and returns all available symbol data.
    ///
    /// Implementations may read from dyld, a cached database, a network source, etc.
    /// Throws if the data cannot be loaded.
    func loadSymbols() async throws -> (
        classes: [ObjCClassDescriptor],
        types: [SwiftTypeDescriptor],
        images: [DyldImageDescriptor]
    )
}
