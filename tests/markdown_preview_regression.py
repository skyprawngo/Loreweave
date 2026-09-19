#!/usr/bin/env python3
from pathlib import Path
import subprocess, tempfile
root = Path(__file__).resolve().parents[1]
code = r'''
import AppKit
import SwiftUI
func expect(_ value: @autoclosure () -> Bool, _ label: String) { precondition(value(), label); print("PASS " + label) }
enum L10n { static func get(_ key: String) -> String { key } }
enum AppColors {
    static var textEditorBackground: Color { .white }
    static var nsEditorText: NSColor { .black }
}
let app = NSApplication.shared
func render(_ source: String) throws -> NSAttributedString {
    MarkdownPreviewRenderer.render(try MarkdownPreviewRenderer.parse(source), font: .systemFont(ofSize: 14),
        color: .black, lineHeightMultiple: 1.25, letterSpacing: 0.5)
}
let source = "**굵게** *기울임* ***둘 다*** ~~취소~~ <u>밑줄</u> `**코드**`\n한글 😀 é"
let result = try render(source)
expect(result.string == "굵게 기울임 둘 다 취소 밑줄 **코드**\n한글 😀 é", "inline syntax becomes visible content without losing unicode or line breaks")
func attributes(_ word: String) -> [NSAttributedString.Key: Any] { result.attributes(at: (result.string as NSString).range(of: word).location, effectiveRange: nil) }
expect(NSFontManager.shared.traits(of: attributes("굵게")[.font] as! NSFont).contains(.boldFontMask), "strong renders bold")
expect(NSFontManager.shared.traits(of: attributes("기울임")[.font] as! NSFont).contains(.italicFontMask), "emphasis renders italic")
expect(NSFontManager.shared.traits(of: attributes("둘 다")[.font] as! NSFont).contains([.boldFontMask, .italicFontMask]), "nested bold italic retains both traits")
expect(attributes("취소")[.strikethroughStyle] as? Int == 1, "strikethrough renders")
expect(attributes("밑줄")[.underlineStyle] as? Int == 1, "toolbar underline renders without HTML markers")
expect(try! render("\\*plain\\* `<u>code</u>`").string == "*plain* <u>code</u>", "escapes and code remain literal")
expect(try! render("<u>unfinished").string == "<u>unfinished", "unmatched underline syntax remains visible")
expect(source.contains("**굵게**"), "rendering does not mutate Markdown source")
let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
window.contentView = NSHostingView(rootView: MarkdownPreviewView(source: source, fontName: "SF Pro", fontSize: 14, lineHeightMultiple: 1.25, letterSpacing: 0.5))
window.orderFront(nil)
func findText(_ view: NSView) -> NSTextView? {
    if let text = view as? NSTextView { return text }
    for child in view.subviews { if let found = findText(child) { return found } }
    return nil
}
let deadline = Date().addingTimeInterval(8)
while findText(window.contentView!)?.string != result.string, Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
window.displayIfNeeded()
let preview = findText(window.contentView!)!
expect(preview.string == result.string && !preview.isEditable && preview.isSelectable, "real hosted preview displays formatted text read-only")
expect(preview.frame.width > 100 && preview.frame.height > 0, "preview has a usable scroll viewport")
window.orderOut(nil)
print("ALL MARKDOWN PREVIEW REGRESSIONS PASSED")
'''
with tempfile.TemporaryDirectory(prefix='markdown-preview-') as work:
    work = Path(work)
    (work/'main.swift').write_text(code)
    sources = [root/'TextlinkEditor/Services/Editor/Markdown/MarkdownPreviewRenderer.swift',
               root/'TextlinkEditor/Views/MainEditor/EditorPanel/MarkdownPreviewView.swift']
    subprocess.run(['swiftc', *map(str, sources), str(work/'main.swift'), '-o', str(work/'test')], check=True)
    subprocess.run([str(work/'test')], check=True)
