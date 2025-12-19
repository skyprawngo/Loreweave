//
//  ChatMessageView.swift
//  Loreweave
//
//  개별 채팅 메시지 뷰
//

import SwiftUI

struct ChatMessageView: View {
    let message: AIMessage

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // 아이콘
            messageIcon
                .frame(width: 28, height: 28)

            // 메시지 내용
            VStack(alignment: .leading, spacing: 4) {
                // 역할 및 시간
                HStack(spacing: 8) {
                    Text(roleDisplayName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(roleColor)

                    Text(message.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundStyle(AppColors.textTertiary)
                }

                // 메시지 본문
                if message.isStreaming && message.content.isEmpty {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text(L10n.get("ai.chat.thinking"))
                            .font(.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                } else {
                    Text(message.content)
                        .font(.body)
                        .foregroundStyle(AppColors.textPrimary)
                        .textSelection(.enabled)

                    // 스트리밍 중 표시
                    if message.isStreaming {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(AppColors.accent)
                                .frame(width: 6, height: 6)
                                .opacity(0.8)
                            Text(L10n.get("ai.chat.streaming"))
                                .font(.caption2)
                                .foregroundStyle(AppColors.textTertiary)
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(messageBackground)
        .cornerRadius(8)
    }

    @ViewBuilder
    private var messageIcon: some View {
        switch message.role {
        case .user:
            Image(systemName: "person.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(AppColors.accent)
        case .assistant:
            Image(systemName: "brain.head.profile")
                .font(.system(size: 24))
                .foregroundStyle(.purple)
        case .system:
            Image(systemName: "gear")
                .font(.system(size: 24))
                .foregroundStyle(AppColors.textSecondary)
        }
    }

    private var roleDisplayName: String {
        switch message.role {
        case .user:
            return L10n.get("ai.chat.user")
        case .assistant:
            return L10n.get("ai.chat.assistant")
        case .system:
            return L10n.get("ai.chat.system")
        }
    }

    private var roleColor: Color {
        switch message.role {
        case .user:
            return AppColors.accent
        case .assistant:
            return .purple
        case .system:
            return AppColors.textSecondary
        }
    }

    private var messageBackground: Color {
        switch message.role {
        case .user:
            return AppColors.accent.opacity(0.08)
        case .assistant:
            return AppColors.controlBackground
        case .system:
            return AppColors.textSecondary.opacity(0.1)
        }
    }
}

#Preview {
    VStack(spacing: 8) {
        ChatMessageView(message: AIMessage(
            role: .user,
            content: "안녕하세요, 이 문장을 수정해 주세요."
        ))

        ChatMessageView(message: AIMessage(
            role: .assistant,
            content: "네, 문장을 수정해 드리겠습니다. 어떤 부분을 수정하면 될까요?"
        ))

        ChatMessageView(message: AIMessage(
            role: .assistant,
            content: "",
            isStreaming: true
        ))
    }
    .padding()
    .frame(width: 350)
}
