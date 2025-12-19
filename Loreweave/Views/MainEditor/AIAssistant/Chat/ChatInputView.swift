//
//  ChatInputView.swift
//  Loreweave
//
//  채팅 입력 영역 뷰
//

import SwiftUI

struct ChatInputView: View {
    @Binding var inputText: String
    let isProcessing: Bool
    let onSend: () -> Void
    let onCancel: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(alignment: .bottom, spacing: 8) {
                // 텍스트 입력 필드
                TextField(L10n.get("ai.chat.inputPlaceholder"), text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .padding(10)
                    .background(AppColors.controlBackground)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isFocused ? AppColors.accent : AppColors.controlBorder, lineWidth: 1)
                    )
                    .focused($isFocused)
                    .onSubmit {
                        if !inputText.isEmpty && !isProcessing {
                            onSend()
                        }
                    }

                // 전송/취소 버튼
                if isProcessing {
                    Button(action: onCancel) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help(L10n.get("ai.chat.cancel"))
                } else {
                    Button(action: onSend) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(inputText.isEmpty ? AppColors.textTertiary : AppColors.accent)
                    }
                    .buttonStyle(.plain)
                    .disabled(inputText.isEmpty)
                    .help(L10n.get("ai.chat.send"))
                }
            }
            .padding(12)
        }
    }
}

#Preview {
    VStack {
        Spacer()
        ChatInputView(
            inputText: .constant(""),
            isProcessing: false,
            onSend: {},
            onCancel: {}
        )
    }
    .frame(width: 350, height: 200)
}
