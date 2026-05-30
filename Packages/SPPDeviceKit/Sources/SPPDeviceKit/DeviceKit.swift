// DeviceKit.swift
// SPPDeviceKit
//
// macOS only. Depends on SPPCore, SPPIPCModels.

import Foundation
import SPPCore

// MARK: - DeviceConnectionKind

public enum DeviceConnectionKind: String, Codable, Hashable, Sendable {
    case usb
    case network
    case simulator
}

// MARK: - DeviceCapabilities

public struct DeviceCapabilities: OptionSet, Sendable, Codable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let install      = DeviceCapabilities(rawValue: 1 << 0)
    public static let launch       = DeviceCapabilities(rawValue: 1 << 1)
    public static let debug        = DeviceCapabilities(rawValue: 1 << 2)
    public static let screenshot   = DeviceCapabilities(rawValue: 1 << 3)
    public static let syslog       = DeviceCapabilities(rawValue: 1 << 4)
    public static let fileTransfer = DeviceCapabilities(rawValue: 1 << 5)
    public static let all: DeviceCapabilities = [.install, .launch, .debug, .screenshot, .syslog, .fileTransfer]
}

// MARK: - SPPDevice

public struct SPPDevice: Identifiable, Codable, Sendable {
    public let id: String
    public let name: String
    public let modelName: String
    public let systemVersion: String
    public let connectionKind: DeviceConnectionKind
    public let capabilities: DeviceCapabilities
    public let isSimulator: Bool

    public var displayName: String {
        "\(name) (\(systemVersion))"
    }

    public init(
        id: String,
        name: String,
        modelName: String,
        systemVersion: String,
        connectionKind: DeviceConnectionKind,
        capabilities: DeviceCapabilities,
        isSimulator: Bool
    ) {
        self.id = id
        self.name = name
        self.modelName = modelName
        self.systemVersion = systemVersion
        self.connectionKind = connectionKind
        self.capabilities = capabilities
        self.isSimulator = isSimulator
    }
}

// MARK: - DeviceSessionState

public enum DeviceSessionState: Sendable {
    case idle
    case connecting
    case connected
    case installing
    case error(String)
}

// MARK: - DeviceSession

public protocol DeviceSession: Actor {
    var device: SPPDevice { get }
    var state: DeviceSessionState { get async }
    func installPackage(at url: URL) async throws
    func launchApp(bundleID: String) async throws
    func captureScreenshot() async throws -> Data
    func startSyslog() -> AsyncStream<String>
    func disconnect() async
}

// MARK: - Process helpers (private)

private enum ProcessError: Error {
    case launchFailed(String)
    case nonZeroExit(Int32, String)
}

private func runProcess(
    executableURL: URL,
    arguments: [String]
) async throws -> (stdout: Data, stderr: Data) {
    try await withCheckedThrowingContinuation { continuation in
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            continuation.resume(throwing: ProcessError.launchFailed(error.localizedDescription))
            return
        }

        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        if process.terminationStatus != 0 {
            let stderrString = String(data: stderrData, encoding: .utf8) ?? ""
            continuation.resume(
                throwing: ProcessError.nonZeroExit(process.terminationStatus, stderrString)
            )
        } else {
            continuation.resume(returning: (stdoutData, stderrData))
        }
    }
}

private let xcrunURL = URL(fileURLWithPath: "/usr/bin/xcrun")

// MARK: - SimulatorDeviceProvider

public actor SimulatorDeviceProvider {

    public init() {}

    public func availableSimulators() async throws -> [SPPDevice] {
        let (stdoutData, _) = try await runProcess(
            executableURL: xcrunURL,
            arguments: ["simctl", "list", "devices", "--json"]
        )

        guard let json = try? JSONSerialization.jsonObject(with: stdoutData) as? [String: Any],
              let devicesMap = json["devices"] as? [String: [[String: Any]]] else {
            return []
        }

        var results: [SPPDevice] = []

        for (runtimeKey, deviceList) in devicesMap {
            // Extract the OS version from the runtime identifier, e.g.
            // "com.apple.CoreSimulator.SimRuntime.iOS-17-0" → "iOS 17.0"
            let systemVersion = parseSystemVersion(from: runtimeKey)

            for deviceDict in deviceList {
                guard
                    let udid = deviceDict["udid"] as? String,
                    let name = deviceDict["name"] as? String,
                    let availability = deviceDict["availability"] as? String,
                    availability != "(unavailable)"
                else { continue }

                // Also skip explicitly unavailable devices via isAvailable
                if let isAvailable = deviceDict["isAvailable"] as? Bool, !isAvailable {
                    continue
                }

                let modelName = (deviceDict["deviceTypeIdentifier"] as? String)
                    .flatMap { extractModelName(from: $0) } ?? name

                let device = SPPDevice(
                    id: udid,
                    name: name,
                    modelName: modelName,
                    systemVersion: systemVersion,
                    connectionKind: .simulator,
                    capabilities: .all,
                    isSimulator: true
                )
                results.append(device)
            }
        }

        return results.sorted { $0.name < $1.name }
    }

    public func boot(deviceID: String) async throws {
        do {
            _ = try await runProcess(executableURL: xcrunURL, arguments: ["simctl", "boot", deviceID])
        } catch ProcessError.nonZeroExit(_, let stderr) {
            // Ignore "already booted" errors
            if stderr.contains("already booted") || stderr.contains("Unable to boot device in current state: Booted") {
                return
            }
            throw ProcessError.nonZeroExit(1, stderr)
        }
    }

    public func shutdown(deviceID: String) async throws {
        _ = try await runProcess(executableURL: xcrunURL, arguments: ["simctl", "shutdown", deviceID])
    }

    // MARK: Private helpers

    private func parseSystemVersion(from runtimeKey: String) -> String {
        // e.g. "com.apple.CoreSimulator.SimRuntime.iOS-17-0"
        guard let lastComponent = runtimeKey.split(separator: ".").last else {
            return runtimeKey
        }
        let parts = lastComponent.split(separator: "-")
        guard parts.count >= 2 else { return String(lastComponent) }
        let osName = String(parts[0])
        let versionParts = parts.dropFirst().joined(separator: ".")
        return "\(osName) \(versionParts)"
    }

    private func extractModelName(from deviceTypeIdentifier: String) -> String? {
        // e.g. "com.apple.CoreSimulator.SimDeviceType.iPhone-15-Pro"
        guard let lastComponent = deviceTypeIdentifier.split(separator: ".").last else {
            return nil
        }
        return lastComponent.replacingOccurrences(of: "-", with: " ")
    }
}

// MARK: - SimulatorSession

public final actor SimulatorSession: DeviceSession {

    public let device: SPPDevice
    private(set) var sessionState: DeviceSessionState = .idle

    public init(device: SPPDevice) {
        self.device = device
    }

    public var state: DeviceSessionState {
        get async { sessionState }
    }

    public func installPackage(at url: URL) async throws {
        sessionState = .installing
        do {
            _ = try await runProcess(
                executableURL: xcrunURL,
                arguments: ["simctl", "install", device.id, url.path]
            )
            sessionState = .connected
        } catch {
            sessionState = .error(error.localizedDescription)
            throw error
        }
    }

    public func launchApp(bundleID: String) async throws {
        _ = try await runProcess(
            executableURL: xcrunURL,
            arguments: ["simctl", "launch", device.id, bundleID]
        )
    }

    public func captureScreenshot() async throws -> Data {
        // `xcrun simctl io <udid> screenshot -` writes PNG to stdout
        let (stdoutData, _) = try await runProcess(
            executableURL: xcrunURL,
            arguments: ["simctl", "io", device.id, "screenshot", "-"]
        )
        return stdoutData
    }

    public func startSyslog() -> AsyncStream<String> {
        let udid = device.id
        return AsyncStream<String> { continuation in
            let process = Process()
            process.executableURL = xcrunURL
            process.arguments = [
                "simctl", "spawn", udid,
                "log", "stream",
                "--predicate", #"process != """#
            ]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe() // discard stderr

            process.terminationHandler = { _ in
                continuation.finish()
            }

            do {
                try process.run()
            } catch {
                continuation.finish()
                return
            }

            let handle = pipe.fileHandleForReading

            // Read lines asynchronously using notifications
            handle.readabilityHandler = { fileHandle in
                let data = fileHandle.availableData
                guard !data.isEmpty else {
                    handle.readabilityHandler = nil
                    continuation.finish()
                    return
                }
                if let text = String(data: data, encoding: .utf8) {
                    for line in text.components(separatedBy: "\n") {
                        let trimmed = line.trimmingCharacters(in: .newlines)
                        if !trimmed.isEmpty {
                            continuation.yield(trimmed)
                        }
                    }
                }
            }

            continuation.onTermination = { _ in
                process.terminate()
                handle.readabilityHandler = nil
            }
        }
    }

    public func disconnect() async {
        sessionState = .idle
    }
}

// MARK: - DeviceManager

public actor DeviceManager {

    private var sessions: [String: any DeviceSession] = [:]
    public let simulatorProvider = SimulatorDeviceProvider()

    public init() {}

    public func availableDevices() async throws -> [SPPDevice] {
        // Phase 1: simulator devices only
        return try await simulatorProvider.availableSimulators()
    }

    public func session(for device: SPPDevice) -> (any DeviceSession)? {
        sessions[device.id]
    }

    public func connect(to device: SPPDevice) async throws -> any DeviceSession {
        if let existing = sessions[device.id] {
            return existing
        }

        guard device.isSimulator || device.connectionKind == .simulator else {
            throw SPPError.unsupported("Physical device connection")
        }

        let session = SimulatorSession(device: device)
        sessions[device.id] = session
        return session
    }

    public func disconnect(deviceID: String) async {
        if let session = sessions[deviceID] {
            await session.disconnect()
            sessions.removeValue(forKey: deviceID)
        }
    }
}
