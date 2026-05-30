import SwiftUI
import SPPCore
import SPPIPCModels
import SPPRuntimeKit
import SPPUIBuilderKit

// MARK: - SimulatorHostApp

/// Entry point for the iOS companion app that hosts the simulated device environment
/// and communicates with Swift Playground++ Studio over the local network.
@main
struct SimulatorHostApp: App {

    // MARK: Environment

    @StateObject private var hostEnv = SimulatorHostEnvironment()

    // MARK: Scene

    var body: some Scene {
        WindowGroup {
            SimulatorHostContentView()
                .environmentObject(hostEnv)
        }
    }
}
