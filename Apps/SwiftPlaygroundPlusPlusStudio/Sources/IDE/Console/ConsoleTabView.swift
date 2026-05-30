import SwiftUI
import SPPCore

// MARK: - Console Tab

enum ConsoleTab: String, CaseIterable, Identifiable {
    case build     = "Build"
    case simulator = "Simulator"
    case runtime   = "Runtime"
    case packages  = "Packages"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .build:     return "hammer"
        case .simulator: return "iphone"
        case .runtime:   return "play.circle"
        case .packages:  return "shippingbox"
        }
    }
}

// MARK: - Console Tab View

struct ConsoleTabView: View {

    @State private var selectedTab: ConsoleTab = .build
    @State private var hoveredTab:  ConsoleTab? = nil

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            panelDivider
            tabContent
        }
        .background(IDETheme.Colors.consoleBackground)
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(ConsoleTab.allCases) { tab in
                    tabButton(tab)
                }
            }
            .padding(.leading, 8)

            Spacer()

            Text("CONSOLE")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color(white: 0.24))
                .kerning(1.0)
                .padding(.trailing, 14)
        }
        .frame(height: IDETheme.Layout.tabBarHeight)
        .background(IDETheme.Colors.headerBackground)
    }

    @ViewBuilder
    private func tabButton(_ tab: ConsoleTab) -> some View {
        let isSelected = selectedTab == tab
        let isHovered  = hoveredTab == tab

        Button(action: { withAnimation(IDETheme.Animation.snap) { selectedTab = tab } }) {
            ZStack(alignment: .bottom) {
                // Background
                Rectangle()
                    .fill(
                        isSelected
                            ? Color.white.opacity(0.07)
                            : isHovered ? Color.white.opacity(0.04) : Color.clear
                    )

                // Label
                HStack(spacing: 4) {
                    Image(systemName: tab.systemImage)
                        .font(.system(size: 10, weight: isSelected ? .medium : .regular))
                    Text(tab.rawValue)
                        .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                }
                .foregroundStyle(
                    isSelected
                        ? Color(white: 0.90)
                        : isHovered ? Color(white: 0.56) : Color(white: 0.36)
                )
                .padding(.horizontal, 10)
                .frame(maxHeight: .infinity)

                // Active underline
                Rectangle()
                    .fill(isSelected ? Color.accentColor : Color.clear)
                    .frame(height: 2)
            }
            .frame(height: IDETheme.Layout.tabBarHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoveredTab = $0 ? tab : nil }
        .animation(IDETheme.Animation.micro, value: isHovered)
        .animation(IDETheme.Animation.snap, value: isSelected)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .build:
            BuildConsoleView()
        case .simulator:
            SimulatorPanelView()
        case .runtime:
            ConsoleContentPlaceholder(label: "Runtime Output", systemImage: "play.circle", description: "Live stdout / stderr from a connected device process.")
        case .packages:
            ConsoleContentPlaceholder(label: "Package Manager", systemImage: "shippingbox", description: "Theos package resolution and dependency output.")
        }
    }

    // MARK: - Helpers

    private var panelDivider: some View {
        Rectangle()
            .fill(IDETheme.Colors.panelSeparator)
            .frame(height: IDETheme.Layout.separatorWeight)
    }
}

// MARK: - Console Content Placeholder

private struct ConsoleContentPlaceholder: View {
    let label: String
    let systemImage: String
    var description: String = ""

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .thin))
                .foregroundStyle(Color(white: 0.28))

            VStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(white: 0.32))
                if !description.isEmpty {
                    Text(description)
                        .font(IDETheme.Typography.caption)
                        .foregroundStyle(Color(white: 0.26))
                        .multilineTextAlignment(.center)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preview

struct ConsoleTabView_Previews: PreviewProvider {
    static var previews: some View {
        ConsoleTabView()
            .environmentObject(AppEnvironment())
            .frame(width: 900, height: 200)
            .preferredColorScheme(.dark)
    }
}
