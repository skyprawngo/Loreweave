//
//  LoreweaveApp.swift
//  Loreweave
//
//  AI 소설 편집기 + 소설 플랫폼
//

import SwiftUI

@main
struct LoreweaveApp: App {
    @State private var projectManager = ProjectManager.shared
    @State private var permissionManager = PermissionManager.shared
    @State private var appCommands = AppCommands.shared
    @State private var themeManager = ThemeManager.shared

    var body: some Scene {
        // Welcome 윈도우 - 고정 크기, 최대화/최소화 불가
        Window(L10n.app.name, id: "welcome") {
            AppRootView(
                projectManager: projectManager,
                permissionManager: permissionManager
            )
            .background(WindowAccessor { window in
                window.standardWindowButton(.zoomButton)?.isEnabled = false
                window.standardWindowButton(.miniaturizeButton)?.isEnabled = false
                window.styleMask.remove(.resizable)
            })
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        // 메인 에디터 윈도우
        WindowGroup(id: "editor", for: UUID.self) { _ in
            MainEditorView(projectManager: projectManager)
                .environmentObject(appCommands)
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

// MARK: - App Root View

/// 앱 시작 시 권한 설정 여부 및 시작 동작 설정에 따라 화면 분기
struct AppRootView: View {
    @Bindable var projectManager: ProjectManager
    @Bindable var permissionManager: PermissionManager
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var showWelcome = false
    @State private var hasAttemptedAutoOpen = false

    private var userSettings: UserSettings { UserSettings.shared }

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
        .onAppear {
            tryOpenLastProjectIfNeeded()
        }
    }

    private func tryOpenLastProjectIfNeeded() {
        guard !hasAttemptedAutoOpen else { return }
        hasAttemptedAutoOpen = true

        // 권한 설정이 완료되지 않았으면 시도하지 않음
        guard permissionManager.hasCompletedPermissionSetup else { return }

        // 마지막 프로젝트 자동 열기 설정이 아니면 시도하지 않음
        guard userSettings.appLaunchBehavior == .openLastProject else { return }

        // 마지막으로 열린 프로젝트 가져오기
        guard let lastProjectURL = userSettings.getLastOpenedProject() else { return }

        // 프로젝트 열기 시도
        if let project = projectManager.openProjectFromFile(at: lastProjectURL) {
            projectManager.openProject(project)
            openWindow(id: "editor", value: UUID())
            dismissWindow(id: "welcome")
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
