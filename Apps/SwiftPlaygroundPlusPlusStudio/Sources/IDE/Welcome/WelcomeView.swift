import SwiftUI
import AppKit
import SPPCore

// MARK: - WelcomeView

/// macOS welcome screen displayed when no project is currently open.
///
/// Presents branding on the left and a concise set of project actions on the
/// right: creating a new project, opening an existing `.sppproject` bundle, or
/// re-opening a recent project.
struct WelcomeView: View {

    // MARK: Dependencies

    @EnvironmentObject var appEnv: AppEnvironment

    // MARK: State

    @State private var showNewProject = false
    @State private var openError: String?
    @State private var showOpenError = false

    // MARK: Body

    var body: some View {
        HStack(spacing: 0) {
            brandingSection
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(brandingBackground)

            Divider()

            actionsSection
                .frame(width: 260)
                .frame(maxHeight: .infinity)
                .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 700, height: 420)
        .sheet(isPresented: $showNewProject) {
            NewProjectView()
                .environmentObject(appEnv)
        }
        .alert("Could Not Open Project", isPresented: $showOpenError, presenting: openError) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }

    // MARK: - Branding Section

    private var brandingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Spacer()

            Image(systemName: "swift")
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
                .foregroundStyle(.orange)

            Text("Swift Playground++ Studio")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text("Jailbreak Tweak IDE")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            Spacer()

            Text("Version \(appVersionString)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var brandingBackground: some View {
        LinearGradient(
            colors: [
                Color(NSColor.windowBackgroundColor),
                Color(NSColor.controlBackgroundColor)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            actionHeader("Start")

            WelcomeActionButton(
                systemImage: "plus.square",
                title: "New Project",
                action: { showNewProject = true }
            )

            WelcomeActionButton(
                systemImage: "folder",
                title: "Open Project\u{2026}",
                action: openProjectPanel
            )

            if !appEnv.projectService.recentProjectURLs.isEmpty {
                Divider().padding(.vertical, 8)

                actionHeader("Recent Projects")

                recentProjectsList
            }

            Spacer()
        }
        .padding(.top, 20)
        .padding(.horizontal, 16)
    }

    private func actionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
    }

    private var recentProjectsList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(appEnv.projectService.recentProjectURLs, id: \.absoluteString) { url in
                    RecentProjectRow(url: url) {
                        openProject(at: url)
                    }
                }
            }
        }
        .frame(maxHeight: 160)
    }

    // MARK: - Actions

    private func openProjectPanel() {
        let panel = NSOpenPanel()
        panel.title = "Open Project"
        panel.message = "Choose a Swift Playground++ Studio project"
        panel.allowedContentTypes = []
        panel.allowsOtherFileTypes = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        // Filter .sppproject bundles (packages are directories on disk)
        panel.treatsFilePackagesAsDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        openProject(at: url)
    }

    private func openProject(at url: URL) {
        Task { @MainActor in
            do {
                try await appEnv.projectService.openProject(at: url)
            } catch {
                openError = error.localizedDescription
                showOpenError = true
            }
        }
    }

    // MARK: - Helpers

    private var appVersionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}

// MARK: - WelcomeActionButton

private struct WelcomeActionButton: View {
    let systemImage: String
    let title: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .frame(width: 20, alignment: .center)
                    .foregroundStyle(Color.accentColor)
                Text(title)
                    .font(.system(size: 13))
                Spacer()
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovered ? Color(NSColor.selectedContentBackgroundColor).opacity(0.15) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - RecentProjectRow

private struct RecentProjectRow: View {
    let url: URL
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    .frame(width: 20, alignment: .center)
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))

                VStack(alignment: .leading, spacing: 1) {
                    Text(url.deletingPathExtension().lastPathComponent)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Text(url.deletingLastPathComponent().path(percentEncoded: false))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovered ? Color(NSColor.selectedContentBackgroundColor).opacity(0.15) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
