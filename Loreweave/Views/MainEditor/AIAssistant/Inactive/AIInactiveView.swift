//
//  AIInactiveView.swift
//  Loreweave
//
//  AI 어시스턴트 비활성화 상태 뷰
//

import SwiftUI

struct AIInactiveView: View {
    let onConnectTapped: () -> Void

    /// 저장된 AI CLI 타입 (있으면 헤더에 표시)
    private var savedCLIType: AICLIType? {
        AICLIType(rawValue: UserSettings.shared.aiAssistantCLIType)
    }

    /// 헤더에 표시할 이름
    private var headerTitle: String {
        savedCLIType?.displayName ?? L10n.get("ai.assistant.inactive.title")
    }

    /// 헤더에 표시할 아이콘 이미지 이름 (저장된 경우)
    private var headerIconImageName: String? {
        savedCLIType?.iconImageName
    }

    var body: some View {
        VStack(spacing: 0) {
            // 헤더
            HStack {
                if let imageName = headerIconImageName {
                    Image(imageName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .foregroundStyle(AppColors.accent)
                } else {
                    Image(systemName: "sparkles")
                        .foregroundStyle(AppColors.accent)
                }
                Text(headerTitle)
                    .font(.headline)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // 콘텐츠
            VStack(spacing: 24) {
                Spacer()

                // 아이콘
                Image(systemName: "sparkles")
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

                // 활성화 버튼
                Button(action: onConnectTapped) {
                    Text(L10n.get("ai.assistant.connect"))
                        .frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#Preview {
    AIInactiveView(onConnectTapped: {})
        .frame(width: 320, height: 400)
}
