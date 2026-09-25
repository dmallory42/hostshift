import AppKit
import SwiftUI
import HostsCore

@main @MainActor struct EditorChecks {
    static func main() {
        let alignedEditor = NSTextView(frame: NSRect(x: 0, y: 0, width: 700, height: 300))
        alignedEditor.isRichText = false
        HostsTextFormatting.configure(alignedEditor)
        let columns = "127.0.0.1\t\thost\n255.255.255.255\thost\n::1             host"
        alignedEditor.string = columns
        func hostPositions() -> [CGFloat] {
            let text = alignedEditor.string as NSString
            let layout = alignedEditor.layoutManager!
            layout.ensureLayout(for: alignedEditor.textContainer!)
            var positions: [CGFloat] = []
            var offset = 0
            while offset < text.length {
                let match = text.range(of: "host", range: NSRange(location: offset, length: text.length - offset))
                if match.location == NSNotFound { break }
                positions.append(layout.location(forGlyphAt: layout.glyphIndexForCharacter(at: match.location)).x)
                offset = NSMaxRange(match)
            }
            return positions
        }
        let positions = hostPositions()
        precondition(positions.count == 3 && positions.allSatisfy { abs($0 - positions[0]) < 0.01 })
        precondition(alignedEditor.string == columns)
        print("PASS tabs and spaces align on the same character grid without changing file contents")
        alignedEditor.setSelectedRange(NSRange(location: (columns as NSString).length, length: 0))
        alignedEditor.insertText("\n::1\t\t\t\thost", replacementRange: alignedEditor.selectedRange())
        let typedPositions = hostPositions()
        precondition(typedPositions.count == 4 && typedPositions.allSatisfy { abs($0 - positions[0]) < 0.01 })
        print("PASS newly typed lines retain character-aligned tab stops")
        let sample = "# 😀 Comment\r\n127.0.0.1\tlocal.test alias.test # inline\r\n::1 localhost\n"
        let tokens = HostsSyntax.tokens(in: sample)
        let fields = tokens.map { (sample as NSString).substring(with: $0.range) }
        precondition(fields == ["# 😀 Comment", "127.0.0.1", "local.test", "alias.test", "# inline", "::1", "localhost"])
        precondition(tokens.map(\.kind) == [.comment, .address, .hostname, .hostname, .comment, .address, .hostname])
        precondition(HostsSyntax.tokens(in: " \t\r\n").isEmpty)
        print("PASS syntax ranges handle Unicode comments, CRLF, IPv6, aliases and blank lines")
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 200))
        editor.isRichText = false
        editor.allowsUndo = true
        editor.string = sample
        editor.setSelectedRange(NSRange(location: 17, length: 4))
        let before = editor.selectedRanges
        HostsSyntaxHighlighter.apply(to: editor)
        precondition(editor.string == sample && editor.selectedRanges == before)
        precondition(editor.undoManager?.canUndo != true)
        let color = editor.layoutManager?.temporaryAttribute(.foregroundColor, atCharacterIndex: tokens[1].range.location, effectiveRange: nil) as? NSColor
        precondition(color == .systemPurple)
        let attributes = editor.textStorage!.attributes(at: tokens[1].range.location, effectiveRange: nil)
        precondition(attributes[.foregroundColor] as? NSColor != .systemPurple)
        print("PASS highlighting preserves text, selection and undo history; colors stay out of stored text")
        editor.string = "# replaced"
        HostsSyntaxHighlighter.apply(to: editor)
        let commentColor = editor.layoutManager?.temporaryAttribute(.foregroundColor, atCharacterIndex: 0, effectiveRange: nil) as? NSColor
        precondition(commentColor == .secondaryLabelColor)
        editor.string = ""
        HostsSyntaxHighlighter.apply(to: editor)
        print("PASS highlighting updates after replacement and handles empty text")
        let invalid = "# 😀 Comment\r\ninvalid example.test\r\n127.0.0.1 bad/name\r\n"
        let diagnostics = HostsValidator.diagnostics(in: invalid)
        precondition(diagnostics.map(\.line) == [2, 3])
        precondition(diagnostics.map(\.description) == HostsValidator.issues(in: invalid))
        precondition(HostsValidator.diagnostics(in: "\0").first?.line == nil)
        print("PASS diagnostics expose accurate line numbers and preserve existing validation messages")
        editor.string = invalid
        let coordinator = HostsTextCoordinator(text: .constant(invalid))
        coordinator.selectLine(3, in: editor)
        let selected = (editor.string as NSString).substring(with: editor.selectedRange())
        precondition(selected == "127.0.0.1 bad/name")
        coordinator.selectLine(2, in: editor)
        precondition((editor.string as NSString).substring(with: editor.selectedRange()) == "invalid example.test")
        let validSelection = editor.selectedRange()
        coordinator.selectLine(100, in: editor)
        precondition(editor.selectedRange() == validSelection)
        precondition(editor.string == invalid)
        print("PASS issue navigation selects UTF-16/CRLF lines without editing text and ignores stale line numbers")
    }
}
