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
    @Binding var selectedLineRange: ClosedRange<Int>?

    let fontSize: CGFloat
    let fontName: String
    let lineHeightMultiple: CGFloat
    let letterSpacing: CGFloat
    let isEditable: Bool

    // MARK: - NSViewRepresentable

    func makeNSView(context: Context) -> LoreEditorView {
        var config = EditorConfiguration()
        config.fontSize = fontSize
        config.fontName = fontName
        config.lineHeightMultiple = lineHeightMultiple
        config.letterSpacing = letterSpacing

        let state = EditorState(text: text, configuration: config)
        state.isEditable = isEditable

        let editorView = LoreEditorView(editorState: state)

        // 콜백 설정
        editorView.textView.onTextChange = { newText in
            DispatchQueue.main.async {
                context.coordinator.isUpdating = true
                text = newText
                context.coordinator.isUpdating = false
            }
        }

        editorView.textView.onCursorChange = { line, range in
            DispatchQueue.main.async {
                cursorLine = line
                selectedLineRange = range
            }
        }

        context.coordinator.editorView = editorView
        context.coordinator.editorState = state

        return editorView
    }

    func updateNSView(_ editorView: LoreEditorView, context: Context) {
        guard let state = context.coordinator.editorState else { return }

        // 업데이트 중복 방지
        guard !context.coordinator.isUpdating else { return }

        // 설정 변경 확인
        var configChanged = false

        if state.configuration.fontSize != fontSize {
            state.setFontSize(fontSize)
            configChanged = true
        }

        if state.configuration.lineHeightMultiple != lineHeightMultiple {
            state.setLineHeightMultiple(lineHeightMultiple)
            configChanged = true
        }

        if state.configuration.fontName != fontName {
            state.setFontName(fontName)
            configChanged = true
        }

        if state.configuration.letterSpacing != letterSpacing {
            state.setLetterSpacing(letterSpacing)
            configChanged = true
        }

        if state.isEditable != isEditable {
            state.isEditable = isEditable
        }

        // 텍스트 동기화 (외부에서 변경된 경우)
        let currentText = state.getText()
        if currentText != text {
            context.coordinator.isUpdating = true
            state.loadText(text)
            editorView.documentDidChange()
            context.coordinator.isUpdating = false
        }

        // 설정 변경 시 갱신
        if configChanged {
            editorView.refreshState()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: - Coordinator

    class Coordinator {
        weak var editorView: LoreEditorView?
        weak var editorState: EditorState?
        var isUpdating: Bool = false
    }
}

// MARK: - Preview

#Preview {
    LoreEditorRepresentable(
        text: .constant("# Hello, World!\n\nThis is a test.\nLine 4\nLine 5\n\n한글 테스트입니다.\n긴 텍스트 테스트입니다."),
        cursorLine: .constant(1),
        selectedLineRange: .constant(nil),
        fontSize: 14,
        fontName: "SF Pro",
        lineHeightMultiple: 1.5,
        letterSpacing: 0,
        isEditable: true
    )
    .frame(width: 600, height: 400)
}
