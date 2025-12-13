//
//  MainEditorView.swift
//  Loreweave
//
//  메인 에디터 화면
//  계층 구조:
//  - MainEditorView (HStack)
//    ├── NavigationSplitView
//    │   ├── SidebarView (sidebar)
//    │   └── EditorContainerView (detail)
//    └── AIAssistantView (우측 패널)
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

    // UI 상태
    @State private var isAIPanelVisible: Bool = true
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var searchText: String = ""

    var body: some View {
        HStack(spacing: 0) {
            // 메인 콘텐츠 (NavigationSplitView)
            NavigationSplitView(columnVisibility: $columnVisibility) {
                // 사이드바
                SidebarView()
                    .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 350)
            } detail: {
                // 에디터 컨테이너
                EditorContainerView(trailingPadding: 0)
                    .environmentObject(appCommands)
            }
            .navigationSplitViewStyle(.balanced)

            // AI 첨삭 패널 (우측)
            if isAIPanelVisible {
                AIAssistantView()
                    .frame(width: aiPanelWidth)
                    .ignoresSafeArea(.container, edges: .top)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .background(ThemeAwareBackground(material: .sidebar, blendingMode: .behindWindow))
        .ignoresSafeArea(.container, edges: .top)
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

            // 스포트라이트 검색
            ToolbarItem(placement: .principal) {
                SpotlightView(text: $searchText) {
                    // TODO: 검색 기능 구현
                }
            }

            // AI 패널 토글 버튼
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isAIPanelVisible.toggle()
                    }
                }) {
                    Image(systemName: isAIPanelVisible ? "sidebar.trailing" : "sparkle")
                }
                .help(L10n.ai.togglePanel)
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
