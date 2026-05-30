import SwiftUI
import SPPCore
import SPPIPCModels

// MARK: - SimulatorHostContentView

/// Root content view for the iOS companion app.
///
/// Displays the current connection state, device information, Bonjour
/// advertisement status, and a rolling list of received runtime events.
struct SimulatorHostContentView: View {

    // MARK: Dependencies

    @EnvironmentObject var hostEnv: SimulatorHostEnvironment

    // MARK: Body

    var body: some View {
        NavigationStack {
            List {
                connectionSection
                deviceSection
                advertisingSection
                eventsSection
            }
            .navigationTitle("SPP Simulator Host")
            .listStyle(.inset)
        }
    }

    // MARK: - Connection Section

    private var connectionSection: some View {
        Section("Connection") {
            HStack(spacing: 12) {
                Circle()
                    .fill(hostEnv.isConnected ? Color.green : Color.orange)
                    .frame(width: 10, height: 10)
                    .shadow(color: hostEnv.isConnected ? .green.opacity(0.6) : .clear, radius: 4)

                VStack(alignment: .leading, spacing: 2) {
                    Text(hostEnv.isConnected ? "Connected" : "Waiting for connection")
                        .font(.headline)
                    if let address = hostEnv.studioAddress, hostEnv.isConnected {
                        Text(address)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Launch Swift Playground++ Studio on your Mac")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if let lastID = hostEnv.lastCommandID {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Last Command")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(lastID.uuidString.prefix(8) + "\u{2026}")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Device Section

    private var deviceSection: some View {
        Section("Device") {
            LabeledContent("Name") {
                Text(hostEnv.deviceInfo)
                    .foregroundStyle(.secondary)
            }

            LabeledContent("Status") {
                Label(
                    hostEnv.isConnected ? "Active" : "Idle",
                    systemImage: hostEnv.isConnected ? "checkmark.circle.fill" : "circle.dotted"
                )
                .foregroundStyle(hostEnv.isConnected ? .green : .secondary)
                .font(.subheadline)
            }
        }
    }

    // MARK: - Advertising Section

    private var advertisingSection: some View {
        Section("Network") {
            LabeledContent("Bonjour") {
                Label("Advertising", systemImage: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(.blue)
                    .font(.subheadline)
            }
        }
    }

    // MARK: - Events Section

    @ViewBuilder
    private var eventsSection: some View {
        if !hostEnv.runtimeEvents.isEmpty {
            Section("Runtime Events (\(hostEnv.runtimeEvents.count))") {
                ForEach(hostEnv.runtimeEvents.reversed(), id: \.self) { event in
                    Text(event)
                        .font(.caption.monospaced())
                        .foregroundStyle(.primary)
                }
            }
        } else {
            Section("Runtime Events") {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: "tray")
                            .font(.title2)
                            .foregroundStyle(.tertiary)
                        Text("No events yet")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 8)
                    Spacer()
                }
            }
        }
    }
}
