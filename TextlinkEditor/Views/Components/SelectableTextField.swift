//
//  SelectableTextField.swift
//  TextlinkEditor
//
//  텍스트 선택 범위를 지정할 수 있는 NSTextField 래퍼
//

import SwiftUI
import AppKit

/// 초기 텍스트 선택 범위를 지정할 수 있는 텍스트 필드
struct SelectableTextField: NSViewRepresentable {
    @Binding var text: String
    /// 선택할 텍스트 범위 (문자 인덱스)
    var selectRange: Range<Int>
    /// 엔터 키 입력 시 호출
    var onCommit: () -> Void
    /// ESC 키 입력 시 호출
    var onCancel: () -> Void
    /// 포커스를 잃었을 때 호출 (외부 클릭 시)
    var onFocusLost: (() -> Void)?

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.delegate = context.coordinator
        textField.stringValue = text
        textField.font = NSFont.systemFont(ofSize: 12)
        textField.isBordered = true
        textField.bezelStyle = .roundedBezel
        textField.focusRingType = .exterior
        textField.backgroundColor = NSColor.controlBackgroundColor

        // 초기 선택 범위 설정 및 포커스
        DispatchQueue.main.async {
            textField.window?.makeFirstResponder(textField)
            if let fieldEditor = textField.window?.fieldEditor(true, for: textField) as? NSTextView {
                fieldEditor.selectedRange = NSRange(
                    location: selectRange.lowerBound,
                    length: selectRange.count
                )
            }
        }

        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SelectableTextField

        init(_ parent: SelectableTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField else { return }
            parent.text = textField.stringValue
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            // 포커스를 잃었을 때 (외부 클릭 등)
            parent.onFocusLost?()
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                // Enter 키
                parent.onCommit()
                return true
            } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                // ESC 키
                parent.onCancel()
                return true
            }
            return false
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        SelectableTextField(
            text: .constant("example.txt"),
            selectRange: 0..<7,
            onCommit: { print("Commit") },
            onCancel: { print("Cancel") }
        )
        .frame(width: 200)
    }
    .padding(40)
}
