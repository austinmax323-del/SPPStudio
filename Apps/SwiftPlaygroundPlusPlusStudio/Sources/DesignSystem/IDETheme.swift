import SwiftUI
import AppKit
import SPPCore

// MARK: - IDE Theme

enum IDETheme {

    // MARK: Colors

    enum Colors {
        // Main surfaces
        static let editorBackground    = Color(red: 0.102, green: 0.102, blue: 0.152)
        static let sidebarBackground   = Color(red: 0.078, green: 0.078, blue: 0.115)
        static let inspectorBackground = Color(red: 0.078, green: 0.078, blue: 0.115)

        // Console
        static let consoleBackground   = Color(red: 0.056, green: 0.056, blue: 0.082)
        static let consoleGutter       = Color(white: 0.20)
        static let consolePrimary      = Color(white: 0.80)
        static let consoleSecondary    = Color(white: 0.40)
        static let consoleError        = Color(red: 1.00, green: 0.36, blue: 0.36)
        static let consoleWarning      = Color(red: 1.00, green: 0.74, blue: 0.24)
        static let consoleSuccess      = Color(red: 0.34, green: 0.92, blue: 0.52)
        static let consoleInfo         = Color(red: 0.44, green: 0.76, blue: 1.00)

        // Interactive states
        static let hoverFill           = Color(white: 1.0, opacity: 0.07)
        static let hoverFillStrong     = Color(white: 1.0, opacity: 0.11)
        static let activeFill          = Color(white: 1.0, opacity: 0.15)
        static let selectedFill        = Color.accentColor.opacity(0.22)
        static let selectedRowFill     = Color.accentColor.opacity(0.18)
        static let segmentBackground   = Color(white: 1.0, opacity: 0.06)

        // Structure
        static let headerBackground    = Color(white: 0.0, opacity: 0.28)
        static let cardBackground      = Color(white: 1.0, opacity: 0.045)
        static let rowDivider          = Color(white: 1.0, opacity: 0.07)
        static let panelSeparator      = Color(white: 1.0, opacity: 0.09)
        static let panelBorder         = Color(white: 1.0, opacity: 0.11)

        // File type accents
        static let swiftOrange         = Color(red: 0.96, green: 0.56, blue: 0.20)
        static let objcBlue            = Color(red: 0.28, green: 0.66, blue: 0.92)
        static let logosXMPurple       = Color(red: 0.58, green: 0.42, blue: 0.88)
        static let makefileGreen       = Color(red: 0.58, green: 0.82, blue: 0.38)

        // Diagnostics (SwiftUI surfaces — Problems list, badges)
        static let diagnosticError     = consoleError
        static let diagnosticWarning   = consoleWarning
        static let diagnosticNote      = consoleInfo
    }

    // MARK: AppKit Editor Colors

    /// `NSColor` tokens for the AppKit editor surface (diagnostic underlines and
    /// gutter markers). Kept alongside `Colors` so the editor never hardcodes hex.
    enum EditorColors {
        static let diagnosticError   = NSColor(red: 1.00, green: 0.36, blue: 0.36, alpha: 1)
        static let diagnosticWarning = NSColor(red: 1.00, green: 0.74, blue: 0.24, alpha: 1)
        static let diagnosticNote    = NSColor(red: 0.44, green: 0.76, blue: 1.00, alpha: 1)

        static func underline(for severity: Diagnostic.Severity) -> NSColor {
            switch severity {
            case .error:   return diagnosticError
            case .warning: return diagnosticWarning
            case .note:    return diagnosticNote
            }
        }
    }

    // MARK: Typography

    enum Typography {
        static let panelTitle    = Font.system(size: 11, weight: .semibold)
        static let sectionHeader = Font.system(size: 10, weight: .semibold)
        static let label         = Font.system(size: 11)
        static let labelMono     = Font.system(size: 11, design: .monospaced)
        static let body          = Font.system(size: 12)
        static let bodyMono      = Font.system(size: 12, design: .monospaced)
        static let caption       = Font.system(size: 10)
        static let captionMono   = Font.system(size: 10, design: .monospaced)
    }

    // MARK: Layout

    enum Layout {
        static let tabBarHeight:     CGFloat = 30
        static let editorTabHeight:  CGFloat = 33
        static let panelTitleHeight: CGFloat = 34
        static let rowVertical:      CGFloat = 7
        static let rowVerticalTight: CGFloat = 5
        static let panelPadding:     CGFloat = 12
        static let cardRadius:       CGFloat = 7
        static let chipRadius:       CGFloat = 4
        static let iconSize:         CGFloat = 13
        static let sidebarIconSize:  CGFloat = 14
        static let separatorWeight:  CGFloat = 0.5
    }

    // MARK: Animation

    enum Animation {
        static let micro    = SwiftUI.Animation.easeInOut(duration: 0.08)
        static let snap     = SwiftUI.Animation.easeInOut(duration: 0.10)
        static let standard = SwiftUI.Animation.spring(response: 0.22, dampingFraction: 0.88)
    }
}

// MARK: - View Modifiers

extension View {

    func ideSectionHeader() -> some View {
        self
            .font(IDETheme.Typography.sectionHeader)
            .foregroundStyle(Color(white: 0.40))
            .kerning(0.8)
    }

    func idePanelTitle() -> some View {
        self
            .font(IDETheme.Typography.panelTitle)
            .foregroundStyle(.primary)
    }

    func ideCaption() -> some View {
        self
            .font(IDETheme.Typography.caption)
            .foregroundStyle(.tertiary)
    }

    func ideCard() -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: IDETheme.Layout.cardRadius, style: .continuous)
                    .fill(IDETheme.Colors.cardBackground)
            )
            .clipShape(RoundedRectangle(cornerRadius: IDETheme.Layout.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: IDETheme.Layout.cardRadius, style: .continuous)
                    .strokeBorder(IDETheme.Colors.panelBorder, lineWidth: IDETheme.Layout.separatorWeight)
            )
    }

    func ideComingSoonChip() -> some View {
        self
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Color(white: 0.40))
            .kerning(0.6)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(IDETheme.Colors.segmentBackground)
                    .overlay(Capsule().strokeBorder(IDETheme.Colors.panelBorder, lineWidth: 0.5))
            )
    }
}

// MARK: - IDE Status Badge

struct IDEStatusBadge: View {
    let count: Int
    let color: Color
    let icon: String

    var body: some View {
        if count > 0 {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                Text("\(count)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
            }
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.14)))
        }
    }
}
