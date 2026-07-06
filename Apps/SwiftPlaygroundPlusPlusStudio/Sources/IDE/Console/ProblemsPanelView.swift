import SwiftUI
import SPPCore

// MARK: - Problems Panel

/// Lists every diagnostic in the project, grouped by file. Clicking a row jumps
/// the editor to the diagnostic's location (`NavigateToLineEvent`). Pure view
/// over `FileDiagnosticsStore` — it owns no diagnostic state.
struct ProblemsPanelView: View {

    @EnvironmentObject var appEnv: AppEnvironment
    @EnvironmentObject var diagnostics: FileDiagnosticsStore

    private var groups: [FileGroup] {
        diagnostics.diagnosticsByFile
            .map { fileID, diags in
                FileGroup(
                    fileID: fileID,
                    displayPath: appEnv.currentProject?.file(with: fileID)?.relativePath
                        ?? appEnv.currentProject?.file(with: fileID)?.name
                        ?? "Unknown file",
                    diagnostics: diags,
                    worst: diags.map(\.severity).max() ?? .note
                )
            }
            .sorted { lhs, rhs in
                if lhs.worst != rhs.worst { return lhs.worst > rhs.worst }
                return lhs.displayPath < rhs.displayPath
            }
    }

    var body: some View {
        if diagnostics.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(groups) { group in
                        fileHeader(group)
                        ForEach(group.diagnostics) { diag in
                            DiagnosticRow(diagnostic: diag) {
                                appEnv.eventBus.publish(
                                    NavigateToLineEvent(
                                        fileID: group.fileID,
                                        line: diag.line,
                                        column: diag.column
                                    )
                                )
                            }
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    // MARK: - Pieces

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 18, weight: .thin))
                .foregroundStyle(Color(white: 0.28))
            Text("No problems")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(white: 0.32))
            Text("Errors and warnings from the last build appear here.")
                .font(IDETheme.Typography.caption)
                .foregroundStyle(Color(white: 0.26))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func fileHeader(_ group: FileGroup) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "doc")
                .font(.system(size: 9))
                .foregroundStyle(Color(white: 0.34))
            Text(group.displayPath)
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(white: 0.50))
                .lineLimit(1)
                .truncationMode(.head)
            Spacer(minLength: 0)
            Text("\(group.diagnostics.count)")
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(Color(white: 0.30))
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 3)
    }

    private struct FileGroup: Identifiable {
        let fileID: UUID
        let displayPath: String
        let diagnostics: [Diagnostic]
        let worst: Diagnostic.Severity
        var id: UUID { fileID }
    }
}

// MARK: - Diagnostic Row

private struct DiagnosticRow: View {
    let diagnostic: Diagnostic
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(color)
                    .frame(width: 14, alignment: .center)

                Text(diagnostic.message)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(white: 0.80))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                Text(location)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color(white: 0.34))
            }
            .padding(.horizontal, 12)
            .padding(.leading, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovered ? IDETheme.Colors.hoverFill : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Jump to \(location)")
    }

    private var location: String {
        if let col = diagnostic.column { return "\(diagnostic.line):\(col)" }
        return "\(diagnostic.line)"
    }

    private var icon: String {
        switch diagnostic.severity {
        case .error:   return "xmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .note:    return "info.circle.fill"
        }
    }

    private var color: Color {
        switch diagnostic.severity {
        case .error:   return IDETheme.Colors.diagnosticError
        case .warning: return IDETheme.Colors.diagnosticWarning
        case .note:    return IDETheme.Colors.diagnosticNote
        }
    }
}
