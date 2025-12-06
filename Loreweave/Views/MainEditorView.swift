//
//  MainEditorView.swift
//  Loreweave
//
//  메인 에디터 화면
//  계층 구조:
//  - MainEditorView (ZStack)
//    ├── NavigationSplitView (배경, 에디터 우측 패딩으로 AI 패널 공간 확보)
//    │   ├── SidebarView (sidebar)
//    │   └── EditorContainerView (detail)
//    └── AIAssistantView (오버레이, 우측)
//

import SwiftUI
import UniformTypeIdentifiers

struct MainEditorView: View {
    @Bindable var projectManager: ProjectManager
    @EnvironmentObject var appCommands: AppCommands

    private var fileSystemManager: FileSystemManager { FileSystemManager.shared }
    private var tabManager: EditorTabManager { EditorTabManager.shared }

    // AI 패널 크기
    private let aiPanelWidth: CGFloat = 350
    private let aiPanelPadding: CGFloat = 8

    /// AI 패널 전체 폭 (패널 폭 + 패딩)
    private var aiPanelTotalWidth: CGFloat {
        aiPanelWidth + aiPanelPadding * 2
    }

    // UI 상태
    @State private var isAIPanelVisible: Bool = true
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var searchText: String = ""

    // 찾기/바꾸기 상태
    @State private var showFindReplace: Bool = false
    @State private var findSearchText: String = ""
    @State private var replaceText: String = ""
    @State private var searchScope: SearchScope = .currentFile
    @State private var searchOptions: SearchOptions = SearchOptions()
    @State private var showReplaceField: Bool = false
    @State private var matchCount: Int = 0

    var body: some View {
        ZStack(alignment: .trailing) {
            // 메인 콘텐츠 (NavigationSplitView)
            NavigationSplitView(columnVisibility: $columnVisibility) {
                // 사이드바
                SidebarView()
                    .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 350)
            } detail: {
                // 에디터 컨테이너 (AI 패널 폭 정보 전달)
                EditorContainerView(
                    showFindReplace: $showFindReplace,
                    findSearchText: $findSearchText,
                    replaceText: $replaceText,
                    searchScope: $searchScope,
                    searchOptions: $searchOptions,
                    showReplaceField: $showReplaceField,
                    matchCount: $matchCount,
                    trailingPadding: isAIPanelVisible ? aiPanelTotalWidth : 0
                )
                .environmentObject(appCommands)
            }
            .navigationSplitViewStyle(.balanced)

            // AI 첨삭 패널 (우측 오버레이)
            if isAIPanelVisible {
                AIAssistantView(onToggle: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isAIPanelVisible = false
                    }
                })
                .padding(.horizontal, aiPanelPadding)
                .padding(.bottom, aiPanelPadding)
                .frame(width: aiPanelTotalWidth)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            // AI 패널 토글 버튼 (패널 닫혔을 때만 표시)
            if !isAIPanelVisible {
                VStack {
                    HStack {
                        Spacer()
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                isAIPanelVisible = true
                            }
                        }) {
                            Image(systemName: "sparkle")
                                .font(.system(size: 14))
                                .foregroundStyle(AppColors.toolbarIcon)
                        }
                        .buttonStyle(.plain)
                        .help(L10n.ai.togglePanel)
                        .padding(.trailing, 16)
                        .padding(.top, 14)
                    }
                    Spacer()
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isAIPanelVisible)
        .animation(.easeInOut(duration: 0.25), value: columnVisibility)
        .toolbar {
            // 네비게이션 버튼
            ToolbarItemGroup(placement: .navigation) {
                NavigationButtonsView(
                    onBack: { goBack() },
                    onForward: { goForward() }
                )
            }

            // 검색 필드
            ToolbarItem(placement: .principal) {
                SearchFieldView(text: $searchText) {
                    if !showFindReplace {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showFindReplace = true
                        }
                    }
                }
            }
        }
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .onAppear {
            initializeFileSystem()
            // 앱을 활성화
            NSApp.activate(ignoringOtherApps: true)
        }
        .onDisappear {
            fileSystemManager.closeProject()
        }
        // 커맨드 핸들링
        .onReceive(appCommands.$closeTabRequested) { requested in
            if requested { handleCloseTab(); appCommands.closeTabRequested = false }
        }
        .onReceive(appCommands.$closeAllTabsRequested) { requested in
            if requested { handleCloseAllTabs(); appCommands.closeAllTabsRequested = false }
        }
        .onReceive(appCommands.$toggleSidebarRequested) { requested in
            if requested {
                withAnimation(.easeInOut(duration: 0.25)) {
                    columnVisibility = columnVisibility == .all ? .detailOnly : .all
                }
                appCommands.toggleSidebarRequested = false
            }
        }
        .onReceive(appCommands.$toggleAIPanelRequested) { requested in
            if requested {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isAIPanelVisible.toggle()
                }
                appCommands.toggleAIPanelRequested = false
            }
        }
        .onReceive(appCommands.$nextTabRequested) { requested in
            if requested { handleNextTab(); appCommands.nextTabRequested = false }
        }
        .onReceive(appCommands.$previousTabRequested) { requested in
            if requested { handlePreviousTab(); appCommands.previousTabRequested = false }
        }
        .onReceive(appCommands.$goToTabRequested) { tabIndex in
            if let index = tabIndex { handleGoToTab(index); appCommands.goToTabRequested = nil }
        }
        .onReceive(appCommands.$newFileRequested) { requested in
            if requested { handleNewFile(); appCommands.newFileRequested = false }
        }
        .onReceive(appCommands.$newFolderRequested) { requested in
            if requested { handleNewFolder(); appCommands.newFolderRequested = false }
        }
        .onReceive(appCommands.$refreshProjectRequested) { requested in
            if requested { handleRefreshProject(); appCommands.refreshProjectRequested = false }
        }
        .onReceive(appCommands.$openFileRequested) { requested in
            if requested { handleOpenFile(); appCommands.openFileRequested = false }
        }
        .onReceive(appCommands.$openProjectRequested) { requested in
            if requested { handleOpenProject(); appCommands.openProjectRequested = false }
        }
        .onChange(of: searchText) { oldValue, newValue in
            if !newValue.isEmpty && oldValue.isEmpty {
                appCommands.findRequested = true
            }
        }
    }

    // MARK: - File System

    private func initializeFileSystem() {
        guard let projectPath = projectManager.currentProject?.path else { return }
        fileSystemManager.initializeProject(at: projectPath)
    }

    private func closeProjectAndCleanup() {
        fileSystemManager.closeProject()
        projectManager.closeProject()
    }

    // MARK: - Navigation

    private func goBack() {
        // TODO: 이전 파일/위치로 이동
    }

    private func goForward() {
        // TODO: 다음 파일/위치로 이동
    }

    // MARK: - Command Handlers

    private func handleCloseTab() {
        tabManager.closeCurrentTab()
    }

    private func handleCloseAllTabs() {
        tabManager.closeAllTabs()
    }

    private func handleNextTab() {
        tabManager.selectNextTab()
    }

    private func handlePreviousTab() {
        tabManager.selectPreviousTab()
    }

    private func handleGoToTab(_ index: Int) {
        tabManager.selectTab(at: index - 1)
    }

    private func handleNewFile() {
        guard let rootItem = fileSystemManager.projectRoot else { return }
        fileSystemManager.showNewFileDialog(in: rootItem) { _ in }
    }

    private func handleNewFolder() {
        guard let rootItem = fileSystemManager.projectRoot else { return }
        fileSystemManager.showNewFolderDialog(in: rootItem) { _ in }
    }

    private func handleRefreshProject() {
        fileSystemManager.refreshProject()
    }

    private func handleOpenFile() {
        let panel = NSOpenPanel()
        panel.title = L10n.get("shortcut.file.open")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.text, .plainText, .utf8PlainText]

        if let projectPath = projectManager.currentProject?.path {
            panel.directoryURL = projectPath
        }

        guard panel.runModal() == .OK else { return }

        for url in panel.urls {
            let fileItem = FileSystemItem(url: url, isDirectory: false)
            tabManager.openFile(fileItem)
        }
    }

    private func handleOpenProject() {
        guard let url = projectManager.showOpenPanel() else { return }

        fileSystemManager.closeProject()
        tabManager.closeAllTabs()

        // openProjectFromFile이 세션도 복원함
        if projectManager.openProjectFromFile(at: url) != nil {
            initializeFileSystem()
        }
    }
}

#Preview {
    MainEditorView(projectManager: ProjectManager.shared)
        .environmentObject(AppCommands.shared)
}
