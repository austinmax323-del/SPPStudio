import SwiftUI
import AppKit
import UniformTypeIdentifiers
import SPPDeviceKit

// MARK: - Simulator Panel

struct SimulatorPanelView: View {

    @EnvironmentObject private var appEnv: AppEnvironment
    @EnvironmentObject private var sim: SimulatorService
    @EnvironmentObject private var preflight: InjectionPreflightService
    @EnvironmentObject private var injection: InjectionExecutionService
    @EnvironmentObject private var verification: InjectionVerificationService
    @EnvironmentObject private var coordinator: SimulatorRunCoordinator

    var body: some View {
        VStack(spacing: 0) {
            simulatorToolbar
            panelDivider
            if !canRunPipeline && !coordinator.isRunning && coordinator.stages.isEmpty {
                prerequisitesRow
                panelDivider
            }
            if !coordinator.stages.isEmpty {
                pipelineStrip
                panelDivider
            }
            if let diag = verification.diagnosis {
                diagnosisRow(diag)
                panelDivider
            }
            if showPreflightPanel || preflight.isRunning || preflight.result != nil {
                preflightStrip
                panelDivider
            }
            logArea
        }
        .task { if sim.devices.isEmpty { await sim.refresh() } }
    }

    // MARK: - Toolbar

    @State private var showDeployPopover   = false
    @State private var showPreflightPanel  = false
    @State private var preflightBundleID   = ""

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
            toolbarSeparator
            preflightButton
            toolbarSeparator
            runInSimulatorButton
            Spacer()
            crashBadge
            errorLabel
        }
        .padding(.horizontal, 12)
        .frame(height: IDETheme.Layout.tabBarHeight)
        .background(IDETheme.Colors.headerBackground)
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

    // MARK: - Preflight Button

    private var preflightButton: some View {
        Button(action: {
            showPreflightPanel = true
            Task { await runPreflight() }
        }) {
            HStack(spacing: 4) {
                if preflight.isRunning {
                    ProgressView().scaleEffect(0.45).frame(width: 10, height: 10)
                } else {
                    Image(systemName: preflightStatusIcon)
                        .font(.system(size: 10))
                }
                Text("Preflight")
                    .font(.system(size: 11))
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(preflightButtonColor)
        .help("Run injection preflight checks")
    }

    private var preflightStatusIcon: String {
        guard let r = preflight.result else { return "checklist" }
        if r.failCount > 0 { return "xmark.circle" }
        if r.warnCount > 0 { return "exclamationmark.triangle" }
        return "checkmark.circle"
    }

    private var preflightButtonColor: Color {
        guard let r = preflight.result else { return Color(white: 0.55) }
        if r.failCount > 0 { return IDETheme.Colors.consoleError }
        if r.warnCount > 0 { return Color.yellow }
        return IDETheme.Colors.consoleSuccess
    }

    // MARK: - Preflight Strip

    @ViewBuilder
    private var preflightStrip: some View {
        VStack(spacing: 0) {
            // Header row
            HStack(spacing: 10) {
                Text("INJECTION PREFLIGHT")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color(white: 0.36))
                    .kerning(1.0)

                if preflight.isRunning {
                    ProgressView().scaleEffect(0.5).frame(width: 10, height: 10)
                    Text("Running…")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color(white: 0.44))
                } else if let r = preflight.result {
                    Text(r.summary)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(r.failCount > 0 ? IDETheme.Colors.consoleError
                                         : r.warnCount > 0 ? Color.yellow
                                         : IDETheme.Colors.consoleSuccess)
                }

                // Artifact path badges — show what's tracked regardless of whether
                // preflight has run, so the user knows what the build produced.
                artifactBadge(
                    label: ".deb",
                    url: appEnv.lastBuiltPackageURL,
                    missingHint: "no build"
                )
                artifactBadge(
                    label: ".dylib",
                    url: appEnv.lastBuiltDylibURL,
                    missingHint: "no build"
                )

                verificationBadge

                Spacer()

                // Bundle ID picker: prefill from installed apps if available
                HStack(spacing: 4) {
                    Text("Target:")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(white: 0.40))
                    if !sim.installedApps.isEmpty {
                        Picker("", selection: $preflightBundleID) {
                            Text("Select…").tag("")
                            ForEach(sim.installedApps) { app in
                                Text("\(app.displayName) — \(app.bundleID)")
                                    .tag(app.bundleID)
                            }
                        }
                        .pickerStyle(.menu)
                        .font(.system(size: 10))
                        .frame(maxWidth: 180)
                    } else {
                        TextField("com.example.App", text: $preflightBundleID)
                            .font(.system(size: 10, design: .monospaced))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 160)
                    }
                }

                Button(action: { Task { await runPreflight() } }) {
                    Label("Re-run", systemImage: "arrow.clockwise")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color(white: 0.50))
                .disabled(preflight.isRunning)

                injectButton

                Button(action: { showPreflightPanel = false; preflight.result.map { _ in () } }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color(white: 0.36))
            }
            .padding(.horizontal, 12)
            .frame(height: IDETheme.Layout.tabBarHeight)
            .background(IDETheme.Colors.headerBackground)

            // Check rows
            if let r = preflight.result {
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(r.checks) { check in
                            preflightCheckRow(check)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: min(CGFloat(r.checks.count) * 22 + 8, 130))
                .background(IDETheme.Colors.consoleBackground)
            }
        }
    }

    @ViewBuilder
    private func preflightCheckRow(_ check: InjectionPreflightResult.Check) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: statusIcon(for: check.status))
                .font(.system(size: 10))
                .foregroundStyle(statusColor(for: check.status))
                .frame(width: 14)
            Text(check.name)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(white: 0.68))
                .frame(width: 180, alignment: .leading)
            Text(check.detail)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color(white: 0.48))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }

    private func statusIcon(for status: InjectionPreflightResult.CheckStatus) -> String {
        switch status {
        case .pass: return "checkmark.circle.fill"
        case .fail: return "xmark.circle.fill"
        case .warn: return "exclamationmark.triangle.fill"
        case .skip: return "minus.circle"
        }
    }

    private func statusColor(for status: InjectionPreflightResult.CheckStatus) -> Color {
        switch status {
        case .pass: return IDETheme.Colors.consoleSuccess
        case .fail: return IDETheme.Colors.consoleError
        case .warn: return .yellow
        case .skip: return Color(white: 0.38)
        }
    }

    // MARK: - Artifact Badge

    @ViewBuilder
    private func artifactBadge(label: String, url: URL?, missingHint: String) -> some View {
        let exists = url.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        HStack(spacing: 3) {
            Circle()
                .fill(url == nil ? Color(white: 0.26) : exists ? IDETheme.Colors.consoleSuccess : IDETheme.Colors.consoleError)
                .frame(width: 5, height: 5)
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(url == nil ? Color(white: 0.30) : exists ? Color(white: 0.55) : IDETheme.Colors.consoleError)
        }
        .help(url.map { "\(label): \($0.path)" } ?? "\(label): \(missingHint)")
    }

    // MARK: - Diagnosis Row

    /// Thin summary row that shows the verification service's correlated verdict in
    /// one sentence (full reasoning in the tooltip). UI only displays what
    /// InjectionVerificationService derived; it does not interpret evidence itself.
    @ViewBuilder
    private func diagnosisRow(_ diag: InjectionDiagnosis) -> some View {
        let (color, icon): (Color, String) = {
            switch diag.severity {
            case .ok:      return (IDETheme.Colors.consoleSuccess, "checkmark.seal.fill")
            case .warning: return (Color.yellow, "exclamationmark.triangle.fill")
            case .info:    return (Color.accentColor, "info.circle.fill")
            case .problem: return (IDETheme.Colors.consoleError, "xmark.octagon.fill")
            }
        }()
        HStack(spacing: 7) {
            Image(systemName: icon).font(.system(size: 11)).foregroundStyle(color)
            Text(diag.headline)
                .font(.system(size: 10))
                .foregroundStyle(Color(white: 0.74))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(IDETheme.Colors.headerBackground)
        .help(diag.detail)
    }

    // MARK: - Verification Badges

    /// Shows three independent runtime-evidence states from InjectionVerificationService:
    ///   "dylib" — constructor (%ctor) marker seen in syslog
    ///   "hook"  — a %hook body marker seen in syslog
    ///   "image" — dylib found in the process image list via vmmap (marker-independent)
    /// These are orthogonal. Marker evidence needs the tweak to cooperate; image
    /// evidence does not.
    @ViewBuilder
    private var verificationBadge: some View {
        if verification.isVerifying || verification.isProbingImage {
            HStack(spacing: 3) {
                ProgressView().scaleEffect(0.4).frame(width: 8, height: 8)
                Text(verification.isProbingImage ? "probing" : "verifying")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(white: 0.50))
            }
            .help("Collecting injection evidence (syslog markers + vmmap image list)")
        } else if verification.lastResult != nil || verification.lastImageResult != nil {
            HStack(spacing: 8) {
                if let v = verification.lastResult {
                    evidenceDot(
                        label: "dylib",
                        observed: v.loadObserved,
                        pendingIsError: true,   // no load = hard fail
                        help: v.loadObserved
                            ? "Dylib loaded — \(v.loadMarker) seen:\n\(v.loadLine ?? "")"
                            : "Dylib load NOT confirmed — \(v.loadMarker) not seen"
                    )
                    evidenceDot(
                        label: "hook",
                        observed: v.hookObserved,
                        pendingIsError: false,  // load-but-no-hook = warn, not error
                        help: v.hookObserved
                            ? "Hook fired — \(v.hookMarker) seen:\n\(v.hookLine ?? "")"
                            : "No hook body observed — \(v.hookMarker) not seen. Load ≠ hook."
                    )
                }
                imageEvidenceDot
            }
            .help(verification.lastImageResult?.summary
                  ?? verification.lastResult?.summary ?? "")
        }
    }

    /// Image-list dot. Distinct from marker dots: its underlying status has four
    /// cases (mapped / notMapped / unavailable / failed), so it is not a simple bool.
    @ViewBuilder
    private var imageEvidenceDot: some View {
        if let img = verification.lastImageResult {
            let (color, icon): (Color, String) = {
                switch img.status {
                case .mapped:        return (IDETheme.Colors.consoleSuccess, "checkmark.circle.fill")
                case .notMapped:     return (IDETheme.Colors.consoleError, "xmark.circle.fill")
                case .processExited: return (Color.orange, "clock.badge.xmark")
                case .unavailable:   return (Color(white: 0.40), "minus.circle")
                case .failed:        return (Color.yellow, "exclamationmark.triangle.fill")
                }
            }()
            HStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 9)).foregroundStyle(color)
                Text("image")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(color)
            }
            .help(img.matchedLine.map { "\(img.summary)\n\($0)" } ?? img.summary)
        }
    }

    @ViewBuilder
    private func evidenceDot(label: String, observed: Bool, pendingIsError: Bool, help: String) -> some View {
        let color: Color = observed
            ? IDETheme.Colors.consoleSuccess
            : (pendingIsError ? IDETheme.Colors.consoleError : Color.yellow)
        HStack(spacing: 3) {
            Image(systemName: observed ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 9))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(color)
        }
        .help(help)
    }

    // MARK: - Run-in-Simulator Pipeline

    /// One prerequisite for the pipeline, with its satisfied state and an actionable hint.
    private struct Prerequisite: Identifiable {
        let id: String
        let label: String
        let met: Bool
        let hint: String
    }

    /// The ordered prerequisites the pipeline needs before it can run. The build
    /// artifact is intentionally NOT here — it is produced by the pipeline's own
    /// build step, so it isn't required up front.
    private var pipelinePrerequisites: [Prerequisite] {
        let hasProject = appEnv.currentProject != nil
        let hasSim     = sim.activeDevice != nil
        let booted     = sim.activeDeviceIsBooted
        let hasBundle  = !preflightBundleID.trimmingCharacters(in: .whitespaces).isEmpty
        let appsHint   = sim.installedApps.isEmpty
            ? "Type a target bundle ID in the Preflight → Target field"
            : "Pick a target app from the Preflight → Target menu"
        return [
            Prerequisite(id: "project", label: "project",
                         met: hasProject, hint: "Open or create a project"),
            Prerequisite(id: "sim", label: "simulator",
                         met: hasSim, hint: "Select a simulator from the device menu"),
            Prerequisite(id: "booted", label: "booted",
                         met: hasSim && booted, hint: "Boot the selected simulator"),
            Prerequisite(id: "bundle", label: "bundle ID",
                         met: hasBundle, hint: appsHint)
        ]
    }

    /// Enabled when every prerequisite is met. The pipeline runs preflight itself,
    /// so it does not require a prior preflight pass. "booted" is part of the gate so
    /// the disabled state is explained up front rather than failing later at preflight.
    private var canRunPipeline: Bool {
        pipelinePrerequisites.allSatisfy { $0.met }
    }

    /// First unmet prerequisite's hint — the specific reason the button is disabled.
    private var pipelineBlockReason: String? {
        pipelinePrerequisites.first(where: { !$0.met })?.hint
    }

    @ViewBuilder
    private var runInSimulatorButton: some View {
        Button(action: { Task { await startPipeline() } }) {
            HStack(spacing: 4) {
                if coordinator.isRunning {
                    ProgressView().scaleEffect(0.45).frame(width: 10, height: 10)
                } else {
                    Image(systemName: "play.fill").font(.system(size: 10))
                }
                Text(coordinator.isRunning ? "Running…" : "Run in Simulator")
                    .font(.system(size: 10, weight: .semibold))
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(canRunPipeline ? Color.accentColor : Color(white: 0.26))
        .disabled(!canRunPipeline || coordinator.isRunning || appEnv.isBuilding)
        .help(pipelineBlockReason
              ?? "Build → Preflight → Inject → Verify, end-to-end, stopping at the first failure")
    }

    // MARK: - Prerequisites Row

    /// Compact guidance shown when the pipeline can't run yet. Lists each
    /// prerequisite with a met/unmet indicator and a one-line hint for the first
    /// thing to fix. Hidden once everything is satisfied.
    @ViewBuilder
    private var prerequisitesRow: some View {
        HStack(spacing: 8) {
            Text("TO RUN")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color(white: 0.36))
                .kerning(1.0)
            ForEach(pipelinePrerequisites) { req in
                HStack(spacing: 3) {
                    Image(systemName: req.met ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 9))
                        .foregroundStyle(req.met ? IDETheme.Colors.consoleSuccess : Color(white: 0.34))
                    Text(req.label)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(req.met ? Color(white: 0.55) : Color(white: 0.40))
                }
                .help(req.met ? "\(req.label): ready" : req.hint)
            }
            if let reason = pipelineBlockReason {
                Text("— \(reason)")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.yellow.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: IDETheme.Layout.tabBarHeight)
        .background(IDETheme.Colors.headerBackground)
    }

    // MARK: - Pipeline Strip (compact readout)

    private var pipelineStrip: some View {
        HStack(spacing: 6) {
            Text("PIPELINE")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color(white: 0.36))
                .kerning(1.0)
            ForEach(coordinator.stages) { stage in
                pipelineChip(stage)
            }
            Spacer()
            Button(action: { coordinator.reset() }) {
                Image(systemName: "xmark").font(.system(size: 9))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color(white: 0.36))
            .disabled(coordinator.isRunning)
        }
        .padding(.horizontal, 12)
        .frame(height: IDETheme.Layout.tabBarHeight)
        .background(IDETheme.Colors.headerBackground)
    }

    @ViewBuilder
    private func pipelineChip(_ stage: SimulatorRunCoordinator.RunStage) -> some View {
        let (color, icon): (Color, String) = {
            switch stage.outcome {
            case .pending: return (Color(white: 0.30), "circle")
            case .running: return (Color.accentColor, "circle.dotted")
            case .passed:  return (IDETheme.Colors.consoleSuccess, "checkmark.circle.fill")
            case .failed:  return (IDETheme.Colors.consoleError, "xmark.circle.fill")
            case .warn:    return (Color.yellow, "exclamationmark.triangle.fill")
            }
        }()
        HStack(spacing: 3) {
            if stage.outcome == .running {
                ProgressView().scaleEffect(0.35).frame(width: 8, height: 8)
            } else {
                Image(systemName: icon).font(.system(size: 9)).foregroundStyle(color)
            }
            Text(stage.label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(color)
        }
        .help(stage.detail.isEmpty ? stage.label : "\(stage.label): \(stage.detail)")
    }

    // MARK: - Pipeline Orchestration

    /// Orchestrates the full simulator pipeline by sequencing the existing services.
    /// Contains NO injection/build/verification logic of its own — it only calls the
    /// owners of each step and records their structured results. Stops at the first
    /// hard failure (build / preflight / launch); evidence stages are observational.
    /// Collects the selected simulator + bundle ID and hands orchestration to the
    /// coordinator. The View owns no pipeline progression — it only gathers inputs.
    private func startPipeline() async {
        guard let device = sim.activeDevice else { return }
        let bundleID = preflightBundleID.trimmingCharacters(in: .whitespaces)
        let target = SimulatorTarget(device: device, bootedIDs: sim.bootedDeviceIDs)
        await coordinator.run(target: target, bundleID: bundleID)
    }

    // MARK: - Inject Button

    /// Inject is allowed only when preflight has run and reported no failures,
    /// and a dylib + bundle ID are actually present. Preflight is the gate;
    /// this view does not re-derive readiness independently.
    private var canInject: Bool {
        guard let r = preflight.result, r.passed else { return false }
        guard let dylib = effectiveInjectionDylib,
              FileManager.default.fileExists(atPath: dylib.path) else { return false }
        guard !preflightBundleID.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        guard sim.activeDevice != nil else { return false }
        return true
    }

    @ViewBuilder
    private var injectButton: some View {
        Button(action: { Task { await runInjection() } }) {
            HStack(spacing: 4) {
                if injection.isExecuting {
                    ProgressView().scaleEffect(0.45).frame(width: 10, height: 10)
                } else {
                    Image(systemName: "syringe")
                        .font(.system(size: 10))
                }
                Text(injection.isExecuting ? "Injecting…" : "Inject")
                    .font(.system(size: 10, weight: .medium))
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(canInject ? IDETheme.Colors.consoleSuccess : Color(white: 0.26))
        .disabled(!canInject || injection.isExecuting)
        .help(canInject
              ? "Launch the target app on the simulator with DYLD_INSERT_LIBRARIES set to the built dylib"
              : "Run a passing preflight first (needs booted simulator, bundle ID, and built dylib)")
    }

    // MARK: - Run Injection

    /// The dylib to inject/inspect. Prefer the iphonesimulator build (platform 7,
    /// actually mappable) over the device build (platform 2, which preflight will
    /// correctly reject). Falls back to the device dylib so preflight still reports
    /// the platform mismatch clearly instead of finding nothing.
    private var effectiveInjectionDylib: URL? {
        appEnv.lastBuiltSimulatorDylibURL ?? appEnv.lastBuiltDylibURL
    }

    /// Thin trigger: validates the selected target/bundle/dylib and hands the
    /// launch + verification sequence to the coordinator. No orchestration here.
    private func runInjection() async {
        guard let device = sim.activeDevice,
              let dylib = effectiveInjectionDylib else { return }
        let bundleID = preflightBundleID.trimmingCharacters(in: .whitespaces)
        guard !bundleID.isEmpty else { return }

        let target = SimulatorTarget(device: device, bootedIDs: sim.bootedDeviceIDs)
        await coordinator.runInjectOnly(target: target, bundleID: bundleID, dylibURL: dylib)
    }

    // MARK: - Run Preflight

    /// Thin trigger: collects the selected target, bundle ID, and artifact URLs,
    /// then hands the readiness check to the coordinator. No orchestration here.
    private func runPreflight() async {
        // Convert the currently selected SimulatorService device into a SimulatorTarget.
        // Boot state comes from sim.bootedDeviceIDs which SimulatorService maintains.
        let target: SimulatorTarget? = sim.activeDevice.map {
            SimulatorTarget(device: $0, bootedIDs: sim.bootedDeviceIDs)
        }
        let bundleID = preflightBundleID.trimmingCharacters(in: .whitespaces).isEmpty
            ? nil : preflightBundleID
        await coordinator.runPreflightOnly(
            target: target,
            bundleID: bundleID,
            packageURL: appEnv.lastBuiltPackageURL,
            dylibURL: effectiveInjectionDylib
        )
    }

    // MARK: - Crash Badge

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
        if !sim.syslogLines.isEmpty {
            SyslogTextView(lines: sim.syslogLines)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !injectionPanelLogs.isEmpty {
            injectionLogView
        } else {
            emptyState
        }
    }

    /// Injection execution + load-verification logs merged in timestamp order.
    /// Each line is already prefixed with "[HH:mm:ss.SSS]" by its service, so a
    /// lexicographic sort on that prefix yields chronological order.
    private var injectionPanelLogs: [String] {
        (injection.logs + verification.logs).sorted { lhs, rhs in
            lhs.prefix(14) < rhs.prefix(14)
        }
    }

    /// Plain text log of injection execution + load verification output.
    /// Shown when no live syslog stream is active.
    private var injectionLogView: some View {
        let lines = injectionPanelLogs
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                        Text(line)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(injectionLogColor(line))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .id(idx)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(IDETheme.Colors.consoleBackground)
            .onChange(of: lines.count) {
                if let last = lines.indices.last {
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
        }
    }

    private func injectionLogColor(_ line: String) -> Color {
        if line.contains("✓") { return IDETheme.Colors.consoleSuccess }
        if line.contains("✗") || line.contains("⚠") { return IDETheme.Colors.consoleError }
        if line.contains("$") || line.contains("INJECT →") { return Color.accentColor }
        if line.contains("NOTE:") { return Color.yellow.opacity(0.8) }
        return Color(white: 0.62)
    }

    private var emptyState: some View {
        Text(sim.activeDeviceIsBooted
             ? "Press Stream to start live syslog."
             : sim.devices.isEmpty
                 ? "No simulators found — press ↻ to refresh."
                 : "Select and boot a simulator to stream logs.")
            .font(.system(size: 11))
            .foregroundStyle(Color(white: 0.28))
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
