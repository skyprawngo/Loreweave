//
//  FileSystemItemRow.swift
//  TextlinkEditor
//
//  파일 시스템 항목 단일 행 뷰 (재귀 없음)
//

import SwiftUI

struct FileSystemItemRow: View {
    @Bindable var item: FileSystemItem
    let depth: Int
    /// 선택 콜백 (항목, 수정자 키)
    let onSelect: (FileSystemItem, EventModifiers) -> Void
    var onMoveItem: ((FileSystemItem, FileSystemItem) -> Void)?
    /// 캐시 갱신 콜백 (펼침/접기, 파일 생성/삭제/이름 변경 등 모든 변경 시)
    var onCacheUpdate: (() -> Void)?
    /// 삭제 후 콜백 (삭제된 항목 전달)
    var onItemDeleted: ((FileSystemItem) -> Void)?
    /// 선택 상태 체크 클로저
    var isItemSelected: ((UUID) -> Bool)?
    /// URL로 항목 찾기 클로저
    var findItemByURL: ((URL) -> FileSystemItem?)?
    /// 부모 폴더들의 세로선 표시 여부 배열
    var parentTreeLines: [Bool] = []

    /// 현재 항목이 선택되었는지 여부
    private var isSelected: Bool {
        isItemSelected?(item.id) ?? false
    }

    @State private var isHovered: Bool = false
    @State private var isEditing: Bool = false
    @State private var editingName: String = ""
    @State private var isDropTargeted: Bool = false
    @FocusState private var isTextFieldFocused: Bool
    @FocusState private var isRowFocused: Bool

    private let fileSystemManager = FileSystemManager.shared

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
        HStack(spacing: 4) {
            // 들여쓰기 + 세로선
            treeIndentation

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
        .onTapGesture {
            let modifiers = currentEventModifiers()
            onSelect(item, modifiers)
            // Shift/Command 없이 폴더 클릭 시에만 펼치기/접기
            if item.isDirectory && !modifiers.contains(.shift) && !modifiers.contains(.command) {
                toggleExpand()
            }
            // 선택 시 포커스 부여
            if !isEditing {
                isRowFocused = true
            }
        }
        .contextMenu { contextMenuContent }
        .focusable(!isEditing)
        .focusEffectDisabled()
        .focused($isRowFocused)
        .onKeyPress(.return) {
            if isSelected && !isEditing {
                startEditing()
                return .handled
            }
            return .ignored
        }
        .onChange(of: isSelected) { _, newValue in
            if !newValue {
                isRowFocused = false
            }
        }
        // 드래그 소스
        .draggable(item.url.absoluteString) {
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

            if let sourceItem = findItemByURL?(sourceURL) {
                onMoveItem?(sourceItem, item)
            }
            return true
        } isTargeted: { targeted in
            if item.isDirectory {
                isDropTargeted = targeted
            }
        }
    }

    // MARK: - Tree Indentation

    private var treeIndentation: some View {
        HStack(spacing: 0) {
            ForEach(0..<depth, id: \.self) { index in
                ZStack {
                    if index < parentTreeLines.count && parentTreeLines[index] {
                        Rectangle()
                            .fill(AppColors.separator)
                            .frame(width: 1)
                    }
                }
                .frame(width: 16)
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
        onCacheUpdate?()
    }

    private func startEditing() {
        editingName = item.name
        isEditing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            isTextFieldFocused = true
        }
    }

    private func finishEditing() {
        let newName = editingName.trimmingCharacters(in: .whitespaces)
        if !newName.isEmpty && newName != item.name {
            if fileSystemManager.rename(item, to: newName) {
                onCacheUpdate?()
            }
        }
        isEditing = false
    }

    private func cancelEditing() {
        isEditing = false
    }

    private func showNewFileDialog() {
        fileSystemManager.showNewFileDialog(in: item) { [self] newItem in
            if newItem != nil {
                onCacheUpdate?()
            }
        }
    }

    private func showNewFolderDialog() {
        fileSystemManager.showNewFolderDialog(in: item) { [self] newItem in
            if newItem != nil {
                onCacheUpdate?()
            }
        }
    }

    private func showDeleteConfirmation() {
        let itemToDelete = item  // 캡처용 복사
        fileSystemManager.showDeleteConfirmation(for: item) { deleted in
            if deleted {
                onCacheUpdate?()
                onItemDeleted?(itemToDelete)
            }
        }
    }

    private func revealInFinder() {
        fileSystemManager.revealInFinder(item)
    }

    private func openWithDefaultApp() {
        fileSystemManager.openWithDefaultApp(item)
    }

    /// 현재 NSEvent에서 수정자 키 상태를 SwiftUI EventModifiers로 변환
    private func currentEventModifiers() -> EventModifiers {
        let flags = NSEvent.modifierFlags
        var modifiers: EventModifiers = []
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        return modifiers
    }
}

#Preview {
    let root = FileSystemItem(
        url: URL(fileURLWithPath: "/tmp/Test"),
        isDirectory: true
    )

    return FileSystemItemRow(
        item: root,
        depth: 0,
        onSelect: { _, _ in }
    )
    .frame(width: 220)
    .padding()
}
