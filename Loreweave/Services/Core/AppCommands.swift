//
//  AppCommands.swift
//  Loreweave
//
//  앱 전역 커맨드 관리 - 단축키 액션 전달용
//

import SwiftUI
import Combine

// MARK: - App Commands

/// 앱 전역 커맨드 관리자
/// 메뉴바 단축키 액션을 뷰로 전달하는 역할
final class AppCommands: ObservableObject {
    static let shared = AppCommands()

    // MARK: - File Commands
    @Published var newFileRequested = false
    @Published var newFolderRequested = false
    @Published var openFileRequested = false
    @Published var saveRequested = false
    @Published var saveAsRequested = false
    @Published var closeTabRequested = false
    @Published var closeAllTabsRequested = false

    // MARK: - Edit Commands
    @Published var findRequested = false
    @Published var findAndReplaceRequested = false

    // MARK: - View Commands
    @Published var toggleSidebarRequested = false
    @Published var toggleAIPanelRequested = false
    @Published var zoomInRequested = false
    @Published var zoomOutRequested = false
    @Published var resetZoomRequested = false

    // MARK: - Tab Commands
    @Published var nextTabRequested = false
    @Published var previousTabRequested = false
    @Published var goToTabRequested: Int? = nil

    // MARK: - Project Commands
    @Published var openProjectRequested = false
    @Published var newProjectRequested = false
    @Published var refreshProjectRequested = false

    private init() {}

    // MARK: - Reset Methods

    /// 파일 커맨드 리셋
    func resetFileCommands() {
        newFileRequested = false
        newFolderRequested = false
        openFileRequested = false
        saveRequested = false
        saveAsRequested = false
        closeTabRequested = false
        closeAllTabsRequested = false
    }

    /// 편집 커맨드 리셋
    func resetEditCommands() {
        findRequested = false
        findAndReplaceRequested = false
    }

    /// 보기 커맨드 리셋
    func resetViewCommands() {
        toggleSidebarRequested = false
        toggleAIPanelRequested = false
        zoomInRequested = false
        zoomOutRequested = false
        resetZoomRequested = false
    }

    /// 탭 커맨드 리셋
    func resetTabCommands() {
        nextTabRequested = false
        previousTabRequested = false
        goToTabRequested = nil
    }

    /// 프로젝트 커맨드 리셋
    func resetProjectCommands() {
        openProjectRequested = false
        newProjectRequested = false
        refreshProjectRequested = false
    }
}

// MARK: - Loreweave Commands

/// 앱 메뉴바 커맨드 정의
struct LoreweaveCommands: Commands {
    @ObservedObject var appCommands: AppCommands

    var body: some Commands {
        // 파일 메뉴
        CommandGroup(replacing: .newItem) {
            Button(L10n.get("shortcut.file.new")) {
                appCommands.newFileRequested = true
            }
            .keyboardShortcut("n", modifiers: .command)

            Button(L10n.get("shortcut.file.newFolder")) {
                appCommands.newFolderRequested = true
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Divider()

            Button(L10n.get("shortcut.file.open")) {
                appCommands.openFileRequested = true
            }
            .keyboardShortcut("o", modifiers: .command)

            Button(L10n.get("shortcut.project.open")) {
                appCommands.openProjectRequested = true
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .saveItem) {
            Button(L10n.get("shortcut.file.save")) {
                appCommands.saveRequested = true
            }
            .keyboardShortcut("s", modifiers: .command)

            Button(L10n.get("shortcut.file.saveAs")) {
                appCommands.saveAsRequested = true
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
        }

        // 편집 메뉴 - 찾기
        CommandGroup(after: .pasteboard) {
            Divider()

            Button(L10n.get("shortcut.edit.find")) {
                appCommands.findRequested = true
            }
            .keyboardShortcut("f", modifiers: .command)

            Button(L10n.get("shortcut.edit.findAndReplace")) {
                appCommands.findAndReplaceRequested = true
            }
            .keyboardShortcut("f", modifiers: [.command, .option])
        }

        // 보기 메뉴
        CommandGroup(replacing: .sidebar) {
            Button(L10n.get("shortcut.view.toggleSidebar")) {
                appCommands.toggleSidebarRequested = true
            }
            .keyboardShortcut("b", modifiers: .command)

            Button(L10n.get("shortcut.view.toggleAIPanel")) {
                appCommands.toggleAIPanelRequested = true
            }
            .keyboardShortcut("j", modifiers: .command)

            Divider()

            Button(L10n.get("shortcut.view.zoomIn")) {
                appCommands.zoomInRequested = true
            }
            .keyboardShortcut("=", modifiers: .command)

            Button(L10n.get("shortcut.view.zoomOut")) {
                appCommands.zoomOutRequested = true
            }
            .keyboardShortcut("-", modifiers: .command)

            Button(L10n.get("shortcut.view.resetZoom")) {
                appCommands.resetZoomRequested = true
            }
            .keyboardShortcut("0", modifiers: .command)
        }

        // 창 메뉴 - 탭 네비게이션
        CommandGroup(after: .windowArrangement) {
            Divider()

            Button(L10n.get("shortcut.tab.next")) {
                appCommands.nextTabRequested = true
            }
            .keyboardShortcut(.tab, modifiers: .control)

            Button(L10n.get("shortcut.tab.previous")) {
                appCommands.previousTabRequested = true
            }
            .keyboardShortcut(.tab, modifiers: [.control, .shift])

            Divider()

            Button(L10n.get("shortcut.file.closeTab")) {
                appCommands.closeTabRequested = true
            }
            .keyboardShortcut("w", modifiers: .command)

            Button(L10n.get("shortcut.file.closeAllTabs")) {
                appCommands.closeAllTabsRequested = true
            }
            .keyboardShortcut("w", modifiers: [.command, .option])

            Divider()

            // 탭 1-9 이동
            ForEach(1...9, id: \.self) { index in
                Button(L10n.get("shortcut.tab.goTo\(index)")) {
                    appCommands.goToTabRequested = index
                }
                .keyboardShortcut(KeyEquivalent(Character("\(index)")), modifiers: .command)
            }
        }
    }
}
