//
//  AIChatView.swift
//  Loreweave
//
//  AI 채팅 메인 뷰
//

import SwiftUI

struct AIChatView: View {
    let cliType: AICLIType
    @Binding var messages: [AIMessage]
    @Binding var inputText: String
    let isProcessing: Bool
    let onSend: () -> Void
    let onCancel: () -> Void
    let onClearHistory: () -> Void
    let onDisconnect: () -> Void

    @State private var scrollProxy: ScrollViewProxy?

    var body: some View {
        VStack(spacing: 0) {
            // 헤더
            chatHeader

            // 메시지 목록
            if messages.isEmpty {
                emptyStateView
            } else {
                messageList
            }

            // 입력 영역
            ChatInputView(
                inputText: $inputText,
                isProcessing: isProcessing,
                onSend: onSend,
                onCancel: onCancel
            )
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Header

    private var chatHeader: some View {
        HStack {
            // AI 아이콘 및 이름
            Image(systemName: cliType.iconName)
                .foregroundStyle(AppColors.accent)
            Text(cliType.displayName)
                .font(.headline)

            Spacer()

            // 메뉴 버튼
            Menu {
                Button(action: onClearHistory) {
                    Label(L10n.get("ai.chat.clearHistory"), systemImage: "trash")
                }

                Divider()

                Button(role: .destructive, action: onDisconnect) {
                    Label(L10n.get("ai.chat.disconnect"), systemImage: "link.badge.xmark")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(AppColors.toolbarIcon)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 40))
                .foregroundStyle(AppColors.toolbarIcon)

            Text(L10n.get("ai.chat.empty"))
                .font(.subheadline)
                .foregroundStyle(AppColors.textSecondary)

            Text(L10n.get("ai.chat.emptyDescription"))
                .font(.caption)
                .foregroundStyle(AppColors.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(messages) { message in
                        ChatMessageView(message: message)
                            .id(message.id)
                    }
                }
                .padding(12)
            }
            .onAppear {
                scrollProxy = proxy
            }
            .onChange(of: messages.count) { _, _ in
                scrollToBottom()
            }
            .onChange(of: messages.last?.content) { _, _ in
                scrollToBottom()
            }
        }
    }

    private func scrollToBottom() {
        guard let lastMessage = messages.last else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            scrollProxy?.scrollTo(lastMessage.id, anchor: .bottom)
        }
    }
}

#Preview {
    AIChatView(
        cliType: .claude,
        messages: .constant([
            AIMessage(role: .user, content: "안녕하세요!"),
            AIMessage(role: .assistant, content: "안녕하세요! 무엇을 도와드릴까요?")
        ]),
        inputText: .constant(""),
        isProcessing: false,
        onSend: {},
        onCancel: {},
        onClearHistory: {},
        onDisconnect: {}
    )
    .frame(width: 350, height: 500)
}
