import SwiftUI
import AppKit
import SPPCore
import SPPTheosKit

// MARK: - NewProjectView

struct NewProjectView: View {

    @EnvironmentObject var appEnv: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    @State private var projectName: String = ""
    @State private var bundleID: String = ""
    @State private var selectedTemplate: NICTemplate = .logosTweak
    @State private var previousSlug: String = ""

    @State private var isCreating: Bool = false
    @State private var errorMessage: String?
    @State private var showError: Bool = false

    @FocusState private var focusedField: Field?

    enum Field { case name, bundleID }

    private var isFormValid: Bool {
        !projectName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !bundleID.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            formBody
            Divider()
            footer
        }
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            focusedField = .name
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                if let sheet = NSApp.windows.first(where: { $0.isSheet }) {
                    sheet.makeKey()
                } else {
                    NSApp.keyWindow?.makeKey()
                }
            }
        }
        .alert("Could Not Create Project", isPresented: $showError, presenting: errorMessage) { _ in
            Button("OK", role: .cancel) {}
        } message: { msg in
            Text(msg)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("New Project")
                    .font(.headline)
                Text("Configure your jailbreak tweak project")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    // MARK: - Form

    private var formBody: some View {
        VStack(alignment: .leading, spacing: 20) {
            projectInfoFields
            templatePicker
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
    }

    private var projectInfoFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            fieldRow(label: "Project Name", placeholder: "My Awesome Tweak") {
                TextField("My Awesome Tweak", text: $projectName)
                    .focused($focusedField, equals: .name)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: projectName) { _, newValue in
                        autofillBundleID(from: newValue)
                    }
            }

            fieldRow(label: "Bundle ID", placeholder: "com.example.mytweak") {
                TextField("com.example.mytweak", text: $bundleID)
                    .focused($focusedField, equals: .bundleID)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }
        }
    }

    private func fieldRow<F: View>(label: String, placeholder: String, @ViewBuilder field: () -> F) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
            field()
        }
    }

    private var templatePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Template")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)

            VStack(spacing: 0) {
                ForEach(NICTemplate.allTemplates, id: \.id) { template in
                    templateRow(template)
                }
            }
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color(NSColor.separatorColor), lineWidth: 0.5)
            )

            templateDescriptionRow
        }
    }

    private func templateRow(_ template: NICTemplate) -> some View {
        let isSelected = selectedTemplate.id == template.id
        return Button(action: { selectedTemplate = template }) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 18)

                Image(systemName: templateIcon(for: template))
                    .font(.system(size: 13))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 16)

                Text(template.displayName)
                    .font(.system(size: 13))

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var templateDescriptionRow: some View {
        let text: String = {
            switch selectedTemplate.id {
            case NICTemplate.logosTweak.id:
                return "Logos tweak using Objective-C with Logos syntax. Best for hooking system frameworks."
            case NICTemplate.orionTweak.id:
                return "Orion tweak written in Swift. Modern Swift syntax for hooking iOS classes."
            case NICTemplate.preferenceBundle.id:
                return "Preference bundle for adding a Settings.app pane to your tweak."
            default:
                return ""
            }
        }()

        if !text.isEmpty {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.top, 0.5)
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.escape, modifiers: [])

            Button(isCreating ? "Creating…" : "Create") {
                createProject()
            }
            .keyboardShortcut(.return, modifiers: [])
            .disabled(!isFormValid || isCreating)
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    // MARK: - Logic

    private func autofillBundleID(from name: String) {
        guard bundleID.isEmpty ||
              bundleID == "com.example.\(previousSlug)" else { return }
        let slug = name
            .lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined()
        if !slug.isEmpty {
            bundleID = "com.example.\(slug)"
        }
        previousSlug = slug
    }

    private func createProject() {
        let name   = projectName.trimmingCharacters(in: .whitespaces)
        let bundle = bundleID.trimmingCharacters(in: .whitespaces)

        let panel = NSOpenPanel()
        panel.title = "Choose Location for \"\(name)\""
        panel.message = "\"\(name).sppproject\" will be created in the chosen folder."
        panel.prompt = "Create Here"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let outputURL = panel.url else { return }

        isCreating = true
        Task { @MainActor in
            defer { isCreating = false }
            do {
                _ = try await appEnv.projectService.createProject(
                    name: name,
                    bundleID: bundle,
                    outputDirectory: outputURL
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    // MARK: - Helpers

    private func templateIcon(for template: NICTemplate) -> String {
        switch template.id {
        case NICTemplate.logosTweak.id:       return "chevron.left.forwardslash.chevron.right"
        case NICTemplate.orionTweak.id:       return "swift"
        case NICTemplate.preferenceBundle.id: return "gearshape"
        default:                              return "doc"
        }
    }
}
