//
//  LoreEditorRepresentable.swift
//  Loreweave
//
//  LoreEditorView의 SwiftUI 래퍼
//

import SwiftUI

// MARK: - Lore Editor Representable

/// LoreEditorView를 SwiftUI에서 사용하기 위한 래퍼
struct LoreEditorRepresentable: NSViewRepresentable {
    @Binding var text: String
    @Binding var cursorLine: Int
    @Binding var cursorColumn: Int
    @Binding var selectedLineRange: ClosedRange<Int>?
    @Binding var externallyModifiedLines: Set<Int>

    let fontSize: CGFloat
    let fontName: String
    let lineHeightMultiple: CGFloat
    let letterSpacing: CGFloat
    let isEditable: Bool
    let initialCursorPosition: (line: Int, column: Int)?

    /// 탭 전환 시 현재 편집 중인 텍스트와 커서 위치를 부모에게 알리는 콜백
    /// (조합 중인 텍스트 확정 후의 최종 상태)
    var onContentWillChange: ((URL?, String, Int, Int) -> Void)?

    var documentID: UUID?
    var documentURL: URL?
    var editCommand: EditorCommand? = nil
    var contentRevision: UUID? = nil
    var isDocumentActive: ((UUID?, URL?, UUID?) -> Bool)? = nil

    func makeNSView(context: Context) -> LoreEditorView {
        let state = EditorState(text: text)
        let view = LoreEditorView(editorState: state)
        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.editorView = view
        coordinator.documentID = documentID
        coordinator.documentURL = documentURL
        coordinator.contentRevision = contentRevision
        if let documentID { coordinator.states[documentID] = state }
        configure(state)
        if let position = initialCursorPosition {
            state.selection.moveCursor(to: state.selection.clampPosition(
                TextPosition(line: position.line, column: position.column), in: state.document))
        }
        view.textView.onTextChange = { [weak coordinator] value in
            guard let coordinator, let view = coordinator.editorView else { return }
            let id = coordinator.documentID
            let revision = coordinator.contentRevision
            coordinator.pendingText = value
            let position = view.editorState.selection.cursor
            coordinator.parent.onContentWillChange?(coordinator.documentURL, value, position.line, position.column)
            DispatchQueue.main.async { [weak coordinator] in
                guard let coordinator, coordinator.documentID == id,
                      coordinator.parent.documentID == id,
                      coordinator.contentRevision == revision,
                      coordinator.parent.isDocumentActive?(id, coordinator.documentURL, revision) ?? true else { return }
                coordinator.parent.text = value
            }
        }
        view.textView.onCursorChange = { [weak coordinator] line, range in
            guard let coordinator, let view = coordinator.editorView else { return }
            let id = coordinator.documentID
            let revision = coordinator.contentRevision
            let column = view.editorState.selection.cursor.column
            DispatchQueue.main.async { [weak coordinator] in
                guard let coordinator, coordinator.documentID == id,
                      coordinator.parent.documentID == id,
                      coordinator.contentRevision == revision,
                      coordinator.parent.isDocumentActive?(id, coordinator.documentURL, revision) ?? true else { return }
                coordinator.parent.cursorLine = line
                coordinator.parent.cursorColumn = column
                coordinator.parent.selectedLineRange = range
            }
        }
        coordinator.flushObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("editorWillPerformFileOperation"), object: nil, queue: .main
        ) { [weak coordinator] _ in
            guard let coordinator, let view = coordinator.editorView else { return }
            view.textView.commitMarkedTextSilently()
            let position = view.editorState.selection.cursor
            let value = view.editorState.getText()
            coordinator.pendingText = value
            if view.editorState.isEditable {
                coordinator.parent.onContentWillChange?(coordinator.documentURL, value, position.line, position.column)
            }
            if coordinator.parent.isDocumentActive?(coordinator.documentID, coordinator.documentURL, coordinator.contentRevision) ?? true {
                coordinator.parent.text = value
            }
        }
        view.startObservingScroll()
        DispatchQueue.main.async { [weak view, weak coordinator] in
            guard let coordinator, coordinator.parent.isDocumentActive?(coordinator.documentID, coordinator.documentURL, coordinator.contentRevision) ?? true else { return }
            view?.scrollToLine(state.selection.cursor.line)
            view?.focus()
        }
        return view
    }

    func updateNSView(_ view: LoreEditorView, context: Context) {
        // A SwiftUI update can still describe the old document while its parent is loading
        // the next one. Do not consume commands or reload an obsolete presentation.
        guard isDocumentActive?(documentID, documentURL, contentRevision) ?? true else { return }
        let coordinator = context.coordinator
        let changedDocument = coordinator.documentID != documentID
        if coordinator.contentRevision != contentRevision { coordinator.pendingText = nil }
        if coordinator.pendingText == text { coordinator.pendingText = nil }
        if changedDocument {
            coordinator.pendingText = nil
            view.textView.commitMarkedTextSilently()
            let oldState = view.editorState
            let position = oldState.selection.cursor
            if oldState.isEditable {
                onContentWillChange?(coordinator.documentURL, oldState.getText(), position.line, position.column)
            }
            view.textView.discardMarkedText()
            let next = documentID.flatMap { coordinator.states[$0] } ?? EditorState(text: text)
            if next.getText() != text { next.loadText(text) }
            if let documentID { coordinator.states[documentID] = next }
            if let position = initialCursorPosition {
                next.selection.moveCursor(to: next.selection.clampPosition(
                    TextPosition(line: position.line, column: position.column), in: next.document))
            }
            coordinator.documentID = documentID
            coordinator.documentURL = documentURL
            view.editorState = next
            view.textView.resetInputContext()
        } else if coordinator.pendingText == nil && view.editorState.getText() != text {
            // A new disk revision or a parent-issued replacement invalidates old undo offsets.
            let position = view.editorState.selection.cursor
            view.editorState.loadText(text)
            view.editorState.selection.moveCursor(to: view.editorState.selection.clampPosition(position, in: view.editorState.document))
        }
        coordinator.parent = self
        coordinator.documentURL = documentURL
        coordinator.contentRevision = contentRevision
        configure(view.editorState)
        view.editorState.externallyModifiedLines = externallyModifiedLines
        if let command = editCommand, command.id != coordinator.lastCommandID {
            coordinator.lastCommandID = command.id
            view.textView.commitMarkedTextIfNeeded()
            view.textView.performEditorCommand(command)
        }
        view.documentDidChange()
        if changedDocument {
            let id = documentID
            let revision = contentRevision
            DispatchQueue.main.async { [weak view, weak coordinator] in
                guard let view, let coordinator, coordinator.documentID == id,
                      coordinator.contentRevision == revision,
                      coordinator.parent.isDocumentActive?(id, coordinator.documentURL, revision) ?? true else { return }
                view.scrollToLine(view.editorState.selection.cursor.line)
                view.cursorDidChange()
                coordinator.parent.cursorLine = view.editorState.selection.cursor.line + 1
                coordinator.parent.cursorColumn = view.editorState.selection.cursor.column
                coordinator.parent.selectedLineRange = view.editorState.selection.selectedLineRange.map { ($0.lowerBound + 1)...($0.upperBound + 1) }
                view.focus()
            }
        }
    }

    private func configure(_ state: EditorState) {
        var config = state.configuration
        config.fontSize = fontSize
        config.fontName = fontName
        config.lineHeightMultiple = lineHeightMultiple
        config.letterSpacing = letterSpacing
        state.configuration = config
        state.isEditable = isEditable
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    class Coordinator {
        var parent: LoreEditorRepresentable
        weak var editorView: LoreEditorView?
        var documentID: UUID?
        var documentURL: URL?
        var contentRevision: UUID?
        var states: [UUID: EditorState] = [:]
        var pendingText: String?
        var flushObserver: NSObjectProtocol?
        deinit { if let flushObserver { NotificationCenter.default.removeObserver(flushObserver) } }
        var lastCommandID: UUID?
        init(parent: LoreEditorRepresentable) { self.parent = parent }
    }
}

// MARK: - Preview

#Preview {
    LoreEditorRepresentable(
        text: .constant("# Hello, World!\n\nThis is a test.\nLine 4\nLine 5\n\n한글 테스트입니다.\n긴 텍스트 테스트입니다."),
        cursorLine: .constant(1),
        cursorColumn: .constant(0),
        selectedLineRange: .constant(nil),
        externallyModifiedLines: .constant([3, 4]),
        fontSize: 14,
        fontName: "SF Pro",
        lineHeightMultiple: 1.5,
        letterSpacing: 0,
        isEditable: true,
        initialCursorPosition: nil,
        onContentWillChange: { _, _, _, _ in },
        documentID: nil,
        documentURL: nil
    )
    .frame(width: 600, height: 400)
}
