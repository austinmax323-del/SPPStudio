import SwiftUI
import SPPCore

// MARK: - Project File Navigator View

struct ProjectFileNavigatorView: View {

    @EnvironmentObject var appEnv: AppEnvironment
    @State private var selectedFileID: UUID? = nil

    var body: some View {
        Group {
            if let project = appEnv.currentProject {
                fileTree(for: project)
            } else {
                emptyState
            }
        }
        .onReceive(appEnv.eventBus.publisher(for: FileSelectedEvent.self)) { event in
            selectedFileID = event.fileID
        }
    }

    // MARK: - File Tree

    private func fileTree(for project: SPPProject) -> some View {
        List {
            ForEach(project.files) { file in
                FileTreeNode(file: file, selectedFileID: selectedFileID) { selectedFile in
                    appEnv.eventBus.publish(FileSelectedEvent(fileID: selectedFile.id))
                }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "folder.badge.questionmark")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("Open a project to see files")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - File Tree Node

private struct FileTreeNode: View {

    let file: SPPFile
    let selectedFileID: UUID?
    let onSelect: (SPPFile) -> Void

    @EnvironmentObject var appEnv: AppEnvironment
    @State private var isExpanded: Bool
    @State private var isRenaming = false
    @State private var inputText = ""
    @State private var actionError: String?
    @State private var showError = false
    @State private var showNewFile = false
    @State private var showNewFolder = false
    @State private var showDeleteConfirm = false
    @FocusState private var renameFieldFocused: Bool

    // MARK: Init (restores collapse state from UserDefaults)

    init(file: SPPFile, selectedFileID: UUID?, onSelect: @escaping (SPPFile) -> Void) {
        self.file = file
        self.selectedFileID = selectedFileID
        self.onSelect = onSelect
        let key = "spp.expanded.\(file.relativePath)"
        let stored = UserDefaults.standard.object(forKey: key) as? Bool ?? true
        self._isExpanded = State(initialValue: stored)
    }

    // MARK: Body

    var body: some View {
        Group {
            if file.isDirectory {
                DisclosureGroup(isExpanded: $isExpanded) {
                    ForEach(file.children) { child in
                        FileTreeNode(file: child, selectedFileID: selectedFileID, onSelect: onSelect)
                    }
                } label: {
                    rowContent
                }
            } else {
                rowContent
            }
        }
        .onChange(of: isExpanded) { _, value in
            if file.isDirectory {
                UserDefaults.standard.set(value, forKey: "spp.expanded.\(file.relativePath)")
            }
        }
        .contextMenu {
            if file.isDirectory {
                Button("New File\u{2026}") { inputText = ""; showNewFile = true }
                Button("New Folder\u{2026}") { inputText = ""; showNewFolder = true }
                Divider()
            }
            Button("Rename") { inputText = file.name; isRenaming = true }
            Button("Reveal in Finder") { appEnv.projectService.revealInFinder(file) }
            Divider()
            Button("Delete", role: .destructive) { showDeleteConfirm = true }
        }
        .alert("New File", isPresented: $showNewFile) {
            TextField("Filename (e.g. Tweak.xm)", text: $inputText)
            Button("Create") { performCreateFile() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Create a new file inside \"\(file.name)\".") }
        .alert("New Folder", isPresented: $showNewFolder) {
            TextField("Folder name", text: $inputText)
            Button("Create") { performCreateFolder() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Create a new folder inside \"\(file.name)\".") }
        .confirmationDialog("Delete \"\(file.name)\"?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { performDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(file.isDirectory
                 ? "Deletes the folder and all contents. This cannot be undone."
                 : "This cannot be undone.")
        }
        .alert("Error", isPresented: $showError, presenting: actionError) { _ in
            Button("OK", role: .cancel) {}
        } message: { msg in Text(msg) }
    }

    // MARK: - Row content (normal vs. rename-field)

    @ViewBuilder
    private var rowContent: some View {
        if isRenaming {
            HStack(spacing: 6) {
                Image(systemName: file.isDirectory ? "folder.fill" : file.contentType.systemImageName)
                    .font(.system(size: 11))
                    .foregroundStyle(iconColor)
                    .frame(width: 16, alignment: .center)
                TextField("", text: $inputText)
                    .font(.system(size: 12))
                    .textFieldStyle(.plain)
                    .focused($renameFieldFocused)
                    .onSubmit { commitRename() }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 3)
            .onChange(of: renameFieldFocused) { _, focused in
                if !focused { isRenaming = false }
            }
            .onAppear { renameFieldFocused = true }
        } else {
            FileRowView(
                file: file,
                isSelected: selectedFileID == file.id
            ) {
                onSelect(file)
            }
        }
    }

    // MARK: - Actions

    private func commitRename() {
        let name = inputText.trimmingCharacters(in: .whitespaces)
        isRenaming = false
        guard !name.isEmpty, name != file.name else { return }
        do {
            try appEnv.projectService.renameFile(file, to: name)
        } catch { show(error) }
    }

    private func performCreateFile() {
        let name = inputText.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        do {
            try appEnv.projectService.createFile(name: name, in: file, contentType: .infer(from: name))
        } catch { show(error) }
    }

    private func performCreateFolder() {
        let name = inputText.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        do {
            try appEnv.projectService.createFolder(name: name, in: file)
        } catch { show(error) }
    }

    private func performDelete() {
        do {
            try appEnv.projectService.deleteFile(file)
        } catch { show(error) }
    }

    private func show(_ error: Error) {
        actionError = error.localizedDescription
        showError = true
    }

    private var iconColor: Color {
        if file.isDirectory { return .accentColor }
        switch file.contentType {
        case .swift, .orionSwift: return IDETheme.Colors.swiftOrange
        case .objc, .objcHeader:  return IDETheme.Colors.objcBlue
        case .logosXM:            return IDETheme.Colors.logosXMPurple
        case .makefile:           return IDETheme.Colors.makefileGreen
        default:                  return Color(white: 0.46)
        }
    }
}

// MARK: - File Row View

struct FileRowView: View {

    let file: SPPFile
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: iconName)
                    .font(.system(size: 11))
                    .foregroundStyle(iconColor)
                    .frame(width: 16, alignment: .center)

                Text(file.name)
                    .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? Color(white: 0.94) : Color(white: 0.80))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 1)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(
                    isSelected
                        ? IDETheme.Colors.selectedRowFill
                        : (isHovered ? IDETheme.Colors.hoverFill : Color.clear)
                )
        )
        .onHover { isHovered = $0 }
        .animation(IDETheme.Animation.micro, value: isHovered)
    }

    // MARK: - Icon resolution

    private var iconName: String {
        if file.isDirectory { return "folder.fill" }
        if file.contentType != .unknown { return file.contentType.systemImageName }
        switch (file.name as NSString).pathExtension.lowercased() {
        case "json":              return "curlybraces"
        case "md":                return "doc.plaintext"
        case "txt":               return "doc.plaintext"
        case "sh", "zsh", "bash": return "terminal"
        case "py":                return "chevron.left.forwardslash.chevron.right"
        case "rb":                return "diamond.fill"
        case "js", "ts", "jsx", "tsx": return "chevron.left.forwardslash.chevron.right"
        case "css":               return "paintpalette"
        case "html":              return "globe"
        case "xml":               return "chevron.left.forwardslash.chevron.right"
        case "dylib", "a":        return "link"
        case "png", "jpg", "jpeg", "gif", "svg": return "photo"
        default:                  return "doc"
        }
    }

    private var iconColor: Color {
        if file.isDirectory { return .accentColor }
        switch file.contentType {
        case .swift, .orionSwift: return IDETheme.Colors.swiftOrange
        case .objc, .objcHeader:  return IDETheme.Colors.objcBlue
        case .logosXM:            return IDETheme.Colors.logosXMPurple
        case .makefile:           return IDETheme.Colors.makefileGreen
        case .control:            return Color(red: 0.60, green: 0.70, blue: 0.90)
        case .plist:              return Color(red: 0.70, green: 0.70, blue: 0.70)
        case .resource:           return Color(red: 0.70, green: 0.55, blue: 0.85)
        case .sppui:              return Color(red: 0.40, green: 0.80, blue: 0.70)
        default:
            // Extension-based tinting for unknown types
            switch (file.name as NSString).pathExtension.lowercased() {
            case "json":              return Color(red: 0.90, green: 0.75, blue: 0.35)
            case "md", "txt":         return Color(white: 0.58)
            case "sh", "zsh", "bash": return Color(red: 0.45, green: 0.85, blue: 0.55)
            case "py":                return Color(red: 0.40, green: 0.65, blue: 0.90)
            case "rb":                return Color(red: 0.85, green: 0.30, blue: 0.30)
            case "js", "ts":          return Color(red: 0.95, green: 0.80, blue: 0.25)
            case "css":               return Color(red: 0.45, green: 0.75, blue: 0.95)
            case "html":              return Color(red: 0.90, green: 0.45, blue: 0.25)
            default:                  return Color(white: 0.42)
            }
        }
    }
}

// MARK: - Preview

struct ProjectFileNavigatorView_Previews: PreviewProvider {
    static var previews: some View {
        ProjectFileNavigatorView()
            .environmentObject(previewEnv)
            .frame(width: 240, height: 400)
    }

    private static var previewEnv: AppEnvironment = {
        let e = AppEnvironment()
        e.projectService.currentProject = SPPProject(
            name: "MyTweak",
            bundleID: "com.example.mytweak",
            files: [
                SPPFile(
                    name: "Sources",
                    relativePath: "Sources",
                    isDirectory: true,
                    children: [
                        SPPFile(name: "Tweak.xm",   relativePath: "Sources/Tweak.xm",    contentType: .logosXM),
                        SPPFile(name: "Tweak.swift", relativePath: "Sources/Tweak.swift", contentType: .swift)
                    ]
                ),
                SPPFile(name: "Makefile", relativePath: "Makefile", contentType: .makefile),
                SPPFile(name: "control",  relativePath: "control",  contentType: .control)
            ]
        )
        return e
    }()
}
