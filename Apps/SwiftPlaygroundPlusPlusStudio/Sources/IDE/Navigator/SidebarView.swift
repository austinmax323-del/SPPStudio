import SwiftUI
import SPPCore

// MARK: - Navigator Tab

enum NavigatorTab: String, CaseIterable, Identifiable {
    case files    = "Files"
    case hooks    = "Hooks"
    case symbols  = "Symbols"
    case search   = "Search"
    case runtime  = "Runtime"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .files:   return "doc.on.doc"
        case .hooks:   return "bolt"
        case .symbols: return "diamond"
        case .search:  return "magnifyingglass"
        case .runtime: return "waveform"
        }
    }

    var selectedImage: String {
        switch self {
        case .files:   return "doc.on.doc.fill"
        case .hooks:   return "bolt.fill"
        case .symbols: return "diamond.fill"
        case .search:  return "magnifyingglass"
        case .runtime: return "waveform"
        }
    }
}

// MARK: - Sidebar View

struct SidebarView: View {

    @EnvironmentObject var appEnv: AppEnvironment

    @State private var selectedTab: NavigatorTab = .files
    @State private var hoveredTab: NavigatorTab? = nil

    var body: some View {
        VStack(spacing: 0) {
            navigatorTabBar
            panelDivider
            if let project = appEnv.currentProject {
                projectHeader(for: project)
                panelDivider
            }
            navigatorContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(IDETheme.Colors.sidebarBackground)
    }

    // MARK: - Navigator Tab Bar

    private var navigatorTabBar: some View {
        HStack(spacing: 0) {
            ForEach(NavigatorTab.allCases) { tab in
                navigatorTabButton(tab)
            }
        }
        .frame(height: IDETheme.Layout.panelTitleHeight)
        .background(IDETheme.Colors.headerBackground)
    }

    @ViewBuilder
    private func navigatorTabButton(_ tab: NavigatorTab) -> some View {
        let isSelected = selectedTab == tab
        let isHovered  = hoveredTab == tab

        Button(action: { withAnimation(IDETheme.Animation.snap) { selectedTab = tab } }) {
            ZStack(alignment: .bottom) {
                // Hover/selected background
                Rectangle()
                    .fill(
                        isSelected
                            ? IDETheme.Colors.selectedRowFill
                            : isHovered ? IDETheme.Colors.hoverFill : Color.clear
                    )

                // Icon
                Image(systemName: isSelected ? tab.selectedImage : tab.systemImage)
                    .font(.system(size: IDETheme.Layout.sidebarIconSize, weight: isSelected ? .medium : .light))
                    .foregroundStyle(
                        isSelected
                            ? Color.accentColor
                            : isHovered ? Color(white: 0.62) : Color(white: 0.34)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Active indicator
                Rectangle()
                    .fill(isSelected ? Color.accentColor : Color.clear)
                    .frame(height: 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tab.rawValue)
        .onHover { hoveredTab = $0 ? tab : nil }
        .animation(IDETheme.Animation.micro, value: isHovered)
        .animation(IDETheme.Animation.snap, value: isSelected)
    }

    // MARK: - Project Header

    private func projectHeader(for project: SPPProject) -> some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 20, height: 20)
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.orange.opacity(0.88))
            }

            Text(project.name)
                .font(IDETheme.Typography.label)
                .fontWeight(.semibold)
                .lineLimit(1)
                .foregroundStyle(Color(white: 0.90))

            Spacer(minLength: 4)

            Text("v\(project.version.description)")
                .font(IDETheme.Typography.captionMono)
                .foregroundStyle(Color(white: 0.36))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: IDETheme.Layout.chipRadius, style: .continuous)
                        .fill(IDETheme.Colors.segmentBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: IDETheme.Layout.chipRadius, style: .continuous)
                                .strokeBorder(IDETheme.Colors.panelBorder, lineWidth: 0.5)
                        )
                )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(IDETheme.Colors.headerBackground.opacity(0.5))
    }

    // MARK: - Navigator Content

    @ViewBuilder
    private var navigatorContent: some View {
        switch selectedTab {
        case .files:
            ProjectFileNavigatorView()
        case .hooks:
            NavigatorPlaceholderView(label: "Hook Graph", systemImage: "bolt.fill", description: "Hook call graphs will appear here during active debugging.")
        case .symbols:
            NavigatorPlaceholderView(label: "Symbol Index", systemImage: "diamond.fill", description: "Indexed symbols from your project and linked frameworks.")
        case .search:
            NavigatorPlaceholderView(label: "Project Search", systemImage: "magnifyingglass", description: "Full-text search across all project sources.")
        case .runtime:
            NavigatorPlaceholderView(label: "Runtime Inspector", systemImage: "waveform", description: "Live process and memory inspection during a connected session.")
        }
    }

    // MARK: - Helpers

    private var panelDivider: some View {
        Rectangle()
            .fill(IDETheme.Colors.panelSeparator)
            .frame(height: IDETheme.Layout.separatorWeight)
    }
}

// MARK: - Navigator Placeholder View

private struct NavigatorPlaceholderView: View {
    let label: String
    let systemImage: String
    var description: String = ""

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .ultraLight))
                .foregroundStyle(Color(white: 0.22))

            VStack(spacing: 5) {
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(white: 0.30))

                if !description.isEmpty {
                    Text(description)
                        .font(IDETheme.Typography.caption)
                        .foregroundStyle(Color(white: 0.24))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.horizontal, 20)
                }
            }

            Text("COMING SOON")
                .ideComingSoonChip()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preview

struct SidebarView_Previews: PreviewProvider {
    static var previews: some View {
        SidebarView()
            .environmentObject(AppEnvironment())
            .frame(width: 240, height: 600)
            .preferredColorScheme(.dark)
    }
}
