import SwiftUI
import AppKit
import UniformTypeIdentifiers
import SPPDeviceKit

// MARK: - Simulator Panel

struct SimulatorPanelView: View {

    @EnvironmentObject private var appEnv: AppEnvironment
    @EnvironmentObject private var sim: SimulatorService

    var body: some View {
        VStack(spacing: 0) {
            simulatorToolbar
            panelDivider
            logArea
        }
        .task { if sim.devices.isEmpty { await sim.refresh() } }
    }

    // MARK: - Toolbar

    @State private var showDeployPopover = false

    private var simulatorToolbar: some View {
        HStack(spacing: 8) {
            refreshButton
            toolbarSeparator
            devicePicker
            toolbarSeparator
            bootButton
            shutdownButton
            toolbarSeparator
            syslogToggle
            toolbarSeparator
            deployButton
            Spacer()
            crashBadge
            errorLabel
        }
        .padding(.horizontal, 12)
        .frame(height: IDETheme.Layout.tabBarHeight - 2)
        .background(Color.black.opacity(0.18))
    }

    private var refreshButton: some View {
        Button(action: { Task { await sim.refresh() } }) {
            if sim.isRefreshing {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 13, height: 13)
            } else {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color(white: 0.44))
        .help("Refresh simulator list")
    }

    private var devicePicker: some View {
        Picker("", selection: Binding(
            get: { sim.activeDeviceID ?? "" },
            set: { sim.activeDeviceID = $0.isEmpty ? nil : $0 }
        )) {
            if sim.devices.isEmpty {
                Text("No Simulators").tag("").foregroundStyle(Color(white: 0.36))
            }
            ForEach(sim.devices) { device in
                HStack(spacing: 5) {
                    Circle()
                        .fill(sim.bootedDeviceIDs.contains(device.id) ? Color.green : Color(white: 0.26))
                        .frame(width: 5, height: 5)
                    Text(device.displayName)
                }
                .tag(device.id)
            }
        }
        .pickerStyle(.menu)
        .font(.system(size: 11))
        .frame(maxWidth: 220)
        .disabled(sim.devices.isEmpty)
    }

    private var bootButton: some View {
        Button(action: {
            guard let device = sim.activeDevice else { return }
            Task { await sim.boot(device) }
        }) {
            HStack(spacing: 4) {
                if sim.isBooting {
                    ProgressView().scaleEffect(0.45).frame(width: 10, height: 10)
                } else {
                    Circle()
                        .fill(sim.activeDeviceIsBooted ? Color.green : Color(white: 0.30))
                        .frame(width: 5, height: 5)
                }
                Text(sim.isBooting ? "Booting\u{2026}" : (sim.activeDeviceIsBooted ? "Booted" : "Boot"))
                    .font(.system(size: 11))
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(sim.activeDeviceIsBooted
            ? IDETheme.Colors.consoleSuccess
            : Color(white: 0.55))
        .disabled(sim.activeDevice == nil || sim.activeDeviceIsBooted || sim.isBooting)
        .help("Boot selected simulator")
    }

    private var shutdownButton: some View {
        Button(action: {
            guard let device = sim.activeDevice else { return }
            Task { await sim.shutdown(device) }
        }) {
            Image(systemName: "stop.fill")
                .font(.system(size: 10))
        }
        .buttonStyle(.plain)
        .foregroundStyle(sim.activeDeviceIsBooted
            ? IDETheme.Colors.consoleError
            : Color(white: 0.26))
        .disabled(sim.activeDevice == nil || !sim.activeDeviceIsBooted)
        .help("Shutdown selected simulator")
    }

    private var syslogToggle: some View {
        Button(action: {
            if sim.isStreamingSyslog {
                sim.stopSyslog()
            } else if let device = sim.activeDevice {
                Task { await sim.startSyslog(for: device) }
            }
        }) {
            Label(
                sim.isStreamingSyslog ? "Stop" : "Stream",
                systemImage: sim.isStreamingSyslog ? "stop.circle.fill" : "play.circle"
            )
            .font(.system(size: 11))
        }
        .buttonStyle(.plain)
        .foregroundStyle(sim.isStreamingSyslog
            ? IDETheme.Colors.consoleError
            : sim.activeDeviceIsBooted ? Color.accentColor : Color(white: 0.26))
        .disabled(!sim.isStreamingSyslog && (sim.activeDevice == nil || !sim.activeDeviceIsBooted))
        .help(sim.isStreamingSyslog ? "Stop syslog stream" : "Start live syslog stream")
    }

    private var deployButton: some View {
        Button(action: { showDeployPopover.toggle() }) {
            Label("Deploy", systemImage: "arrow.up.to.line")
                .font(.system(size: 11))
        }
        .buttonStyle(.plain)
        .foregroundStyle(sim.activeDeviceIsBooted ? Color.accentColor : Color(white: 0.26))
        .disabled(!sim.activeDeviceIsBooted)
        .help("Install .app bundle and launch on selected simulator")
        .popover(isPresented: $showDeployPopover, arrowEdge: .bottom) {
            DeployPopoverView()
                .environmentObject(sim)
        }
    }

    @ViewBuilder
    private var crashBadge: some View {
        if sim.crashCount > 0 {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.octagon.fill")
                    .font(.system(size: 10))
                Text("\(sim.crashCount) crash\(sim.crashCount == 1 ? "" : "es")")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(IDETheme.Colors.consoleError)
            .padding(.trailing, 4)
        }
    }

    @ViewBuilder
    private var errorLabel: some View {
        if let err = sim.lastError {
            Text(err)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(IDETheme.Colors.consoleError)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 220)
        }
    }

    // MARK: - Log Area

    @ViewBuilder
    private var logArea: some View {
        if sim.syslogLines.isEmpty {
            emptyState
        } else {
            SyslogTextView(lines: sim.syslogLines)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var emptyState: some View {
        HStack(spacing: 8) {
            Image(systemName: sim.activeDeviceIsBooted ? "play.circle" : "iphone.slash")
                .font(.system(size: 12, weight: .ultraLight))
                .foregroundStyle(Color(white: 0.20))
            Text(sim.activeDeviceIsBooted
                 ? "Press Stream to start live syslog."
                 : sim.devices.isEmpty
                     ? "No simulators found. Press \u{21BB} to refresh."
                     : "Select and boot a simulator to stream logs.")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color(white: 0.22))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private var toolbarSeparator: some View {
        Rectangle()
            .fill(IDETheme.Colors.rowDivider)
            .frame(width: IDETheme.Layout.separatorWeight, height: 14)
    }

    private var panelDivider: some View {
        Rectangle()
            .fill(IDETheme.Colors.panelSeparator)
            .frame(height: IDETheme.Layout.separatorWeight)
    }
}

// MARK: - Syslog NSTextView

private struct SyslogTextView: NSViewRepresentable {

    let lines: [SimulatorService.SyslogLine]

    func makeNSView(context: Context) -> NSScrollView {
        let storage       = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let container     = NSTextContainer(containerSize: NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        ))
        container.widthTracksTextView = false
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)

        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 200),
                            textContainer: container)
        tv.isEditable               = false
        tv.isSelectable             = true
        tv.isRichText               = true
        tv.allowsUndo               = false
        tv.usesFindBar              = true
        tv.drawsBackground          = true
        tv.textContainerInset       = NSSize(width: 10, height: 8)
        tv.backgroundColor          = NSColor(red: 0.056, green: 0.056, blue: 0.082, alpha: 1.0)
        tv.isHorizontallyResizable  = true
        tv.isVerticallyResizable    = true
        tv.minSize                  = .zero
        tv.maxSize                  = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                             height: CGFloat.greatestFiniteMagnitude)
        tv.autoresizingMask         = [.width, .height]
        tv.font                     = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular)
        tv.textColor                = NSColor(white: 0.72, alpha: 1)

        let sv = NSScrollView()
        sv.documentView           = tv
        sv.hasVerticalScroller    = true
        sv.hasHorizontalScroller  = true
        sv.autohidesScrollers     = true
        sv.backgroundColor        = NSColor(red: 0.056, green: 0.056, blue: 0.082, alpha: 1.0)
        return sv
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tv      = scrollView.documentView as? NSTextView,
              let storage = tv.textStorage else { return }

        let c = context.coordinator
        let selection = tv.selectedRange()

        if lines.isEmpty {
            if c.renderedCount > 0 {
                storage.setAttributedString(NSAttributedString())
                c.reset()
            }
            return
        }

        let firstID = lines.first!.id
        let lastID  = lines.last!.id

        if c.renderedCount == lines.count && c.renderedLastID == lastID {
            // Identical — no-op
        } else if c.renderedFirstID == firstID && lines.count > c.renderedCount {
            // Pure append
            for i in c.renderedCount ..< lines.count {
                append(lines[i], to: storage)
            }
            c.renderedCount  = lines.count
            c.renderedLastID = lastID
            tv.scrollToEndOfDocument(nil)
        } else {
            // Full rebuild (first render or trim)
            storage.setAttributedString(NSAttributedString())
            for line in lines { append(line, to: storage) }
            c.renderedCount   = lines.count
            c.renderedFirstID = firstID
            c.renderedLastID  = lastID
            tv.scrollToEndOfDocument(nil)
        }

        tv.setSelectedRange(clamped(selection, in: storage.string))
    }

    private func append(_ line: SimulatorService.SyslogLine, to storage: NSTextStorage) {
        let text = line.text + "\n"
        let lower = text.lowercased()
        let color: NSColor
        let bg: NSColor
        if line.isCrash {
            color = NSColor(red: 1.0, green: 0.30, blue: 0.30, alpha: 1)
            bg    = NSColor(red: 1.0, green: 0.18, blue: 0.18, alpha: 0.08)
        } else if lower.contains("fault") || lower.contains("error") {
            color = NSColor(red: 1.0, green: 0.40, blue: 0.40, alpha: 1)
            bg    = NSColor.clear
        } else if lower.contains("warning") || lower.contains("warn") {
            color = NSColor(red: 1.0, green: 0.74, blue: 0.24, alpha: 1)
            bg    = NSColor.clear
        } else if lower.contains("debug") {
            color = NSColor(white: 0.46, alpha: 1)
            bg    = NSColor.clear
        } else {
            color = NSColor(white: 0.72, alpha: 1)
            bg    = NSColor.clear
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font:            NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular),
            .foregroundColor: color,
            .backgroundColor: bg
        ]
        storage.beginEditing()
        storage.append(NSAttributedString(string: text, attributes: attrs))
        storage.endEditing()
    }

    private func clamped(_ range: NSRange, in source: String) -> NSRange {
        let length   = (source as NSString).length
        let location = min(max(0, range.location), length)
        return NSRange(location: location, length: min(max(0, range.length), length - location))
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var renderedCount: Int    = 0
        var renderedFirstID: UUID? = nil
        var renderedLastID: UUID?  = nil

        func reset() {
            renderedCount   = 0
            renderedFirstID = nil
            renderedLastID  = nil
        }
    }
}

// MARK: - Deploy Popover

private struct DeployPopoverView: View {

    @EnvironmentObject private var sim: SimulatorService
    @State private var bundleID: String = ""
    @State private var isBusy: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            // Install
            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("INSTALL")
                Button(action: pickAndInstall) {
                    Label("Choose .app Bundle\u{2026}", systemImage: "folder")
                        .font(.system(size: 11))
                }
                .disabled(isBusy)
            }

            Divider()

            // Installed apps picker
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    sectionLabel("INSTALLED APPS")
                    if sim.isFetchingApps {
                        ProgressView().scaleEffect(0.5).frame(width: 10, height: 10)
                    } else {
                        Button(action: { Task { await sim.fetchInstalledApps() } }) {
                            Image(systemName: "arrow.clockwise").font(.system(size: 10))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color(white: 0.40))
                        .help("Scan installed apps on booted simulator")
                    }
                }
                if sim.installedApps.isEmpty {
                    Text(sim.isFetchingApps ? "Scanning\u{2026}" : "No user apps — press \u{21BB} to scan")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color(white: 0.30))
                } else {
                    Picker("", selection: $bundleID) {
                        Text("Select app\u{2026}").tag("")
                        ForEach(sim.installedApps) { app in
                            Text("\(app.displayName)  \(app.bundleID)")
                                .font(.system(size: 11))
                                .tag(app.bundleID)
                        }
                    }
                    .pickerStyle(.menu)
                    .font(.system(size: 11))
                }
            }

            Divider()

            // Launch
            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("LAUNCH")
                HStack(spacing: 6) {
                    TextField("com.example.App", text: $bundleID)
                        .font(.system(size: 11, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                    Button("Launch") {
                        Task { isBusy = true; await sim.launchApp(bundleID: bundleID); isBusy = false }
                    }
                    .disabled(bundleID.trimmingCharacters(in: .whitespaces).isEmpty || isBusy)
                    if isBusy { ProgressView().scaleEffect(0.5).frame(width: 12, height: 12) }
                }
            }
        }
        .padding(16)
        .frame(minWidth: 340)
        .preferredColorScheme(.dark)
        .task { if sim.installedApps.isEmpty { await sim.fetchInstalledApps() } }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Color(white: 0.36))
            .kerning(1.0)
    }

    private func pickAndInstall() {
        let panel = NSOpenPanel()
        panel.title               = "Select .app Bundle"
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseFiles      = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { isBusy = true; await sim.installApp(packageURL: url); isBusy = false }
        }
    }
}

// MARK: - Preview

struct SimulatorPanelView_Previews: PreviewProvider {
    static var previews: some View {
        let env = AppEnvironment()
        SimulatorPanelView()
            .environmentObject(env)
            .environmentObject(env.simulatorService)
            .frame(width: 900, height: 180)
            .preferredColorScheme(.dark)
    }
}
