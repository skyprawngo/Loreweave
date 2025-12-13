//
//  LoreweaveApp.swift
//  Loreweave
//
//  AI 소설 편집기 + 소설 플랫폼
//

import SwiftUI

@main
struct LoreweaveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var projectManager = ProjectManager.shared
    @State private var permissionManager = PermissionManager.shared
    @State private var appCommands = AppCommands.shared
    @State private var themeManager = ThemeManager.shared
    @State private var appFontName = UserSettings.shared.appFontName
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        // Welcome 윈도우 - 고정 크기, 최대화/최소화 불가
        Window(L10n.app.name, id: "welcome") {
            WelcomeWindowContent(
                projectManager: projectManager,
                permissionManager: permissionManager
            )
            .background(WindowAccessor { window in
                window.standardWindowButton(.zoomButton)?.isEnabled = false
                window.standardWindowButton(.miniaturizeButton)?.isEnabled = false
                window.styleMask.remove(.resizable)
            })
            .onReceive(NotificationCenter.default.publisher(for: .openEditorWindow)) { _ in
                openWindow(id: "editor")
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        // 메인 에디터 윈도우
        WindowGroup(id: "editor") {
            DelayedContentView {
                MainEditorView(projectManager: projectManager)
                    .environmentObject(appCommands)
                    .background(WindowAccessor { window in
                        window.titlebarAppearsTransparent = true
                    })
            }
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1400, height: 900)
        .commands {
            LoreweaveCommands(appCommands: appCommands)
        }

        // 설정 윈도우 - 크기 조절 가능
        Window(L10n.get("settings.windowTitle"), id: "settings") {
            SettingsView()
                .frame(minWidth: 500, minHeight: 400)
        }
        .windowStyle(.automatic)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 700, height: 500)
        .defaultPosition(.center)
        .keyboardShortcut(",", modifiers: .command)
    }
}

// MARK: - Welcome Window Content

/// Welcome 윈도우 콘텐츠 (권한 설정 또는 Welcome 뷰)
struct WelcomeWindowContent: View {
    @Bindable var projectManager: ProjectManager
    @Bindable var permissionManager: PermissionManager

    @State private var showWelcome = false

    var body: some View {
        Group {
            if showWelcome || permissionManager.hasCompletedPermissionSetup {
                WelcomeView(projectManager: projectManager)
            } else {
                PermissionRequestView(permissionManager: permissionManager) {
                    showWelcome = true
                }
            }
        }
    }
}

// MARK: - Delayed Content View

/// 윈도우에 뷰가 완전히 연결될 때까지 콘텐츠 로딩을 지연
/// First Responder 오류 방지용
struct DelayedContentView<Content: View>: View {
    let content: () -> Content
    @State private var isReady = false

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        Group {
            if isReady {
                content()
            } else {
                Color.clear
                    .onAppear {
                        DispatchQueue.main.async {
                            isReady = true
                        }
                    }
            }
        }
    }
}

// MARK: - Window Accessor

struct WindowAccessor: NSViewRepresentable {
    let configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                configure(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - App Delegate

/// 앱 시작/종료 관리
class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    /// 마지막 프로젝트 자동 열기 모드 여부
    private var isAutoOpenMode = false

    /// 종료 대기 중인 수정된 탭 목록
    private var pendingModifiedTabs: [EditorTab] = []

    /// 앱 시작 직전 - 윈도우 표시 전에 호출됨
    func applicationWillFinishLaunching(_ notification: Notification) {
        let userSettings = UserSettings.shared
        let permissionManager = PermissionManager.shared

        // 자동 열기 조건 확인: 권한 설정 완료 + 마지막 프로젝트 열기 설정 + 마지막 프로젝트 존재
        isAutoOpenMode = permissionManager.hasCompletedPermissionSetup
            && userSettings.appLaunchBehavior == .openLastProject
            && userSettings.hasLastOpenedProject()
    }

    /// 앱 시작 완료 - 윈도우 표시 후 호출됨
    func applicationDidFinishLaunching(_ notification: Notification) {
        if isAutoOpenMode {
            // 마지막 프로젝트 열기 모드: Welcome 윈도우 닫고 에디터 열기
            openLastProjectAndEditor()
        }
        // 그 외: Welcome 윈도우가 기본으로 열림 (SwiftUI Window 기본 동작)
    }

    /// 마지막 프로젝트를 열고 에디터 윈도우 표시
    private func openLastProjectAndEditor() {
        let projectManager = ProjectManager.shared

        guard let lastProjectURL = UserSettings.shared.getLastOpenedProject(),
              projectManager.openProjectFromFile(at: lastProjectURL) != nil else {
            // 프로젝트 열기 실패 시 Welcome 윈도우 유지
            return
        }

        // Welcome 윈도우 닫기
        if let welcomeWindow = NSApp.windows.first(where: { $0.identifier?.rawValue == "welcome" }) {
            welcomeWindow.close()
        }

        // 에디터 윈도우 열기 (NotificationCenter를 통해 SwiftUI openWindow 호출)
        NotificationCenter.default.post(name: .openEditorWindow, object: nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 현재 열린 프로젝트가 있으면 세션 저장
        if let projectPath = ProjectManager.shared.currentProject?.path {
            EditorTabManager.shared.saveSession(to: projectPath)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // 마지막 윈도우가 닫혀도 앱 종료하지 않음 (macOS 표준 동작)
        return false
    }

    // MARK: - 종료 시 저장 확인

    /// 앱 종료 요청 시 호출 - 저장되지 않은 변경사항 확인
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let tabManager = EditorTabManager.shared

        // 수정된 탭 목록 필터링
        let modifiedTabs = tabManager.tabs.filter { $0.isModified }

        // 수정된 탭이 없으면 바로 종료
        guard !modifiedTabs.isEmpty else {
            return .terminateNow
        }

        // 수정된 탭 목록 저장 후 순차적으로 다이얼로그 표시
        pendingModifiedTabs = modifiedTabs
        showNextSaveDialog()

        return .terminateLater
    }

    /// 다음 저장 다이얼로그 표시
    private func showNextSaveDialog() {
        // 대기 중인 탭이 없으면 종료 진행
        guard let tab = pendingModifiedTabs.first else {
            NSApp.reply(toApplicationShouldTerminate: true)
            return
        }

        // 에디터 윈도우 찾기
        guard let window = NSApp.windows.first(where: {
            $0.identifier?.rawValue.contains("editor") == true
        }) else {
            // 윈도우가 없으면 그냥 종료
            NSApp.reply(toApplicationShouldTerminate: true)
            return
        }

        let alert = NSAlert()
        alert.messageText = L10n.get("app.quit.saveChangesTitle")
        alert.informativeText = String(format: L10n.get("app.quit.saveChangesMessage"), tab.title)
        alert.alertStyle = .warning

        // 버튼 순서: 저장 (기본) / 저장 안 함 / 취소
        alert.addButton(withTitle: L10n.get("app.quit.save"))
        alert.addButton(withTitle: L10n.get("app.quit.dontSave"))
        alert.addButton(withTitle: L10n.get("common.cancel"))

        alert.beginSheetModalWithArrowNavigation(for: window) { [weak self] response in
            guard let self = self else { return }

            switch response {
            case .alertFirstButtonReturn:
                // 저장 버튼 클릭
                self.saveTabAndContinue(tab)

            case .alertSecondButtonReturn:
                // 저장 안 함 버튼 클릭 - 다음 탭으로 진행
                self.pendingModifiedTabs.removeFirst()
                self.proceedToNextDialog()

            default:
                // 취소 버튼 클릭 - 종료 취소
                self.pendingModifiedTabs.removeAll()
                NSApp.reply(toApplicationShouldTerminate: false)
            }
        }
    }

    /// 시트가 닫힌 후 다음 다이얼로그 표시 (딜레이 적용)
    private func proceedToNextDialog() {
        // 시트가 완전히 닫힌 후 다음 다이얼로그 표시
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.showNextSaveDialog()
        }
    }

    /// 탭 저장 후 다음 다이얼로그로 진행
    private func saveTabAndContinue(_ tab: EditorTab) {
        let tabManager = EditorTabManager.shared

        // 탭 인덱스 찾기
        guard let tabIndex = tabManager.tabs.firstIndex(where: { $0.id == tab.id }) else {
            // 탭을 찾을 수 없으면 다음으로 진행
            pendingModifiedTabs.removeFirst()
            proceedToNextDialog()
            return
        }

        // 캐시된 내용 가져오기
        if let content = tabManager.getCachedContent(for: tab.url) {
            _ = tabManager.saveTab(at: tabIndex, content: content)
        }

        // 다음 탭으로 진행
        pendingModifiedTabs.removeFirst()
        proceedToNextDialog()
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// 에디터 윈도우 열기 요청
    static let openEditorWindow = Notification.Name("openEditorWindow")
}
