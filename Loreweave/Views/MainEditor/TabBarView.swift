//
//  TabBarView.swift
//  Loreweave
//
//  에디터 탭바 뷰 - EditorTabManager와 연동
//

import SwiftUI

struct TabBarView: View {
    @State private var tabManager = EditorTabManager.shared
    @State private var fileSystemManager = FileSystemManager.shared
    @State private var isAddButtonHovered = false
    @State private var isAddButtonPressed = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(Array(tabManager.tabs.enumerated()), id: \.element.id) { index, tab in
                    TabItemView(
                        title: tab.title,
                        isModified: tab.isModified,
                        justSaved: tab.justSaved,
                        isSelected: tabManager.selectedTabIndex == index,
                        fileExists: tab.fileExists,
                        onSelect: { tabManager.selectTab(at: index) },
                        onClose: { tabManager.closeTab(at: index) }
                    )
                }

                Button(action: { showNewFileDialog() }) {
                    ZStack {
                        addButtonBackground
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppColors.addButtonIcon)
                    }
                    .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .clipShape(Capsule())
                .onHover { isAddButtonHovered = $0 }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in isAddButtonPressed = true }
                        .onEnded { _ in isAddButtonPressed = false }
                )
                .padding(.leading, 4)
                .help(L10n.tabs.newTab)

                Spacer()
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 36)
        .background(AppColors.barBackground)
        .overlay(alignment: .bottom) {
            if tabManager.tabs.isEmpty {
                Divider()
            }
        }
    }

    @ViewBuilder
    private var addButtonBackground: some View {
        if isAddButtonPressed {
            AppColors.addButtonPressed
        } else if isAddButtonHovered {
            AppColors.addButtonHover
        } else {
            Color.clear
        }
    }

    private func showNewFileDialog() {
        guard let targetDirectory = fileSystemManager.targetDirectoryForNewFile else { return }
        fileSystemManager.showNewFileDialog(in: targetDirectory) { _ in }
    }
}

struct TabItemView: View {
    let title: String
    let isModified: Bool
    let justSaved: Bool
    let isSelected: Bool
    let fileExists: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false
    @State private var isCloseButtonHovering = false
    /// 저장 완료 점 표시 여부 (애니메이션용)
    @State private var showSavedIndicator = false

    /// 탭 배경색 (글래스모피즘 스타일)
    private var tabBackgroundColor: Color {
        if isSelected {
            return AppColors.tabSelectedBackground
        } else if isHovering {
            return AppColors.tabHoverBackground
        } else {
            return AppColors.tabDefaultBackground
        }
    }

    /// 탭 테두리 색상
    private var tabBorderColor: Color {
        if isSelected {
            return AppColors.tabSelectedBorder
        } else {
            return AppColors.tabDefaultBorder
        }
    }

    /// 상태 표시 점 색상
    private var indicatorColor: Color {
        if showSavedIndicator {
            return AppColors.savedIndicator
        } else if isModified {
            return AppColors.modifiedIndicator
        } else {
            return .clear
        }
    }

    /// 상태 표시 점 표시 여부
    private var showIndicator: Bool {
        (isModified || showSavedIndicator) && !isHovering
    }

    var body: some View {
        HStack(spacing: 6) {
            // 닫기 버튼 / 수정 상태 표시 (같은 위치)
            ZStack {
                // 수정/저장 상태 점 (마우스오버가 아닐 때만 표시)
                Circle()
                    .fill(indicatorColor)
                    .frame(width: 8, height: 8)
                    .opacity(showIndicator ? 1 : 0)
                    .scaleEffect(showIndicator ? 1 : 0.5)
                    .animation(.easeOut(duration: 0.2), value: showIndicator)
                    .animation(.easeInOut(duration: 0.15), value: indicatorColor)

                // 닫기 버튼 (마우스오버 시에만 표시)
                if isHovering {
                    Button(action: onClose) {
                        ZStack {
                            Circle()
                                .fill(isCloseButtonHovering ? AppColors.tabCloseHoverBackground : Color.clear)
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(isCloseButtonHovering ? AppColors.toolbarIconActive : AppColors.toolbarIcon)
                        }
                    }
                    .buttonStyle(.plain)
                    .onHover { isCloseButtonHovering = $0 }
                    .help(L10n.tabs.close)
                }
            }
            .frame(width: 14, height: 14)

            Text(title)
                .font(.system(size: 12))
                .lineLimit(1)
                .strikethrough(!fileExists, color: .secondary)
                .foregroundStyle(fileExists ? AppColors.tabText : .secondary)
        }
        .padding(.leading, 12)
        .padding(.trailing, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(tabBackgroundColor)
                .shadow(color: isSelected ? AppColors.tabSelectedShadow : Color.clear, radius: 1, y: 0.5)
        )
        .overlay(
            Capsule()
                .strokeBorder(tabBorderColor, lineWidth: 0.5)
        )
        .contentShape(Capsule())
        .onTapGesture(perform: onSelect)
        .onHover { hovering in
            isHovering = hovering
        }
        .onChange(of: justSaved) { _, newValue in
            if newValue {
                // 저장됨 표시 시작
                withAnimation(.easeOut(duration: 0.15)) {
                    showSavedIndicator = true
                }
            } else {
                // 저장됨 표시 해제 (페이드아웃)
                withAnimation(.easeOut(duration: 0.3)) {
                    showSavedIndicator = false
                }
            }
        }
    }
}

#Preview {
    TabBarView()
}
