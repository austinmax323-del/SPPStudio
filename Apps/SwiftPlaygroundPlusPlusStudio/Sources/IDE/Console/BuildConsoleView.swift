import SwiftUI
import SPPCore

// MARK: - Build Console View

struct BuildConsoleView: View {

    @EnvironmentObject var appEnv: AppEnvironment

    private let bottomAnchorID = "build_console_bottom"
    @State private var autoScroll = true

    var body: some View {
        VStack(spacing: 0) {
            consoleToolbar
            panelDivider
            if appEnv.buildLog.isEmpty {
                emptyState
            } else {
                scrollingLog
            }
        }
    }

    // MARK: - Toolbar

    private var consoleToolbar: some View {
        HStack(spacing: 10) {
            buildStatusLabel
            Spacer()
            badgePills
            toolbarSeparator
            scrollLockButton
            toolbarSeparator
            clearButton
        }
        .padding(.horizontal, 12)
        .frame(height: IDETheme.Layout.tabBarHeight - 2)
        .background(Color.black.opacity(0.18))
    }

    private var scrollLockButton: some View {
        Button(action: { autoScroll.toggle() }) {
            Image(systemName: autoScroll ? "arrow.down.to.line" : "lock.slash")
                .font(.system(size: 11))
        }
        .buttonStyle(.plain)
        .foregroundStyle(autoScroll ? Color.accentColor : Color(white: 0.44))
        .help(autoScroll ? "Auto-scroll on — click to lock" : "Auto-scroll off — click to unlock")
    }

    private var buildStatusLabel: some View {
        let errorCount = appEnv.buildLog.filter(\.isError).count
        return Group {
            if appEnv.isBuilding {
                Label("Building\u{2026}", systemImage: "clock")
                    .foregroundStyle(Color(white: 0.55))
            } else if errorCount > 0 {
                Label("Build Failed", systemImage: "xmark.circle.fill")
                    .foregroundStyle(IDETheme.Colors.consoleError)
            } else if appEnv.buildLog.contains(where: { $0.text.hasPrefix("=== BUILD SUCCEEDED") }) {
                Label("Build Succeeded", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(IDETheme.Colors.consoleSuccess)
            } else {
                Label("Ready", systemImage: "minus.circle")
                    .foregroundStyle(Color(white: 0.30))
            }
        }
        .font(.system(size: 11, weight: .medium))
    }

    private var badgePills: some View {
        let errorCount   = appEnv.buildLog.filter(\.isError).count
        let warningCount = appEnv.buildLog.filter {
            !$0.isError && ($0.text.lowercased().contains("warning:") || $0.text.lowercased().contains("warn:"))
        }.count
        return HStack(spacing: 5) {
            IDEStatusBadge(count: errorCount,   color: IDETheme.Colors.consoleError,   icon: "xmark.circle.fill")
            IDEStatusBadge(count: warningCount, color: IDETheme.Colors.consoleWarning, icon: "exclamationmark.triangle.fill")
        }
    }

    private var toolbarSeparator: some View {
        Rectangle()
            .fill(IDETheme.Colors.rowDivider)
            .frame(width: IDETheme.Layout.separatorWeight, height: 14)
    }

    private var clearButton: some View {
        Button(action: { appEnv.buildLog.removeAll() }) {
            Image(systemName: "trash")
                .font(.system(size: 11))
        }
        .buttonStyle(.plain)
        .foregroundStyle(appEnv.buildLog.isEmpty ? Color(white: 0.22) : Color(white: 0.44))
        .disabled(appEnv.buildLog.isEmpty)
        .help("Clear build log")
    }

    // MARK: - Empty State

    private var emptyState: some View {
        HStack(spacing: 8) {
            Image(systemName: "hammer")
                .font(.system(size: 12, weight: .ultraLight))
                .foregroundStyle(Color(white: 0.20))
            Text("No build output yet. Press ⌘B to build.")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color(white: 0.22))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Scrolling Log

    private var scrollingLog: some View {
        BuildLogTextView(entries: appEnv.buildLog, autoScroll: autoScroll)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private var panelDivider: some View {
        Rectangle()
            .fill(IDETheme.Colors.panelSeparator)
            .frame(height: IDETheme.Layout.separatorWeight)
    }
}

// MARK: - Build Log NSTextView (selectable, copyable, Cmd+A)

private struct BuildLogTextView: NSViewRepresentable {

    let entries: [AppEnvironment.BuildLogEntry]
    let autoScroll: Bool

    func makeNSView(context: Context) -> NSScrollView {
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(containerSize: NSSize(width: CGFloat.greatestFiniteMagnitude,
                                                                  height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = false
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)

        let tv = BuildLogNativeTextView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 240),
            textContainer: textContainer
        )

        tv.isEditable = false
        tv.isSelectable = true
        tv.isRichText = true
        tv.allowsUndo = false
        tv.usesFindBar = true
        tv.drawsBackground = true
        tv.textContainerInset = NSSize(width: 10, height: 8)
        tv.backgroundColor = NSColor(red: 0.056, green: 0.056, blue: 0.082, alpha: 1.0)
        tv.isHorizontallyResizable = true
        tv.isVerticallyResizable = true
        tv.minSize = .zero
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                            height: CGFloat.greatestFiniteMagnitude)
        tv.autoresizingMask = [.width, .height]
        tv.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        tv.textColor = NSColor(white: 0.78, alpha: 1)

        let scrollView = NSScrollView()
        scrollView.documentView = tv

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.backgroundColor = NSColor(red: 0.056, green: 0.056, blue: 0.082, alpha: 1.0)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tv = scrollView.documentView as? NSTextView,
              let storage = tv.textStorage else { return }

        let selection = tv.selectedRange()
        let shouldScrollToEnd = autoScroll && context.coordinator.isNearBottom(scrollView)
        let c = context.coordinator

        if entries.isEmpty {
            if c.renderedCount > 0 {
                storage.setAttributedString(NSAttributedString())
                c.reset()
            }
            tv.setSelectedRange(NSRange(location: 0, length: 0))
            return
        }

        let firstID = entries.first!.id
        let lastID  = entries.last!.id

        if c.renderedCount == entries.count && c.renderedLastID == lastID {
            // Identical — nothing to do.
        } else if c.renderedFirstID == firstID && entries.count > c.renderedCount {
            // Pure append: front is unchanged, only new tail entries added.
            for i in c.renderedCount ..< entries.count {
                append(entries[i], lineNum: i + 1, to: storage)
            }
            c.renderedCount = entries.count
            c.renderedLastID = lastID
        } else {
            // Front changed (trim) or first render — full rebuild.
            storage.setAttributedString(NSAttributedString())
            for (i, entry) in entries.enumerated() {
                append(entry, lineNum: i + 1, to: storage)
            }
            c.renderedCount = entries.count
            c.renderedFirstID = firstID
            c.renderedLastID = lastID
        }

        tv.setSelectedRange(clamped(selection, in: storage.string))
        if shouldScrollToEnd { tv.scrollToEndOfDocument(nil) }
    }

    private static let ansiRegex: NSRegularExpression? =
        try? NSRegularExpression(pattern: "\u{001B}(?:\\[[0-9;]*[mGKHFJABCDHf]|[\\[\\]()]|[0-9A-Za-z])")

    private func stripANSI(_ raw: String) -> String {
        guard let re = Self.ansiRegex else { return raw }
        return re.stringByReplacingMatches(
            in: raw, range: NSRange(raw.startIndex..., in: raw), withTemplate: ""
        )
    }

    private func append(_ entry: AppEnvironment.BuildLogEntry, lineNum: Int, to storage: NSTextStorage) {
        let gutter = NSAttributedString(
            string: String(format: "%5d  ", lineNum),
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular),
                .foregroundColor: NSColor(white: 0.22, alpha: 1)
            ]
        )

        let t = stripANSI(entry.text)
        let defaultMsgColor: NSColor
        if entry.isError {
            defaultMsgColor = NSColor(red: 1.0, green: 0.36, blue: 0.36, alpha: 1)
        } else if t.lowercased().contains("warning:") || t.lowercased().contains("warn:") {
            defaultMsgColor = NSColor(red: 1.0, green: 0.74, blue: 0.24, alpha: 1)
        } else if t.hasPrefix("===") {
            defaultMsgColor = NSColor(red: 0.44, green: 0.76, blue: 1.0, alpha: 1)
        } else if t.hasPrefix("  Package:") || t.hasPrefix("dm.pl:") {
            defaultMsgColor = NSColor(red: 0.34, green: 0.92, blue: 0.52, alpha: 1)
        } else {
            defaultMsgColor = NSColor(white: 0.78, alpha: 1)
        }

        let isWarning = !entry.isError &&
            (t.lowercased().contains("warning:") || t.lowercased().contains("warn:"))
        let bgColor: NSColor
        if entry.isError {
            bgColor = NSColor(red: 1.0, green: 0.18, blue: 0.18, alpha: 0.07)
        } else if isWarning {
            bgColor = NSColor(red: 1.0, green: 0.74, blue: 0.0, alpha: 0.04)
        } else {
            bgColor = NSColor.clear
        }

        let msg = attributedANSIString(
            entry.text + "\n",
            defaultColor: defaultMsgColor,
            backgroundColor: bgColor
        )

        storage.beginEditing()
        storage.append(gutter)
        storage.append(msg)
        storage.endEditing()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    private func attributedANSIString(
        _ raw: String,
        defaultColor: NSColor,
        backgroundColor: NSColor
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let ns = raw as NSString
        let full = NSRange(location: 0, length: ns.length)
        var cursor = 0
        var color = defaultColor
        let baseAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .backgroundColor: backgroundColor
        ]

        Self.ansiRegex?.enumerateMatches(in: raw, range: full) { match, _, _ in
            guard let match else { return }
            if match.range.location > cursor {
                result.append(NSAttributedString(
                    string: ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)),
                    attributes: baseAttrs.merging([.foregroundColor: color]) { _, new in new }
                ))
            }
            color = colorAfterANSI(ns.substring(with: match.range), current: color, fallback: defaultColor)
            cursor = match.range.location + match.range.length
        }

        if cursor < ns.length {
            result.append(NSAttributedString(
                string: ns.substring(with: NSRange(location: cursor, length: ns.length - cursor)),
                attributes: baseAttrs.merging([.foregroundColor: color]) { _, new in new }
            ))
        }

        return result
    }

    private func colorAfterANSI(_ sequence: String, current: NSColor, fallback: NSColor) -> NSColor {
        guard sequence.hasPrefix("\u{001B}["),
              sequence.hasSuffix("m") else { return current }
        let body = sequence.dropFirst(2).dropLast()
        let codes = body.split(separator: ";").compactMap { Int($0) }
        if codes.isEmpty || codes.contains(0) { return fallback }
        if codes.contains(31) || codes.contains(91) { return NSColor(red: 1.0, green: 0.36, blue: 0.36, alpha: 1) }
        if codes.contains(33) || codes.contains(93) { return NSColor(red: 1.0, green: 0.74, blue: 0.24, alpha: 1) }
        if codes.contains(32) || codes.contains(92) { return NSColor(red: 0.34, green: 0.92, blue: 0.52, alpha: 1) }
        if codes.contains(34) || codes.contains(94) { return NSColor(red: 0.44, green: 0.76, blue: 1.0, alpha: 1) }
        if codes.contains(35) || codes.contains(95) { return NSColor(red: 0.78, green: 0.52, blue: 1.0, alpha: 1) }
        if codes.contains(36) || codes.contains(96) { return NSColor(red: 0.45, green: 0.88, blue: 0.92, alpha: 1) }
        if codes.contains(37) || codes.contains(97) { return NSColor(white: 0.88, alpha: 1) }
        return current
    }

    private func clamped(_ range: NSRange, in source: String) -> NSRange {
        let length = (source as NSString).length
        let location = min(max(0, range.location), length)
        let maxLength = max(0, length - location)
        return NSRange(location: location, length: min(max(0, range.length), maxLength))
    }

    final class Coordinator {
        var renderedCount: Int = 0
        var renderedFirstID: UUID? = nil
        var renderedLastID: UUID? = nil

        func reset() {
            renderedCount = 0
            renderedFirstID = nil
            renderedLastID = nil
        }

        func isNearBottom(_ scrollView: NSScrollView) -> Bool {
            guard let documentView = scrollView.documentView else { return true }
            let visible = scrollView.contentView.bounds
            let distance = documentView.bounds.maxY - visible.maxY
            return distance <= 36
        }
    }
}

private final class BuildLogNativeTextView: NSTextView {
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command),
              let chars = event.charactersIgnoringModifiers?.lowercased()
        else { return super.performKeyEquivalent(with: event) }

        switch chars {
        case "a":
            selectAll(nil)
            return true
        case "c":
            copy(nil)
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }
}

// MARK: - Preview

struct BuildConsoleView_Previews: PreviewProvider {
    static var previews: some View {
        let env: AppEnvironment = {
            let e = AppEnvironment()
            e.buildLog = [
                .init(text: "=== BUILD STARTED ===",                    isError: false),
                .init(text: "  Compiling Tweak.xm ...",                 isError: false),
                .init(text: "  Linking libMyTweak.dylib ...",           isError: false),
                .init(text: "  warning: implicit conversion loses int", isError: false),
                .init(text: "  error: use of undeclared identifier 'x'",isError: true),
                .init(text: "=== BUILD FAILED (1 error, 1 warning) ===", isError: true)
            ]
            return e
        }()
        BuildConsoleView()
            .environmentObject(env)
            .frame(width: 900, height: 180)
            .preferredColorScheme(.dark)
    }
}
