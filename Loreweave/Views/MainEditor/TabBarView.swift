//
//  TabBarView.swift
//  Loreweave
//
//  에디터 탭바 뷰 - EditorTabManager와 연동
//

import SwiftUI

struct TabBarView: View {
    private var tabManager: EditorTabManager { EditorTabManager.shared }
    private var fileSystemManager: FileSystemManager { FileSystemManager.shared }

    @State private var isAddButtonHovered = false
    @State private var isAddButtonPressed = false
    @State private var draggingTabId: UUID?
    @State private var dragOverTabId: UUID?

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
                        isDragging: draggingTabId == tab.id,
                        isDragOver: dragOverTabId == tab.id,
                        onSelect: { tabManager.selectTab(at: index) },
                        onClose: { tabManager.closeTab(at: index) }
                    )
                    .onDrag {
                        draggingTabId = tab.id
                        return NSItemProvider(object: tab.id.uuidString as NSString)
                    }
                    .onDrop(of: [.text], delegate: TabDropDelegate(
                        tabId: tab.id,
                        tabIndex: index,
                        tabManager: tabManager,
                        draggingTabId: $draggingTabId,
                        dragOverTabId: $dragOverTabId
                    ))
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
        .overlay(alignment: .bottom) {
            if tabManager.tabs.isEmpty {
                Divider()
            }
        }
        .onChange(of: tabManager.tabs) { _, _ in
            // 탭 목록이 변경되면 드래그 상태 초기화
            draggingTabId = nil
            dragOverTabId = nil
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
    var isDragging: Bool = false
    var isDragOver: Bool = false
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false
    @State private var isCloseButtonHovering = false
    /// 저장 완료 점 표시 여부 (애니메이션용)
    @State private var showSavedIndicator = false

    /// 탭 배경색 (선택되지 않은 탭용)
    private var tabBackgroundColor: Color {
        if isHovering {
            return AppColors.tabHoverBackground
        } else {
            return AppColors.tabSelectedBackground // 기본 배경을 기존 선택 배경으로
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
                .fill(isSelected ? Color.clear : tabBackgroundColor)
        )
        .glassEffect(isSelected ? .regular : .clear, in: .capsule)
        .contentShape(Capsule())
        .opacity(isDragging ? 0.5 : 1.0)
        .overlay(alignment: .leading) {
            // 드롭 위치 표시 인디케이터
            if isDragOver {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 2)
                    .offset(x: -1)
            }
        }
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

// MARK: - Tab Drop Delegate

struct TabDropDelegate: DropDelegate {
    let tabId: UUID
    let tabIndex: Int
    let tabManager: EditorTabManager
    @Binding var draggingTabId: UUID?
    @Binding var dragOverTabId: UUID?

    func dropEntered(info: DropInfo) {
        // 드래그 중인 탭이 자기 자신이면 무시
        guard draggingTabId != tabId else { return }
        dragOverTabId = tabId
    }

    func dropExited(info: DropInfo) {
        dragOverTabId = nil
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let draggingId = draggingTabId else { return false }
        guard let sourceIndex = tabManager.tabs.firstIndex(where: { $0.id == draggingId }) else { return false }

        // 드롭 위치 계산
        let destinationIndex = tabIndex

        if sourceIndex != destinationIndex {
            tabManager.moveTab(from: sourceIndex, to: destinationIndex)
        }

        // 상태 초기화
        draggingTabId = nil
        dragOverTabId = nil

        return true
    }

    func validateDrop(info: DropInfo) -> Bool {
        return draggingTabId != nil && draggingTabId != tabId
    }
}

#Preview {
    TabBarView()
}
