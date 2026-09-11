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

final class ToolbarNativeSearchField: NSSearchField {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, self.window === window else { return }
            window.makeFirstResponder(self)
        }
    }
}

/// 툴바용 NSSearchField 래퍼
struct ToolbarSearchField: NSViewRepresentable {
    @Binding var text: String
    var prompt: String
    var onSearch: () -> Void = {}
    var onCancel: () -> Void = {}

    func makeNSView(context: Context) -> NSSearchField {
        let searchField = ToolbarNativeSearchField()
        searchField.placeholderString = prompt
        searchField.delegate = context.coordinator
        searchField.bezelStyle = .roundedBezel
        searchField.focusRingType = .none
        DispatchQueue.main.async { [weak searchField] in
            guard let searchField else { return }
            searchField.window?.makeFirstResponder(searchField)
        }
        return searchField
    }

    func updateNSView(_ nsView: NSSearchField, context: Context) {
        context.coordinator.onSearch = onSearch
        context.coordinator.onCancel = onCancel
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSearch: onSearch)
    }

    class Coordinator: NSObject, NSSearchFieldDelegate {
        @Binding var text: String

        var onCancel: () -> Void = {}
        var onSearch: () -> Void
        init(text: Binding<String>, onSearch: @escaping () -> Void) {
            _text = text
            self.onSearch = onSearch
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) { onCancel(); return true }
            if commandSelector == #selector(NSResponder.insertNewline(_:)) { onSearch(); return true }
            return false
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let searchField = obj.object as? NSSearchField else { return }
            text = searchField.stringValue
        }
    }
}

private struct ProjectSearchPresentation: Identifiable {
    let id = UUID()
    let projectURL: URL?
}

struct MainEditorView: View {
    @Bindable var projectManager: ProjectManager
    @EnvironmentObject var appCommands: AppCommands
    @Environment(\.openWindow) private var openWindow

    private var fileSystemManager: FileSystemManager { FileSystemManager.shared }
    @State private var tabManager = EditorTabManager.shared

    // AI 패널 크기
    @State private var aiPanelWidth = UserSettings.shared.aiAssistantPanelWidth
    @State private var projectSearchPresentation: ProjectSearchPresentation?
    @State private var showingNewProject = false
    @State private var newProjectName = ""
    @State private var newProjectDirectory: URL?

    // UI 상태
    @State private var isAIPanelVisible: Bool = true
    @State private var isAIDetailView: Bool = false  // AI 패널 상세 뷰 모드
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var searchText: String = ""
    @State private var isSearchExpanded = false
    @State private var windowWidth: CGFloat = 1400
    @State private var editorWidth: CGFloat = 800
    @State private var sidebarWidth: CGFloat = 250

    private var resolvedAIPanelWidth: CGFloat {
        min(aiPanelWidth, max(280, windowWidth - (columnVisibility == .detailOnly ? 0 : sidebarWidth) - 360))
    }

    var body: some View {
        HStack(spacing: 0) {
            // 메인 콘텐츠 (NavigationSplitView)
            NavigationSplitView(columnVisibility: $columnVisibility) {
                // 사이드바 (ProjectExplorerView)
                ProjectExplorerView()
                    .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 350)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { sidebarWidth = $0 }
            } detail: {
                // 에디터 컨테이너
                EditorContainerView(projectManager: projectManager)
                    .environmentObject(appCommands)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { editorWidth = $0 }
            }
            .navigationSplitViewStyle(.balanced)

            // AI 패널 (우측)
            if isAIPanelVisible {
                Rectangle().fill(AppColors.separator).frame(width: 1)
                    .padding(.horizontal, 3)
                    .contentShape(Rectangle())
                    .gesture(DragGesture().onChanged { value in
                        aiPanelWidth = min(600, max(280, UserSettings.shared.aiAssistantPanelWidth - value.translation.width))
                    }.onEnded { _ in UserSettings.shared.aiAssistantPanelWidth = aiPanelWidth })
            }
            // Hiding a panel must not recreate its account/chat state or cancel its request.
            AIAssistantView(
                projectFolderURL: projectManager.currentProject?.path,
                isInDetailView: $isAIDetailView
            )
            .frame(width: resolvedAIPanelWidth)
            .frame(width: isAIPanelVisible ? resolvedAIPanelWidth : 0, alignment: .trailing)
            .clipped()
            .accessibilityHidden(!isAIPanelVisible)
            .allowsHitTesting(isAIPanelVisible)
        }
        .background(ThemeAwareBackground(material: .sidebar, blendingMode: .behindWindow)
            .ignoresSafeArea(edges: .top))
        .frame(minWidth: 1000, minHeight: 500)
        // Avoid full-document wrap layout at every animation frame when panels resize.
        .transaction { $0.animation = nil }

        .toolbar {
            ToolbarItem(placement: .navigation) {
                HStack(spacing: 8) {
                    NavigationButtonsView(onBack: goBack, onForward: goForward,
                        canGoBack: tabManager.canGoBack, canGoForward: tabManager.canGoForward)
                    Group {
                        if isSearchExpanded {
                            ToolbarSearchField(text: $searchText,
                                prompt: L10n.get("toolbar.searchPlaceholder"),
                                onSearch: { projectSearchPresentation = ProjectSearchPresentation(projectURL: projectManager.currentProject?.path) },
                                onCancel: { isSearchExpanded = false })
                                .frame(width: min(200, max(140, editorWidth * 0.3)), height: 30)
                                .glassEffect(.regular, in: .capsule)
                        } else {
                            Button { isSearchExpanded = true } label: {
                                Image(systemName: "magnifyingglass").frame(width: 16, height: 16)
                            }
                            .buttonStyle(.plain)
                            .frame(width: 32, height: 32)
                            .glassEffect(.regular.interactive(), in: .circle)
                            .help(L10n.get("search.project"))
                            .accessibilityLabel(L10n.get("search.project"))
                        }
                    }
                    TabBarView()
                        .frame(minWidth: 100, maxWidth: .infinity)
                }
                .animation(.smooth(duration: 0.22), value: isSearchExpanded)
                .frame(width: max(300, windowWidth - (columnVisibility == .detailOnly ? 0 : sidebarWidth) - 180))
            }
            .sharedBackgroundVisibility(.hidden)

            ToolbarSpacer(.flexible, placement: .primaryAction)
            ToolbarItemGroup(placement: .primaryAction) {
                Button { NSApp.keyWindow?.toggleFullScreen(nil) } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .help(L10n.get("toolbar.toggleFullScreen"))
                .accessibilityLabel(L10n.get("toolbar.toggleFullScreen"))
                Button { openWindow(id: "settings") } label: {
                    Image(systemName: "gearshape")
                }
                .help(L10n.get("sidebar.settings"))
                .accessibilityLabel(L10n.get("sidebar.settings"))
                Button { isAIPanelVisible.toggle() } label: {
                    Image(systemName: "sidebar.trailing")
                }
                .help(L10n.ai.togglePanel)
                .accessibilityLabel(L10n.ai.togglePanel)
            }
        }
        .sheet(item: $projectSearchPresentation) { presentation in
            ProjectSearchView(projectURL: presentation.projectURL, query: $searchText)
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
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { windowWidth = $0 }
        .toolbar(removing: .title)
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
                    columnVisibility = columnVisibility == .all ? .detailOnly : .all
                    appCommands.toggleSidebarRequested = false
                }
            }
            .onReceive(appCommands.$toggleAIPanelRequested) { requested in
                if requested {
                    isAIPanelVisible.toggle()
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
