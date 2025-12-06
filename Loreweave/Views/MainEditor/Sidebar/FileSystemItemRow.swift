//
//  FileSystemItemRow.swift
//  Loreweave
//
//  파일 시스템 항목 행 뷰 (트리 구조 표시용)
//

import SwiftUI

struct FileSystemItemRow: View {
    @Bindable var item: FileSystemItem
    let depth: Int
    let onSelect: (FileSystemItem) -> Void
    let onDoubleClick: (FileSystemItem) -> Void
    var onMoveItem: ((FileSystemItem, FileSystemItem) -> Void)?
    /// 선택된 항목인지 여부 (부모에서 전달)
    var isSelected: Bool = false
    /// 현재 선택된 항목 ID (자식 뷰로 전달용)
    var selectedItemId: UUID?
    /// 부모 폴더들의 세로선 표시 여부 배열 (depth별로 세로선 표시 여부)
    var parentTreeLines: [Bool] = []

    @State private var isHovered: Bool = false
    @State private var isEditing: Bool = false
    @State private var editingName: String = ""
    @State private var isDropTargeted: Bool = false
    @FocusState private var isTextFieldFocused: Bool
    @FocusState private var isRowFocused: Bool

    private let fileSystemManager = FileSystemManager.shared
    private let tabManager = EditorTabManager.shared

    /// 행 배경색 (파인더 스타일)
    private var rowBackgroundColor: Color {
        if isEditing {
            return AppColors.sidebarItemHover
        } else if isDropTargeted {
            return AppColors.sidebarItemSelected.opacity(0.7)
        } else if isSelected {
            return AppColors.sidebarItemHover
        } else {
            return Color.clear
        }
    }

    /// 확장자를 제외한 파일명 반환
    private var fileNameWithoutExtension: String {
        if item.isDirectory {
            return item.name
        }
        let name = item.name
        if let dotIndex = name.lastIndex(of: ".") {
            return String(name[..<dotIndex])
        }
        return name
    }

    /// 섹션 폴더의 아이콘 색상
    private var iconColor: Color {
        if item.isSection {
            return AppColors.accent
        }
        return item.isDirectory ? AppColors.accent : AppColors.toolbarIcon
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 현재 항목 행
            rowContent

            // 자식 항목 (펼쳐진 경우에만 렌더링 - lazy loading)
            if item.isDirectory && item.isExpanded {
                childrenContent
            }
        }
        .animation(.easeOut(duration: 0.15), value: item.isExpanded)
    }

    // MARK: - Row Content

    private var rowContent: some View {
        HStack(spacing: 4) {
            // 들여쓰기 + 세로선
            HStack(spacing: 0) {
                ForEach(0..<depth, id: \.self) { index in
                    ZStack {
                        // 부모 폴더의 세로선 (해당 depth에 세로선이 필요한 경우)
                        if index < parentTreeLines.count && parentTreeLines[index] {
                            Rectangle()
                                .fill(AppColors.separator)
                                .frame(width: 1)
                        }
                    }
                    .frame(width: 16)
                }
            }

            // 폴더 펼침/접기 버튼 또는 공간
            if item.isDirectory {
                expandButton
            } else {
                Spacer()
                    .frame(width: 16)
            }

            // 아이콘
            Image(systemName: item.iconName)
                .font(.system(size: 13))
                .foregroundStyle(iconColor)
                .frame(width: 16)

            // 이름 (편집 모드 또는 표시 모드)
            if isEditing {
                editingTextField
            } else {
                Text(item.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            // 폴더인 경우 하위 항목 개수 표시
            if item.isDirectory && item.childCount > 0 {
                Text("\(item.childCount)")
                    .font(.system(size: 10))
                    .foregroundStyle(AppColors.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(AppColors.controlBackground.opacity(0.5))
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(rowBackgroundColor)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture(count: 2) {
            if item.isDirectory {
                toggleExpand()
            } else {
                onDoubleClick(item)
            }
        }
        .onTapGesture(count: 1) {
            onSelect(item)
            if item.isDirectory {
                toggleExpand()
            }
            // 선택 시 즉시 포커스 부여
            if !isEditing {
                isRowFocused = true
            }
        }
        .contextMenu { contextMenuContent }
        // 선택된 상태에서 Enter 키로 이름 편집 시작
        .focusable(!isEditing)
        .focusEffectDisabled()  // 기본 포커스 외형선 비활성화
        .focused($isRowFocused)
        .onKeyPress(.return) {
            if isSelected && !isEditing {
                startEditing()
                return .handled
            }
            return .ignored
        }
        .onChange(of: isSelected) { _, newValue in
            // 선택 해제 시 포커스도 해제
            if !newValue {
                isRowFocused = false
            }
        }
        // 드래그 소스
        .draggable(item.url.absoluteString) {
            // 드래그 중 표시할 미리보기
            HStack(spacing: 4) {
                Image(systemName: item.iconName)
                    .font(.system(size: 13))
                    .foregroundStyle(iconColor)
                Text(item.name)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AppColors.controlBackground)
            .cornerRadius(4)
        }
        // 드롭 타겟 (폴더에만)
        .dropDestination(for: String.self) { droppedItems, _ in
            guard item.isDirectory,
                  let urlString = droppedItems.first,
                  let sourceURL = URL(string: urlString) else {
                return false
            }

            // 자기 자신이나 자신의 하위 폴더로는 이동 불가
            if sourceURL == item.url || item.url.path.hasPrefix(sourceURL.path + "/") {
                return false
            }

            // 드래그된 항목 찾기
            if let sourceItem = findItem(by: sourceURL) {
                onMoveItem?(sourceItem, item)
            }
            return true
        } isTargeted: { targeted in
            // 폴더에만 드롭 타겟 표시
            if item.isDirectory {
                isDropTargeted = targeted
            }
        }
    }

    // MARK: - Expand Button

    private var expandButton: some View {
        Button(action: { toggleExpand() }) {
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppColors.toolbarIcon)
                .frame(width: 16, height: 16)
                .rotationEffect(.degrees(item.isExpanded ? 90 : 0))
                .animation(.easeOut(duration: 0.15), value: item.isExpanded)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Editing TextField

    private var editingTextField: some View {
        SelectableTextField(
            text: $editingName,
            selectRange: 0..<fileNameWithoutExtension.count,
            onCommit: { finishEditing() },
            onCancel: { cancelEditing() },
            onFocusLost: { finishEditing() }
        )
        .font(.system(size: 12))
        .focused($isTextFieldFocused)
    }

    // MARK: - Children Content (Lazy)

    @ViewBuilder
    private var childrenContent: some View {
        if let children = item.children, !children.isEmpty {
            ForEach(Array(children.enumerated()), id: \.element.id) { index, child in
                let isLastChild = index == children.count - 1
                // 현재 depth에서 세로선을 그릴지 여부 (마지막 자식이 아니면 세로선 유지)
                let newTreeLines = parentTreeLines + [!isLastChild]

                FileSystemItemRow(
                    item: child,
                    depth: depth + 1,
                    onSelect: onSelect,
                    onDoubleClick: onDoubleClick,
                    onMoveItem: onMoveItem,
                    isSelected: selectedItemId == child.id,
                    selectedItemId: selectedItemId,
                    parentTreeLines: newTreeLines
                )
            }
        }
    }

    // MARK: - Find Item Helper

    /// URL로 FileSystemItem 찾기 (프로젝트 루트에서 재귀 탐색)
    private func findItem(by url: URL) -> FileSystemItem? {
        guard let root = fileSystemManager.projectRoot else { return nil }
        return findItemRecursively(in: root, url: url)
    }

    private func findItemRecursively(in item: FileSystemItem, url: URL) -> FileSystemItem? {
        if item.url == url {
            return item
        }
        if let children = item.children {
            for child in children {
                if let found = findItemRecursively(in: child, url: url) {
                    return found
                }
            }
        }
        return nil
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var contextMenuContent: some View {
        if item.isDirectory {
            Button(action: { showNewFileDialog() }) {
                Label(L10n.get("explorer.newFile"), systemImage: "doc.badge.plus")
            }

            Button(action: { showNewFolderDialog() }) {
                Label(L10n.get("explorer.newFolder"), systemImage: "folder.badge.plus")
            }

            Divider()
        }

        Button(action: { startEditing() }) {
            Label(L10n.get("explorer.rename"), systemImage: "pencil")
        }

        Divider()

        Button(action: { revealInFinder() }) {
            Label(L10n.get("explorer.revealInFinder"), systemImage: "folder")
        }

        if !item.isDirectory {
            Button(action: { openWithDefaultApp() }) {
                Label(L10n.get("explorer.openWith"), systemImage: "arrow.up.forward.app")
            }
        }

        Divider()

        Button(role: .destructive, action: { showDeleteConfirmation() }) {
            Label(L10n.common.delete, systemImage: "trash")
        }
    }

    // MARK: - Actions

    private func toggleExpand() {
        fileSystemManager.toggleExpand(item)
    }

    private func startEditing() {
        editingName = item.name
        isEditing = true
        // 약간의 지연 후 포커스 설정
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            isTextFieldFocused = true
        }
    }

    private func finishEditing() {
        let newName = editingName.trimmingCharacters(in: .whitespaces)
        if !newName.isEmpty && newName != item.name {
            _ = fileSystemManager.rename(item, to: newName)
        }
        isEditing = false
    }

    private func cancelEditing() {
        isEditing = false
    }

    private func showNewFileDialog() {
        fileSystemManager.showNewFileDialog(in: item) { _ in }
    }

    private func showNewFolderDialog() {
        fileSystemManager.showNewFolderDialog(in: item) { _ in }
    }

    private func showDeleteConfirmation() {
        fileSystemManager.showDeleteConfirmation(for: item) { _ in }
    }

    private func revealInFinder() {
        fileSystemManager.revealInFinder(item)
    }

    private func openWithDefaultApp() {
        fileSystemManager.openWithDefaultApp(item)
    }
}

#Preview {
    let root = FileSystemItem(
        url: URL(fileURLWithPath: "/tmp/Test"),
        isDirectory: true
    )
    let child1 = FileSystemItem(
        url: URL(fileURLWithPath: "/tmp/Test/chapter1.md"),
        isDirectory: false,
        parent: root
    )
    let child2 = FileSystemItem(
        url: URL(fileURLWithPath: "/tmp/Test/Subfolder"),
        isDirectory: true,
        parent: root
    )
    root.children = [child1, child2]
    root.isExpanded = true

    return FileSystemItemRow(
        item: root,
        depth: 0,
        onSelect: { _ in },
        onDoubleClick: { _ in }
    )
    .frame(width: 220)
    .padding()
}
