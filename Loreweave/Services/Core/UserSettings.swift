//
//  UserSettings.swift
//  Loreweave
//
//  사용자 설정 및 디렉토리 접근 권한 관리
//

import Foundation
import SwiftUI

/// 앱 시작 시 동작 설정
enum AppLaunchBehavior: String, CaseIterable, Identifiable {
    case showWelcome = "showWelcome"
    case openLastProject = "openLastProject"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .showWelcome: return L10n.get("settings.launch.showWelcome")
        case .openLastProject: return L10n.get("settings.launch.openLastProject")
        }
    }
}

/// 앱 테마 설정
enum AppTheme: String, CaseIterable, Identifiable {
    case system = "system"
    case light = "light"
    case dark = "dark"
    case opaque = "opaque"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return L10n.get("settings.theme.system")
        case .light: return L10n.get("settings.theme.light")
        case .dark: return L10n.get("settings.theme.dark")
        case .opaque: return L10n.get("settings.theme.opaque")
        }
    }
}

/// AI 제공자 설정
enum AIProvider: String, CaseIterable, Identifiable {
    case openai = "openai"
    case anthropic = "anthropic"
    case local = "local"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openai: return "OpenAI"
        case .anthropic: return "Anthropic Claude"
        case .local: return L10n.get("settings.ai.local")
        }
    }
}

/// 앱 언어 설정
enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "system"
    case korean = "ko"
    case english = "en"
    case japanese = "ja"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return L10n.get("settings.language.system")
        case .korean: return "한국어"
        case .english: return "English"
        case .japanese: return "日本語"
        }
    }
}

/// 자동 저장 옵션
enum AutoSaveOption: String, CaseIterable, Identifiable {
    case disabled = "disabled"
    case everyFiveMinutes = "5min"
    case everyTenMinutes = "10min"
    case onTabChange = "tabChange"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .disabled: return L10n.get("settings.autoSave.disabled")
        case .everyFiveMinutes: return L10n.get("settings.autoSave.everyFiveMinutes")
        case .everyTenMinutes: return L10n.get("settings.autoSave.everyTenMinutes")
        case .onTabChange: return L10n.get("settings.autoSave.onTabChange")
        }
    }

    /// 자동 저장 간격 (초). disabled와 onTabChange는 0 반환 (타이머 사용 안 함)
    var intervalSeconds: Int {
        switch self {
        case .disabled: return 0
        case .everyFiveMinutes: return 300
        case .everyTenMinutes: return 600
        case .onTabChange: return 0
        }
    }

    /// 자동 저장이 활성화되어 있는지 여부
    var isEnabled: Bool {
        self != .disabled
    }
}

/// 사용자 설정 관리자
@Observable
final class UserSettings {
    static let shared = UserSettings()

    private let defaults = UserDefaults.standard

    // MARK: - Keys

    private enum Keys {
        static let appLaunchBehavior = "userSettings.appLaunchBehavior"
        static let appTheme = "userSettings.appTheme"
        static let appLanguage = "userSettings.appLanguage"
        static let autoSaveOption = "userSettings.autoSaveOption"
        static let aiProvider = "userSettings.aiProvider"
        static let aiApiKey = "userSettings.aiApiKey"
        static let editorFontSize = "userSettings.editorFontSize"
        static let editorLineSpacing = "userSettings.editorLineSpacing"
        static let editorFontName = "userSettings.editorFontName"
        static let showLineNumbers = "userSettings.showLineNumbers"
        static let defaultProjectLocation = "userSettings.defaultProjectLocation"
        static let lastOpenedProject = "userSettings.lastOpenedProject"
        static let recentProjectPaths = "userSettings.recentProjectPaths"
        static let maxRecentProjects = "userSettings.maxRecentProjects"
        static let aiAssistantPanelWidth = "userSettings.aiAssistantPanelWidth"
        static let sidebarWidth = "userSettings.sidebarWidth"
        static let appFontName = "userSettings.appFontName"
    }

    // MARK: - 일반 설정

    /// 앱 시작 시 동작
    var appLaunchBehavior: AppLaunchBehavior {
        get {
            guard let raw = defaults.string(forKey: Keys.appLaunchBehavior),
                  let behavior = AppLaunchBehavior(rawValue: raw) else {
                return .showWelcome
            }
            return behavior
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.appLaunchBehavior) }
    }

    /// 앱 테마
    var appTheme: AppTheme {
        get {
            guard let raw = defaults.string(forKey: Keys.appTheme),
                  let theme = AppTheme(rawValue: raw) else {
                return .system
            }
            return theme
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.appTheme) }
    }

    /// 앱 언어
    var appLanguage: AppLanguage {
        get {
            guard let raw = defaults.string(forKey: Keys.appLanguage),
                  let language = AppLanguage(rawValue: raw) else {
                return .system
            }
            return language
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.appLanguage)
            applyLanguageSetting(newValue)
        }
    }

    // MARK: - 자동 저장 설정

    /// 자동 저장 옵션
    var autoSaveOption: AutoSaveOption {
        get {
            guard let raw = defaults.string(forKey: Keys.autoSaveOption),
                  let option = AutoSaveOption(rawValue: raw) else {
                return .everyFiveMinutes
            }
            return option
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.autoSaveOption) }
    }

    // MARK: - AI 설정

    /// AI 제공자
    var aiProvider: AIProvider {
        get {
            guard let raw = defaults.string(forKey: Keys.aiProvider),
                  let provider = AIProvider(rawValue: raw) else {
                return .anthropic
            }
            return provider
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.aiProvider) }
    }

    /// AI API 키 (Keychain에 저장하는 것이 권장됨)
    var aiApiKey: String {
        get { defaults.string(forKey: Keys.aiApiKey) ?? "" }
        set { defaults.set(newValue, forKey: Keys.aiApiKey) }
    }

    // MARK: - 에디터 설정

    /// 에디터 폰트 크기
    var editorFontSize: CGFloat {
        get { CGFloat(defaults.object(forKey: Keys.editorFontSize) as? Double ?? 14.0) }
        set { defaults.set(Double(newValue), forKey: Keys.editorFontSize) }
    }

    /// 에디터 줄간격 (lineHeightMultiple 값)
    /// 1.0 = 100% 기본값, 1.25 = 125%, 1.5 = 150%, 2.0 = 200%
    var editorLineSpacing: CGFloat {
        get { CGFloat(defaults.object(forKey: Keys.editorLineSpacing) as? Double ?? 1.0) }
        set { defaults.set(Double(newValue), forKey: Keys.editorLineSpacing) }
    }

    /// 에디터 폰트 이름
    var editorFontName: String {
        get { defaults.string(forKey: Keys.editorFontName) ?? "SF Pro" }
        set { defaults.set(newValue, forKey: Keys.editorFontName) }
    }

    /// 줄 번호 표시
    var showLineNumbers: Bool {
        get { defaults.object(forKey: Keys.showLineNumbers) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.showLineNumbers) }
    }

    // MARK: - 디렉토리 설정

    /// 기본 프로젝트 저장 위치 (Security-Scoped Bookmark)
    var defaultProjectLocationBookmark: Data? {
        get { defaults.data(forKey: Keys.defaultProjectLocation) }
        set { defaults.set(newValue, forKey: Keys.defaultProjectLocation) }
    }

    /// 기본 프로젝트 저장 위치 URL 가져오기
    func getDefaultProjectLocation() -> URL? {
        guard let bookmarkData = defaultProjectLocationBookmark else { return nil }

        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale {
                // Bookmark이 오래된 경우 갱신 시도
                if let newBookmark = try? url.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                ) {
                    defaultProjectLocationBookmark = newBookmark
                }
            }

            return url
        } catch {
            print("Failed to resolve default project location bookmark: \(error)")
            return nil
        }
    }

    /// 기본 프로젝트 저장 위치 설정
    func setDefaultProjectLocation(_ url: URL) -> Bool {
        do {
            let bookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            defaultProjectLocationBookmark = bookmarkData
            return true
        } catch {
            print("Failed to save default project location bookmark: \(error)")
            return false
        }
    }

    // MARK: - 마지막으로 열린 프로젝트

    /// 마지막으로 열린 프로젝트 Bookmark Data
    private var lastOpenedProjectBookmark: Data? {
        get { defaults.data(forKey: Keys.lastOpenedProject) }
        set { defaults.set(newValue, forKey: Keys.lastOpenedProject) }
    }

    /// 마지막으로 열린 프로젝트가 저장되어 있는지 확인 (Security-Scoped 접근 없이)
    func hasLastOpenedProject() -> Bool {
        return lastOpenedProjectBookmark != nil
    }

    /// 마지막으로 열린 프로젝트 URL 가져오기
    func getLastOpenedProject() -> URL? {
        guard let bookmarkData = lastOpenedProjectBookmark else { return nil }

        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            // Security-Scoped Resource 접근 시작
            guard url.startAccessingSecurityScopedResource() else {
                print("Failed to start accessing security scoped resource for last opened project")
                return nil
            }

            // 파일이 존재하는지 확인
            guard FileManager.default.fileExists(atPath: url.path) else {
                url.stopAccessingSecurityScopedResource()
                lastOpenedProjectBookmark = nil
                return nil
            }

            if isStale {
                // Bookmark 갱신
                if let newBookmark = try? url.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                ) {
                    lastOpenedProjectBookmark = newBookmark
                }
            }

            // 접근 권한은 유지 (호출자가 사용 후 stopAccessingSecurityScopedResource 호출 필요)
            return url
        } catch {
            print("Failed to resolve last opened project bookmark: \(error)")
            lastOpenedProjectBookmark = nil
            return nil
        }
    }

    /// 마지막으로 열린 프로젝트 저장
    func setLastOpenedProject(_ url: URL) {
        do {
            let bookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            lastOpenedProjectBookmark = bookmarkData
        } catch {
            print("Failed to save last opened project bookmark: \(error)")
        }
    }

    /// 마지막으로 열린 프로젝트 삭제
    func clearLastOpenedProject() {
        lastOpenedProjectBookmark = nil
    }

    // MARK: - 최근 프로젝트

    /// 최대 최근 프로젝트 수
    var maxRecentProjects: Int {
        get { defaults.object(forKey: Keys.maxRecentProjects) as? Int ?? 10 }
        set { defaults.set(newValue, forKey: Keys.maxRecentProjects) }
    }

    /// 최근 프로젝트 경로 목록 (Bookmark Data)
    private var recentProjectBookmarks: [Data] {
        get { defaults.array(forKey: Keys.recentProjectPaths) as? [Data] ?? [] }
        set { defaults.set(newValue, forKey: Keys.recentProjectPaths) }
    }

    /// 최근 프로젝트 URL 목록 가져오기
    func getRecentProjects() -> [URL] {
        var urls: [URL] = []
        var validBookmarks: [Data] = []

        for bookmarkData in recentProjectBookmarks {
            do {
                var isStale = false
                let url = try URL(
                    resolvingBookmarkData: bookmarkData,
                    options: .withSecurityScope,
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )

                // 파일이 존재하는지 확인
                if FileManager.default.fileExists(atPath: url.path) {
                    urls.append(url)

                    if isStale {
                        // Bookmark 갱신
                        if let newBookmark = try? url.bookmarkData(
                            options: .withSecurityScope,
                            includingResourceValuesForKeys: nil,
                            relativeTo: nil
                        ) {
                            validBookmarks.append(newBookmark)
                        } else {
                            validBookmarks.append(bookmarkData)
                        }
                    } else {
                        validBookmarks.append(bookmarkData)
                    }
                }
            } catch {
                // 무효한 bookmark는 건너뜀
                continue
            }
        }

        // 유효한 bookmark만 저장
        if validBookmarks.count != recentProjectBookmarks.count {
            recentProjectBookmarks = validBookmarks
        }

        return urls
    }

    /// 최근 프로젝트에 추가
    func addRecentProject(_ url: URL) {
        do {
            let bookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )

            var bookmarks = recentProjectBookmarks

            // 이미 존재하는 경우 제거 (중복 방지)
            bookmarks.removeAll { existingData in
                var isStale = false
                if let existingURL = try? URL(
                    resolvingBookmarkData: existingData,
                    options: .withSecurityScope,
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                ) {
                    return existingURL == url
                }
                return false
            }

            // 맨 앞에 추가
            bookmarks.insert(bookmarkData, at: 0)

            // 최대 개수 제한
            if bookmarks.count > maxRecentProjects {
                bookmarks = Array(bookmarks.prefix(maxRecentProjects))
            }

            recentProjectBookmarks = bookmarks
        } catch {
            print("Failed to add recent project: \(error)")
        }
    }

    /// 최근 프로젝트에서 제거
    func removeRecentProject(_ url: URL) {
        var bookmarks = recentProjectBookmarks
        bookmarks.removeAll { existingData in
            var isStale = false
            if let existingURL = try? URL(
                resolvingBookmarkData: existingData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                return existingURL == url
            }
            return false
        }
        recentProjectBookmarks = bookmarks
    }

    /// 최근 프로젝트 목록 초기화
    func clearRecentProjects() {
        recentProjectBookmarks = []
    }

    // MARK: - UI 레이아웃 설정

    /// AI 어시스턴트 패널 너비
    var aiAssistantPanelWidth: CGFloat {
        get { CGFloat(defaults.object(forKey: Keys.aiAssistantPanelWidth) as? Double ?? 320.0) }
        set { defaults.set(Double(newValue), forKey: Keys.aiAssistantPanelWidth) }
    }

    /// 사이드바 너비
    var sidebarWidth: CGFloat {
        get { CGFloat(defaults.object(forKey: Keys.sidebarWidth) as? Double ?? 220.0) }
        set { defaults.set(Double(newValue), forKey: Keys.sidebarWidth) }
    }

    // MARK: - 앱 전역 폰트 설정

    /// 앱 전역 폰트 이름 (에디터와 줄번호 제외)
    /// 빈 문자열이면 시스템 폰트 사용
    var appFontName: String {
        get { defaults.string(forKey: Keys.appFontName) ?? "" }
        set { defaults.set(newValue, forKey: Keys.appFontName) }
    }

    // MARK: - Private

    private init() {}

    /// 언어 설정 적용
    private func applyLanguageSetting(_ language: AppLanguage) {
        switch language {
        case .system:
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        case .korean, .english, .japanese:
            UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
        }
    }

    // MARK: - 설정 초기화

    /// 모든 설정을 기본값으로 초기화
    func resetAllSettings() {
        let allKeys = [
            Keys.appLaunchBehavior,
            Keys.appTheme,
            Keys.appLanguage,
            Keys.autoSaveOption,
            Keys.aiProvider,
            Keys.aiApiKey,
            Keys.editorFontSize,
            Keys.editorLineSpacing,
            Keys.editorFontName,
            Keys.showLineNumbers,
            Keys.defaultProjectLocation,
            Keys.lastOpenedProject,
            Keys.recentProjectPaths,
            Keys.maxRecentProjects,
            Keys.aiAssistantPanelWidth,
            Keys.sidebarWidth,
            Keys.appFontName
        ]

        for key in allKeys {
            defaults.removeObject(forKey: key)
        }
    }
}
