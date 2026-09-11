#!/usr/bin/env python3
"""Compile and run the actual text engine without an app/Xcode build."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
engine = root / 'Loreweave/Services/Editor/TextEngine'
sources = [engine / name for name in ['TextDocument.swift', 'TextSelection.swift', 'ViewportManager.swift', 'EditorState.swift', 'EditorCommand.swift']]
sources += sorted((engine / 'EditorState').glob('*.swift'))
sources += [root / 'Loreweave/Views/MainEditor/EditorPanel/LoreTextView' / name for name in ['LineRenderer.swift', 'LoreTextView.swift', 'LoreEditorView.swift', 'GutterView.swift']]
harness = r'''
import Foundation
import AppKit
import CoreText

enum MarkdownFormatType { case bold, italic, boldItalic, strikethrough, underline }
enum AppColors {
    static let nsTextEditorBackground = NSColor.textBackgroundColor
    static let nsEditorText = NSColor.textColor
    static let nsEditorCursor = NSColor.textColor
    static let nsCurrentLineHighlight = NSColor.controlBackgroundColor
}
enum ShortcutAction { case moveLineUp, moveLineDown, duplicateLineUp, duplicateLineDown, deleteWordBackward, deleteToLineStart, unrelated }
final class KeyboardShortcutManager {
    static let shared = KeyboardShortcutManager()
    func action(matching event: NSEvent) -> ShortcutAction? { nil }
}
final class TextUndoHistoryManager {
    static let shared = TextUndoHistoryManager()
    enum Area { case editor }
    func setFocusedArea(_ area: Area) {}
}
func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
    precondition(condition(), name)
    print("PASS \(name)")
}
let menuView = LoreTextView(editorState: EditorState(text: "menu"))
expect(menuView.responds(to: NSSelectorFromString("paste:")), "native paste selector")
expect(menuView.responds(to: NSSelectorFromString("copy:")), "native copy selector")
expect(menuView.responds(to: NSSelectorFromString("cut:")), "native cut selector")
menuView.selectAll(nil)
expect(menuView.editorState.copy() == "menu", "native select all")
let value = "😀e\u{301}한\n👨‍👩‍👧‍👦Z"
let document = TextDocument(text: value)
for line in 0..<document.lineCount {
    for column in 0...(document.getLine(line)?.count ?? 0) {
        let pos = TextPosition(line: line, column: column)
        expect(document.positionFromUTF16Offset(document.utf16Offset(from: pos)) == pos, "UTF16 roundtrip \(line):\(column)")
    }
}
expect("😀AB".characterOffset(atUTF16: 2) == 1, "emoji hit position")
expect("e\u{301}X".characterOffset(atUTF16: 1) == 0, "no split grapheme")
let state = EditorState(text: "original 😀")
state.selectAll()
state.insertText("replacement")
expect(state.getText() == "replacement", "selection replacement")
expect(state.undo() && state.getText() == "original 😀", "replacement single undo")
expect(state.redo() && state.getText() == "replacement", "replacement redo")
state.loadText("😀 alpha 😀 beta")
expect(state.find("😀", forward: true), "find emoji")
expect(state.selection.range.normalized.end.column == 1, "find Unicode selection")
state.execute(EditorCommand(.replace("😀", replacement: "별", all: true)))
expect(state.getText() == "별 alpha 별 beta", "replace all")
expect(state.undo() && state.getText() == "😀 alpha 😀 beta", "replace all single undo")
state.selection.moveCursor(line: 0, column: 999)
state.deleteBackward()
expect(state.getText() == "😀 alpha 😀 bet", "stale cursor clamped before delete")
state.selectAll()
state.execute(EditorCommand(.format(.bold)))
expect(state.getText() == "**😀 alpha 😀 bet**", "format selection")
expect(state.undo() && state.getText() == "😀 alpha 😀 bet", "format undo")
let second = EditorState(text: state.getText())
expect(!second.canUndo, "equal text independent document undo")
let combining = EditorState(text: "e")
combining.selection.moveCursor(line: 0, column: 1)
combining.insertText("\u{301}")
expect(combining.getText() == "e\u{301}" && combining.selection.cursor.column == 1, "combining insertion cursor")
expect(combining.undo() && combining.getText() == "e", "combining insertion undo")
combining.loadText("eX")
combining.selection.select(from: TextPosition(line: 0, column: 1), to: TextPosition(line: 0, column: 2))
combining.replaceSelection(with: "\u{301}")
expect(combining.getText() == "e\u{301}", "combining replacement")
expect(combining.undo() && combining.getText() == "eX", "combining replacement undo")
let renderer = LineRenderer(font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular))
let emojiLine = CTLineCreateWithAttributedString(NSAttributedString(string: "😀AB", attributes: [.font: renderer.font]))
let emojiEndX = CTLineGetOffsetForStringIndex(emojiLine, 2, nil)
expect(renderer.characterIndex(at: emojiEndX, in: "😀AB") == 1, "renderer emoji click")
let paragraph = String(repeating: "😀 word ", count: 30)
let beginning = renderer.caretRect(in: paragraph, column: 0, viewportWidth: 90)
let ending = renderer.caretRect(in: paragraph, column: paragraph.count, viewportWidth: 90)
expect(ending.minY > beginning.minY && ending.minX <= 90, "wrapped caret geometry")
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 200, pixelsHigh: 500, bitsPerSample: 8,
                             samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                             bytesPerRow: 0, bitsPerPixel: 0)!
let context = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
renderer.renderSelection(line: TextLine(content: paragraph), lineIndex: 0,
                         selection: TextRange(start: TextPosition(line: 0, column: 2), end: TextPosition(line: 0, column: 20)),
                         at: .zero, in: context, viewportWidth: 90)
renderer.renderComposition(before: "😀", marked: "한글", after: paragraph, at: .zero, in: context, viewportWidth: 90)
print("PASS wrapped selection and composition rendering")
let inputState = EditorState(text: "😀AB")
inputState.selection.moveCursor(line: 0, column: 1)
let inputView = LoreTextView(editorState: inputState)
expect(inputView.selectedRange().location == 2, "NSTextInputClient UTF16 cursor")
inputView.setMarkedText("한", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
expect(inputView.markedRange() == NSRange(location: 2, length: 1), "IME marked range")
expect(inputView.selectedRange().location == 3, "IME selection in marked text")
expect(inputView.attributedSubstring(forProposedRange: NSRange(location: 2, length: 1), actualRange: nil)?.string == "한", "IME composed substring")
inputView.commitMarkedTextSilently()
expect(inputState.getText() == "😀한AB", "IME flush commit")
inputView.insertText("Z", replacementRange: NSRange(location: 0, length: 2))
expect(inputState.getText() == "Z한AB", "NSTextInputClient replacement UTF16")
let editor = LoreEditorView(editorState: inputState)
editor.frame = CGRect(x: 0, y: 0, width: 300, height: 200)
editor.documentDidChange()
expect(editor.textView.yPosition(for: 0, viewportWidth: 200) == 0, "layout origins")
inputState.loadText("one\ntwo")
inputState.selection.moveCursor(line: 1, column: 0)
expect(inputView.performConfiguredShortcut(.moveLineUp) && inputState.getText() == "two\none", "configured move-line command")
expect(inputView.performConfiguredShortcut(.duplicateLineDown) && inputState.getText() == "two\ntwo\none", "configured duplicate command")
expect(!inputView.performConfiguredShortcut(.unrelated), "unrelated shortcut falls through")

let chunkDoc = TextDocument(text: (0..<1025).map { "line \($0) 한😀" }.joined(separator: "\n"))
let chunkOriginal = chunkDoc.getText()
let revisions = chunkDoc.chunkVersions
chunkDoc.insert("Z", atLine: 256, column: 0)
expect(chunkDoc.chunkVersions[0] == revisions[0] && chunkDoc.chunkVersions[2] == revisions[2], "unchanged chunks retain revision")
expect(chunkDoc.getText().components(separatedBy: "\n")[256] == "Zline 256 한😀", "serialized chunk updates")
chunkDoc.delete(fromLine: 256, column: 0, toLine: 256, column: 1)
expect(chunkDoc.getText() == chunkOriginal, "chunk serialization restores exact Unicode")
chunkDoc.insert("\nnew\n", atLine: 255, column: 2)
expect(chunkDoc.getText() == chunkDoc.lines.map { $0.content }.joined(separator: "\n"), "cross chunk insertion serialization")
chunkDoc.delete(fromLine: 254, column: 0, toLine: 770, column: 2)
expect(chunkDoc.getText() == chunkDoc.lines.map { $0.content }.joined(separator: "\n"), "cross chunk deletion serialization")
let chunkState = EditorState(text: (0..<800).map { $0 % 17 == 0 ? String(repeating: "한글😀 ", count: 40) : "short" }.joined(separator: "\n"))
let chunkView = LoreTextView(editorState: chunkState)
for width: CGFloat in [200, 350] {
    var expectedY: CGFloat = 0
    let referenceRenderer = LineRenderer(font: chunkState.configuration.font)
    referenceRenderer.lineHeightMultiple = chunkState.configuration.lineHeightMultiple
    for index in 0..<chunkState.document.lineCount {
        expect(chunkView.yPosition(for: index, viewportWidth: width) == expectedY, "chunk origin \(width):\(index)")
        expect(chunkView.lineIndex(atY: expectedY + 0.1, viewportWidth: width) == index, "height lookup \(width):\(index)")
        expectedY += referenceRenderer.calculateHeight(for: chunkState.document.getLineObject(index)!, viewportWidth: width)
    }
    expect(chunkView.totalContentHeight(viewportWidth: width) == expectedY, "exact wrapped total")
}
chunkState.document.insert("\n" + String(repeating: "long ", count: 100), atLine: 255, column: 0)
let boundaryY = chunkView.yPosition(for: 257, viewportWidth: 200)
expect(chunkView.lineIndex(atY: boundaryY, viewportWidth: 200) == 257, "layout rebuild after structural edit")

let resizeState = EditorState(text: String(repeating: "short 한😀\n", count: 10000))
let resizeView = LoreTextView(editorState: resizeState)
let narrowHeight = resizeView.totalContentHeight(viewportWidth: 400)
let measuredAtNarrow = resizeView.layoutMeasurementCount
expect(resizeView.totalContentHeight(viewportWidth: 700) == narrowHeight, "widening retains exact single-row heights")
expect(resizeView.layoutMeasurementCount == measuredAtNarrow, "widening avoids Core Text remeasurement")
_ = resizeView.totalContentHeight(viewportWidth: 400)
expect(resizeView.layoutMeasurementCount == measuredAtNarrow, "panel return restores cached layout")
resizeState.document.insert(String(repeating: "long ", count: 200), atLine: 300, column: 0)
let editedNarrowHeight = resizeView.totalContentHeight(viewportWidth: 400)
expect(editedNarrowHeight > narrowHeight, "cached width invalidates edited chunk")
_ = resizeView.totalContentHeight(viewportWidth: 700)
expect(resizeView.totalContentHeight(viewportWidth: 400) == editedNarrowHeight, "edited layout survives toggle roundtrip")
print("ALL TEXT ENGINE REGRESSIONS PASSED")
'''
with tempfile.TemporaryDirectory(prefix='lore-text-tests-') as directory:
    main = Path(directory) / 'main.swift'
    main.write_text(harness)
    executable = Path(directory) / 'test'
    subprocess.run(['swiftc', *map(str, sources), str(main), '-o', str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
