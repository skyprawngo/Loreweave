//
//  AIInactiveView.swift
//  Loreweave
//
//  AI 어시스턴트 비활성화 상태 뷰
//

import SwiftUI

struct AIInactiveView: View {
    let onConnectTapped: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // 아이콘
            Image(systemName: "brain.head.profile")
                .font(.system(size: 48))
                .foregroundStyle(AppColors.toolbarIcon)

            // 제목
            Text(L10n.get("ai.assistant.inactive.title"))
                .font(.headline)
                .foregroundStyle(AppColors.textPrimary)

            // 설명
            Text(L10n.get("ai.assistant.inactive.description"))
                .font(.subheadline)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            // 연결 버튼
            Button(action: onConnectTapped) {
                Label(L10n.get("ai.assistant.connect"), systemImage: "link")
                    .frame(minWidth: 160)
            }
            .buttonStyle(.borderedProminent)
            .tint(.accentColor)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    AIInactiveView(onConnectTapped: {})
        .frame(width: 320, height: 400)
}
