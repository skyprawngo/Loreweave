//
//  KeyboardShortcutManager.swift
//  Loreweave
//
//  키보드 단축키 관리 서비스 (샌드박스 위치에 JSON 파일로 저장)
//

import Foundation
import SwiftUI
import Carbon.HIToolbox

// MARK: - Shortcut Action

/// 단축키로 실행할 수 있는 액션 목록
enum ShortcutAction: String, CaseIterable, Identifiable, Codable {
    // 파일 관련
    case newFile = "file.new"
    case newFolder = "file.newFolder"
    case openFile = "file.open"
    case save = "file.save"
    case saveAs = "file.saveAs"
    case closeTab = "file.closeTab"
    case closeAllTabs = "file.closeAllTabs"

    // 편집 관련
    case undo = "edit.undo"
    case redo = "edit.redo"
    case cut = "edit.cut"
    case copy = "edit.copy"
    case paste = "edit.paste"
    case selectAll = "edit.selectAll"
    case find = "edit.find"
    case findAndReplace = "edit.findAndReplace"

    // 보기 관련
    case toggleSidebar = "view.toggleSidebar"
    case toggleAIPanel = "view.toggleAIPanel"
    case zoomIn = "view.zoomIn"
    case zoomOut = "view.zoomOut"
    case resetZoom = "view.resetZoom"

    // 탭 네비게이션
    case nextTab = "tab.next"
    case previousTab = "tab.previous"
    case goToTab1 = "tab.goTo1"
    case goToTab2 = "tab.goTo2"
    case goToTab3 = "tab.goTo3"
    case goToTab4 = "tab.goTo4"
    case goToTab5 = "tab.goTo5"
    case goToTab6 = "tab.goTo6"
    case goToTab7 = "tab.goTo7"
    case goToTab8 = "tab.goTo8"
    case goToTab9 = "tab.goTo9"

    // AI 관련
    case aiContinueWriting = "ai.continueWriting"
    case aiRefine = "ai.refine"
    case aiSummarize = "ai.summarize"

    // 프로젝트 관련
    case openProject = "project.open"
    case newProject = "project.new"
    case refreshProject = "project.refresh"

    var id: String { rawValue }

    /// 액션 카테고리
    var category: ShortcutCategory {
        switch self {
        case .newFile, .newFolder, .openFile, .save, .saveAs, .closeTab, .closeAllTabs:
            return .file
        case .undo, .redo, .cut, .copy, .paste, .selectAll, .find, .findAndReplace:
            return .edit
        case .toggleSidebar, .toggleAIPanel, .zoomIn, .zoomOut, .resetZoom:
            return .view
        case .nextTab, .previousTab, .goToTab1, .goToTab2, .goToTab3, .goToTab4,
             .goToTab5, .goToTab6, .goToTab7, .goToTab8, .goToTab9:
            return .tab
        case .aiContinueWriting, .aiRefine, .aiSummarize:
            return .ai
        case .openProject, .newProject, .refreshProject:
            return .project
        }
    }

    /// macOS 시스템 기본 기능 여부 (텍스트 편집 기본 단축키)
    var isSystemDefault: Bool {
        switch self {
        case .undo, .redo, .cut, .copy, .paste, .selectAll:
            return true
        default:
            return false
        }
    }

    /// 액션 표시 이름
    var displayName: String {
        L10n.get("shortcut.\(rawValue)")
    }
}

// MARK: - Shortcut Category

/// 단축키 카테고리
enum ShortcutCategory: String, CaseIterable, Identifiable {
    case file
    case edit
    case view
    case tab
    case ai
    case project

    var id: String { rawValue }

    var displayName: String {
        L10n.get("shortcut.category.\(rawValue)")
    }
}

// MARK: - Modifier Keys

/// 수정자 키
struct ModifierKeys: OptionSet, Codable, Hashable {
    let rawValue: Int

    static let command = ModifierKeys(rawValue: 1 << 0)
    static let shift = ModifierKeys(rawValue: 1 << 1)
    static let option = ModifierKeys(rawValue: 1 << 2)
    static let control = ModifierKeys(rawValue: 1 << 3)

    /// SwiftUI EventModifiers로 변환
    var eventModifiers: SwiftUI.EventModifiers {
        var modifiers: SwiftUI.EventModifiers = []
        if contains(.command) { modifiers.insert(.command) }
        if contains(.shift) { modifiers.insert(.shift) }
        if contains(.option) { modifiers.insert(.option) }
        if contains(.control) { modifiers.insert(.control) }
        return modifiers
    }

    /// 표시용 문자열 (예: "⌘⇧")
    var displayString: String {
        var symbols: [String] = []
        if contains(.control) { symbols.append("⌃") }
        if contains(.option) { symbols.append("⌥") }
        if contains(.shift) { symbols.append("⇧") }
        if contains(.command) { symbols.append("⌘") }
        return symbols.joined()
    }
}

// MARK: - Keyboard Shortcut Binding

/// 단축키 바인딩 (액션과 키 조합)
struct ShortcutBinding: Codable, Identifiable, Equatable {
    var id: String { action.rawValue }

    let action: ShortcutAction
    var key: String  // 예: "n", "s", "f1", "tab"
    var modifiers: ModifierKeys
    var isEnabled: Bool

    /// 표시용 문자열 (예: "⌘N")
    var displayString: String {
        let keyDisplay = key.count == 1 ? key.uppercased() : key.capitalized
        return "\(modifiers.displayString)\(keyDisplay)"
    }

    /// SwiftUI KeyboardShortcut으로 변환
    var keyboardShortcut: KeyboardShortcut? {
        guard isEnabled, let keyEquivalent = KeyEquivalent(key) else { return nil }
        return KeyboardShortcut(keyEquivalent, modifiers: modifiers.eventModifiers)
    }
}

// MARK: - KeyEquivalent Extension

extension KeyEquivalent {
    init?(_ string: String) {
        guard !string.isEmpty else { return nil }

        // 특수 키 처리
        switch string.lowercased() {
        case "return", "enter": self = .return
        case "tab": self = .tab
        case "space": self = .space
        case "delete", "backspace": self = .delete
        case "escape", "esc": self = .escape
        case "up": self = .upArrow
        case "down": self = .downArrow
        case "left": self = .leftArrow
        case "right": self = .rightArrow
        case "home": self = .home
        case "end": self = .end
        case "pageup": self = .pageUp
        case "pagedown": self = .pageDown
        default:
            // 단일 문자
            if string.count == 1, let char = string.lowercased().first {
                self = KeyEquivalent(char)
            } else {
                return nil
            }
        }
    }
}

// MARK: - Keyboard Shortcut Manager

@Observable
final class KeyboardShortcutManager {
    static let shared = KeyboardShortcutManager()

    /// 현재 단축키 바인딩 목록
    private(set) var bindings: [ShortcutBinding] = []

    /// 단축키 파일 경로
    private var shortcutsFileURL: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let appFolder = appSupport.appendingPathComponent("Loreweave", isDirectory: true)

        // 폴더가 없으면 생성
        if !FileManager.default.fileExists(atPath: appFolder.path) {
            try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
        }

        return appFolder.appendingPathComponent("shortcuts.json")
    }

    private init() {
        loadShortcuts()
    }

    // MARK: - Default Shortcuts

    /// 기본 단축키 설정
    private static var defaultBindings: [ShortcutBinding] {
        [
            // 파일
            ShortcutBinding(action: .newFile, key: "n", modifiers: .command, isEnabled: true),
            ShortcutBinding(action: .newFolder, key: "n", modifiers: [.command, .shift], isEnabled: true),
            ShortcutBinding(action: .openFile, key: "o", modifiers: .command, isEnabled: true),
            ShortcutBinding(action: .save, key: "s", modifiers: .command, isEnabled: true),
            ShortcutBinding(action: .saveAs, key: "s", modifiers: [.command, .shift], isEnabled: true),
            ShortcutBinding(action: .closeTab, key: "w", modifiers: .command, isEnabled: true),
            ShortcutBinding(action: .closeAllTabs, key: "w", modifiers: [.command, .option], isEnabled: true),

            // 편집
            ShortcutBinding(action: .undo, key: "z", modifiers: .command, isEnabled: true),
            ShortcutBinding(action: .redo, key: "z", modifiers: [.command, .shift], isEnabled: true),
            ShortcutBinding(action: .cut, key: "x", modifiers: .command, isEnabled: true),
            ShortcutBinding(action: .copy, key: "c", modifiers: .command, isEnabled: true),
            ShortcutBinding(action: .paste, key: "v", modifiers: .command, isEnabled: true),
            ShortcutBinding(action: .selectAll, key: "a", modifiers: .command, isEnabled: true),
            ShortcutBinding(action: .find, key: "f", modifiers: .command, isEnabled: true),
            ShortcutBinding(action: .findAndReplace, key: "f", modifiers: [.command, .option], isEnabled: true),

            // 보기
            ShortcutBinding(action: .toggleSidebar, key: "b", modifiers: .command, isEnabled: true),
            ShortcutBinding(action: .toggleAIPanel, key: "j", modifiers: .command, isEnabled: true),
            ShortcutBinding(action: .zoomIn, key: "=", modifiers: .command, isEnabled: true),
            ShortcutBinding(action: .zoomOut, key: "-", modifiers: .command, isEnabled: true),
            ShortcutBinding(action: .resetZoom, key: "0", modifiers: .command, isEnabled: true),

            // 탭 네비게이션
            ShortcutBinding(action: .nextTab, key: "tab", modifiers: .control, isEnabled: true),
            ShortcutBinding(action: .previousTab, key: "tab", modifiers: [.control, .shift], isEnabled: true),
            ShortcutBinding(action: .goToTab1, key: "1", modifiers: .command, isEnabled: true),
            ShortcutBinding(action: .goToTab2, key: "2", modifiers: .command, isEnabled: true),
            ShortcutBinding(action: .goToTab3, key: "3", modifiers: .command, isEnabled: true),
            ShortcutBinding(action: .goToTab4, key: "4", modifiers: .command, isEnabled: true),
            ShortcutBinding(action: .goToTab5, key: "5", modifiers: .command, isEnabled: true),
            ShortcutBinding(action: .goToTab6, key: "6", modifiers: .command, isEnabled: true),
            ShortcutBinding(action: .goToTab7, key: "7", modifiers: .command, isEnabled: true),
            ShortcutBinding(action: .goToTab8, key: "8", modifiers: .command, isEnabled: true),
            ShortcutBinding(action: .goToTab9, key: "9", modifiers: .command, isEnabled: true),

            // AI
            ShortcutBinding(action: .aiContinueWriting, key: "return", modifiers: [.command, .shift], isEnabled: true),
            ShortcutBinding(action: .aiRefine, key: "r", modifiers: [.command, .shift], isEnabled: true),
            ShortcutBinding(action: .aiSummarize, key: "u", modifiers: [.command, .shift], isEnabled: true),

            // 프로젝트
            ShortcutBinding(action: .openProject, key: "o", modifiers: [.command, .shift], isEnabled: true),
            ShortcutBinding(action: .newProject, key: "n", modifiers: [.command, .option], isEnabled: true),
            ShortcutBinding(action: .refreshProject, key: "r", modifiers: .command, isEnabled: true),
        ]
    }

    // MARK: - Load & Save

    /// 단축키 파일 로드
    func loadShortcuts() {
        if FileManager.default.fileExists(atPath: shortcutsFileURL.path) {
            do {
                let data = try Data(contentsOf: shortcutsFileURL)
                let decoder = JSONDecoder()
                bindings = try decoder.decode([ShortcutBinding].self, from: data)

                // 새로 추가된 액션이 있으면 기본값으로 추가
                let existingActions = Set(bindings.map { $0.action })
                for defaultBinding in Self.defaultBindings {
                    if !existingActions.contains(defaultBinding.action) {
                        bindings.append(defaultBinding)
                    }
                }
            } catch {
                print("Failed to load shortcuts: \(error)")
                bindings = Self.defaultBindings
            }
        } else {
            // 파일이 없으면 기본값 사용
            bindings = Self.defaultBindings
            saveShortcuts()
        }
    }

    /// 단축키 파일 저장
    func saveShortcuts() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(bindings)
            try data.write(to: shortcutsFileURL)
        } catch {
            print("Failed to save shortcuts: \(error)")
        }
    }

    // MARK: - Get & Update

    /// 특정 액션의 단축키 바인딩 가져오기
    func binding(for action: ShortcutAction) -> ShortcutBinding? {
        bindings.first { $0.action == action }
    }

    /// 단축키 바인딩 업데이트
    func updateBinding(_ binding: ShortcutBinding) {
        if let index = bindings.firstIndex(where: { $0.action == binding.action }) {
            bindings[index] = binding
            saveShortcuts()
        }
    }

    /// 단축키 활성화/비활성화 토글
    func toggleEnabled(for action: ShortcutAction) {
        if let index = bindings.firstIndex(where: { $0.action == action }) {
            bindings[index].isEnabled.toggle()
            saveShortcuts()
        }
    }

    /// 특정 액션의 단축키 키 변경
    func setKey(_ key: String, modifiers: ModifierKeys, for action: ShortcutAction) {
        if let index = bindings.firstIndex(where: { $0.action == action }) {
            bindings[index].key = key
            bindings[index].modifiers = modifiers
            saveShortcuts()
        }
    }

    /// 기본값으로 초기화
    func resetToDefaults() {
        bindings = Self.defaultBindings
        saveShortcuts()
    }

    /// 특정 액션만 기본값으로 초기화
    func resetToDefault(for action: ShortcutAction) {
        if let defaultBinding = Self.defaultBindings.first(where: { $0.action == action }),
           let index = bindings.firstIndex(where: { $0.action == action }) {
            bindings[index] = defaultBinding
            saveShortcuts()
        }
    }

    // MARK: - Conflict Detection

    /// 단축키 충돌 확인
    func findConflict(key: String, modifiers: ModifierKeys, excluding action: ShortcutAction) -> ShortcutBinding? {
        bindings.first { binding in
            binding.action != action &&
            binding.isEnabled &&
            binding.key.lowercased() == key.lowercased() &&
            binding.modifiers == modifiers
        }
    }

    // MARK: - Category Helpers

    /// 카테고리별 바인딩 가져오기
    func bindings(for category: ShortcutCategory) -> [ShortcutBinding] {
        bindings.filter { $0.action.category == category }
    }
}
