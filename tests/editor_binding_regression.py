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
engine = root / 'TextlinkEditor/Services/Editor/TextEngine'
views = root / 'TextlinkEditor/Views/MainEditor/EditorPanel/TextlinkTextView'
sources = [engine / name for name in ['TextDocument.swift', 'TextSelection.swift', 'ViewportManager.swift', 'EditorState.swift', 'EditorCommand.swift']]
sources += sorted((engine / 'EditorState').glob('*.swift'))
sources += [root / 'TextlinkEditor/Services/Core/EditorToolRegistry.swift']
sources += [views / 'PreparedManuscript.swift', views / 'EditorToolBridge.swift', views / 'NativeManuscriptView.swift']
representable = (views / 'TextlinkEditorRepresentable.swift').read_text().split('// MARK: - Preview')[0]
representable = representable.replace('struct TextlinkEditorRepresentable: NSViewRepresentable {', 'struct TextlinkEditorRepresentable {\n    struct Context { let coordinator: Coordinator }')
harness = r'''
import Foundation
import AppKit
import SwiftUI

enum L10n { static func get(_ key: String) -> String { key } }
enum MarkdownFormatType { case bold, italic, boldItalic, strikethrough, underline }
enum AppColors {
    static let nsTextEditorBackground = NSColor.textBackgroundColor
    static let nsEditorText = NSColor.textColor
    static let nsEditorCursor = NSColor.textColor
    static let nsCurrentLineHighlight = NSColor.controlBackgroundColor
}
enum ShortcutAction {
    case moveLineUp, moveLineDown, duplicateLineUp, duplicateLineDown, deleteWordBackward, deleteToLineStart, unrelated, inline
    var rawValue: String { self == .inline ? "ai.inline" : String(describing: self) }
}
final class KeyboardShortcutManager {
    static let shared = KeyboardShortcutManager()
    func action(matching event: NSEvent) -> ShortcutAction? {
        event.keyCode == 34 && event.modifierFlags.intersection([.command, .option, .shift, .control]) == [.command, .option] ? .inline : nil
    }
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
func parent(_ id: UUID, _ url: URL, editable: Bool = true, position: (line: Int, column: Int)? = nil) -> TextlinkEditorRepresentable {
    TextlinkEditorRepresentable(text: binding(content), cursorLine: binding(cursorLine), cursorColumn: binding(cursorColumn),
        selectedLineRange: binding(selected), externallyModifiedLines: binding(modified),
        fontSize: 14, fontName: "Menlo", lineHeightMultiple: 1.5, letterSpacing: 0,
        isEditable: editable, initialCursorPosition: position,
        onContentWillChange: { url, value, _, _ in if let url { cache[url] = value } },
        documentID: id, documentURL: url,
        contentRevision: revision.value,
        isDocumentActive: { id, url, expectedRevision in active.value.0 == id && active.value.1 == url && revision.value == expectedRevision })
}
var p = parent(a, urlA)
let coordinator = p.makeCoordinator()
let context = TextlinkEditorRepresentable.Context(coordinator: coordinator)
let view = p.makeNSView(context: context)
drain()
view.textView.insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0))
expect(cache[urlA] == view.textView.string, "typing updates owner cache synchronously")
drain()
p.updateNSView(view, context: context)
expect(view.textView.undoManager!.canUndo, "A records undo")
let aText = content.value
content.value = aText
active.value = (b, urlB)
p = parent(b, urlB)
p.updateNSView(view, context: context)
drain()
expect(!view.textView.undoManager!.canUndo, "same text B has independent undo")
active.value = (a, urlA)
p = parent(a, urlA)
p.updateNSView(view, context: context)
drain()
expect(view.textView.undoManager!.canUndo, "A undo retained after B")
view.textView.undoManager!.undo()
expect(view.textView.string == "same", "A undo restores own text")
content.value = view.textView.string
let renamed = URL(fileURLWithPath: "/tmp/renamed.md")
active.value = (a, renamed)
p = parent(a, renamed)
p.updateNSView(view, context: context)
expect(view.textView.undoManager!.canRedo, "same UUID rename preserves redo")
view.textView.setMarkedText("한", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
NotificationCenter.default.post(name: Notification.Name("editorWillPerformFileOperation"), object: nil)
expect(cache[renamed] == view.textView.string && content.value.contains("한"), "flush owns renamed document")
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
expect(view.textView.string.contains("queued-A"), "obsolete presentation cannot consume editor command")
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
expect(view.textView.string == "B external revision", "external revision clears pending buffer")
expect(!view.textView.undoManager!.canUndo, "external revision invalidates obsolete undo")
// A failed read presents a disabled empty state but must never become a saved draft.
var invalid = parent(b, urlB)
invalid = TextlinkEditorRepresentable(text: binding(content), cursorLine: binding(cursorLine), cursorColumn: binding(cursorColumn),
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
view.textView.setSelectedRange(NSRange(location: 0, length: 2))
drain()
expect(selected.value == 1...1, "native selection publishes status range")
var captured: String?
let capture: (String, NSRange) -> Void = { text, range in captured = (text as NSString).substring(with: range) }
NotificationCenter.default.post(name: Notification.Name("editorWillPerformFileOperation"), object: nil, userInfo: ["captureSelection": capture])
expect(captured == "sa", "AI capture preserves selected manuscript range")
let original = view.textView.string
let apply: (String, NSRange) -> String? = { text, _ in text == original ? "AI proposal" : nil }
NotificationCenter.default.post(name: Notification.Name("editorWillPerformFileOperation"), object: nil, userInfo: ["applyRevision": apply])
expect(view.textView.string == "AI proposal" && cache[urlA] == "AI proposal", "AI apply updates actual native editor and owner cache")
view.textView.undo(nil)
expect(view.textView.string == original, "AI application is native Undo operation")
var staleInvoked = false
let staleCapture: (String, NSRange) -> Void = { _, _ in staleInvoked = true }
active.value = (b, urlB)
NotificationCenter.default.post(name: Notification.Name("editorWillPerformFileOperation"), object: nil, userInfo: ["captureSelection": staleCapture])
expect(!staleInvoked, "inactive presentation cannot capture another manuscript")
active.value = (b, urlB)
content.value = ""
let loading = parent(b, urlB, editable: false)
loading.updateNSView(view, context: context)
revision.value = UUID()
content.value = "first\nsecond\nlast"
let loaded = parent(b, urlB, position: (line: 2, column: 2))
loaded.updateNSView(view, context: context)
drain()
expect(view.textView.selectedRange().location == 15, "asynchronous loading restores remembered cursor")
expect(cursorLine.value == 3 && cursorColumn.value == 2, "loaded cursor publishes native position")
expect(view.textView.textLayoutManager != nil, "tab switching and AI edits retain TextKit 2")

// Count actual NSTextView snapshots: geometry-only updates must not read the
// complete document. The temporary test source only removes `final` to observe it.
final class SnapshotCountingView: NativeManuscriptTextView {
    var snapshotReads = 0
    override var string: String {
        get { snapshotReads += 1; return super.string }
        set { super.string = newValue }
    }
}
let counting = SnapshotCountingView()
content.value = String(repeating: "한글 장편 😀 폭 변경 검증 문장입니다.\n", count: 100000)
counting.load(content.value)
view.textView.delegate = nil
view.documentView = counting
counting.delegate = coordinator
coordinator.editors[b] = counting
parent(b, urlB).updateNSView(view, context: context)
drain()
counting.snapshotReads = 0
for _ in 0..<100 { parent(b, urlB).updateNSView(view, context: context) }
expect(counting.snapshotReads == 0, "100 geometry-only updates take no whole-document snapshots")
content.value = "external replacement without a new revision"
parent(b, urlB).updateNSView(view, context: context)
expect(counting.string == content.value, "changed binding without revision still replaces native text")
counting.insertText("native ", replacementRange: NSRange(location: 0, length: 0))
drain()
parent(b, urlB).updateNSView(view, context: context)
expect(counting.string == content.value && counting.undoManager!.canUndo, "native publication retains text and undo with snapshot guard")
print("EDITOR BINDING REGRESSION COMPLETED")
'''
with tempfile.TemporaryDirectory(prefix='lore-binding-tests-') as directory:
    directory = Path(directory)
    adapter = directory / 'Representable.swift'
    adapter.write_text(representable)
    observable_native = directory / 'NativeManuscriptView.swift'
    observable_native.write_text((views / 'NativeManuscriptView.swift').read_text().replace(
        'final class NativeManuscriptTextView:', 'class NativeManuscriptTextView:', 1))
    sources = [observable_native if path.name == 'NativeManuscriptView.swift' else path for path in sources]
    main = directory / 'main.swift'
    main.write_text(harness)
    executable = directory / 'test'
    subprocess.run(['swiftc', *map(str, sources), str(adapter), str(main), '-o', str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
