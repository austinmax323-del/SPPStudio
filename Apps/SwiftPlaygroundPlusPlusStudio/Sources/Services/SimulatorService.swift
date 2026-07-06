import Foundation
import SPPDeviceKit

// MARK: - SimulatorService

@MainActor
public final class SimulatorService: ObservableObject {

    // MARK: - Published State

    @Published public var devices: [SPPDevice] = []
    @Published public var bootedDeviceIDs: Set<String> = []
    @Published public var activeDeviceID: String? = nil
    @Published public var isRefreshing: Bool = false
    @Published public var isBooting: Bool = false
    @Published public var syslogLines: [SyslogLine] = []
    @Published public var crashCount: Int = 0
    @Published public var isStreamingSyslog: Bool = false
    @Published public var installedApps: [SimulatorApp] = []
    @Published public var isFetchingApps: Bool = false
    @Published public var lastError: String? = nil

    public struct SyslogLine: Identifiable, Sendable {
        public let id = UUID()
        public let text: String
        public let isCrash: Bool
    }

    public struct SimulatorApp: Identifiable, Hashable, Sendable {
        public let id: String       // bundle ID
        public let bundleID: String
        public let displayName: String
        public let version: String
    }

    // MARK: - Computed

    public var activeDevice: SPPDevice? {
        devices.first { $0.id == activeDeviceID }
    }

    public var activeDeviceIsBooted: Bool {
        guard let id = activeDeviceID else { return false }
        return bootedDeviceIDs.contains(id)
    }

    // MARK: - Private

    private let provider = SimulatorDeviceProvider()
    private let manager  = DeviceManager()
    private var activeSyslogSession: SimulatorSession?
    private var syslogTask: Task<Void, Never>?

    public init() {}

    // MARK: - Device Discovery & Refresh

    public func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        lastError    = nil
        defer { isRefreshing = false }

        do {
            let devs = try await provider.availableSimulators()
            let ids  = await fetchBootedIDs()
            devices         = devs
            bootedDeviceIDs = ids
            // Preserve active selection if still valid; otherwise pick first booted, then first.
            if let current = activeDeviceID, devs.contains(where: { $0.id == current }) {
                // keep it
            } else {
                activeDeviceID = devs.first(where: { ids.contains($0.id) })?.id
                    ?? devs.first?.id
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Boot / Shutdown

    public func boot(_ device: SPPDevice) async {
        guard !isBooting else { return }
        isBooting = true
        lastError = nil
        defer { isBooting = false }
        do {
            try await provider.boot(deviceID: device.id)
            bootedDeviceIDs.insert(device.id)
        } catch {
            lastError = "Boot failed: \(error.localizedDescription)"
        }
    }

    public func shutdown(_ device: SPPDevice) async {
        lastError = nil
        do {
            try await provider.shutdown(deviceID: device.id)
            bootedDeviceIDs.remove(device.id)
            if activeDeviceID == device.id { stopSyslog() }
        } catch {
            lastError = "Shutdown failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Syslog Stream

    public func startSyslog(for device: SPPDevice) async {
        stopSyslog()
        syslogLines         = []
        crashCount          = 0
        isStreamingSyslog   = true
        let session         = SimulatorSession(device: device)
        activeSyslogSession = session
        let stream          = await session.startSyslog()

        syslogTask = Task { [weak self] in
            for await line in stream {
                guard let self else { break }
                let crash = Self.isCrashLine(line)
                self.syslogLines.append(SyslogLine(text: line, isCrash: crash))
                if crash { self.crashCount += 1 }
                if self.syslogLines.count > 5_000 {
                    self.syslogLines.removeFirst(self.syslogLines.count - 5_000)
                }
            }
            self?.isStreamingSyslog   = false
            self?.activeSyslogSession = nil
        }
    }

    public func stopSyslog() {
        syslogTask?.cancel()
        syslogTask          = nil
        isStreamingSyslog   = false
        activeSyslogSession = nil
    }

    // MARK: - Installed App Discovery

    public func fetchInstalledApps() async {
        guard let deviceID = activeDeviceID else { return }
        isFetchingApps = true
        lastError      = nil
        defer { isFetchingApps = false }
        let apps = await queryInstalledApps(deviceID: deviceID)
        installedApps = apps
    }

    private func queryInstalledApps(deviceID: String) async -> [SimulatorApp] {
        let result = await ProcessRunner.run(
            executable: "/usr/bin/xcrun",
            arguments: ["simctl", "listapps", deviceID],
            environment: SimulatorToolchain.processEnvironment()
        )
        var apps: [SimulatorApp] = []
        if let raw = try? PropertyListSerialization.propertyList(from: Data(result.stdout.utf8), format: nil),
           let dict = raw as? [String: [String: Any]] {
            for (bundleID, info) in dict {
                guard (info["ApplicationType"] as? String) == "User" else { continue }
                let name = (info["CFBundleDisplayName"] as? String)
                    ?? (info["CFBundleName"] as? String)
                    ?? bundleID
                let ver  = (info["CFBundleShortVersionString"] as? String)
                    ?? (info["CFBundleVersion"] as? String)
                    ?? ""
                apps.append(SimulatorApp(
                    id: bundleID, bundleID: bundleID,
                    displayName: name, version: ver
                ))
            }
        }
        return apps.sorted { $0.displayName < $1.displayName }
    }

    // MARK: - Crash Detection

    private static let crashPatterns = [
        "ReportCrash", "Terminating app due to uncaught exception",
        "*** Terminating", "CRASH:", "EXC_BAD_ACCESS", "SIGABRT", "SIGSEGV"
    ]

    private static func isCrashLine(_ line: String) -> Bool {
        crashPatterns.contains(where: { line.contains($0) })
    }

    // MARK: - Install / Launch

    public func installApp(packageURL: URL) async {
        guard let device = activeDevice else {
            lastError = "No active device selected."
            return
        }
        lastError = nil
        do {
            let session = try await manager.connect(to: device)
            try await session.installPackage(at: packageURL)
        } catch {
            lastError = "Install failed: \(error.localizedDescription)"
        }
    }

    public func launchApp(bundleID: String) async {
        guard let device = activeDevice else {
            lastError = "No active device selected."
            return
        }
        lastError = nil
        do {
            let session = try await manager.connect(to: device)
            try await session.launchApp(bundleID: bundleID)
        } catch {
            lastError = "Launch failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Private

    private func fetchBootedIDs() async -> Set<String> {
        let result = await ProcessRunner.run(
            executable: "/usr/bin/xcrun",
            arguments: ["simctl", "list", "devices", "booted", "--json"],
            environment: SimulatorToolchain.processEnvironment()
        )
        var ids = Set<String>()
        if let json = try? JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: Any],
           let map  = json["devices"] as? [String: [[String: Any]]] {
            for list in map.values {
                for d in list {
                    if let udid = d["udid"] as? String { ids.insert(udid) }
                }
            }
        }
        return ids
    }
}
