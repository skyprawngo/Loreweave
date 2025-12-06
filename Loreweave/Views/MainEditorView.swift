//
//  MainEditorView.swift
//  Loreweave
//
//  메인 에디터 화면 - 사이드바, 탭바, 에디터, AI 패널 포함
//

import SwiftUI

struct MainEditorView: View {
    @Bindable var projectManager: ProjectManager
    @EnvironmentObject var appCommands: AppCommands
    @State private var fileSystemManager = FileSystemManager.shared
    @State private var tabManager = EditorTabManager.shared
    @State private var isAIPanelVisible: Bool = true
    @State private var isSidebarVisible: Bool = true
    @State private var searchText: String = ""
    @State private var editorFontSize: CGFloat = 16

    // 찾기/바꾸기 상태 (오버레이용)
    @State private var showFindReplace: Bool = false
    @State private var findSearchText: String = ""
    @State private var replaceText: String = ""
    @State private var searchScope: SearchScope = .currentFile
    @State private var searchOptions: SearchOptions = SearchOptions()
    @State private var showReplaceField: Bool = false
    @State private var matchCount: Int = 0

    // EditorView 참조용
    @State private var editorView: EditorView?

    var body: some View {
        NavigationSplitView(columnVisibility: Binding(
            get: { isSidebarVisible ? .all : .detailOnly },
            set: { isSidebarVisible = ($0 != .detailOnly) }
        )) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 300)
        } detail: {
            ZStack(alignment: .topTrailing) {
                // 에디터 영역 (탭바 + 에디터)
                ZStack(alignment: .top) {
                    VStack(spacing: 0) {
                        // 탭바
                        TabBarView()

                        // 에디터
                        EditorView(
                            showFindReplace: $showFindReplace,
                            findSearchText: $findSearchText,
                            replaceText: $replaceText,
                            searchScope: $searchScope,
                            searchOptions: $searchOptions,
                            showReplaceField: $showReplaceField,
                            matchCount: $matchCount
                        )
                        .environmentObject(appCommands)
                    }

                    // 찾기/바꾸기 오버레이 (검색 필드 아래에 표시)
                    if showFindReplace {
                        VStack(spacing: 0) {
                            FindReplaceView(
                                isVisible: $showFindReplace,
                                searchText: $findSearchText,
                                replaceText: $replaceText,
                                searchScope: $searchScope,
                                searchOptions: $searchOptions,
                                showReplace: $showReplaceField,
                                matchCount: matchCount,
                                onFind: { performFind() },
                                onFindNext: { findNext() },
                                onFindPrevious: { findPrevious() },
                                onReplace: { replaceOne() },
                                onReplaceAll: { replaceAll() }
                            )
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(AppColors.barBackground)
                                    .shadow(color: AppColors.shadowDrop, radius: 8, y: 4)
                            )
                            .padding(.horizontal, 16)
                            .padding(.top, 8)

                            Spacer()
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .padding(.trailing, isAIPanelVisible ? 350 : 0)
                .animation(.easeInOut(duration: 0.25), value: isAIPanelVisible)

                // AI 패널 (탭바와 동일 계층, 우측 오버레이)
                if isAIPanelVisible {
                    AIAssistantView()
                        .frame(width: 350)
                        .padding(.trailing, 8)
                        .padding(.top, 8)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .trailing))
                }
            }
        }
        .navigationTitle("")
        .toolbar {
            // 이전/다음 네비게이션 버튼 (파인더 스타일)
            ToolbarItemGroup(placement: .navigation) {
                NavigationButtonsView(
                    onBack: { goBack() },
                    onForward: { goForward() }
                )
            }

            // 검색 텍스트박스
            ToolbarItem(placement: .principal) {
                SearchFieldView(text: $searchText) {
                    // 검색 필드 활성화 시 찾기/바꾸기 오버레이 표시
                    if !showFindReplace {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showFindReplace = true
                        }
                    }
                }
            }

            // AI 패널 토글 버튼
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isAIPanelVisible.toggle()
                    }
                }) {
                    Image(systemName: "sparkle")
                        .symbolVariant(isAIPanelVisible ? .none : .slash)
                        .foregroundStyle(AppColors.accent)
                }
                .help(L10n.ai.togglePanel)
            }
        }
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .onAppear {
            initializeFileSystem()
        }
        .onDisappear {
            fileSystemManager.closeProject()
        }
        // 커맨드 핸들링 (저장은 EditorView에서 처리)
        .onReceive(appCommands.$closeTabRequested) { requested in
            if requested { handleCloseTab(); appCommands.closeTabRequested = false }
        }
        .onReceive(appCommands.$closeAllTabsRequested) { requested in
            if requested { handleCloseAllTabs(); appCommands.closeAllTabsRequested = false }
        }
        .onReceive(appCommands.$toggleSidebarRequested) { requested in
            if requested { isSidebarVisible.toggle(); appCommands.toggleSidebarRequested = false }
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
        // 툴바 검색 필드 입력 시 FindReplaceView 열기
        .onChange(of: searchText) { oldValue, newValue in
            if !newValue.isEmpty && oldValue.isEmpty {
                appCommands.findRequested = true
            }
        }
    }

    // MARK: - File System Initialization

    private func initializeFileSystem() {
        guard let projectPath = projectManager.currentProject?.path else { return }
        fileSystemManager.initializeProject(at: projectPath)
    }

    private func closeProjectAndCleanup() {
        fileSystemManager.closeProject()
        projectManager.closeProject()
    }

    // MARK: - Navigation Actions

    private func goBack() {
        // TODO: 이전 파일/위치로 이동 기능 구현
    }

    private func goForward() {
        // TODO: 다음 파일/위치로 이동 기능 구현
    }

    // MARK: - Command Handlers

    /// 탭 닫기 처리
    private func handleCloseTab() {
        tabManager.closeCurrentTab()
    }

    /// 모든 탭 닫기 처리
    private func handleCloseAllTabs() {
        tabManager.closeAllTabs()
    }

    /// 다음 탭 이동
    private func handleNextTab() {
        tabManager.selectNextTab()
    }

    /// 이전 탭 이동
    private func handlePreviousTab() {
        tabManager.selectPreviousTab()
    }

    /// 특정 탭으로 이동
    private func handleGoToTab(_ index: Int) {
        tabManager.selectTab(at: index - 1) // 1-based to 0-based
    }

    /// 새 파일 생성
    private func handleNewFile() {
        guard let rootItem = fileSystemManager.projectRoot else { return }
        fileSystemManager.showNewFileDialog(in: rootItem) { _ in }
    }

    // MARK: - Find/Replace Functions

    /// 찾기 수행
    private func performFind() {
        // EditorView에서 실제 검색 로직 처리
        // 여기서는 상태만 관리
    }

    /// 다음 찾기
    private func findNext() {
        performFind()
    }

    /// 이전 찾기
    private func findPrevious() {
        performFind()
    }

    /// 하나 바꾸기
    private func replaceOne() {
        // EditorView에서 처리
    }

    /// 모두 바꾸기
    private func replaceAll() {
        // EditorView에서 처리
    }

    /// 새 폴더 생성
    private func handleNewFolder() {
        guard let rootItem = fileSystemManager.projectRoot else { return }
        fileSystemManager.showNewFolderDialog(in: rootItem) { _ in }
    }

    /// 프로젝트 새로고침
    private func handleRefreshProject() {
        fileSystemManager.refreshProject()
    }
}

#Preview {
    MainEditorView(projectManager: ProjectManager.shared)
        .environmentObject(AppCommands.shared)
}
