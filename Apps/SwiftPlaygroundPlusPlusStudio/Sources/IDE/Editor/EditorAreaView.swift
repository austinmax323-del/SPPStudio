import SwiftUI
import AppKit
import SPPCore

// MARK: - Editor Tab Model

struct EditorTab: Identifiable {
    let id        = UUID()
    let fileID    : UUID
    let fileName  : String
    let contentType: SPPFile.FileContentType
    var contents  : String
    var saved     : String
    var selectedRange = NSRange(location: 0, length: 0)
    var scrollOffset  = NSPoint.zero

    var isDirty: Bool { contents != saved }
}

// MARK: - Editor Area View

struct EditorAreaView: View {

    @EnvironmentObject var appEnv: AppEnvironment

    @State private var tabs: [EditorTab] = []
    @State private var activeTabID: UUID? = nil
    @State private var loadError: String? = nil

    private var activeTab: EditorTab? {
        guard let id = activeTabID else { return nil }
        return tabs.first { $0.id == id }
    }

    private var projectFileSignature: String {
        guard let project = appEnv.currentProject else { return "" }
        return project.files
            .flatMap { $0.allFiles() }
            .filter { !$0.isDirectory }
            .map { $0.id.uuidString }
            .sorted()
            .joined(separator: "|")
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            panelDivider
            editorBody
        }
        .background(IDETheme.Colors.editorBackground)
        .onReceive(appEnv.eventBus.publisher(for: FileSelectedEvent.self)) { event in
            openOrFocusTab(fileID: event.fileID)
        }
        .onAppear {
            openFirstProjectFileIfNeeded()
        }
        .onChange(of: appEnv.currentProject?.id) { _, _ in
            resetEditorTabs()
            openFirstProjectFileIfNeeded()
        }
        .onChange(of: projectFileSignature) { _, _ in
            pruneInvalidTabs()
            openFirstProjectFileIfNeeded()
        }
        .background {
            ZStack {
                Button("") { saveActiveTab() }
                    .keyboardShortcut("s", modifiers: .command)
                Button("") { closeActiveTab() }
                    .keyboardShortcut("w", modifiers: .command)
                Button("") { navigateTabs(direction: -1) }
                    .keyboardShortcut("[", modifiers: [.command, .shift])
                Button("") { navigateTabs(direction: 1) }
                    .keyboardShortcut("]", modifiers: [.command, .shift])
                Button("") { triggerFind() }
                    .keyboardShortcut("f", modifiers: .command)
                Button("") { triggerFind(showReplace: true) }
                    .keyboardShortcut("f", modifiers: [.command, .option])
            }
            .frame(width: 0, height: 0)
            .opacity(0)
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                if tabs.isEmpty {
                    emptyTabSlot
                } else {
                    ForEach(tabs) { tab in
                        tabButton(for: tab)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: IDETheme.Layout.editorTabHeight)
        .background(IDETheme.Colors.headerBackground)
    }

    private var emptyTabSlot: some View {
        HStack(spacing: 5) {
            Image(systemName: "doc.text")
                .font(.system(size: 11, weight: .light))
                .foregroundStyle(Color(white: 0.28))
            Text("No file selected")
                .font(.system(size: 11))
                .foregroundStyle(Color(white: 0.30))
        }
        .padding(.horizontal, 14)
    }

    private func tabButton(for tab: EditorTab) -> some View {
        let isActive = activeTabID == tab.id
        return TabButtonView(
            tab: tab,
            isActive: isActive,
            iconColor: tabIconColor(for: tab.contentType),
            onSelect: { activeTabID = tab.id },
            onClose: { closeTab(tab) }
        )
    }

    // MARK: - Tab Icon Color

    private func tabIconColor(for ct: SPPFile.FileContentType) -> Color {
        switch ct {
        case .swift, .orionSwift: return IDETheme.Colors.swiftOrange
        case .objc, .objcHeader:  return IDETheme.Colors.objcBlue
        case .logosXM:            return IDETheme.Colors.logosXMPurple
        case .makefile:           return IDETheme.Colors.makefileGreen
        default:                  return Color(white: 0.50)
        }
    }

    // MARK: - Editor Body

    @ViewBuilder
    private var editorBody: some View {
        if let tab = activeTab {
            VStack(spacing: 0) {
                editorHeader(for: tab)
                panelDivider
                editorPool
            }
        } else {
            noSelectionView
        }
    }

    // All open tab editors coexist in a ZStack; only the active tab's NSScrollView
    // is visible. This preserves each tab's NSTextView instance — and therefore its
    // undo stack, caret, and scroll position — across tab switches.
    private var editorPool: some View {
        ZStack {
            ForEach(tabs) { tab in
                CodeEditorView(
                    text: Binding(
                        get: { tabs.first(where: { $0.id == tab.id })?.contents ?? "" },
                        set: { if let i = tabs.firstIndex(where: { $0.id == tab.id }) { tabs[i].contents = $0 } }
                    ),
                    contentType: tab.contentType,
                    tabID: tab.id,
                    fileID: tab.fileID,
                    isActive: tab.id == activeTabID,
                    selection: Binding(
                        get: { tabs.first(where: { $0.id == tab.id })?.selectedRange ?? NSRange(location: 0, length: 0) },
                        set: { if let i = tabs.firstIndex(where: { $0.id == tab.id }) { tabs[i].selectedRange = $0 } }
                    ),
                    scrollOffset: Binding(
                        get: { tabs.first(where: { $0.id == tab.id })?.scrollOffset ?? .zero },
                        set: { if let i = tabs.firstIndex(where: { $0.id == tab.id }) { tabs[i].scrollOffset = $0 } }
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func editorHeader(for tab: EditorTab) -> some View {
        HStack(spacing: 8) {
            Image(systemName: tab.contentType.systemImageName)
                .font(.system(size: 11))
                .foregroundStyle(tabIconColor(for: tab.contentType))

            if let project = appEnv.currentProject,
               let file = project.file(with: tab.fileID) {
                Text(file.relativePath)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color(white: 0.40))
            }

            Spacer()

            if tab.isDirty {
                Text("Unsaved")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.accentColor.opacity(0.8))
            }

            Button(action: saveActiveTab) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 11))
                    .foregroundStyle(tab.isDirty ? Color.accentColor : Color(white: 0.26))
            }
            .buttonStyle(.plain)
            .disabled(!tab.isDirty)
            .help("Save  ⌘S")

            Rectangle()
                .fill(IDETheme.Colors.rowDivider)
                .frame(width: IDETheme.Layout.separatorWeight, height: 14)

            Button(action: { triggerFind() }) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10.5))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color(white: 0.44))
            .help("Find  ⌘F")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(IDETheme.Colors.headerBackground.opacity(0.6))
    }

    // MARK: - No Selection / Landing

    @ViewBuilder
    private var noSelectionView: some View {
        if let project = appEnv.currentProject {
            projectStartScreen(for: project)
        } else {
            EditorLandingView()
        }
    }

    private func projectStartScreen(for project: SPPProject) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                projectIdentityHeader(for: project)
                quickActionsSection
                let leafFiles = project.files.flatMap { $0.allFiles() }.filter { !$0.isDirectory }
                if !leafFiles.isEmpty {
                    projectFilesSection(files: leafFiles)
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func projectIdentityHeader(for project: SPPProject) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.orange.opacity(0.16))
                    .frame(width: 44, height: 44)
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.orange.opacity(0.90))
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(project.name)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color(white: 0.92))
                HStack(spacing: 6) {
                    Text(project.bundleID)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Color(white: 0.38))
                    Text("·")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(white: 0.26))
                    Text("v\(project.version.description)")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Color(white: 0.30))
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: IDETheme.Layout.cardRadius, style: .continuous)
                .fill(IDETheme.Colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: IDETheme.Layout.cardRadius, style: .continuous)
                        .strokeBorder(IDETheme.Colors.panelBorder, lineWidth: IDETheme.Layout.separatorWeight)
                )
        )
    }

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("QUICK ACTIONS")
                .ideSectionHeader()
            HStack(spacing: 8) {
                EditorStartButton(icon: "hammer",         label: "Build",    color: .orange) {
                    appEnv.buildCurrentProject()
                }
                EditorStartButton(icon: "play.fill",      label: "Run",      color: .green) {
                    appEnv.revealLastPackage()
                }
                EditorStartButton(icon: "doc.badge.plus", label: "New File", color: .blue)
            }
        }
    }

    private func projectFilesSection(files: [SPPFile]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("PROJECT FILES")
                .ideSectionHeader()
            VStack(spacing: 0) {
                ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                    EditorStartFileRow(
                        file: file,
                        showDivider: index < files.count - 1
                    ) {
                        appEnv.eventBus.publish(FileSelectedEvent(fileID: file.id))
                    }
                }
            }
            .ideCard()
        }
    }

    // MARK: - Find & Replace

    private func triggerFind(showReplace: Bool = false) {
        guard let window = NSApp.keyWindow else { return }
        // Ensure the visible CodeTextView has focus before sending the find action.
        if let tv = visibleCodeTextView(in: window.contentView) {
            window.makeFirstResponder(tv)
        }
        let item = NSMenuItem()
        item.tag = showReplace
            ? NSTextFinder.Action.showReplaceInterface.rawValue
            : NSTextFinder.Action.showFindInterface.rawValue
        NSApp.sendAction(#selector(NSTextView.performFindPanelAction(_:)), to: nil, from: item)
    }

    private func visibleCodeTextView(in view: NSView?) -> CodeTextView? {
        guard let view, !view.isHidden else { return nil }
        if let tv = view as? CodeTextView { return tv }
        return view.subviews.lazy.compactMap { visibleCodeTextView(in: $0) }.first
    }

    // MARK: - Tab Management

    private func openOrFocusTab(fileID: UUID) {
        pruneInvalidTabs()

        // Already open → just focus
        if let existing = tabs.first(where: { $0.fileID == fileID }) {
            activeTabID = existing.id
            return
        }
        // Load and open
        guard let file = appEnv.currentProject?.file(with: fileID),
              !file.isDirectory else { return }

        let contents: String
        do {
            contents = try appEnv.projectService.loadFileContents(file)
        } catch {
            loadError = error.localizedDescription
            return
        }

        let tab = EditorTab(
            fileID:      file.id,
            fileName:    file.name,
            contentType: file.contentType,
            contents:    contents,
            saved:       contents
        )
        tabs.append(tab)
        activeTabID = tab.id
    }

    private func openFirstProjectFileIfNeeded() {
        guard activeTabID == nil,
              let project = appEnv.currentProject,
              let firstFile = project.files
                .flatMap({ $0.allFiles() })
                .first(where: { !$0.isDirectory })
        else { return }

        openOrFocusTab(fileID: firstFile.id)
    }

    private func closeTab(_ tab: EditorTab) {
        guard let idx = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        tabs.remove(at: idx)
        if activeTabID == tab.id {
            activeTabID = tabs.isEmpty ? nil : tabs[min(idx, tabs.count - 1)].id
        }
    }

    private func saveActiveTab() {
        guard let tabID = activeTabID,
              let tabIdx = tabs.firstIndex(where: { $0.id == tabID }),
              tabs[tabIdx].isDirty else { return }

        let tab = tabs[tabIdx]
        guard let file = appEnv.currentProject?.file(with: tab.fileID) else { return }
        do {
            try appEnv.projectService.saveFileContents(tab.contents, to: file)
            tabs[tabIdx].saved = tab.contents
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func closeActiveTab() {
        guard let id = activeTabID,
              let tab = tabs.first(where: { $0.id == id }) else { return }
        closeTab(tab)
    }

    private func navigateTabs(direction: Int) {
        guard tabs.count > 1,
              let id = activeTabID,
              let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        activeTabID = tabs[(idx + direction + tabs.count) % tabs.count].id
    }

    private func resetEditorTabs() {
        tabs.removeAll()
        activeTabID = nil
        loadError = nil
    }

    private func pruneInvalidTabs() {
        guard let project = appEnv.currentProject else {
            resetEditorTabs()
            return
        }

        let validFileIDs = Set(project.files
            .flatMap { $0.allFiles() }
            .filter { !$0.isDirectory }
            .map(\.id))
        let previousActiveID = activeTabID

        tabs.removeAll { !validFileIDs.contains($0.fileID) }

        if let previousActiveID,
           tabs.contains(where: { $0.id == previousActiveID }) {
            activeTabID = previousActiveID
        } else {
            activeTabID = tabs.first?.id
        }
    }

    // MARK: - Helpers

    private var panelDivider: some View {
        Rectangle()
            .fill(IDETheme.Colors.panelSeparator)
            .frame(height: IDETheme.Layout.separatorWeight)
    }
}

// MARK: - Tab Button View

private struct TabButtonView: View {
    let tab: EditorTab
    let isActive: Bool
    let iconColor: Color
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovered = false
    @State private var closeHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 5) {
                Image(systemName: tab.contentType.systemImageName)
                    .font(.system(size: 10))
                    .foregroundStyle(iconColor)

                Text(tab.fileName)
                    .font(.system(size: 11.5, weight: isActive ? .medium : .regular))
                    .foregroundStyle(isActive ? Color(white: 0.92) : Color(white: 0.52))
                    .lineLimit(1)

                closeOrDot
            }
            .padding(.horizontal, 12)
            .frame(height: IDETheme.Layout.editorTabHeight)
            .background(
                ZStack(alignment: .bottom) {
                    isActive
                        ? IDETheme.Colors.editorBackground.opacity(0.7)
                        : (isHovered ? Color(white: 1.0, opacity: 0.05) : Color.black.opacity(0.10))
                    if isActive {
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.85))
                            .frame(height: 1.5)
                    }
                }
            )
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(IDETheme.Colors.panelSeparator)
                    .frame(width: IDETheme.Layout.separatorWeight)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(IDETheme.Animation.micro, value: isHovered)
    }

    @ViewBuilder
    private var closeOrDot: some View {
        ZStack {
            // Dirty dot — visible only when not hovered
            if tab.isDirty {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 5, height: 5)
                    .opacity((isHovered || isActive) ? 0 : 1)
            }

            // Close button — visible on hover or when tab is active
            if isHovered || isActive || tab.isDirty {
                Button(action: onClose) {
                    ZStack {
                        Circle()
                            .fill(closeHovered ? Color(white: 1.0, opacity: 0.18) : Color.clear)
                            .frame(width: 14, height: 14)
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(
                                closeHovered
                                    ? Color(white: 0.90)
                                    : Color(white: isActive ? 0.48 : 0.32)
                            )
                    }
                }
                .buttonStyle(.plain)
                .frame(width: 14, height: 14)
                .onHover { closeHovered = $0 }
                .animation(IDETheme.Animation.micro, value: closeHovered)
                .opacity(tab.isDirty && !isHovered && !isActive ? 0 : 1)
            }
        }
        .frame(width: 14, height: 14)
    }
}

// MARK: - Code Text View (NSTextView subclass for current-line + bracket highlights)

final class CodeTextView: NSTextView {
    var bracketMatchRanges: (NSRange, NSRange)? {
        didSet { needsDisplay = true }
    }
    weak var renderOverlay: CodeTextRenderOverlayView?
    private(set) var drawCount = 0
    private(set) var lastDirtyRect = NSRect.zero

    override var isOpaque: Bool { true }

    override var wantsLayer: Bool {
        get { false }
        set { }
    }

    override var wantsUpdateLayer: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        needsDisplay = true
        layer?.needsDisplay()
    }

    override func draw(_ dirtyRect: NSRect) {
        drawCount += 1
        lastDirtyRect = dirtyRect
        backgroundColor.setFill()
        dirtyRect.fill()

        guard let layoutManager, let textContainer else { return }
        layoutManager.ensureLayout(for: textContainer)

        let origin = textContainerOrigin
        let containerDirtyRect = dirtyRect.offsetBy(dx: -origin.x, dy: -origin.y)
        let glyphRange = layoutManager.glyphRange(forBoundingRect: containerDirtyRect, in: textContainer)
        guard glyphRange.location != NSNotFound, glyphRange.length > 0 else { return }

        layoutManager.drawBackground(forGlyphRange: glyphRange, at: origin)
        layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: origin)
    }
}

final class CodeTextRenderOverlayView: NSView {
    weak var textView: CodeTextView?
    weak var scrollView: NSScrollView?

    init(textView: CodeTextView, scrollView: NSScrollView) {
        self.textView = textView
        self.scrollView = scrollView
        super.init(frame: .zero)
        wantsLayer = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }

    override var wantsLayer: Bool {
        get { false }
        set { }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard
            let textView,
            let scrollView,
            let storage = textView.textStorage,
            let layoutManager = textView.layoutManager,
            let textContainer = textView.textContainer
        else { return }

        layoutManager.ensureLayout(for: textContainer)
        let origin = textView.textContainerOrigin
        let clipOrigin = scrollView.contentView.bounds.origin
        let containerDirtyRect = dirtyRect
            .offsetBy(dx: clipOrigin.x - origin.x, dy: clipOrigin.y - origin.y)
        let glyphRange = layoutManager.glyphRange(forBoundingRect: containerDirtyRect, in: textContainer)
        guard glyphRange.location != NSNotFound, glyphRange.length > 0 else { return }

        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { lineRect, usedRect, _, lineGlyphRange, _ in
            var charRange = layoutManager.characterRange(forGlyphRange: lineGlyphRange, actualGlyphRange: nil)
            guard charRange.length > 0, NSMaxRange(charRange) <= storage.length else { return }

            let source = storage.string as NSString
            while charRange.length > 0 {
                let lastIndex = charRange.location + charRange.length - 1
                let last = source.character(at: lastIndex)
                if last == 10 || last == 13 {
                    charRange.length -= 1
                } else {
                    break
                }
            }
            guard charRange.length > 0 else { return }

            let renderedLine = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: charRange))
            renderedLine.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: renderedLine.length))
            renderedLine.draw(at: NSPoint(
                x: origin.x + usedRect.minX - clipOrigin.x,
                y: origin.y + lineRect.minY - clipOrigin.y
            ))
        }
    }
}

final class CodeClipView: NSClipView {
    override var wantsLayer: Bool {
        get { false }
        set { }
    }
}

final class CodeScrollView: NSScrollView {
    override var wantsLayer: Bool {
        get { false }
        set { }
    }
}

final class CodeEditorContainerView: NSView {
    let scrollView: CodeScrollView
    let renderOverlay: CodeTextRenderOverlayView

    init(scrollView: CodeScrollView, renderOverlay: CodeTextRenderOverlayView) {
        self.scrollView = scrollView
        self.renderOverlay = renderOverlay
        super.init(frame: .zero)
        wantsLayer = false
        addSubview(scrollView)
        addSubview(renderOverlay, positioned: .above, relativeTo: scrollView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var wantsLayer: Bool {
        get { false }
        set { }
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        renderOverlay.frame = bounds
        scrollView.tile()
        renderOverlay.needsDisplay = true
    }
}

// MARK: - Code Editor (NSTextView + ruler + syntax highlighting)

struct CodeEditorView: NSViewRepresentable {

    @Binding var text: String
    let contentType: SPPFile.FileContentType
    let tabID: UUID
    let fileID: UUID
    let isActive: Bool
    @Binding var selection: NSRange
    @Binding var scrollOffset: NSPoint

    func makeNSView(context: Context) -> CodeEditorContainerView {
        let tv = CodeTextView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600)
        )
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.heightTracksTextView = false
        tv.textContainer?.lineFragmentPadding = 4
        tv.textContainer?.containerSize = NSSize(width: 800, height: CGFloat.greatestFiniteMagnitude)

        // Delegate
        tv.delegate = context.coordinator

        // Editing behaviour
        tv.isEditable                              = true
        tv.isSelectable                            = true
        tv.isRichText                              = true
        tv.importsGraphics                         = false
        tv.allowsDocumentBackgroundColorChange     = false
        tv.allowsUndo                              = true
        tv.usesFindBar                             = true
        tv.isAutomaticQuoteSubstitutionEnabled     = false
        tv.isAutomaticDashSubstitutionEnabled      = false
        tv.isAutomaticTextReplacementEnabled       = false
        tv.isAutomaticSpellingCorrectionEnabled    = false
        tv.isContinuousSpellCheckingEnabled        = false
        tv.isGrammarCheckingEnabled                = false

        // Appearance
        tv.font               = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
        tv.textColor          = NSColor(white: 0.82, alpha: 1)
        tv.typingAttributes   = Self.editorTypingAttributes()
        tv.insertionPointColor = NSColor(red: 1.0, green: 0.96, blue: 0.88, alpha: 1)
        tv.backgroundColor    = NSColor(red: 0.102, green: 0.102, blue: 0.152, alpha: 1)
        tv.drawsBackground    = true
        tv.textContainerInset = NSSize(width: 8, height: 10)
        tv.selectedTextAttributes = [
            .backgroundColor: NSColor(red: 0.22, green: 0.47, blue: 0.86, alpha: 0.68),
            .foregroundColor: NSColor(white: 0.97, alpha: 1)
        ]

        // Keep the text container tied to the visible editor width. The text view
        // stays vertically resizable; adding .height here fights the layout manager
        // and can leave glyphs laid out but not redrawn.
        tv.isHorizontallyResizable = false
        tv.isVerticallyResizable   = true
        tv.minSize                 = .zero
        tv.maxSize                 = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.autoresizingMask        = [.width]

        // Tab width: 4 spaces
        let tabFont  = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
        let spaceW   = (" " as NSString).size(withAttributes: [.font: tabFont]).width
        let tabStyle = NSMutableParagraphStyle()
        tabStyle.defaultTabInterval = spaceW * 4
        tabStyle.tabStops           = []
        tv.defaultParagraphStyle    = tabStyle
        tv.typingAttributes[.paragraphStyle] = tabStyle

        // Plain scroll view. SwiftUI owns the outer frame; this subtree renders
        // through AppKit's normal draw pipeline.
        let scrollView = CodeScrollView()
        scrollView.contentView = CodeClipView()
        scrollView.documentView               = tv
        let renderOverlay = CodeTextRenderOverlayView(textView: tv, scrollView: scrollView)
        tv.renderOverlay = renderOverlay
        scrollView.hasVerticalScroller        = true
        scrollView.hasHorizontalScroller      = false
        scrollView.autohidesScrollers         = true
        scrollView.scrollerStyle              = .overlay
        scrollView.verticalScrollElasticity   = .allowed
        scrollView.horizontalScrollElasticity = .allowed
        scrollView.backgroundColor            = NSColor(red: 0.102, green: 0.102, blue: 0.152, alpha: 1)
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.scrollViewDidScroll(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        // Line-number gutter
        let ruler = LineNumberRulerView(scrollView: scrollView, orientation: .verticalRuler)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler  = true
        scrollView.rulersVisible     = true
        context.coordinator.ruler    = ruler
        context.coordinator.lastRenderedText = tv.string
        RuntimeInvariantInspector.register(
            tabID: tabID,
            fileID: fileID,
            contentType: contentType,
            textView: tv,
            scrollView: scrollView
        )

        return CodeEditorContainerView(scrollView: scrollView, renderOverlay: renderOverlay)
    }

    func updateNSView(_ container: CodeEditorContainerView, context: Context) {
        context.coordinator.parent = self
        let scrollView = container.scrollView
        container.isHidden = !isActive
        scrollView.isHidden = !isActive
        container.needsLayout = true
        guard isActive, let tv = scrollView.documentView as? CodeTextView else { return }
        if Self.syncTextLayout(tv, in: scrollView) {
            DispatchQueue.main.async { [weak tv] in tv?.display() }
        }
        RuntimeInvariantInspector.updateActive(tabID: tabID, fileID: fileID, selection: tv.selectedRange())

        if context.coordinator.lastRenderedText != text {
            context.coordinator.isApplyingExternalUpdate = true
            if let storage = tv.textStorage {
                storage.setAttributedString(NSAttributedString(
                    string: text,
                    attributes: Self.editorTypingAttributes()
                ))
                SyntaxHighlighter.apply(to: storage, contentType: contentType)
            }
            tv.textColor = NSColor(white: 0.82, alpha: 1)
            tv.typingAttributes = Self.editorTypingAttributes()
            tv.setSelectedRange(clamped(selection, in: text))
            Self.syncTextLayout(tv, in: scrollView, forceDisplay: true)
            tv.undoManager?.removeAllActions()
            context.coordinator.lastRenderedText = text
            context.coordinator.isApplyingExternalUpdate = false
            context.coordinator.updateEditorChrome(tv)
            context.coordinator.ruler?.needsDisplay = true
            tv.needsDisplay = true
            // Defer a second layout+display pass to after SwiftUI's layout phase.
            // On first open the scroll view frame may still be zero; the async
            // dispatch ensures the text container has its final width before we
            // force the glyph layout and redraw.
            DispatchQueue.main.async { [weak scrollView, weak tv] in
                guard let scrollView, let tv else { return }
                Self.syncTextLayout(tv, in: scrollView, forceDisplay: true)
                tv.display()
            }
        }

        if tv.selectedRange() != selection {
            tv.setSelectedRange(clamped(selection, in: tv.string))
        }

        if scrollView.contentView.bounds.origin != scrollOffset {
            DispatchQueue.main.async {
                context.coordinator.isRestoringScroll = true
                scrollView.contentView.scroll(to: scrollOffset)
                scrollView.reflectScrolledClipView(scrollView.contentView)
                context.coordinator.isRestoringScroll = false
            }
        }
    }

    @discardableResult
    private static func syncTextLayout(_ tv: CodeTextView, in scrollView: NSScrollView, forceDisplay: Bool = false) -> Bool {
        let clipWidth = scrollView.contentView.bounds.width
        guard clipWidth.isFinite, clipWidth > 0 else { return false }

        var didChangeLayout = false
        let textViewWidth = max(1, clipWidth)
        if abs(tv.frame.width - textViewWidth) > 0.5 {
            tv.setFrameSize(NSSize(
                width: textViewWidth,
                height: max(tv.frame.height, scrollView.contentView.bounds.height)
            ))
            didChangeLayout = true
        }

        if let container = tv.textContainer {
            container.widthTracksTextView = true
            container.heightTracksTextView = false
            if container.containerSize.height != CGFloat.greatestFiniteMagnitude {
                container.containerSize = NSSize(
                    width: container.containerSize.width,
                    height: CGFloat.greatestFiniteMagnitude
                )
                didChangeLayout = true
            }
        }

        guard didChangeLayout || forceDisplay else { return false }

        let fullRange = NSRange(location: 0, length: (tv.string as NSString).length)
        tv.layoutManager?.invalidateLayout(forCharacterRange: fullRange, actualCharacterRange: nil)
        tv.layoutManager?.invalidateDisplay(forCharacterRange: fullRange)
        if let textContainer = tv.textContainer {
            tv.layoutManager?.ensureLayout(for: textContainer)
        }
        tv.needsDisplay = true
        tv.renderOverlay?.frame = tv.frame
        tv.renderOverlay?.needsDisplay = true
        return true
    }

    private func clamped(_ range: NSRange, in source: String) -> NSRange {
        let length = (source as NSString).length
        let location = min(max(0, range.location), length)
        let maxLength = max(0, length - location)
        return NSRange(location: location, length: min(max(0, range.length), maxLength))
    }

    private static func editorTypingAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular),
            .foregroundColor: NSColor(white: 0.82, alpha: 1),
            .paragraphStyle: editorParagraphStyle()
        ]
    }

    private static func editorParagraphStyle() -> NSParagraphStyle {
        let font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
        let spaceW = (" " as NSString).size(withAttributes: [.font: font]).width
        let style = NSMutableParagraphStyle()
        style.defaultTabInterval = spaceW * 4
        style.tabStops = []
        return style
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    static func dismantleNSView(_ nsView: CodeEditorContainerView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
        RuntimeInvariantInspector.unregister(tabID: coordinator.parent.tabID)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditorView
        weak var ruler: LineNumberRulerView?
        var symbolHighlightedRanges: [NSRange] = []
        var lastRenderedText = ""
        var isApplyingExternalUpdate = false
        var isRestoringScroll = false

        init(_ parent: CodeEditorView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            lastRenderedText = tv.string
            let selectedRange = tv.selectedRange()
            if let storage = tv.textStorage {
                SyntaxHighlighter.apply(to: storage, contentType: parent.contentType)
                tv.setSelectedRange(selectedRange)
            }
            (tv as? CodeTextView)?.renderOverlay?.needsDisplay = true
            parent.selection = tv.selectedRange()
            RuntimeInvariantInspector.recordSelection(tabID: parent.tabID, fileID: parent.fileID, selection: parent.selection)
            updateEditorChrome(tv)
            ruler?.needsDisplay = true
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.selection = tv.selectedRange()
            RuntimeInvariantInspector.recordSelection(tabID: parent.tabID, fileID: parent.fileID, selection: parent.selection)
            updateEditorChrome(tv)
            (tv as? CodeTextView)?.renderOverlay?.needsDisplay = true
        }

        @objc func scrollViewDidScroll(_ notification: Notification) {
            guard !isRestoringScroll else { return }
            guard let clipView = notification.object as? NSClipView else { return }
            parent.scrollOffset = clipView.bounds.origin
            (clipView.documentView as? CodeTextView)?.renderOverlay?.needsDisplay = true
            ruler?.needsDisplay = true
        }

        func updateEditorChrome(_ tv: NSTextView) {
            tv.needsDisplay = true
            updateRulerLine(tv)
            updateBracketMatch(tv)
            updateSymbolHighlight(tv)
        }

        private func updateRulerLine(_ tv: NSTextView) {
            let loc = min(tv.selectedRange().location, tv.string.utf16.count)
            let line = (tv.string as NSString).substring(to: loc)
                .components(separatedBy: "\n").count
            ruler?.setCurrentLine(line)
        }

        // MARK: Bracket matching

        private func updateBracketMatch(_ tv: NSTextView) {
            guard let ctv = tv as? CodeTextView else { return }
            let src = tv.string as NSString
            let len = src.length
            let loc = tv.selectedRange().location
            guard len > 0 else { ctv.bracketMatchRanges = nil; return }

            var candidates = [loc]
            if loc > 0 { candidates.append(loc - 1) }

            var startPos: Int? = nil
            var isOpen = false
            for cp in candidates where cp < len {
                let ch = src.character(at: cp)
                if isOpenBracket(ch)  { startPos = cp; isOpen = true;  break }
                if isCloseBracket(ch) { startPos = cp; isOpen = false; break }
            }

            guard let sp = startPos else { ctv.bracketMatchRanges = nil; return }
            let startCh = src.character(at: sp)
            guard let closeCh = pairedBracket(for: startCh) else { ctv.bracketMatchRanges = nil; return }

            if let mp = scanBracket(src, from: sp, open: startCh, close: closeCh, forward: isOpen) {
                ctv.bracketMatchRanges = (NSRange(location: sp, length: 1), NSRange(location: mp, length: 1))
            } else {
                ctv.bracketMatchRanges = nil
            }
        }

        private func isOpenBracket(_ c: unichar)  -> Bool { c == 40 || c == 123 || c == 91 }
        private func isCloseBracket(_ c: unichar) -> Bool { c == 41 || c == 125 || c == 93 }

        private func pairedBracket(for c: unichar) -> unichar? {
            switch c {
            case 40: return 41; case 41: return 40
            case 123: return 125; case 125: return 123
            case 91: return 93;  case 93: return 91
            default: return nil
            }
        }

        private func scanBracket(_ src: NSString, from pos: Int, open: unichar, close: unichar, forward: Bool) -> Int? {
            var depth = 1
            var i = forward ? pos + 1 : pos - 1
            while forward ? i < src.length : i >= 0 {
                let c = src.character(at: i)
                if c == open  { depth += 1 }
                else if c == close { depth -= 1; if depth == 0 { return i } }
                i += forward ? 1 : -1
            }
            return nil
        }

        // MARK: Symbol highlight

        private func updateSymbolHighlight(_ tv: NSTextView) {
            guard let lm = tv.layoutManager else { return }
            let srcLen = tv.string.utf16.count

            for r in symbolHighlightedRanges where r.location + r.length <= srcLen {
                lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: r)
            }
            symbolHighlightedRanges = []

            let sel = tv.selectedRange()
            guard sel.length >= 2, sel.length <= 80,
                  sel.location + sel.length <= (tv.string as NSString).length else { return }

            let selected = (tv.string as NSString).substring(with: sel)
            guard !selected.isEmpty,
                  selected.unicodeScalars.allSatisfy({ v in
                      let n = v.value
                      return (n >= 65 && n <= 90) || (n >= 97 && n <= 122) ||
                             (n >= 48 && n <= 57) || n == 95
                  }) else { return }

            let escaped = NSRegularExpression.escapedPattern(for: selected)
            guard let regex = try? NSRegularExpression(pattern: "\\b\(escaped)\\b") else { return }

            let fullRange = NSRange(location: 0, length: (tv.string as NSString).length)
            let color = NSColor(red: 0.42, green: 0.68, blue: 1.0, alpha: 0.18)
            regex.enumerateMatches(in: tv.string, range: fullRange) { match, _, _ in
                guard let r = match?.range, r != sel else { return }
                lm.addTemporaryAttribute(.backgroundColor, value: color, forCharacterRange: r)
                symbolHighlightedRanges.append(r)
            }
        }
    }
}

// MARK: - Safe subscript

private extension Array {
    subscript(safe idx: Int) -> Element? {
        indices.contains(idx) ? self[idx] : nil
    }
}

// MARK: - Editor Landing View (no project)

private struct EditorLandingView: View {

    @EnvironmentObject var appEnv: AppEnvironment
    @State private var openError: String?
    @State private var showOpenError = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                landingBranding
                landingQuickActions
                if !appEnv.projectService.recentProjectURLs.isEmpty {
                    landingRecentProjects
                }
            }
            .padding(36)
            .frame(maxWidth: 400, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert("Could Not Open Project", isPresented: $showOpenError, presenting: openError) { _ in
            Button("OK", role: .cancel) {}
        } message: { msg in Text(msg) }
    }

    private var landingBranding: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.orange.opacity(0.14))
                    .frame(width: 48, height: 48)
                Image(systemName: "swift")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.orange.opacity(0.92))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Swift Playground++")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color(white: 0.92))
                Text("Jailbreak Tweak IDE")
                    .font(IDETheme.Typography.body)
                    .foregroundStyle(Color(white: 0.36))
            }
        }
    }

    private var landingQuickActions: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("GET STARTED")
                .ideSectionHeader()
            VStack(spacing: 6) {
                LandingActionButton(icon: "plus.square.fill", title: "New Project", subtitle: "Scaffold a tweak from a NIC template", color: .accentColor) {
                    NotificationCenter.default.post(name: .sppNewProjectRequested, object: nil)
                }
                LandingActionButton(icon: "folder", title: "Open Project\u{2026}", subtitle: "Open an existing .sppproject bundle", color: Color(white: 0.50)) {
                    openProjectPanel()
                }
            }
        }
    }

    private var landingRecentProjects: some View {
        let urls = Array(appEnv.projectService.recentProjectURLs.prefix(6))
        return VStack(alignment: .leading, spacing: 9) {
            Text("RECENT")
                .ideSectionHeader()
            VStack(spacing: 0) {
                ForEach(Array(urls.enumerated()), id: \.element.absoluteString) { index, url in
                    LandingRecentRow(url: url, showDivider: index < urls.count - 1) {
                        openProject(at: url)
                    }
                }
            }
            .ideCard()
        }
    }

    private func openProjectPanel() {
        let panel = NSOpenPanel()
        panel.title             = "Open Project"
        panel.message           = "Choose a Swift Playground++ Studio project"
        panel.allowedContentTypes = []
        panel.allowsOtherFileTypes = false
        panel.canChooseFiles    = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openProject(at: url)
    }

    private func openProject(at url: URL) {
        Task { @MainActor in
            do { try await appEnv.projectService.openProject(at: url) } catch {
                openError = error.localizedDescription
                showOpenError = true
            }
        }
    }
}

// MARK: - Landing Action Button

private struct LandingActionButton: View {
    let icon: String; let title: String; var subtitle: String = ""
    let color: Color; let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(color)
                    .frame(width: 18, alignment: .center)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(white: 0.86))
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(IDETheme.Typography.caption)
                            .foregroundStyle(Color(white: 0.36))
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color(white: 0.26))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: IDETheme.Layout.cardRadius, style: .continuous)
                    .fill(isHovered ? IDETheme.Colors.hoverFillStrong : IDETheme.Colors.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: IDETheme.Layout.cardRadius, style: .continuous)
                    .strokeBorder(IDETheme.Colors.panelBorder, lineWidth: IDETheme.Layout.separatorWeight)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(IDETheme.Animation.snap, value: isHovered)
    }
}

// MARK: - Landing Recent Row

private struct LandingRecentRow: View {
    let url: URL; let showDivider: Bool; let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: "shippingbox")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange.opacity(0.70))
                    .frame(width: 14, alignment: .center)
                VStack(alignment: .leading, spacing: 1) {
                    Text(url.deletingPathExtension().lastPathComponent)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(white: 0.82))
                        .lineLimit(1)
                    Text(url.deletingLastPathComponent().path(percentEncoded: false))
                        .font(IDETheme.Typography.caption)
                        .foregroundStyle(Color(white: 0.32))
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 9))
                    .foregroundStyle(Color(white: 0.28))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(isHovered ? IDETheme.Colors.hoverFill : Color.clear)
            .overlay(alignment: .bottom) {
                if showDivider {
                    Rectangle()
                        .fill(IDETheme.Colors.rowDivider)
                        .frame(height: IDETheme.Layout.separatorWeight)
                        .padding(.leading, 34)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(IDETheme.Animation.micro, value: isHovered)
    }
}

// MARK: - Editor Start Button

private struct EditorStartButton: View {
    let icon: String; let label: String; let color: Color
    var action: () -> Void = {}
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(color)
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(white: 0.52))
            }
            .frame(width: 80, height: 58)
            .background(
                RoundedRectangle(cornerRadius: IDETheme.Layout.cardRadius, style: .continuous)
                    .fill(isHovered ? IDETheme.Colors.hoverFillStrong : IDETheme.Colors.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: IDETheme.Layout.cardRadius, style: .continuous)
                    .strokeBorder(IDETheme.Colors.panelBorder, lineWidth: IDETheme.Layout.separatorWeight)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(IDETheme.Animation.snap, value: isHovered)
    }
}

// MARK: - Editor Start File Row

private struct EditorStartFileRow: View {
    let file: SPPFile; let showDivider: Bool; let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: file.contentType.systemImageName)
                    .font(.system(size: 11))
                    .foregroundStyle(iconColor)
                    .frame(width: 14, alignment: .center)
                Text(file.name)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(white: 0.82))
                Spacer()
                Text(file.contentType.rawValue)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color(white: 0.30))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(isHovered ? IDETheme.Colors.hoverFill : Color.clear)
            .overlay(alignment: .bottom) {
                if showDivider {
                    Rectangle()
                        .fill(IDETheme.Colors.rowDivider)
                        .frame(height: IDETheme.Layout.separatorWeight)
                        .padding(.leading, 34)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(IDETheme.Animation.micro, value: isHovered)
    }

    private var iconColor: Color {
        switch file.contentType {
        case .swift, .orionSwift: return IDETheme.Colors.swiftOrange
        case .objc, .objcHeader:  return IDETheme.Colors.objcBlue
        case .logosXM:            return IDETheme.Colors.logosXMPurple
        case .makefile:           return IDETheme.Colors.makefileGreen
        default:                  return Color(white: 0.40)
        }
    }
}

// MARK: - Preview

struct EditorAreaView_Previews: PreviewProvider {
    static var previews: some View {
        EditorAreaView()
            .environmentObject(AppEnvironment())
            .frame(width: 700, height: 600)
            .preferredColorScheme(.dark)
    }
}
