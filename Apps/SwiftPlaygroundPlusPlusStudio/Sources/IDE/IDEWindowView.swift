import SwiftUI
import SPPCore

struct IDEWindowView: View {

    @EnvironmentObject var appEnv: AppEnvironment
    @EnvironmentObject var diagnostics: FileDiagnosticsStore

    @State private var consoleExpanded: Bool = true
    @State private var showNewProject: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            splitView
            if consoleExpanded {
                Rectangle()
                    .fill(IDETheme.Colors.panelSeparator)
                    .frame(height: IDETheme.Layout.separatorWeight)
                ConsoleTabView()
                    .frame(height: 220)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .toolbar { toolbarContent }
        .animation(IDETheme.Animation.standard, value: consoleExpanded)
        .sheet(isPresented: $showNewProject) {
            NewProjectView()
                .environmentObject(appEnv)
        }
        .onReceive(NotificationCenter.default.publisher(for: .sppNewProjectRequested)) { _ in
            showNewProject = true
        }
        .environmentObject(appEnv.simulatorService)
        .environmentObject(appEnv.injectionPreflightService)
        .environmentObject(appEnv.injectionExecutionService)
        .environmentObject(appEnv.injectionVerificationService)
        .environmentObject(appEnv.simulatorRunCoordinator)
    }

    // MARK: - Split View

    private var splitView: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } content: {
            EditorAreaView()
                .navigationSplitViewColumnWidth(min: 320, ideal: 600)
        } detail: {
            InspectorView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 300)
        }
        .navigationSplitViewStyle(.balanced)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {

        ToolbarItemGroup(placement: .navigation) {
            Button(action: {
                consoleExpanded = true
                appEnv.buildCurrentProject()
            }) {
                if appEnv.isBuilding {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "hammer")
                        .symbolRenderingMode(.hierarchical)
                }
            }
            .disabled(appEnv.isBuilding || appEnv.currentProject == nil)
            .keyboardShortcut("b", modifiers: .command)
            .help("Build  ⌘B")

            Button(action: { appEnv.revealLastPackage() }) {
                Image(systemName: "archivebox")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(appEnv.lastBuiltPackageURL != nil ? Color.green : Color.secondary)
            }
            .disabled(appEnv.lastBuiltPackageURL == nil)
            .keyboardShortcut("r", modifiers: .command)
            .help("Reveal .deb in Finder  ⌘R")

            if appEnv.isBuilding {
                Button(action: { appEnv.stopBuild() }) {
                    Image(systemName: "stop.fill")
                        .foregroundStyle(Color.red)
                }
                .help("Stop  ⌘.")
            }
        }

        ToolbarItem(placement: .primaryAction) {
            diagnosticsBadge
        }

        ToolbarItem(placement: .primaryAction) {
            Button(action: { consoleExpanded.toggle() }) {
                Image(systemName: "terminal")
                    .symbolVariant(consoleExpanded ? .fill : .none)
                    .foregroundStyle(consoleExpanded ? Color.accentColor : Color.secondary)
            }
            .help(consoleExpanded ? "Hide Console" : "Show Console")
        }

        ToolbarItem(placement: .principal) {
            projectStatusChip
        }
    }

    @ViewBuilder
    private var diagnosticsBadge: some View {
        let errors = diagnostics.totalErrorCount
        let warnings = diagnostics.totalWarningCount
        if errors > 0 || warnings > 0 {
            Button {
                consoleExpanded = true
                NotificationCenter.default.post(
                    name: .sppShowConsoleTab,
                    object: ConsoleTab.problems.rawValue
                )
            } label: {
                HStack(spacing: 6) {
                    IDEStatusBadge(count: errors, color: IDETheme.Colors.diagnosticError, icon: "xmark.octagon.fill")
                    IDEStatusBadge(count: warnings, color: IDETheme.Colors.diagnosticWarning, icon: "exclamationmark.triangle.fill")
                }
            }
            .buttonStyle(.plain)
            .help("Show Problems")
        }
    }

    private var projectStatusChip: some View {
        HStack(spacing: 6) {
            if let project = appEnv.currentProject {
                Circle()
                    .fill(Color.green)
                    .frame(width: 5, height: 5)
                    .shadow(color: .green.opacity(0.8), radius: 4)
                Text(project.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
            } else {
                Circle()
                    .fill(Color(white: 0.32))
                    .frame(width: 5, height: 5)
                Text("No Project")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(white: 0.45))
            }
        }
        .animation(IDETheme.Animation.snap, value: appEnv.currentProject?.name)
    }
}

struct IDEWindowView_Previews: PreviewProvider {
    static var previews: some View {
        IDEWindowView()
            .environmentObject(AppEnvironment())
            .frame(width: 1200, height: 800)
    }
}
