#!/usr/bin/env python3
"""Execute the production representable body with a constructible Context shim.

SwiftUI does not expose NSViewRepresentable.Context's initializer. Only conformance
and Context construction are replaced; make/update/coordinator/callback bodies are
read from production unchanged. This is not a SwiftUI scheduling/UI test.
"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
engine = root / 'Loreweave/Services/Editor/TextEngine'
views = root / 'Loreweave/Views/MainEditor/EditorPanel/LoreTextView'
sources = [engine / name for name in ['TextDocument.swift', 'TextSelection.swift', 'ViewportManager.swift', 'EditorState.swift', 'EditorCommand.swift']]
sources += sorted((engine / 'EditorState').glob('*.swift'))
sources += [views / name for name in ['LineRenderer.swift', 'LoreTextView.swift', 'LoreEditorView.swift', 'GutterView.swift']]
representable = (views / 'LoreEditorRepresentable.swift').read_text().split('// MARK: - Preview')[0]
representable = representable.replace('struct LoreEditorRepresentable: NSViewRepresentable {', 'struct LoreEditorRepresentable {\n    struct Context { let coordinator: Coordinator }')
harness = r'''
import Foundation
import AppKit
import SwiftUI

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
final class Box<T> { var value: T; init(_ value: T) { self.value = value } }
func binding<T>(_ box: Box<T>) -> Binding<T> { Binding(get: { box.value }, set: { box.value = $0 }) }
func expect(_ condition: @autoclosure () -> Bool, _ name: String) { precondition(condition(), name); print("PASS \(name)") }
func drain() { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
let content = Box("same")
let cursorLine = Box(1)
let cursorColumn = Box(0)
let selected = Box<ClosedRange<Int>?>(nil)
let modified = Box<Set<Int>>([])
let a = UUID(), b = UUID()
let urlA = URL(fileURLWithPath: "/tmp/a.md"), urlB = URL(fileURLWithPath: "/tmp/b.md")
var cache: [URL: String] = [:]
let active = Box<(UUID, URL)>((a, urlA))
let revision = Box(UUID())
func parent(_ id: UUID, _ url: URL) -> LoreEditorRepresentable {
    LoreEditorRepresentable(text: binding(content), cursorLine: binding(cursorLine), cursorColumn: binding(cursorColumn),
        selectedLineRange: binding(selected), externallyModifiedLines: binding(modified),
        fontSize: 14, fontName: "Menlo", lineHeightMultiple: 1.5, letterSpacing: 0,
        isEditable: true, initialCursorPosition: nil,
        onContentWillChange: { url, value, _, _ in if let url { cache[url] = value } },
        documentID: id, documentURL: url,
        contentRevision: revision.value,
        isDocumentActive: { id, url, expectedRevision in active.value.0 == id && active.value.1 == url && revision.value == expectedRevision })
}
var p = parent(a, urlA)
let coordinator = p.makeCoordinator()
let context = LoreEditorRepresentable.Context(coordinator: coordinator)
let view = p.makeNSView(context: context)
drain()
view.textView.insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0))
expect(cache[urlA] == view.editorState.getText(), "typing updates owner cache synchronously")
drain()
p.updateNSView(view, context: context)
expect(view.editorState.canUndo, "A records undo")
let aText = content.value
content.value = aText
active.value = (b, urlB)
p = parent(b, urlB)
p.updateNSView(view, context: context)
drain()
expect(!view.editorState.canUndo, "same text B has independent undo")
active.value = (a, urlA)
p = parent(a, urlA)
p.updateNSView(view, context: context)
drain()
expect(view.editorState.canUndo && view.editorState.undo(), "A undo retained after B")
expect(view.editorState.getText() == "same", "A undo restores own text")
content.value = view.editorState.getText()
let renamed = URL(fileURLWithPath: "/tmp/renamed.md")
active.value = (a, renamed)
p = parent(a, renamed)
p.updateNSView(view, context: context)
expect(view.editorState.canRedo, "same UUID rename preserves redo")
view.textView.setMarkedText("한", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
NotificationCenter.default.post(name: Notification.Name("editorWillPerformFileOperation"), object: nil)
expect(cache[renamed] == view.editorState.getText() && content.value.contains("한"), "flush owns renamed document")
drain()
p.updateNSView(view, context: context)

// Model the scheduling gap between the parent loading B and updateNSView observing B.
view.textView.insertText("queued-A", replacementRange: NSRange(location: NSNotFound, length: 0))
active.value = (b, urlB)
content.value = "B disk content"
let next = parent(b, urlB)
var obsolete = parent(a, renamed)
obsolete.editCommand = EditorCommand(.replace("queued-A", replacement: "WRONG", all: true))
obsolete.updateNSView(view, context: context)
expect(view.editorState.getText().contains("queued-A"), "obsolete presentation cannot consume editor command")
drain()
expect(content.value == "B disk content", "pending A callback cannot replace B binding")
NotificationCenter.default.post(name: Notification.Name("editorWillPerformFileOperation"), object: nil)
expect(content.value == "B disk content", "old document flush cannot replace B binding")
expect(cache[renamed]?.contains("queued-A") == true, "old document flush still preserves A cache")
next.updateNSView(view, context: context)
drain()
view.textView.insertText("queued-B", replacementRange: NSRange(location: NSNotFound, length: 0))
revision.value = UUID()
content.value = "B external revision"
drain()
expect(content.value == "B external revision", "queued same-document callback cannot replace external revision")
let reloaded = parent(b, urlB)
reloaded.updateNSView(view, context: context)
expect(view.editorState.getText() == "B external revision", "external revision clears pending buffer")
expect(!view.editorState.canUndo, "external revision invalidates obsolete undo")
// A failed read presents a disabled empty state but must never become a saved draft.
var invalid = parent(b, urlB)
invalid = LoreEditorRepresentable(text: binding(content), cursorLine: binding(cursorLine), cursorColumn: binding(cursorColumn),
    selectedLineRange: binding(selected), externallyModifiedLines: binding(modified),
    fontSize: 14, fontName: "Menlo", lineHeightMultiple: 1.5, letterSpacing: 0,
    isEditable: false, initialCursorPosition: nil,
    onContentWillChange: { url, value, _, _ in if let url { cache[url] = value } },
    documentID: b, documentURL: urlB, contentRevision: revision.value,
    isDocumentActive: { id, url, expectedRevision in active.value.0 == id && active.value.1 == url && revision.value == expectedRevision })
invalid.updateNSView(view, context: context)
cache[urlB] = "preserved read baseline"
NotificationCenter.default.post(name: Notification.Name("editorWillPerformFileOperation"), object: nil)
expect(cache[urlB] == "preserved read baseline", "read-failure flush cannot overwrite cache")
active.value = (a, urlA)
content.value = "same"
parent(a, urlA).updateNSView(view, context: context)
expect(cache[urlB] == "preserved read baseline", "leaving read-failure document cannot overwrite cache")
print("EDITOR BINDING REGRESSION COMPLETED")
'''
with tempfile.TemporaryDirectory(prefix='lore-binding-tests-') as directory:
    directory = Path(directory)
    adapter = directory / 'Representable.swift'
    adapter.write_text(representable)
    main = directory / 'main.swift'
    main.write_text(harness)
    executable = directory / 'test'
    subprocess.run(['swiftc', *map(str, sources), str(adapter), str(main), '-o', str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
