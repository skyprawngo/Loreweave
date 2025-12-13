//
//  MainEditorView.swift
//  Loreweave
//
//  메인 에디터 화면
//  계층 구조:
//  - MainEditorView (HStack)
//    ├── NavigationSplitView
//    │   ├── ProjectExplorerView (sidebar)
//    │   └── EditorContainerView (detail)
//    └── AIAssistantView (우측 패널)
//

import SwiftUI
import UniformTypeIdentifiers

struct MainEditorView: View {
    @Bindable var projectManager: ProjectManager
    @EnvironmentObject var appCommands: AppCommands

    private var fileSystemManager: FileSystemManager { FileSystemManager.shared }
    @State private var tabManager = EditorTabManager.shared

    // AI 패널 크기
    private let aiPanelWidth: CGFloat = 350

    // UI 상태
    @State private var isAIPanelVisible: Bool = true
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var searchText: String = ""
    @State private var isSpotlightExpanded: Bool = false

    var body: some View {
        ZStack(alignment: .top) {
            // 메인 콘텐츠
            HStack(spacing: 0) {
                // 메인 콘텐츠 (NavigationSplitView)
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    // 사이드바 (ProjectExplorerView)
                    ProjectExplorerView()
                        .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 350)
                } detail: {
                    // 에디터 컨테이너
                    EditorContainerView(projectManager: projectManager)
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

            // 스포트라이트 확장 오버레이
            SpotlightOverlay(text: $searchText, isExpanded: $isSpotlightExpanded)
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
            NSApp.activate(ignoringOtherApps: true)
        }
        .onDisappear {
            fileSystemManager.closeProject()
        }
        .appCommandHandler(
            appCommands: appCommands,
            tabManager: tabManager,
            fileSystemManager: fileSystemManager,
            projectManager: projectManager,
            isAIPanelVisible: $isAIPanelVisible,
            columnVisibility: $columnVisibility,
            onInitializeFileSystem: initializeFileSystem
        )
    }

    // MARK: - File System

    private func initializeFileSystem() {
        guard let projectPath = projectManager.currentProject?.path else { return }
        fileSystemManager.initializeProject(at: projectPath)
    }

    // MARK: - Navigation

    private func goBack() {
        // TODO: 이전 파일/위치로 이동
    }

    private func goForward() {
        // TODO: 다음 파일/위치로 이동
    }
}

// MARK: - App Command Handler Modifier

/// 앱 커맨드 핸들러를 통합한 ViewModifier
struct AppCommandHandlerModifier: ViewModifier {
    let appCommands: AppCommands
    let tabManager: EditorTabManager
    let fileSystemManager: FileSystemManager
    let projectManager: ProjectManager
    @Binding var isAIPanelVisible: Bool
    @Binding var columnVisibility: NavigationSplitViewVisibility
    let onInitializeFileSystem: () -> Void

    func body(content: Content) -> some View {
        content
            // 탭 관련 커맨드
            .onReceive(appCommands.$closeTabRequested) { requested in
                if requested {
                    tabManager.closeCurrentTab()
                    appCommands.closeTabRequested = false
                }
            }
            .onReceive(appCommands.$closeAllTabsRequested) { requested in
                if requested {
                    tabManager.closeAllTabs()
                    appCommands.closeAllTabsRequested = false
                }
            }
            .onReceive(appCommands.$nextTabRequested) { requested in
                if requested {
                    tabManager.selectNextTab()
                    appCommands.nextTabRequested = false
                }
            }
            .onReceive(appCommands.$previousTabRequested) { requested in
                if requested {
                    tabManager.selectPreviousTab()
                    appCommands.previousTabRequested = false
                }
            }
            .onReceive(appCommands.$goToTabRequested) { tabIndex in
                if let index = tabIndex {
                    tabManager.selectTab(at: index - 1)
                    appCommands.goToTabRequested = nil
                }
            }
            // UI 토글 커맨드
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
            // 파일/폴더 커맨드
            .onReceive(appCommands.$newFileRequested) { requested in
                if requested {
                    if let rootItem = fileSystemManager.projectRoot {
                        fileSystemManager.showNewFileDialog(in: rootItem) { _ in }
                    }
                    appCommands.newFileRequested = false
                }
            }
            .onReceive(appCommands.$newFolderRequested) { requested in
                if requested {
                    if let rootItem = fileSystemManager.projectRoot {
                        fileSystemManager.showNewFolderDialog(in: rootItem) { _ in }
                    }
                    appCommands.newFolderRequested = false
                }
            }
            .onReceive(appCommands.$refreshProjectRequested) { requested in
                if requested {
                    fileSystemManager.refreshProject()
                    appCommands.refreshProjectRequested = false
                }
            }
            .onReceive(appCommands.$openFileRequested) { requested in
                if requested {
                    handleOpenFile()
                    appCommands.openFileRequested = false
                }
            }
            .onReceive(appCommands.$openProjectRequested) { requested in
                if requested {
                    handleOpenProject()
                    appCommands.openProjectRequested = false
                }
            }
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

        // 기존 프로젝트 닫기 (세션 저장 포함)
        fileSystemManager.closeProject()

        // 새 프로젝트 열기 (openProjectFromFile 내부에서 세션 복원됨)
        if projectManager.openProjectFromFile(at: url) != nil {
            onInitializeFileSystem()
        }
    }
}

extension View {
    func appCommandHandler(
        appCommands: AppCommands,
        tabManager: EditorTabManager,
        fileSystemManager: FileSystemManager,
        projectManager: ProjectManager,
        isAIPanelVisible: Binding<Bool>,
        columnVisibility: Binding<NavigationSplitViewVisibility>,
        onInitializeFileSystem: @escaping () -> Void
    ) -> some View {
        modifier(AppCommandHandlerModifier(
            appCommands: appCommands,
            tabManager: tabManager,
            fileSystemManager: fileSystemManager,
            projectManager: projectManager,
            isAIPanelVisible: isAIPanelVisible,
            columnVisibility: columnVisibility,
            onInitializeFileSystem: onInitializeFileSystem
        ))
    }
}

#Preview {
    MainEditorView(projectManager: ProjectManager.shared)
        .environmentObject(AppCommands.shared)
}
