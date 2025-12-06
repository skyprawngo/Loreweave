//
//  NavigationButtonsView.swift
//  Loreweave
//
//  파인더 스타일 이전/다음 네비게이션 버튼
//

import SwiftUI

struct NavigationButtonsView: View {
    let onBack: () -> Void
    let onForward: () -> Void

    @State private var isBackHovered: Bool = false
    @State private var isForwardHovered: Bool = false
    @State private var isBackPressed: Bool = false
    @State private var isForwardPressed: Bool = false

    private let buttonSize: CGFloat = 28

    var body: some View {
        HStack(spacing: 0) {
            // 이전 버튼
            navigationButton(
                icon: "chevron.left",
                isHovered: isBackHovered,
                isPressed: isBackPressed,
                action: onBack
            )
            .clipShape(Capsule())
            .onHover { isBackHovered = $0 }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isBackPressed = true }
                    .onEnded { _ in isBackPressed = false }
            )
            .help(L10n.get("toolbar.goBack"))

            // 구분선
            Rectangle()
                .fill(AppColors.separator)
                .frame(width: 1, height: 12)
                .padding(.horizontal, 4)

            // 다음 버튼
            navigationButton(
                icon: "chevron.right",
                isHovered: isForwardHovered,
                isPressed: isForwardPressed,
                action: onForward
            )
            .clipShape(Capsule())
            .onHover { isForwardHovered = $0 }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isForwardPressed = true }
                    .onEnded { _ in isForwardPressed = false }
            )
            .help(L10n.get("toolbar.goForward"))
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func navigationButton(
        icon: String,
        isHovered: Bool,
        isPressed: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                buttonBackground(isHovered: isHovered, isPressed: isPressed)

                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppColors.toolbarIcon)
            }
            .frame(width: buttonSize, height: buttonSize)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func buttonBackground(isHovered: Bool, isPressed: Bool) -> some View {
        if isPressed {
            AppColors.addButtonPressed
        } else if isHovered {
            AppColors.addButtonHover
        } else {
            Color.clear
        }
    }
}

#Preview {
    NavigationButtonsView(
        onBack: { print("Back") },
        onForward: { print("Forward") }
    )
    .padding(40)
    .background(AppColors.barBackground)
}
