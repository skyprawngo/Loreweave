//
//  L10n.swift
//  TextlinkEditor
//
//  JSON 기반 다국어 지원 시스템
//  각 언어별 별도 파일: ko.json, en.json, ja.json
//

import Foundation
import SwiftUI

// MARK: - Localization Manager

@Observable
final class LocalizationManager {
    static let shared = LocalizationManager()

    var currentLanguage: Language {
        didSet {
            UserDefaults.standard.set(currentLanguage.rawValue, forKey: "appLanguage")
            loadStrings()
        }
    }

    private var strings: [String: String] = [:]

    /// 모든 언어의 문자열을 로드하여 비교 분석용으로 제공
    /// AI가 누락된 키를 찾거나 번역 비교할 때 사용
    static func loadAllLanguages() -> [String: [String: String]] {
        var allStrings: [String: [String: String]] = [:]

        for language in Language.allCases {
            if let url = Bundle.main.url(forResource: language.rawValue, withExtension: "json") {
                do {
                    let data = try Data(contentsOf: url)
                    let languageStrings = try JSONDecoder().decode([String: String].self, from: data)
                    allStrings[language.rawValue] = languageStrings
                } catch {
                    print("Failed to load \(language.rawValue).json: \(error)")
                }
            }
        }

        return allStrings
    }

    /// 누락된 키 찾기 - 기준 언어(ko) 대비 다른 언어에서 누락된 키 반환
    static func findMissingKeys(baseLanguage: Language = .korean) -> [String: [String]] {
        let allStrings = loadAllLanguages()
        guard let baseStrings = allStrings[baseLanguage.rawValue] else { return [:] }
        let baseKeys = Set(baseStrings.keys)

        var missingKeys: [String: [String]] = [:]

        for language in Language.allCases where language != baseLanguage {
            var languageKeys = Set<String>()
            if let keys = allStrings[language.rawValue]?.keys {
                languageKeys = Set(keys)
            }
            let missing = baseKeys.filter { !languageKeys.contains($0) }
            if !missing.isEmpty {
                missingKeys[language.rawValue] = Array(missing)
            }
        }

        return missingKeys
    }

    enum Language: String, CaseIterable, Identifiable {
        case korean = "ko"
        case english = "en"
        case japanese = "ja"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .korean: return "한국어"
            case .english: return "English"
            case .japanese: return "日本語"
            }
        }
    }

    private init() {
        if let saved = UserDefaults.standard.string(forKey: "appLanguage"),
           let language = Language(rawValue: saved) {
            self.currentLanguage = language
        } else {
            let preferredLanguage = Locale.current.language.languageCode?.identifier ?? "en"
            self.currentLanguage = Language(rawValue: preferredLanguage) ?? .english
        }
        loadStrings()
    }

    private func loadStrings() {
        guard let url = Bundle.main.url(forResource: currentLanguage.rawValue, withExtension: "json") else {
            print("Failed to find \(currentLanguage.rawValue).json")
            return
        }

        do {
            let data = try Data(contentsOf: url)
            strings = try JSONDecoder().decode([String: String].self, from: data)
        } catch {
            print("Failed to load localization: \(error)")
        }
    }

    func string(for key: String) -> String {
        strings[key] ?? key
    }
}

// MARK: - L10n Accessor

enum L10n {
    private static var manager: LocalizationManager { .shared }

    static func get(_ key: String) -> String {
        manager.string(for: key)
    }

    enum app {
        static var name: String { manager.string(for: "app.name") }
    }

    enum sidebar {
        static var project: String { manager.string(for: "sidebar.project") }
        static var worldbuilding: String { manager.string(for: "sidebar.worldbuilding") }
        static var characters: String { manager.string(for: "sidebar.characters") }
        static var plot: String { manager.string(for: "sidebar.plot") }
        static var storyboard: String { manager.string(for: "sidebar.storyboard") }
        static var editor: String { manager.string(for: "sidebar.editor") }
        static var ideas: String { manager.string(for: "sidebar.ideas") }
        static var settings: String { manager.string(for: "sidebar.settings") }
    }

    enum editor {
        static var newDocument: String { manager.string(for: "editor.newDocument") }
        static var untitled: String { manager.string(for: "editor.untitled") }
        static var save: String { manager.string(for: "editor.save") }
        static var autoSaved: String { manager.string(for: "editor.autoSaved") }
        static var words: String { manager.string(for: "editor.words") }
        static var characters: String { manager.string(for: "editor.characters") }
        static var bold: String { manager.string(for: "editor.bold") }
        static var italic: String { manager.string(for: "editor.italic") }
        static var underline: String { manager.string(for: "editor.underline") }
        static var strikethrough: String { manager.string(for: "editor.strikethrough") }
        static var fontSize: String { manager.string(for: "editor.fontSize") }
        static var lineSpacing: String { manager.string(for: "editor.lineSpacing") }
        static var lineWidth: String { manager.string(for: "editor.lineWidth") }
        static var alignLeft: String { manager.string(for: "editor.alignLeft") }
        static var alignCenter: String { manager.string(for: "editor.alignCenter") }
        static var alignRight: String { manager.string(for: "editor.alignRight") }
        static var alignJustified: String { manager.string(for: "editor.alignJustified") }
    }

    enum ai {
        static var title: String { manager.string(for: "ai.title") }
        static var placeholder: String { manager.string(for: "ai.placeholder") }
        static var welcome: String { manager.string(for: "ai.welcome") }
        static var continueWriting: String { manager.string(for: "ai.continue") }
        static var refine: String { manager.string(for: "ai.refine") }
        static var summarize: String { manager.string(for: "ai.summarize") }
        static var noSelection: String { manager.string(for: "ai.noSelection") }
        static var tools: String { manager.string(for: "ai.tools") }
        static var refineText: String { manager.string(for: "ai.refineText") }
        static var styleConvert: String { manager.string(for: "ai.styleConvert") }
        static var continueWritingAction: String { manager.string(for: "ai.continueWriting") }
        static var consistencyCheck: String { manager.string(for: "ai.consistencyCheck") }
        static var togglePanel: String { manager.string(for: "ai.togglePanel") }
    }

    enum tabs {
        static var close: String { manager.string(for: "tabs.close") }
        static var newTab: String { manager.string(for: "tabs.newTab") }
    }

    enum common {
        static var cancel: String { manager.string(for: "common.cancel") }
        static var confirm: String { manager.string(for: "common.confirm") }
        static var delete: String { manager.string(for: "common.delete") }
        static var edit: String { manager.string(for: "common.edit") }
        static var add: String { manager.string(for: "common.add") }
        static var save: String { manager.string(for: "common.save") }
    }
}

// MARK: - Environment Key

private struct LocalizationManagerKey: EnvironmentKey {
    static let defaultValue = LocalizationManager.shared
}

extension EnvironmentValues {
    var localization: LocalizationManager {
        get { self[LocalizationManagerKey.self] }
        set { self[LocalizationManagerKey.self] = newValue }
    }
}
