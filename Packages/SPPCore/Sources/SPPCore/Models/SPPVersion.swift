import Foundation

public struct SPPVersion: Codable, Hashable, Sendable {
    public var major: Int
    public var minor: Int
    public var patch: Int
    public var prerelease: String?

    public init(major: Int, minor: Int = 0, patch: Int = 0, prerelease: String? = nil) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
    }

    public static let zero = SPPVersion(major: 0)
    public static let one  = SPPVersion(major: 1)
}

extension SPPVersion: Comparable {
    public static func < (lhs: SPPVersion, rhs: SPPVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}

extension SPPVersion: CustomStringConvertible {
    public var description: String {
        var s = "\(major).\(minor).\(patch)"
        if let pre = prerelease { s += "-\(pre)" }
        return s
    }
}

extension SPPVersion: LosslessStringConvertible {
    public init?(_ description: String) {
        let parts = description.split(separator: "-", maxSplits: 1)
        let versionPart = String(parts[0])
        let nums = versionPart.split(separator: ".").compactMap { Int($0) }
        guard nums.count >= 1 else { return nil }
        self.major = nums[0]
        self.minor = nums.count > 1 ? nums[1] : 0
        self.patch = nums.count > 2 ? nums[2] : 0
        self.prerelease = parts.count > 1 ? String(parts[1]) : nil
    }
}
