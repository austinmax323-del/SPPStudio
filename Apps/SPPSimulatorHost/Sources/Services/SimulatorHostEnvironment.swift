import Foundation
#if canImport(UIKit)
import UIKit
#endif
import SPPCore
import SPPIPCModels

// MARK: - SimulatorHostEnvironment

/// Central observable state object for the iOS companion app.
///
/// Manages connection tracking, Bonjour advertisement, and a display-ready log
/// of received `IPCCommand` values. All mutations happen on the main actor so
/// SwiftUI bindings update correctly without explicit `DispatchQueue.main` hops.
@MainActor
final class SimulatorHostEnvironment: ObservableObject {

    // MARK: Published State

    /// Whether a Studio instance is currently connected.
    @Published var isConnected: Bool = false

    /// The resolved host address of the connected Studio instance, if any.
    @Published var studioAddress: String? = nil

    /// The `id` of the most recently received `IPCCommand`, for display in the UI.
    @Published var lastCommandID: UUID? = nil

    /// Human-readable label combining device name and OS version.
    @Published var deviceInfo: String

    /// Ordered list of display strings for received IPC commands / events.
    @Published var runtimeEvents: [String] = []

    // MARK: Init

    init() {
        #if canImport(UIKit)
        let device = UIDevice.current
        deviceInfo = "\(device.name)  \(device.systemName) \(device.systemVersion)"
        #else
        deviceInfo = "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
        #endif
        startAdvertising()
    }

    // MARK: - Bonjour Advertising

    /// Begins Bonjour advertisement so Studio can discover this companion device.
    func startAdvertising() {
        // Placeholder: real implementation will use `NWListener` with
        // `NWParameters.tcp` and register a `_sppstudio._tcp` service.
        print("[SimulatorHostEnvironment] Bonjour advertising placeholder")
    }

    /// Stops the active Bonjour advertisement.
    func stopAdvertising() {
        // Placeholder: tear down the `NWListener` started in `startAdvertising()`.
        print("[SimulatorHostEnvironment] Bonjour advertising stopped")
    }

    // MARK: - Command Handling

    /// Processes an incoming `IPCCommand` from Studio, appending a human-readable
    /// description to `runtimeEvents` and updating `lastCommandID`.
    ///
    /// - Parameter command: The decoded command received over the IPC channel.
    func handleCommand(_ command: IPCCommand) {
        let description = Self.displayString(for: command)
        let timestamp = Self.shortTimestamp()
        runtimeEvents.append("[\(timestamp)] \(description)")
        lastCommandID = UUID()
    }

    // MARK: - Private Helpers

    private static func displayString(for command: IPCCommand) -> String {
        switch command {
        case .ping:
            return "ping"
        case .getStatus:
            return "getStatus"
        case .launchComponent(let id):
            return "launchComponent(\(id.uuidString.prefix(8))\u{2026})"
        case .updateDocument(let doc):
            return "updateDocument(id: \(doc.documentID.uuidString.prefix(8))\u{2026})"
        case .applyTheme(let theme):
            return "applyTheme(\(theme.themeID))"
        case .captureSnapshot:
            return "captureSnapshot"
        case .setOrientation(let orientation):
            return "setOrientation(\(orientation.rawValue))"
        case .runReplay(let sessionID):
            return "runReplay(\(sessionID.uuidString.prefix(8))\u{2026})"
        case .stopReplay:
            return "stopReplay"
        }
    }

    private static func shortTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }
}
