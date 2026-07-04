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
                .environmentObject(appEnv.fileDiagnosticsStore)
                .task {
                    await appEnv.bootstrap()
                    for url in startupProjectURLs() {
                        await openProject(url)
                    }
                    for url in AppDelegate.drainPendingProjectURLs() {
                        await openProject(url)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .sppOpenProjectRequested)) { notification in
                    guard let url = notification.object as? URL else { return }
                    Task { @MainActor in
                        await openProject(url)
                    }
                }
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

                Button("Open Project…") {
                    NSApp.sendAction(#selector(AppDelegate.openProjectAction(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("o", modifiers: [.command])
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

    @MainActor
    private func openProject(_ url: URL) async {
        do {
            try await appEnv.projectService.openProject(at: url)
        } catch {
            appEnv.logger.error("Failed to open project from system open event: \(error.localizedDescription)")
        }
    }

    private func startupProjectURLs() -> [URL] {
        CommandLine.arguments.dropFirst().compactMap { argument in
            guard argument.hasSuffix(".sppproject") else { return nil }
            return URL(fileURLWithPath: argument).standardizedFileURL
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
    private static var pendingProjectURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func newProjectAction(_ sender: Any?) {
        NotificationCenter.default.post(name: .sppNewProjectRequested, object: nil)
    }

    @objc func openProjectAction(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.title = "Open Project"
        panel.message = "Choose a Swift Playground++ Studio project"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = application(NSApp, openFile: url.path)
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        Self.pendingProjectURLs.append(url)
        NotificationCenter.default.post(name: .sppOpenProjectRequested, object: url)
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        for filename in filenames {
            _ = application(sender, openFile: filename)
        }
        sender.reply(toOpenOrPrint: .success)
    }

    static func drainPendingProjectURLs() -> [URL] {
        let urls = pendingProjectURLs
        pendingProjectURLs.removeAll()
        return urls
    }
}

extension Notification.Name {
    static let sppNewProjectRequested = Notification.Name("SPPStudio.NewProjectRequested")
    static let sppOpenProjectRequested = Notification.Name("SPPStudio.OpenProjectRequested")
    /// Requests the console open and select a specific tab. `object` is the
    /// `ConsoleTab.rawValue` to select. Used by the toolbar diagnostics badge.
    static let sppShowConsoleTab = Notification.Name("SPPStudio.ShowConsoleTab")
}
