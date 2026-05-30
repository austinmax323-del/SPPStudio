import AppKit
import SwiftUI
import SPPCore

// MARK: - Application Entry Point

@main
struct SPPStudioApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appEnv = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            IDEWindowView()
                .environmentObject(appEnv)
                .task { await appEnv.bootstrap() }
        }
        .defaultSize(width: 1280, height: 800)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Project…") {
                    NSApp.sendAction(#selector(AppDelegate.newProjectAction(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
            CommandMenu("Debug") {
                Button("Dump Runtime Invariants") {
                    if let url = RuntimeInvariantInspector.writeDump(reason: "Debug menu") {
                        NSLog("SPPStudio runtime invariant dump: \(url.path)")
                    }
                }
                .keyboardShortcut("i", modifiers: [.command, .option, .control])
            }
        }

        Settings {
            SettingsView()
        }
    }
}

// MARK: - Settings View

private struct SettingsView: View {

    private let appVersion = "0.1.0"

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
            AboutSettingsTab(version: appVersion)
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 480, height: 260)
    }
}

// MARK: - General Settings Tab

private struct GeneralSettingsTab: View {

    @AppStorage("spp.settings.editorFontSize") private var editorFontSize: Double = 13
    @AppStorage("spp.settings.showLineNumbers") private var showLineNumbers: Bool = true
    @AppStorage("spp.settings.autoSave") private var autoSave: Bool = true

    var body: some View {
        Form {
            Section("Editor") {
                Stepper(
                    "Font size: \(Int(editorFontSize))pt",
                    value: $editorFontSize,
                    in: 9...24,
                    step: 1
                )
                Toggle("Show line numbers", isOn: $showLineNumbers)
                Toggle("Auto-save on build", isOn: $autoSave)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - About Settings Tab

private struct AboutSettingsTab: View {

    let version: String

    var body: some View {
        Form {
            Section("About") {
                LabeledContent("Application", value: "SwiftPlayground++ Studio")
                LabeledContent("Version", value: version)
                LabeledContent("Build", value: buildNumber)
                LabeledContent("Platform", value: "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func newProjectAction(_ sender: Any?) {
        NotificationCenter.default.post(name: .sppNewProjectRequested, object: nil)
    }
}

extension Notification.Name {
    static let sppNewProjectRequested = Notification.Name("SPPStudio.NewProjectRequested")
}
