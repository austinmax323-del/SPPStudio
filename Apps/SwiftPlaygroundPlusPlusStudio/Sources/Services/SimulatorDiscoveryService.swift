import Foundation
import SPPDeviceKit

// MARK: - SimulatorTarget

/// Injection-focused simulator model. Combines identity, runtime, and boot state
/// into one value — avoids the separate Set<bootedID> pattern used by SimulatorService.
public struct SimulatorTarget: Identifiable, Hashable, Sendable {

    // MARK: - Boot State

    public enum BootState: String, Sendable, Hashable, CaseIterable {
        case booted, booting, shutdown, unknown

        public var isUsable: Bool { self == .booted }

        public var displayName: String {
            switch self {
            case .booted:   return "Booted"
            case .booting:  return "Booting"
            case .shutdown: return "Shutdown"
            case .unknown:  return "Unknown"
            }
        }
    }

    // MARK: - Process Target

    /// A user-installed app that can receive a tweak injection on this simulator.
    public struct ProcessTarget: Identifiable, Hashable, Sendable {
        public let id: String       // bundle ID
        public let bundleID: String
        public let displayName: String
        public let version: String
    }

    // MARK: - Fields

    public let id: String           // = udid; satisfies Identifiable
    public let udid: String
    public let name: String
    public let runtime: String      // e.g. "iOS 17.5"
    public let bootState: BootState
    public var processTargets: [ProcessTarget]

    public init(
        udid: String,
        name: String,
        runtime: String,
        bootState: BootState,
        processTargets: [ProcessTarget] = []
    ) {
        self.id = udid
        self.udid = udid
        self.name = name
        self.runtime = runtime
        self.bootState = bootState
        self.processTargets = processTargets
    }

    public var displayName: String { "\(name) (\(runtime))" }
    public var isUsable: Bool { bootState.isUsable }
}

// MARK: - SPPDevice bridge

extension SimulatorTarget {
    /// Construct a SimulatorTarget from the existing SPPDevice model + a known boot state.
    /// Use this when SimulatorService already has the discovery result cached.
    public init(device: SPPDevice, bootState: BootState) {
        self.init(
            udid: device.id,
            name: device.name,
            runtime: device.systemVersion,
            bootState: bootState
        )
    }

    /// Construct a SimulatorTarget from an SPPDevice, deriving boot state from the
    /// set of booted UDIDs that SimulatorService maintains: booted if present,
    /// shutdown otherwise.
    public init(device: SPPDevice, bootedIDs: Set<String>) {
        self.init(
            device: device,
            bootState: bootedIDs.contains(device.id) ? .booted : .shutdown
        )
    }
}

// MARK: - SimulatorDiscoveryService

/// Injection-focused discovery service. Returns SimulatorTarget values with boot
/// state embedded rather than tracking them in a separate Set.
///
/// Separate from SimulatorService deliberately — injection state ownership must not
/// bleed into the syslog / session management service.
public actor SimulatorDiscoveryService {

    public init() {}

    // MARK: - Discovery

    /// Returns all available simulators with their current boot state.
    /// Returns [] if xcrun or simctl is unavailable; never throws.
    public func discoverTargets() async -> [SimulatorTarget] {
        let result = await ProcessRunner.run(
            executable: "/usr/bin/xcrun",
            arguments: ["simctl", "list", "devices", "--json"],
            environment: SimulatorToolchain.processEnvironment()
        )
        guard result.succeeded else { return [] }
        return parse(Data(result.stdout.utf8))
    }

    /// Returns only booted simulators.
    public func bootedTargets() async -> [SimulatorTarget] {
        await discoverTargets().filter { $0.bootState == .booted }
    }

    /// Re-checks a single UDID for its current boot state.
    /// Useful for staleness detection before running preflight.
    public func refreshBootState(udid: String) async -> SimulatorTarget.BootState {
        let all = await discoverTargets()
        return all.first(where: { $0.udid == udid })?.bootState ?? .unknown
    }

    // MARK: - Process Targets

    /// Fetches user-installed apps on the given booted simulator.
    /// These are the injectable process targets.
    public func fetchProcessTargets(for udid: String) async -> [SimulatorTarget.ProcessTarget] {
        let result = await ProcessRunner.run(
            executable: "/usr/bin/xcrun",
            arguments: ["simctl", "listapps", udid],
            environment: SimulatorToolchain.processEnvironment()
        )
        guard result.succeeded else { return [] }
        guard let raw = try? PropertyListSerialization.propertyList(from: Data(result.stdout.utf8), format: nil),
              let dict = raw as? [String: [String: Any]] else { return [] }
        return dict.compactMap { (bundleID, info) -> SimulatorTarget.ProcessTarget? in
            guard (info["ApplicationType"] as? String) == "User" else { return nil }
            let name = (info["CFBundleDisplayName"] as? String)
                ?? (info["CFBundleName"] as? String)
                ?? bundleID
            let ver  = (info["CFBundleShortVersionString"] as? String) ?? ""
            return SimulatorTarget.ProcessTarget(
                id: bundleID, bundleID: bundleID, displayName: name, version: ver
            )
        }.sorted { $0.displayName < $1.displayName }
    }

    // MARK: - Usability

    /// Returns whether the target can currently receive an injection attempt.
    /// Performs a live boot-state re-check.
    public func checkUsability(udid: String, name: String) async -> (usable: Bool, reason: String) {
        let state = await refreshBootState(udid: udid)
        switch state {
        case .booted:
            return (true, "\(name) is booted and ready.")
        case .booting:
            return (false, "\(name) is still booting. Wait for it to finish.")
        case .shutdown:
            return (false, "\(name) is shut down. Boot it first.")
        case .unknown:
            return (false, "\(name) state unknown — may have been removed or is unavailable.")
        }
    }

    // MARK: - Parsing

    private func parse(_ data: Data) -> [SimulatorTarget] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let map  = json["devices"] as? [String: [[String: Any]]] else { return [] }
        var results: [SimulatorTarget] = []
        for (runtimeKey, deviceList) in map {
            let runtime = parseRuntime(from: runtimeKey)
            for device in deviceList {
                guard let udid = device["udid"] as? String,
                      let name = device["name"] as? String else { continue }
                if let available = device["isAvailable"] as? Bool, !available { continue }
                let state = parseBootState(device["state"] as? String)
                results.append(SimulatorTarget(udid: udid, name: name, runtime: runtime, bootState: state))
            }
        }
        return results.sorted { $0.name < $1.name }
    }

    private func parseBootState(_ raw: String?) -> SimulatorTarget.BootState {
        switch raw?.lowercased() {
        case "booted":   return .booted
        case "booting":  return .booting
        case "shutdown": return .shutdown
        default:         return .unknown
        }
    }

    private func parseRuntime(from key: String) -> String {
        // "com.apple.CoreSimulator.SimRuntime.iOS-17-5" → "iOS 17.5"
        guard let last = key.split(separator: ".").last else { return key }
        let parts = last.split(separator: "-")
        guard parts.count >= 2 else { return String(last) }
        return String(parts[0]) + " " + parts.dropFirst().joined(separator: ".")
    }
}
