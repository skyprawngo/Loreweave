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

// MARK: - Toolbar Search Field

/// 툴바용 NSSearchField 래퍼
struct ToolbarSearchField: NSViewRepresentable {
    @Binding var text: String
    var prompt: String
    var onSearch: () -> Void = {}

    func makeNSView(context: Context) -> NSSearchField {
        let searchField = NSSearchField()
        searchField.placeholderString = prompt
        searchField.delegate = context.coordinator
        searchField.bezelStyle = .roundedBezel
        searchField.focusRingType = .none
        return searchField
    }

    func updateNSView(_ nsView: NSSearchField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSearch: onSearch)
    }

    class Coordinator: NSObject, NSSearchFieldDelegate {
        @Binding var text: String

        var onSearch: () -> Void
        init(text: Binding<String>, onSearch: @escaping () -> Void) {
            _text = text
            self.onSearch = onSearch
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) { onSearch(); return true }
            return false
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let searchField = obj.object as? NSSearchField else { return }
            text = searchField.stringValue
        }
    }
}

struct MainEditorView: View {
    @Bindable var projectManager: ProjectManager
    @EnvironmentObject var appCommands: AppCommands

    private var fileSystemManager: FileSystemManager { FileSystemManager.shared }
    @State private var tabManager = EditorTabManager.shared

    // AI 패널 크기
    @State private var aiPanelWidth = UserSettings.shared.aiAssistantPanelWidth
    @State private var showingProjectSearch = false
    @State private var showingNewProject = false
    @State private var newProjectName = ""
    @State private var newProjectDirectory: URL?

    // UI 상태
    @State private var isAIPanelVisible: Bool = true
    @State private var isAIDetailView: Bool = false  // AI 패널 상세 뷰 모드
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var searchText: String = ""

    var body: some View {
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

            // AI 패널 (우측)
            if isAIPanelVisible {
                Rectangle().fill(AppColors.separator).frame(width: 5)
                    .gesture(DragGesture().onChanged { value in
                        aiPanelWidth = min(600, max(280, UserSettings.shared.aiAssistantPanelWidth - value.translation.width))
                    }.onEnded { _ in UserSettings.shared.aiAssistantPanelWidth = aiPanelWidth })
                AIAssistantView(
                    projectFolderURL: projectManager.currentProject?.path,
                    isInDetailView: $isAIDetailView
                )
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
            // 네비게이션 버튼 + 검색바
            ToolbarItemGroup(placement: .navigation) {
                NavigationButtonsView(
                    onBack: { goBack() },
                    onForward: { goForward() }
                )

                // 검색바 (네비게이션 버튼 오른쪽에 배치, 간격 추가)
                ToolbarSearchField(text: $searchText, prompt: L10n.get("toolbar.searchPlaceholder"), onSearch: { showingProjectSearch = true })
                    .frame(minWidth: 180, maxWidth: 250)
                    .padding(.leading, 12)
                Button { showingProjectSearch = true } label: { Image(systemName: "magnifyingglass") }
                    .help(L10n.get("search.project"))
            }

            // AI 뒤로가기 버튼 (상세 뷰일 때만 표시)
            ToolbarItem(placement: .primaryAction) {
                if isAIPanelVisible && isAIDetailView {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isAIDetailView = false
                        }
                    }) {
                        Label(L10n.get("ai.chat.backToList"), systemImage: "chevron.left")
                    }
                    .help(L10n.get("ai.chat.backToList"))
                }
            }

            // AI 패널 토글 버튼 (가장 우측에 배치)
            ToolbarItem(placement: .confirmationAction) {
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
        .sheet(isPresented: $showingProjectSearch) {
            ProjectSearchView(projectURL: projectManager.currentProject?.path, query: searchText)
        }
        .alert(L10n.get("storage.operationFailed"), isPresented: Binding(
            get: { fileSystemManager.operationError != nil },
            set: { if !$0 { fileSystemManager.operationError = nil } }
        )) {
            Button(L10n.common.confirm) { fileSystemManager.operationError = nil }
        } message: { Text(fileSystemManager.operationError ?? "") }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("aiDraftAction"))) { notification in
            if !isAIPanelVisible {
                isAIPanelVisible = true
                DispatchQueue.main.async { NotificationCenter.default.post(notification) }
            }
        }
        .onReceive(appCommands.$newProjectRequested) { requested in
            if requested {
                appCommands.newProjectRequested = false
                newProjectDirectory = projectManager.defaultSaveDirectory
                showingNewProject = true
            }
        }
        .sheet(isPresented: $showingNewProject) {
            NewProjectSheet(projectName: $newProjectName, selectedDirectory: $newProjectDirectory, projectManager: projectManager) {
                guard let directory = newProjectDirectory,
                      projectManager.createProject(name: newProjectName, at: directory) != nil else { return }
                showingNewProject = false
                newProjectName = ""
                initializeFileSystem()
            } onCancel: { showingNewProject = false }
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
        tabManager.goBack()
    }

    private func goForward() {
        tabManager.goForward()
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
                    if let rootItem = fileSystemManager.targetDirectoryForNewFile {
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
