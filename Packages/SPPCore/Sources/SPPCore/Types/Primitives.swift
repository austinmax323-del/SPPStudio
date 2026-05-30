import Foundation

public struct SPPColor: Codable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
    }

    public static let black    = SPPColor(red: 0,    green: 0,    blue: 0)
    public static let white    = SPPColor(red: 1,    green: 1,    blue: 1)
    public static let clear    = SPPColor(red: 0,    green: 0,    blue: 0,    alpha: 0)
    public static let accent   = SPPColor(red: 0,    green: 0.48, blue: 1)
    public static let red      = SPPColor(red: 1,    green: 0.23, blue: 0.19)
    public static let green    = SPPColor(red: 0.2,  green: 0.78, blue: 0.35)
    public static let orange   = SPPColor(red: 1,    green: 0.58, blue: 0)
}

public struct SPPPoint: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double = 0, y: Double = 0) { self.x = x; self.y = y }
    public static let zero = SPPPoint(x: 0, y: 0)
}

public struct SPPSize: Codable, Hashable, Sendable {
    public var width: Double
    public var height: Double
    public init(width: Double = 0, height: Double = 0) { self.width = width; self.height = height }
    public static let zero = SPPSize(width: 0, height: 0)
}

public struct SPPRect: Codable, Hashable, Sendable {
    public var origin: SPPPoint
    public var size: SPPSize
    public init(origin: SPPPoint = .zero, size: SPPSize = .zero) { self.origin = origin; self.size = size }
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.origin = SPPPoint(x: x, y: y); self.size = SPPSize(width: width, height: height)
    }
    public static let zero = SPPRect(origin: .zero, size: .zero)
    public var minX: Double { origin.x }
    public var minY: Double { origin.y }
    public var maxX: Double { origin.x + size.width }
    public var maxY: Double { origin.y + size.height }
    public var midX: Double { origin.x + size.width / 2 }
    public var midY: Double { origin.y + size.height / 2 }
}

public struct SPPEdgeInsets: Codable, Hashable, Sendable {
    public var top: Double
    public var leading: Double
    public var bottom: Double
    public var trailing: Double
    public init(top: Double = 0, leading: Double = 0, bottom: Double = 0, trailing: Double = 0) {
        self.top = top; self.leading = leading; self.bottom = bottom; self.trailing = trailing
    }
    public init(all value: Double) { self.init(top: value, leading: value, bottom: value, trailing: value) }
    public static let zero = SPPEdgeInsets()
}

public enum Architecture: String, Codable, CaseIterable, Sendable {
    case arm64
    case arm64e
    case x86_64
}

public enum Platform: String, Codable, CaseIterable, Sendable {
    case iOS
    case macOS
    case watchOS
    case tvOS
    case visionOS
}

public enum DevicePlatform: String, Codable, CaseIterable, Sendable {
    case iphone
    case ipad
    case appletv
    case watch
    case mac
    case vision
}

public enum ColorScheme: String, Codable, Sendable {
    case light
    case dark
    case system
}

public struct SourceLocation: Codable, Hashable, Sendable {
    public var fileID: UUID
    public var line: Int
    public var column: Int
    public init(fileID: UUID, line: Int, column: Int = 0) {
        self.fileID = fileID; self.line = line; self.column = column
    }
}

public struct SourceRange: Codable, Hashable, Sendable {
    public var start: SourceLocation
    public var end: SourceLocation
    public init(start: SourceLocation, end: SourceLocation) {
        self.start = start; self.end = end
    }
}
