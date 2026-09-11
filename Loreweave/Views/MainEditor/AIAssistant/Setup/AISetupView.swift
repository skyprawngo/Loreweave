//
//  AISetupView.swift
//  Loreweave
//
//  AI 선택 및 연결 설정 뷰
//

import SwiftUI

struct AISetupView: View {
    @Binding var selectedCLIType: AICLIType?
    let onConfirm: (AICLIType) -> Void
    let onCancel: () -> Void

    /// 헤더에 표시할 이름
    private var headerTitle: String {
        selectedCLIType?.displayName ?? L10n.get("ai.assistant.inactive.title")
    }

    /// 헤더에 표시할 아이콘 이미지 이름 (선택된 경우)
    private var headerIconImageName: String? {
        selectedCLIType?.iconImageName
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
            VStack(spacing: 20) {
                Spacer()

                // 아이콘
                Image(systemName: "cpu")
                    .font(.system(size: 40))
                    .foregroundStyle(AppColors.accent)

                // 제목
                Text(L10n.get("ai.setup.title"))
                    .font(.headline)
                    .foregroundStyle(AppColors.textPrimary)

                // 설명
                Text(L10n.get("ai.setup.description"))
                    .font(.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)

                // AI 선택 드롭다운
                Picker("", selection: $selectedCLIType) {
                    Text(L10n.get("ai.setup.selectPlaceholder"))
                        .tag(nil as AICLIType?)

                    ForEach(AICLIType.allCases) { cliType in
                        Text(cliType.displayName)
                            .tag(cliType as AICLIType?)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 200)

                // 버튼
                HStack(spacing: 12) {
                    Button(action: onCancel) {
                        Text(L10n.get("common.cancel"))
                            .frame(minWidth: 80)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        if let selected = selectedCLIType {
                            onConfirm(selected)
                        }
                    } label: {
                        Text(L10n.get("common.confirm"))
                            .frame(minWidth: 80)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedCLIType == nil)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#Preview {
    AISetupView(
        selectedCLIType: .constant(.claude),
        onConfirm: { _ in },
        onCancel: {}
    )
    .frame(width: 320, height: 400)
}
