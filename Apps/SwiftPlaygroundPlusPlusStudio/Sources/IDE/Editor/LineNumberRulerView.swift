import AppKit
import SPPCore

// MARK: - Line Number Ruler View

final class LineNumberRulerView: NSRulerView {

    private let dimFont          = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular)
    private let activeFont       = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .medium)
    private let dimColor         = NSColor(white: 0.24, alpha: 1)
    private let activeColor      = NSColor(white: 0.70, alpha: 1)
    private let bgColor          = NSColor(red: 0.080, green: 0.080, blue: 0.118, alpha: 1)
    private let activeBgColor    = NSColor(white: 1.0, alpha: 0.044)
    private let accentBarColor   = NSColor(red: 0.36, green: 0.54, blue: 1.0, alpha: 0.72)
    private let borderColor      = NSColor(white: 1.0, alpha: 0.08)

    private(set) var currentLine: Int = 1 {
        didSet { if oldValue != currentLine { needsDisplay = true } }
    }

    /// 1-based line → most-severe diagnostic on that line. Drives the gutter
    /// markers. Owned by the editor's coordinator, which derives it from the
    /// `FileDiagnosticsStore` — the ruler is a pure renderer of this state.
    var diagnosticLines: [Int: Diagnostic.Severity] = [:] {
        didSet { if oldValue != diagnosticLines { needsDisplay = true } }
    }

    override init(scrollView: NSScrollView?, orientation: NSRulerView.Orientation) {
        super.init(scrollView: scrollView, orientation: orientation)
        clientView = scrollView?.documentView
        ruleThickness = 52
    }

    required init(coder: NSCoder) { fatalError() }

    func setCurrentLine(_ line: Int) { currentLine = max(1, line) }

    // MARK: - Drawing

    override func drawHashMarksAndLabels(in dirtyRect: NSRect) {
        guard
            let tv = clientView as? NSTextView,
            let lm = tv.layoutManager,
            tv.textContainer != nil,
            let sv = scrollView
        else { return }

        bgColor.setFill()
        dirtyRect.fill()

        let visible = sv.contentView.bounds
        let origin  = tv.textContainerOrigin
        let source  = tv.string as NSString
        let srcLen  = source.length

        guard srcLen > 0 else {
            drawLabel(1, y: 0, h: 17, isActive: true)
            drawActiveAccent(y: 0, h: 17)
            return
        }

        var lineNumber  = 1
        var prevCharEnd = 0
        let fullGlyphRange = NSRange(location: 0, length: lm.numberOfGlyphs)

        lm.enumerateLineFragments(forGlyphRange: fullGlyphRange) { lineRect, _, _, glyphRange, stop in
            let charRange  = lm.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            let isFirstFrag = charRange.location >= prevCharEnd
            let yInView    = lineRect.minY + origin.y
            let yInRuler   = yInView - visible.minY

            if yInRuler + lineRect.height < dirtyRect.minY - 4 {
                if isFirstFrag { lineNumber += 1 }
                prevCharEnd = charRange.location + charRange.length
                return
            }
            if yInRuler > dirtyRect.maxY + 4 { stop.pointee = true; return }

            if isFirstFrag {
                let isActive = lineNumber == self.currentLine
                if isActive {
                    self.activeBgColor.setFill()
                    NSRect(x: 0, y: yInRuler, width: self.ruleThickness, height: lineRect.height).fill()
                    self.drawActiveAccent(y: yInRuler, h: lineRect.height)
                }
                if let severity = self.diagnosticLines[lineNumber] {
                    self.drawDiagnosticMarker(severity: severity, y: yInRuler, h: lineRect.height)
                }
                self.drawLabel(lineNumber, y: yInRuler, h: lineRect.height, isActive: isActive)
                lineNumber += 1
            }
            prevCharEnd = charRange.location + charRange.length
        }

        // Right-edge separator
        borderColor.setFill()
        NSRect(x: ruleThickness - 0.5, y: dirtyRect.minY, width: 0.5, height: dirtyRect.height).fill()
    }

    private func drawActiveAccent(y: CGFloat, h: CGFloat) {
        accentBarColor.setFill()
        NSRect(x: 0, y: y, width: 2, height: h).fill()
    }

    private func drawDiagnosticMarker(severity: Diagnostic.Severity, y: CGFloat, h: CGFloat) {
        let color = IDETheme.EditorColors.underline(for: severity)
        let d: CGFloat = 6
        let rect = NSRect(x: 5, y: y + (h - d) / 2, width: d, height: d)
        color.setFill()
        NSBezierPath(ovalIn: rect).fill()
    }

    private func drawLabel(_ n: Int, y: CGFloat, h: CGFloat, isActive: Bool) {
        let label = "\(n)" as NSString
        let font  = isActive ? activeFont : dimFont
        let color = isActive ? activeColor : dimColor
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size  = label.size(withAttributes: attrs)
        let x     = ruleThickness - size.width - 12
        let yPos  = y + (h - size.height) / 2
        label.draw(at: NSPoint(x: x, y: yPos), withAttributes: attrs)
    }
}
