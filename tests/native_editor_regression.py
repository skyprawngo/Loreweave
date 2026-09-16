#!/usr/bin/env python3
"""Exercise actual NSTextView navigation/editing and report large-document layout costs."""
from pathlib import Path
import subprocess, tempfile
root = Path(__file__).resolve().parents[1]
engine = root / 'TextlinkEditor/Services/Editor/TextEngine'
views = root / 'TextlinkEditor/Views/MainEditor/EditorPanel/TextlinkTextView'
sources = [engine / name for name in ['TextDocument.swift','TextSelection.swift','ViewportManager.swift','EditorState.swift','EditorCommand.swift']]
sources += sorted((engine / 'EditorState').glob('*.swift'))
sources += [views / 'NativeManuscriptView.swift']
prefix = (root / 'tests/editor_binding_regression.py').read_text().split("harness = r'''",1)[1].split('final class Box',1)[0]
harness = r'''
func expect(_ value: @autoclosure () -> Bool, _ message: String) { precondition(value(), message); print("PASS \(message)") }
func timed(_ name: String, _ work: () -> Void) { let start = CFAbsoluteTimeGetCurrent(); work(); print("TIME \(name): \((CFAbsoluteTimeGetCurrent() - start) * 1000) ms") }
let app = NSApplication.shared
let view = NativeManuscriptTextView()
let host = NativeManuscriptHost(textView: view)
let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
window.contentView = host
window.makeFirstResponder(view)
view.load("alpha beta\n한글 😀 é\nlast")
view.setSelectedRange(NSRange(location: 0, length: 0))
view.moveWordRight(nil)
expect(view.selectedRange().location == 5, "Option Right moves by word")
view.moveWordRightAndModifySelection(nil)
expect((view.string as NSString).substring(with: view.selectedRange()) == " beta", "Option Shift Right extends to next word")
view.moveToEndOfDocumentAndModifySelection(nil)
expect(NSMaxRange(view.selectedRange()) == (view.string as NSString).length, "Command Shift Down extends to document end")
view.moveToBeginningOfDocument(nil)
expect(view.selectedRange().location == 0, "Command Up reaches document start")
view.moveToEndOfLineAndModifySelection(nil)
expect((view.string as NSString).substring(with: view.selectedRange()) == "alpha beta", "Command Shift Right selects current line")
view.moveToEndOfDocument(nil)
view.moveToBeginningOfDocumentAndModifySelection(nil)
expect(view.selectedRange().length == (view.string as NSString).length, "Command Shift Up extends backwards to start")
view.setSelectedRange(NSRange(location: view.offset(line: 1, column: 4), length: 0))
let before = view.selectedRange().location
view.moveLeft(nil)
expect(before - view.selectedRange().location == 2, "native left treats emoji as one character")
view.setSelectedRange(NSRange(location: 0, length: 5))
view.execute(EditorCommand(.format(.bold)))
expect(view.string.hasPrefix("**alpha**"), "formatting uses native editing")
_ = NSApp.sendAction(#selector(NativeManuscriptTextView.undo(_:)), to: view, from: nil)
expect(view.string.hasPrefix("alpha beta"), "native undo restores formatting")
view.execute(EditorCommand(.replace("alpha", replacement: "start", all: true)))
expect(view.string.hasPrefix("start beta"), "replace all retains editor contract")
_ = NSApp.sendAction(#selector(NativeManuscriptTextView.undo(_:)), to: view, from: nil)
expect(view.string.hasPrefix("alpha beta"), "native undo restores replace all")
view.load("😀")
expect(view.lineStarts == [0], "emoji at EOF indexes safely")
view.load("a\r\nb\n")
expect(view.lineStarts == [0,3,5], "CRLF and trailing empty line index")
view.load("abc")
view.isEditable = false
view.replace(NSRange(location: 0, length: 1), with: "x")
expect(view.string == "abc", "read-only prevents command replacement")
view.isEditable = true
view.load("first\nsecond\nthird")
view.setSelectedRange(NSRange(location: 2, length: 0))
let layout = view.layoutManager!
let container = view.textContainer!
layout.ensureLayout(for: container)
let secondGlyph = layout.glyphIndexForCharacter(at: 6)
let originalY = layout.lineFragmentRect(forGlyphAt: secondGlyph, effectiveRange: nil).minY
let panel = NSView()
view.installInlinePanel(panel)
layout.ensureLayout(for: container)
let expandedY = layout.lineFragmentRect(forGlyphAt: secondGlyph, effectiveRange: nil).minY
expect(expandedY - originalY >= 99, "inline panel reserves layout space between manuscript lines")
expect(view.string == "first\nsecond\nthird", "opening inline panel never changes manuscript bytes")
expect(panel.frame.maxY <= expandedY + view.textContainerOrigin.y, "inline panel does not cover next paragraph")
view.replace(NSRange(location: 0, length: 0), with: "prefix ")
expect(view.inlinePanel === panel, "editing keeps inline draft panel alive")
view.undo(nil)
expect(view.string == "first\nsecond\nthird", "inline layout preserves native undo")
view.closeInlinePanel()
layout.ensureLayout(for: container)
expect(abs(layout.lineFragmentRect(forGlyphAt: secondGlyph, effectiveRange: nil).minY - originalY) < 1, "closing inline panel restores paragraph position")
view.load("")
view.installInlinePanel(NSView())
expect(view.string.isEmpty && view.inlinePanel != nil, "inline panel supports empty manuscripts")
view.load("external revision")
expect(view.inlinePanel == nil, "external document replacement removes stale inline anchor")
for count in [1000,10000,100000] {
    let text = String(repeating: "한글 장편 원고입니다. 😀 테스트 문장입니다.\n", count: count)
    timed("load \(count)") { view.load(text) }
    expect(view.lineStarts.count == count + 1, "large manuscript line count \(count)")
    timed("first viewport \(count)") { host.layoutSubtreeIfNeeded(); view.layoutManager!.ensureLayout(forBoundingRect: NSRect(x: 0,y: 0,width: 800,height: 700), in: view.textContainer!) }
    timed("end navigation \(count)") { view.moveToEndOfDocument(nil); view.scrollRangeToVisible(view.selectedRange()) }
    timed("return to start \(count)") { view.moveToBeginningOfDocument(nil); view.scrollRangeToVisible(view.selectedRange()) }
}
view.load("match first\nother\nMATCH target\n")
view.execute(EditorCommand(.locate(line: 2, query: "match")))
expect(view.selectedRange().location == 18, "project search selects exact repeated match line")
print("NATIVE EDITOR REGRESSION COMPLETED")
'''
with tempfile.TemporaryDirectory(prefix='lore-native-test-') as directory:
    directory = Path(directory)
    main = directory/'main.swift'; main.write_text(prefix + harness)
    executable = directory/'test'
    subprocess.run(['swiftc','-O',*map(str,sources),str(main),'-o',str(executable)],check=True)
    subprocess.run([str(executable)],check=True)
