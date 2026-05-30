import SwiftUI
import SPPCore

// MARK: - Inspector View

struct InspectorView: View {

    @EnvironmentObject var appEnv: AppEnvironment

    var body: some View {
        if let project = appEnv.currentProject {
            inspectorContent(for: project)
        } else {
            noSelectionPlaceholder
        }
    }

    // MARK: - Inspector Content

    private func inspectorContent(for project: SPPProject) -> some View {
        VStack(spacing: 0) {
            panelHeader
            panelDivider
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    projectSection(for: project)
                    buildSection(for: project)
                }
                .padding(IDETheme.Layout.panelPadding)
            }
        }
        .background(IDETheme.Colors.inspectorBackground)
    }

    // MARK: - Panel Header

    private var panelHeader: some View {
        HStack(spacing: 7) {
            Image(systemName: "info.circle")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color(white: 0.36))
            Text("Inspector")
                .idePanelTitle()
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: IDETheme.Layout.panelTitleHeight)
        .background(IDETheme.Colors.headerBackground)
    }

    // MARK: - Sections

    private func projectSection(for project: SPPProject) -> some View {
        InspectorSectionView(title: "PROJECT") {
            InspectorRowView(label: "Name",      value: project.name,                mono: false, showDivider: true)
            InspectorRowView(label: "Display",   value: project.displayName,         mono: false, showDivider: true)
            InspectorRowView(label: "Bundle ID", value: project.bundleID,            mono: true,  showDivider: true)
            InspectorRowView(label: "Version",   value: project.version.description, mono: true,  showDivider: !project.author.isEmpty)
            if !project.author.isEmpty {
                InspectorRowView(label: "Author", value: project.author, mono: false, showDivider: false)
            }
        }
    }

    private func buildSection(for project: SPPProject) -> some View {
        InspectorSectionView(title: "BUILD") {
            InspectorRowView(label: "Targets", value: "\(project.targets.count)",                          mono: true, showDivider: true)
            InspectorRowView(label: "Files",   value: "\(project.files.flatMap { $0.allFiles() }.count)", mono: true, showDivider: !project.targets.isEmpty)
            if let target = project.primaryTarget {
                InspectorRowView(label: "Target", value: target.name,                       mono: false, showDivider: true)
                InspectorRowView(label: "Type",   value: target.type.rawValue,              mono: true,  showDivider: true)
                InspectorRowView(label: "Min OS", value: target.buildSettings.minOSVersion, mono: true,  showDivider: false)
            }
        }
    }

    // MARK: - Empty State

    private var noSelectionPlaceholder: some View {
        VStack(spacing: 0) {
            panelHeader
            panelDivider
            VStack(spacing: 10) {
                Image(systemName: "square.3.layers.3d")
                    .font(.system(size: 26, weight: .ultraLight))
                    .foregroundStyle(Color(white: 0.22))
                VStack(spacing: 4) {
                    Text("No Project Open")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(white: 0.30))
                    Text("Open or create a project\nto see its details here.")
                        .font(IDETheme.Typography.caption)
                        .foregroundStyle(Color(white: 0.24))
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(IDETheme.Colors.inspectorBackground)
    }

    // MARK: - Helpers

    private var panelDivider: some View {
        Rectangle()
            .fill(IDETheme.Colors.panelSeparator)
            .frame(height: IDETheme.Layout.separatorWeight)
    }
}

// MARK: - Inspector Section View

private struct InspectorSectionView<Content: View>: View {

    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Text(title)
                    .ideSectionHeader()
                Rectangle()
                    .fill(IDETheme.Colors.rowDivider)
                    .frame(height: IDETheme.Layout.separatorWeight)
            }

            VStack(spacing: 0) {
                content()
            }
            .ideCard()
        }
    }
}

// MARK: - Inspector Row View

private struct InspectorRowView: View {

    let label: String
    let value: String
    let mono: Bool
    let showDivider: Bool

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label)
                    .font(IDETheme.Typography.caption)
                    .foregroundStyle(Color(white: 0.38))
                    .frame(width: 62, alignment: .leading)
                    .lineLimit(1)

                Text(value)
                    .font(mono ? IDETheme.Typography.labelMono : IDETheme.Typography.label)
                    .foregroundStyle(Color(white: 0.84))
                    .lineLimit(2)
                    .textSelection(.enabled)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, IDETheme.Layout.rowVerticalTight + 1)
            .background(isHovered ? IDETheme.Colors.hoverFill : Color.clear)

            if showDivider {
                Rectangle()
                    .fill(IDETheme.Colors.rowDivider)
                    .frame(height: IDETheme.Layout.separatorWeight)
                    .padding(.leading, 10)
            }
        }
        .onHover { isHovered = $0 }
        .animation(IDETheme.Animation.micro, value: isHovered)
    }
}

// MARK: - Preview

struct InspectorView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            InspectorView()
                .environmentObject(withProject)
                .frame(width: 260, height: 500)
                .previewDisplayName("With project")

            InspectorView()
                .environmentObject(AppEnvironment())
                .frame(width: 260, height: 500)
                .previewDisplayName("No selection")
        }
        .preferredColorScheme(.dark)
    }

    private static var withProject: AppEnvironment = {
        let e = AppEnvironment()
        e.projectService.currentProject = SPPProject(
            name: "MyTweak",
            bundleID: "com.example.mytweak",
            targets: [.defaultLogosTarget()],
            files: [SPPFile(name: "Tweak.xm", relativePath: "Tweak.xm", contentType: .logosXM)]
        )
        return e
    }()
}
