//
//  TextlinkEditorRepresentable.swift
//  TextlinkEditor
//
//  TextlinkEditorView의 SwiftUI 래퍼
//

import SwiftUI

// MARK: - Lore Editor Representable

/// TextlinkEditorView를 SwiftUI에서 사용하기 위한 래퍼
struct TextlinkEditorRepresentable: NSViewRepresentable {
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

    var openDocumentIDs: Set<UUID>? = nil

    func makeNSView(context: Context) -> NativeManuscriptHost {
        let coordinator = context.coordinator
        let native = NativeManuscriptTextView()
        native.load(text)
        configure(native)
        let host = NativeManuscriptHost(textView: native)
        coordinator.host = host
        coordinator.documentID = documentID
        coordinator.documentURL = documentURL
        coordinator.contentRevision = contentRevision
        if let documentID { coordinator.editors[documentID] = native }
        native.delegate = coordinator
        if let position = initialCursorPosition {
            native.setSelectedRange(NSRange(location: native.offset(line: position.line, column: position.column), length: 0))
        }
        coordinator.flushObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("editorWillPerformFileOperation"), object: nil, queue: .main
        ) { [weak coordinator] notification in
            guard let coordinator else { return }
            coordinator.flush()
            guard coordinator.parent.isDocumentActive?(coordinator.documentID, coordinator.documentURL, coordinator.contentRevision) ?? true,
                  let native = coordinator.host?.textView, native.isEditable else { return }
            if let capture = notification.userInfo?["captureSelection"] as? (String, NSRange) -> Void {
                capture(native.string, native.selectedRange())
            }
            if let apply = notification.userInfo?["applyRevision"] as? (String, NSRange) -> String?,
               let value = apply(native.string, native.selectedRange()) {
                native.replace(NSRange(location: 0, length: (native.string as NSString).length), with: value)
                coordinator.flush()
            }
        }
        coordinator.focusAndPublish()
        return host
    }

    func updateNSView(_ host: NativeManuscriptHost, context: Context) {
        guard isDocumentActive?(documentID, documentURL, contentRevision) ?? true else { return }
        let coordinator = context.coordinator
        let changed = coordinator.documentID != documentID
        if let openDocumentIDs { coordinator.editors = coordinator.editors.filter { openDocumentIDs.contains($0.key) } }
        if coordinator.contentRevision != contentRevision { coordinator.pendingText = nil }
        if coordinator.pendingText == text { coordinator.pendingText = nil }
        coordinator.isUpdating = true
        defer { coordinator.isUpdating = false }
        if changed {
            coordinator.flush()
            host.textView.delegate = nil
            let native = documentID.flatMap { coordinator.editors[$0] } ?? NativeManuscriptTextView()
            if native.string != text { native.load(text) }
            if let documentID { coordinator.editors[documentID] = native }
            if let position = initialCursorPosition {
                native.setSelectedRange(NSRange(location: native.offset(line: position.line, column: position.column), length: 0))
            }
            host.documentView = native
            native.frame.size.width = host.contentSize.width
            native.delegate = coordinator
            coordinator.pendingText = nil
        } else if coordinator.pendingText == nil && host.textView.string != text {
            let selection = host.textView.selectedRange()
            host.textView.load(text)
            host.textView.setSelectedRange(NSRange(location: min(selection.location, (text as NSString).length), length: 0))
        }
        coordinator.parent = self
        coordinator.documentID = documentID
        coordinator.documentURL = documentURL
        coordinator.contentRevision = contentRevision
        configure(host.textView)
        host.textView.modifiedLines = externallyModifiedLines
        host.verticalRulerView?.needsDisplay = true
        if let command = editCommand, coordinator.lastCommandID != command.id {
            coordinator.lastCommandID = command.id
            coordinator.isUpdating = false
            host.textView.execute(command)
            coordinator.isUpdating = true
        }
        if changed { coordinator.focusAndPublish() }
    }

    private func configure(_ view: NativeManuscriptTextView) {
        view.isEditable = isEditable
        view.isSelectable = true
        let key = "\(fontName)|\(fontSize)|\(lineHeightMultiple)|\(letterSpacing)"
        guard key != view.styleKey else { return }
        view.styleKey = key
        let font = NSFont(name: fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = lineHeightMultiple
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: paragraph,
            .kern: letterSpacing, .foregroundColor: AppColors.nsEditorText]
        view.typingAttributes = attributes
        view.defaultParagraphStyle = paragraph
        view.textStorage?.setAttributes(attributes, range: NSRange(location: 0, length: (view.string as NSString).length))
        view.font = font
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TextlinkEditorRepresentable
        weak var host: NativeManuscriptHost?
        var documentID: UUID?
        var documentURL: URL?
        var contentRevision: UUID?
        var editors: [UUID: NativeManuscriptTextView] = [:]
        var pendingText: String?
        var flushObserver: NSObjectProtocol?
        var lastCommandID: UUID?
        var isUpdating = false
        deinit { if let flushObserver { NotificationCenter.default.removeObserver(flushObserver) } }
        init(parent: TextlinkEditorRepresentable) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating, let native = notification.object as? NativeManuscriptTextView,
                  native === host?.textView else { return }
            native.rebuildLineIndex()
            publishText(native)
        }
        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isUpdating else { return }
            publishSelection()
        }
        func flush() {
            guard let native = host?.textView else { return }
            native.commitComposition()
            native.rebuildLineIndex()
            guard native.isEditable else { return }
            publishText(native)
            if parent.isDocumentActive?(documentID, documentURL, contentRevision) ?? true { parent.text = native.string }
        }
        private func publishText(_ native: NativeManuscriptTextView) {
            let value = native.string
            let position = native.position(at: native.selectedRange().location)
            pendingText = value
            parent.onContentWillChange?(documentURL, value, position.line, position.column)
            let id = documentID, url = documentURL, revision = contentRevision
            DispatchQueue.main.async { [weak self] in
                guard let self, self.documentID == id, self.contentRevision == revision,
                      self.parent.isDocumentActive?(id, url, revision) ?? true else { return }
                self.parent.text = value
            }
            publishSelection()
        }
        private func publishSelection() {
            guard let native = host?.textView else { return }
            let range = native.selectedRange()
            let position = native.position(at: range.location)
            let selected = range.length == 0 ? nil : (position.line + 1)...(native.line(at: NSMaxRange(range)) + 1)
            let id = documentID, url = documentURL, revision = contentRevision
            DispatchQueue.main.async { [weak self] in
                guard let self, self.documentID == id, self.contentRevision == revision,
                      self.parent.isDocumentActive?(id, url, revision) ?? true else { return }
                self.parent.cursorLine = position.line + 1
                self.parent.cursorColumn = position.column
                self.parent.selectedLineRange = selected
            }
        }
        func focusAndPublish() {
            let id = documentID, revision = contentRevision
            DispatchQueue.main.async { [weak self] in
                guard let self, self.documentID == id, self.contentRevision == revision,
                      self.parent.isDocumentActive?(id, self.documentURL, revision) ?? true,
                      let native = self.host?.textView else { return }
                native.scrollRangeToVisible(native.selectedRange())
                native.window?.makeFirstResponder(native)
                self.publishSelection()
            }
        }
    }
}

// MARK: - Preview

#Preview {
    TextlinkEditorRepresentable(
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
