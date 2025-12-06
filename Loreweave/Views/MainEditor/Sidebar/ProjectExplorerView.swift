//
//  ProjectExplorerView.swift
//  Loreweave
//
//  프로젝트 탐색기 뷰 (파인더 스타일)
//

import SwiftUI

struct ProjectExplorerView: View {
    private var fileSystemManager: FileSystemManager { FileSystemManager.shared }
    private var projectManager: ProjectManager { ProjectManager.shared }
    private var tabManager: EditorTabManager { EditorTabManager.shared }

    @State private var selectedItem: FileSystemItem?
    @State private var isRefreshing: Bool = false

    /// EditorView에서 현재 편집 중인 내용을 가져오기 위한 콜백
    var getCurrentEditorContent: (() -> String?)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 헤더
            explorerHeader

            Divider()

            // 파일 트리
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let rootItem = fileSystemManager.projectRoot {
                        if let children = rootItem.children, !children.isEmpty {
                            ForEach(children) { item in
                                FileSystemItemRow(
                                    item: item,
                                    depth: 0,
                                    onSelect: { selected in
                                        handleSingleClick(selected)
                                    },
                                    onDoubleClick: { item in
                                        handleDoubleClick(item)
                                    },
                                    onMoveItem: { sourceItem, destinationFolder in
                                        handleMoveItem(sourceItem, to: destinationFolder)
                                    },
                                    isSelected: selectedItem?.id == item.id,
                                    selectedItemId: selectedItem?.id
                                )
                            }
                        } else {
                            emptyStateView
                        }
                    } else {
                        noProjectView
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
            }
            .frame(maxHeight: .infinity)
        }
        .contextMenu { rootContextMenu }
    }

    // MARK: - Header

    private var explorerHeader: some View {
        HStack {
            Text(projectManager.currentProject?.name ?? L10n.sidebar.project)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppColors.sidebarHeaderText)
                .textCase(.uppercase)

            Spacer()

            // 새 파일 버튼
            Button(action: { showNewFileDialog() }) {
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.toolbarIcon)
            }
            .buttonStyle(.plain)
            .help(L10n.get("explorer.newFile"))
            .disabled(fileSystemManager.projectRoot == nil)

            // 새 폴더 버튼
            Button(action: { showNewFolderDialog() }) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.toolbarIcon)
            }
            .buttonStyle(.plain)
            .help(L10n.get("explorer.newFolder"))
            .disabled(fileSystemManager.projectRoot == nil)

            // 새로고침 버튼
            Button(action: { refresh() }) {
                if isRefreshing {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 12, height: 12)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.toolbarIcon)
                }
            }
            .buttonStyle(.plain)
            .help(L10n.get("explorer.refresh"))
            .disabled(isRefreshing || fileSystemManager.projectRoot == nil)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "folder")
                .font(.system(size: 24))
                .foregroundStyle(AppColors.toolbarIcon)

            Text(L10n.get("explorer.emptyFolder"))
                .font(.system(size: 11))
                .foregroundStyle(AppColors.textTertiary)

            Button(action: { showNewFileDialog() }) {
                Text(L10n.get("explorer.createFirstFile"))
                    .font(.system(size: 11))
            }
            .buttonStyle(.link)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var noProjectView: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 24))
                .foregroundStyle(AppColors.toolbarIcon)

            Text(L10n.get("explorer.noProject"))
                .font(.system(size: 11))
                .foregroundStyle(AppColors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Root Context Menu

    @ViewBuilder
    private var rootContextMenu: some View {
        if fileSystemManager.projectRoot != nil {
            Button(action: { showNewFileDialog() }) {
                Label(L10n.get("explorer.newFile"), systemImage: "doc.badge.plus")
            }

            Button(action: { showNewFolderDialog() }) {
                Label(L10n.get("explorer.newFolder"), systemImage: "folder.badge.plus")
            }

            Divider()

            Button(action: { refresh() }) {
                Label(L10n.get("explorer.refresh"), systemImage: "arrow.clockwise")
            }

            if let rootItem = fileSystemManager.projectRoot {
                Button(action: { fileSystemManager.revealInFinder(rootItem) }) {
                    Label(L10n.get("explorer.revealInFinder"), systemImage: "folder")
                }
            }
        }
    }

    // MARK: - Actions

    private func refresh() {
        isRefreshing = true
        fileSystemManager.refreshProject()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isRefreshing = false
        }
    }

    private func showNewFileDialog() {
        guard let rootItem = fileSystemManager.projectRoot else { return }
        fileSystemManager.showNewFileDialog(in: rootItem) { _ in }
    }

    private func showNewFolderDialog() {
        guard let rootItem = fileSystemManager.projectRoot else { return }
        fileSystemManager.showNewFolderDialog(in: rootItem) { _ in }
    }

    private func handleDoubleClick(_ item: FileSystemItem) {
        if !item.isDirectory {
            tabManager.openFile(item)
        }
    }

    private func handleSingleClick(_ item: FileSystemItem) {
        selectedItem = item
        fileSystemManager.selectedItem = item
        // 파일인 경우 탭으로 열기
        if !item.isDirectory {
            tabManager.openFile(item)
        }
    }

    // MARK: - Drag and Drop

    /// 항목 이동 처리 (저장되지 않은 파일 확인 및 이름 충돌 처리 포함)
    private func handleMoveItem(_ sourceItem: FileSystemItem, to destinationFolder: FileSystemItem) {
        // 1단계: 파일이 수정된 상태인지 확인
        if !sourceItem.isDirectory && tabManager.isModified(url: sourceItem.url) {
            // 수정된 파일 이동 다이얼로그 표시
            fileSystemManager.showModifiedFileMoveDialog(fileName: sourceItem.name) { result in
                switch result {
                case .saveAndMove:
                    // 현재 에디터 내용 가져와서 저장
                    if let content = getCurrentEditorContent?() {
                        if let tabIndex = tabManager.findTab(with: sourceItem.url) {
                            _ = tabManager.saveTab(at: tabIndex, content: content)
                        }
                    }
                    // 저장 후 이름 충돌 확인하여 이동
                    self.checkNameConflictAndMove(sourceItem, to: destinationFolder)

                case .cancel:
                    // 취소 - 아무것도 하지 않음
                    break
                }
            }
        } else {
            // 수정되지 않은 상태이거나 폴더인 경우 이름 충돌 확인하여 이동
            checkNameConflictAndMove(sourceItem, to: destinationFolder)
        }
    }

    /// 이름 충돌 확인 후 이동
    private func checkNameConflictAndMove(_ sourceItem: FileSystemItem, to destinationFolder: FileSystemItem) {
        // 대상 폴더에 같은 이름의 파일이 있는지 확인
        if fileSystemManager.fileExists(named: sourceItem.name, in: destinationFolder) {
            // 이름 충돌 다이얼로그 표시
            fileSystemManager.showNameConflictDialog(fileName: sourceItem.name) { result in
                switch result {
                case .rename(let newName):
                    // 새 이름이 또 충돌하는지 확인
                    if fileSystemManager.fileExists(named: newName, in: destinationFolder) {
                        // 재귀적으로 다시 충돌 다이얼로그 표시
                        self.checkNameConflictAndMove(sourceItem, to: destinationFolder)
                    } else {
                        // 새 이름으로 이동
                        _ = fileSystemManager.move(sourceItem, to: destinationFolder, withNewName: newName)
                    }

                case .cancel:
                    // 취소 - 아무것도 하지 않음
                    break
                }
            }
        } else {
            // 충돌 없음 - 바로 이동
            _ = fileSystemManager.move(sourceItem, to: destinationFolder)
        }
    }
}

#Preview("빈 상태") {
    ProjectExplorerView()
        .frame(width: 220, height: 400)
}

#Preview("모의 데이터") {
    // 모의 프로젝트 구조 생성
    let root = FileSystemItem(
        url: URL(fileURLWithPath: "/tmp/MyNovel.weaveproj"),
        isDirectory: true
    )
    root.isExpanded = true

    // 섹션 폴더들
    let sections = [
        ("세계관", true, 3),
        ("캐릭터", true, 5),
        ("플롯", true, 2),
        ("콘티", true, 0),
        ("에디터", true, 1),
        ("아이디어", true, 4)
    ]

    var sectionItems: [FileSystemItem] = []
    for (name, isDir, childCount) in sections {
        let item = FileSystemItem(
            url: URL(fileURLWithPath: "/tmp/MyNovel.weaveproj/\(name)"),
            isDirectory: isDir,
            parent: root
        )
        // 자식 항목 생성 (개수 표시용)
        if childCount > 0 {
            item.children = (1...childCount).map { index in
                FileSystemItem(
                    url: URL(fileURLWithPath: "/tmp/MyNovel.weaveproj/\(name)/item\(index).md"),
                    isDirectory: false,
                    parent: item
                )
            }
        }
        sectionItems.append(item)
    }
    root.children = sectionItems

    // 첫 번째 폴더 펼치기
    sectionItems[0].isExpanded = true

    return VStack(alignment: .leading, spacing: 0) {
        // 헤더
        HStack {
            Text("MyNovel")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppColors.sidebarHeaderText)
                .textCase(.uppercase)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)

        Divider()

        // 파일 트리
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(sectionItems) { item in
                    FileSystemItemRow(
                        item: item,
                        depth: 0,
                        onSelect: { _ in },
                        onDoubleClick: { _ in }
                    )
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
    }
    .frame(width: 220, height: 400)
}
