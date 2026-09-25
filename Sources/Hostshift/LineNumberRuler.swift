import AppKit
import HostsCore

@MainActor
final class LineNumberRuler: NSRulerView {
    private var lines: [NSRange] = [NSRange(location: 0, length: 0)]
    private weak var editor: NSTextView?

    init(scrollView: NSScrollView, editor: NSTextView) {
        self.editor = editor
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = editor
        ruleThickness = 40
        clipsToBounds = true
        setAccessibilityElement(false)
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(viewportChanged), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        NotificationCenter.default.addObserver(self, selector: #selector(textChanged), name: NSText.didChangeNotification, object: editor)
        updateLines()
    }

    required init(coder: NSCoder) { fatalError("LineNumberRuler is created programmatically") }

    @objc private func viewportChanged(_ notification: Notification) { needsDisplay = true }
    @objc private func textChanged(_ notification: Notification) { updateLines() }

    func updateLines() {
        guard let editor else { return }
        lines = HostsLines.ranges(in: editor.string)
        let font = editor.font ?? .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        let width = (String(lines.count) as NSString).size(withAttributes: [.font: font]).width
        ruleThickness = max(40, ceil(width) + 20)
        needsDisplay = true
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        guard let editor, let layout = editor.layoutManager, let container = editor.textContainer else { return }
        layout.ensureLayout(for: container)
        let origin = editor.textContainerOrigin
        let visible = editor.visibleRect.offsetBy(dx: -origin.x, dy: -origin.y)
        let visibleGlyphs = layout.glyphRange(forBoundingRect: visible, in: container)
        let visibleCharacters = layout.characterRange(forGlyphRange: visibleGlyphs, actualGlyphRange: nil)
        let font = editor.font ?? .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
        let length = (editor.string as NSString).length
        for (index, line) in lines.enumerated() {
            let nextStart = index + 1 < lines.count ? lines[index + 1].location : length + 1
            if nextStart <= visibleCharacters.location { continue }
            if line.location > NSMaxRange(visibleCharacters) { break }
            let fragment: NSRect
            if line.location == length {
                fragment = layout.extraLineFragmentRect
            } else {
                let glyph = layout.glyphIndexForCharacter(at: line.location)
                fragment = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            }
            let label = String(index + 1) as NSString
            let size = label.size(withAttributes: attributes)
            let point = convert(NSPoint(x: origin.x, y: fragment.minY + origin.y), from: editor)
            let y = point.y + max(0, (fragment.height - size.height) / 2)
            label.draw(at: NSPoint(x: bounds.maxX - size.width - 10, y: y), withAttributes: attributes)
        }
        NSColor.separatorColor.setFill()
        NSRect(x: bounds.maxX - 1, y: bounds.minY, width: 1, height: bounds.height).fill()
    }
}
