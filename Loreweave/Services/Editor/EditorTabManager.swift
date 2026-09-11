//
//  EditorTabManager.swift
//  Loreweave
//
//  에디터 탭 관리 (열린 파일 탭 상태 관리)
//

import Foundation
import AppKit
import CryptoKit

// MARK: - Notification Names

extension Notification.Name {
    /// 에디터 탭이 변경됨 (추가, 삭제, 선택 변경 등)
    static let editorTabsDidChange = Notification.Name("editorTabsDidChange")
    static let editorWillPerformFileOperation = Notification.Name("editorWillPerformFileOperation")
}

// MARK: - Tab State (저장용)

/// 탭 상태 저장을 위한 Codable 구조체
struct TabState: Codable {
    let relativePath: String  // 프로젝트 폴더 기준 상대 경로
    let isModified: Bool
    let cursorLine: Int       // 커서 행 위치
    let cursorColumn: Int     // 커서 열 위치
    var draftContent: String?
    var baseContent: String?
    var externalURL: URL?

    init(relativePath: String, isModified: Bool = false, cursorLine: Int = 0, cursorColumn: Int = 0) {
        self.relativePath = relativePath
        self.isModified = isModified
        self.cursorLine = cursorLine
        self.cursorColumn = cursorColumn
    }
}

/// 에디터 세션 상태 (탭 목록 + 선택된 탭)
struct EditorSessionState: Codable {
    let tabs: [TabState]
    let selectedTabIndex: Int

    init(tabs: [TabState], selectedTabIndex: Int) {
        self.tabs = tabs
        self.selectedTabIndex = selectedTabIndex
    }
}

/// 프로젝트별 에디터 설정 (폰트, 크기, 줄간격)
struct ProjectEditorSettings: Codable {
    var fontName: String
    var fontSize: CGFloat
    var lineSpacing: CGFloat  // lineHeightMultiple 값

    init(fontName: String = "SF Pro", fontSize: CGFloat = 14.0, lineSpacing: CGFloat = 1.0) {
        self.fontName = fontName
        self.fontSize = fontSize
        self.lineSpacing = lineSpacing
    }

    /// UserSettings의 기본값에서 생성
    static func fromUserSettings() -> ProjectEditorSettings {
        ProjectEditorSettings(
            fontName: UserSettings.shared.editorFontName,
            fontSize: UserSettings.shared.editorFontSize,
            lineSpacing: UserSettings.shared.editorLineSpacing
        )
    }
}

/// 에디터에서 열린 파일 탭
struct EditorTab: Identifiable, Equatable {
    let id: UUID
    var fileItem: FileSystemItem
    var isModified: Bool
    /// 방금 저장됨 표시 (애니메이션용)
    var justSaved: Bool = false

    var title: String {
        fileItem.name
    }

    var url: URL {
        fileItem.url
    }

    /// 파일이 디스크에 존재하는지 확인
    var fileExists: Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    init(fileItem: FileSystemItem, isModified: Bool = false) {
        self.id = UUID()
        self.fileItem = fileItem
        self.isModified = isModified
    }

    static func == (lhs: EditorTab, rhs: EditorTab) -> Bool {
        lhs.id == rhs.id
    }
}

/// 탭별 편집 상태를 통합 관리하는 구조체
struct TabEditState {
    /// 편집 중인 텍스트
    var content: String
    /// 디스크에 저장된 원본 내용 (수정 여부 판단 기준)
    var originalContent: String
    /// 커서 위치 (line, column)
    var cursorPosition: (line: Int, column: Int)

    /// 수정 여부 (content와 originalContent 비교)
    var isModified: Bool {
        content != originalContent
    }

    init(content: String = "", originalContent: String = "", cursorPosition: (line: Int, column: Int) = (0, 0)) {
        self.content = content
        self.originalContent = originalContent
        self.cursorPosition = cursorPosition
    }

    /// 저장 완료 후 호출 - originalContent를 현재 content로 업데이트
    mutating func markAsSaved() {
        originalContent = content
    }
}

/// 에디터 탭 관리자
@Observable
final class EditorTabManager {
    static let shared = EditorTabManager()

    /// 현재 열린 탭들
    private(set) var tabs: [EditorTab] = []

    /// 탭별 편집 상태 (URL -> TabEditState)
    /// 텍스트, 원본 내용, 커서, 스크롤을 통합 관리
    private var editStates: [URL: TabEditState] = [:]

    /// 현재 선택된 탭 인덱스
    var selectedTabIndex: Int = 0 {
        didSet {
            if selectedTabIndex < 0 { selectedTabIndex = 0 }
            if selectedTabIndex >= tabs.count && tabs.count > 0 {
                selectedTabIndex = tabs.count - 1
            }
            // 선택 탭 변경 시 세션 저장
            if oldValue != selectedTabIndex {
                autoSaveSessionIfNeeded()
            }
        }
    }

    /// 세션 저장 필요 시 저장 (순환 호출 방지)
    private var isSavingSession = false
    private var sessionProjectURL: URL?
    private var recoveryWork: DispatchWorkItem?
    var saveErrors: [URL: String] = [:]
    var lastSavedAt: [URL: Date] = [:]
    var recoveryError: String?
    private var approvedDiscards: Set<URL> = []
    private var navigation: [URL] = []
    private var navigationIndex = -1
    private var navigating = false
    private func autoSaveSessionIfNeeded() {
        guard !isSavingSession else { return }
        guard let projectPath = sessionProjectURL else { return }
        isSavingSession = true
        saveSession(to: projectPath)
        isSavingSession = false
    }

    /// 현재 선택된 탭
    var selectedTab: EditorTab? {
        guard selectedTabIndex >= 0 && selectedTabIndex < tabs.count else { return nil }
        return tabs[selectedTabIndex]
    }

    private let recoveryDirectory: URL

    init(recoveryDirectory: URL? = nil) {
        self.recoveryDirectory = recoveryDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Loreweave/Recovery", isDirectory: true)
    }

    private func localSessionURL(for project: URL) -> URL {
        let digest = SHA256.hash(data: Data(project.standardizedFileURL.path.utf8)).map { String(format: "%02x", $0) }.joined()
        return recoveryDirectory.appendingPathComponent(digest + ".json")
    }

    // MARK: - Tab Operations

    /// 파일을 새 탭으로 열기
    func openFile(_ fileItem: FileSystemItem) {
        // 이미 열려있는 탭인지 확인
        if let existingIndex = tabs.firstIndex(where: { $0.fileItem.url == fileItem.url }) {
            selectedTabIndex = existingIndex
            notifyTabsChanged()
            return
        }

        // 새 탭 생성
        let newTab = EditorTab(fileItem: fileItem)
        tabs.append(newTab)
        selectedTabIndex = tabs.count - 1
        notifyTabsChanged()
    }

    /// 탭 닫기
    /// - Parameters:
    ///   - index: 닫을 탭 인덱스
    ///   - force: true이면 수정 여부와 관계없이 강제 닫기
    func closeTab(at index: Int, force: Bool = false) {
        guard tabs.indices.contains(index) else { return }
        let id = tabs[index].id
        guard force || prepareToClose([tabs[index]]) else { return }
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        removeCachedContent(for: tabs[index].url)
        tabs.remove(at: index)
        if tabs.isEmpty { selectedTabIndex = 0 }
        else if selectedTabIndex >= tabs.count { selectedTabIndex = tabs.count - 1 }
        else if index < selectedTabIndex { selectedTabIndex -= 1 }
        notifyTabsChanged()
    }

    /// 특정 폴더 하위의 모든 파일 탭 닫기
    /// - Parameter folderURL: 폴더 URL
    func closeTabsUnder(folderURL: URL) {
        let folderPath = folderURL.path

        // 뒤에서부터 순회하여 삭제 (인덱스 변화 방지)
        for index in stride(from: tabs.count - 1, through: 0, by: -1) {
            let tabPath = tabs[index].url.path
            if tabPath.hasPrefix(folderPath + "/") || tabPath == folderPath {
                closeTab(at: index, force: true)
            }
        }
    }

    /// 특정 탭 선택
    func selectTab(at index: Int) {
        guard index >= 0 && index < tabs.count else { return }
        selectedTabIndex = index
        notifyTabsChanged()
    }

    /// 새 빈 탭 생성 (제목 없음)
    func createNewTab() {
        // 임시 빈 파일용 FileSystemItem 생성
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("Untitled-\(UUID().uuidString.prefix(8)).md")
        let tempItem = FileSystemItem(url: tempURL, isDirectory: false)
        tempItem.name = L10n.editor.untitled

        let newTab = EditorTab(fileItem: tempItem, isModified: true)
        tabs.append(newTab)
        selectedTabIndex = tabs.count - 1
        notifyTabsChanged()
    }

    /// 탭의 수정 상태 변경
    func setModified(_ isModified: Bool, at index: Int) {
        guard index >= 0 && index < tabs.count else { return }
        tabs[index].isModified = isModified
    }

    /// 현재 탭의 내용 저장
    func saveCurrentTab(content: String) -> Bool {
        guard selectedTab != nil else { return false }
        return saveTab(at: selectedTabIndex, content: content)
    }

    /// 특정 탭의 내용 저장
    func saveTab(at index: Int, content: String) -> Bool {
        guard tabs.indices.contains(index), let state = editStates[tabs[index].url] else { return false }
        let url = tabs[index].url
        do {
            try DocumentFileStore.save(content, at: url, expected: state.originalContent)
            editStates[url]?.content = content
            editStates[url]?.markAsSaved()
            tabs[index].isModified = false
            tabs[index].justSaved = true
            saveErrors[url] = nil
            lastSavedAt[url] = Date()
            autoSaveSessionIfNeeded()
            let id = tabs[index].id
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                if let i = self?.tabs.firstIndex(where: { $0.id == id }) { self?.tabs[i].justSaved = false }
            }
            return true
        } catch {
            saveErrors[url] = error is DocumentFileStore.Failure ? L10n.get("storage.conflict") : error.localizedDescription
            autoSaveSessionIfNeeded()
            return false
        }
    }

    /// URL로 탭의 수정 상태 확인
    func isModified(url: URL) -> Bool {
        return editStates[url]?.isModified ?? false
    }

    // MARK: - Edit State Management (통합 캐시 관리)

    /// URL의 전체 편집 상태 가져오기
    func getEditState(for url: URL) -> TabEditState? {
        return editStates[url]
    }

    /// URL의 편집 상태 설정 (없으면 생성)
    func setEditState(_ state: TabEditState, for url: URL) {
        editStates[url] = state
        if let index = findTab(with: url) { tabs[index].isModified = state.isModified }
    }

    /// URL의 편집 상태 삭제
    func removeEditState(for url: URL) {
        editStates.removeValue(forKey: url)
    }

    /// URL로 캐시된 탭 내용 가져오기
    func getCachedContent(for url: URL) -> String? {
        return editStates[url]?.content
    }

    /// 탭 내용을 캐시에 저장 (편집 상태가 없으면 생성)
    func setCachedContent(_ content: String, for url: URL) {
        guard findTab(with: url) != nil else { return }
        if editStates[url] != nil {
            editStates[url]?.content = content
        } else {
            editStates[url] = TabEditState(content: content, originalContent: content)
        }
        if let index = findTab(with: url) { tabs[index].isModified = editStates[url]?.isModified ?? false }
        recoveryWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.autoSaveSessionIfNeeded() }
        recoveryWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    /// 원본 콘텐츠 설정 (파일 로드 시 사용)
    func setOriginalContent(_ content: String, for url: URL) {
        if editStates[url] != nil {
            editStates[url]?.originalContent = content
        } else {
            editStates[url] = TabEditState(content: content, originalContent: content)
        }
        // 탭의 isModified 상태 동기화
        if let index = findTab(with: url) {
            tabs[index].isModified = editStates[url]?.isModified ?? false
        }
    }

    /// 캐시에서 탭 내용 삭제 (레거시 호환)
    func removeCachedContent(for url: URL) {
        removeEditState(for: url)
    }

    /// URL로 캐시된 커서 위치 가져오기
    func getCachedCursorPosition(for url: URL) -> (line: Int, column: Int)? {
        return editStates[url]?.cursorPosition
    }

    /// 커서 위치를 캐시에 저장
    func setCachedCursorPosition(line: Int, column: Int, for url: URL) {
        if editStates[url] != nil {
            editStates[url]?.cursorPosition = (line, column)
        } else {
            editStates[url] = TabEditState(cursorPosition: (line, column))
        }
    }

    /// 모든 탭 닫기
    @discardableResult
    func closeAllTabs(force: Bool = false) -> Bool {
        guard force || prepareToClose(tabs) else { return false }
        editStates.removeAll()
        tabs.removeAll()
        selectedTabIndex = 0
        notifyTabsChanged()
        return true
    }

    /// 현재 탭 외 모든 탭 닫기
    func closeOtherTabs(except index: Int) {
        guard tabs.indices.contains(index) else { return }
        let keep = tabs[index]
        guard prepareToClose(tabs.filter { $0.id != keep.id }) else { return }
        for tab in tabs where tab.id != keep.id { removeEditState(for: tab.url) }
        tabs = [keep]
        selectedTabIndex = 0
        notifyTabsChanged()
    }

    /// URL로 탭 찾기
    func findTab(with url: URL) -> Int? {
        tabs.firstIndex(where: { $0.fileItem.url == url })
    }

    /// 탭이 비어있는지 확인
    var isEmpty: Bool {
        tabs.isEmpty
    }

    /// 탭 개수
    var count: Int {
        tabs.count
    }

    // MARK: - Navigation

    /// 다음 탭 선택
    func selectNextTab() {
        guard !tabs.isEmpty else { return }
        selectedTabIndex = (selectedTabIndex + 1) % tabs.count
    }

    /// 이전 탭 선택
    func selectPreviousTab() {
        guard !tabs.isEmpty else { return }
        selectedTabIndex = selectedTabIndex > 0 ? selectedTabIndex - 1 : tabs.count - 1
    }

    /// 탭 순서 이동
    func moveTab(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex >= 0 && sourceIndex < tabs.count else { return }
        guard destinationIndex >= 0 && destinationIndex < tabs.count else { return }
        guard sourceIndex != destinationIndex else { return }

        let movedTab = tabs.remove(at: sourceIndex)
        tabs.insert(movedTab, at: destinationIndex)

        // 선택된 탭 인덱스 조정
        if selectedTabIndex == sourceIndex {
            selectedTabIndex = destinationIndex
        } else if sourceIndex < selectedTabIndex && destinationIndex >= selectedTabIndex {
            selectedTabIndex -= 1
        } else if sourceIndex > selectedTabIndex && destinationIndex <= selectedTabIndex {
            selectedTabIndex += 1
        }

        notifyTabsChanged()
    }

    /// 현재 탭 닫기
    func closeCurrentTab() {
        closeTab(at: selectedTabIndex)
    }

    /// 현재 탭 저장 (EditorView에서 내용을 전달받아 저장)
    /// 주의: EditorView와 연동 필요
    func saveCurrentTab() {
        flushEditor()
        guard let tab = selectedTab, let content = getCachedContent(for: tab.url) else { return }
        if !saveTab(at: selectedTabIndex, content: content) { showSaveError(for: tab.url) }
    }

    func goBack() { navigate(to: navigationIndex - 1) }
    func goForward() { navigate(to: navigationIndex + 1) }
    private func navigate(to index: Int) {
        guard navigation.indices.contains(index) else { return }
        navigating = true
        navigationIndex = index
        openFile(FileSystemItem(url: navigation[index], isDirectory: false))
        navigating = false
    }

    func flushEditor() {
        NotificationCenter.default.post(name: .editorWillPerformFileOperation, object: nil)
    }

    /// Resolve all decisions before removing any drafts. Cancel keeps the workspace intact.
    func prepareToClose(_ candidates: [EditorTab]) -> Bool {
        flushEditor()
        approvedDiscards.removeAll()
        var discard: [URL] = []
        for candidate in candidates {
            guard let index = tabs.firstIndex(where: { $0.id == candidate.id }), tabs[index].isModified else { continue }
            let url = tabs[index].url
            let alert = NSAlert()
            alert.messageText = L10n.get("app.quit.saveChangesTitle")
            alert.informativeText = String(format: L10n.get("app.quit.saveChangesMessage"), candidate.title)
            alert.addButton(withTitle: L10n.get("app.quit.save"))
            alert.addButton(withTitle: L10n.get("app.quit.dontSave"))
            alert.addButton(withTitle: L10n.common.cancel)
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                guard let content = getCachedContent(for: url), saveTab(at: index, content: content) else {
                    showSaveError(for: url)
                    return false
                }
            case .alertSecondButtonReturn: discard.append(url)
            default: return false
            }
        }
        approvedDiscards = Set(discard)
        return true
    }

    func showSaveError(for url: URL) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.get("storage.saveFailed")
        alert.informativeText = saveErrors[url] ?? L10n.get("storage.saveFailed")
        alert.addButton(withTitle: L10n.common.confirm)
        alert.runModal()
    }

    func saveAs() {
        flushEditor()
        guard let tab = selectedTab, let content = getCachedContent(for: tab.url) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = tab.title
        panel.directoryURL = tab.url.deletingLastPathComponent()
        guard panel.runModal() == .OK, let target = panel.url else { return }
        do {
            if target == tab.url {
                if !saveTab(at: selectedTabIndex, content: content) { showSaveError(for: tab.url) }
                return
            }
            guard !tabs.contains(where: { $0.url == target }) else { throw DocumentFileStore.Failure.conflict }
            if FileManager.default.fileExists(atPath: target.path) {
                let base = try String(contentsOf: target, encoding: .utf8)
                try DocumentFileStore.save(content, at: target, expected: base)
            } else { try DocumentFileStore.create(content, at: target) }
            relocateTabs(from: tab.url, to: target)
            if let i = findTab(with: target) {
                editStates[target]?.markAsSaved()
                tabs[i].isModified = false
                lastSavedAt[target] = Date()
            }
            autoSaveSessionIfNeeded()
        } catch {
            saveErrors[tab.url] = error.localizedDescription
            showSaveError(for: tab.url)
        }
    }

    func relocateTabs(from old: URL, to new: URL) {
        for i in tabs.indices {
            let source = tabs[i].url
            guard DocumentFileStore.contains(source, in: old) else { continue }
            let suffix = String(source.path.dropFirst(old.path.count))
            let target = URL(fileURLWithPath: new.path + suffix)
            let oldItem = tabs[i].fileItem
            tabs[i].fileItem = FileSystemItem(url: target, isDirectory: oldItem.isDirectory)
            editStates[target] = editStates.removeValue(forKey: source)
            saveErrors[target] = saveErrors.removeValue(forKey: source)
            lastSavedAt[target] = lastSavedAt.removeValue(forKey: source)
        }
        notifyTabsChanged()
    }

    // MARK: - Notifications

    /// 탭 변경 알림 전송 (AppKit 컴포넌트 업데이트용)
    private func notifyTabsChanged() {
        if !navigating, let url = selectedTab?.url, (navigation.indices.contains(navigationIndex) ? navigation[navigationIndex] : nil) != url {
            if navigationIndex + 1 < navigation.count { navigation = Array(navigation.prefix(navigationIndex + 1)) }
            navigation.append(url)
            navigationIndex = navigation.count - 1
        }
        NotificationCenter.default.post(name: .editorTabsDidChange, object: nil)
        // 탭 변경 시 세션 자동 저장
        autoSaveSessionIfNeeded()
    }

    // MARK: - Session Persistence

    /// 세션 상태 파일명
    private static let sessionFileName = "editor-session.json"
    /// 에디터 설정 파일명
    private static let editorSettingsFileName = "editor-settings.json"

    /// 프로젝트의 데이터 폴더 경로
    private func dataFolderURL(for projectURL: URL) -> URL {
        let projectName = projectURL.deletingPathExtension().lastPathComponent
        let dataFolderName = ".\(projectName).\(ProjectManager.dataFolderExtension)"
        return projectURL.appendingPathComponent(dataFolderName)
    }

    /// 프로젝트의 세션 파일 경로
    private func sessionFileURL(for projectURL: URL) -> URL {
        return dataFolderURL(for: projectURL).appendingPathComponent(Self.sessionFileName)
    }

    /// 프로젝트의 에디터 설정 파일 경로
    private func editorSettingsFileURL(for projectURL: URL) -> URL {
        return dataFolderURL(for: projectURL).appendingPathComponent(Self.editorSettingsFileName)
    }

    /// 현재 탭 상태를 프로젝트에 저장
    func saveSession(to projectURL: URL, omittingApprovedDiscards: Bool = false) {
        // 탭 상태를 상대 경로로 변환
        let tabStates = tabs.compactMap { tab -> TabState? in
            let filePath = tab.url.path
            let projectPath = projectURL.path

            // 프로젝트 폴더 내 파일인지 확인
            let isExternal = !filePath.hasPrefix(projectPath + "/")

            // 상대 경로 계산
            let relativePath = isExternal ? tab.url.lastPathComponent : String(filePath.dropFirst(projectPath.count + 1))
            // 커서 위치 가져오기 (editStates에서)
            let cursor = editStates[tab.url]?.cursorPosition ?? (0, 0)
            var snapshot = TabState(relativePath: relativePath, isModified: tab.isModified, cursorLine: cursor.0, cursorColumn: cursor.1)
            if isExternal { snapshot.externalURL = tab.url }
            if let state = editStates[tab.url], state.isModified,
               !(omittingApprovedDiscards && approvedDiscards.contains(tab.url)) {
                snapshot.draftContent = state.content
                snapshot.baseContent = state.originalContent
            }
            return snapshot
        }

        let sessionState = EditorSessionState(
            tabs: tabStates,
            selectedTabIndex: selectedTabIndex
        )

        let sessionFile = sessionFileURL(for: projectURL)

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            // Keep a machine-local mirror even when a project volume becomes unavailable.
            // Absolute external paths are restored only from this app-owned location.
            try FileManager.default.createDirectory(at: recoveryDirectory, withIntermediateDirectories: true)
            try encoder.encode(sessionState).write(to: localSessionURL(for: projectURL), options: .atomic)
            let portableTabs = tabStates.filter { $0.externalURL == nil }
            let selectedURL = selectedTab?.url
            let portableIndex = portableTabs.firstIndex { projectURL.appendingPathComponent($0.relativePath) == selectedURL } ?? 0
            let portable = EditorSessionState(tabs: portableTabs, selectedTabIndex: portableIndex)
            try encoder.encode(portable).write(to: sessionFile, options: .atomic)
            recoveryError = nil
        } catch {
            recoveryError = error.localizedDescription
        }
    }

    /// 프로젝트에서 탭 상태 복원
    func restoreSession(from projectURL: URL) {
        recoveryWork?.cancel()
        isSavingSession = true
        defer { isSavingSession = false }
        sessionProjectURL = projectURL
        recoveryError = nil
        navigation.removeAll()
        navigationIndex = -1
        editStates.removeAll()
        tabs.removeAll()
        selectedTabIndex = 0
        let local = localSessionURL(for: projectURL)
        let portable = sessionFileURL(for: projectURL)
        var decoded: EditorSessionState?
        var trustedLocal = false
        for file in [local, portable] where FileManager.default.fileExists(atPath: file.path) {
            do {
                decoded = try JSONDecoder().decode(EditorSessionState.self, from: Data(contentsOf: file))
                trustedLocal = file == local
                break
            } catch {
                recoveryError = error.localizedDescription
                let archive = file.deletingPathExtension().appendingPathExtension("unreadable-" + UUID().uuidString + ".json")
                try? FileManager.default.copyItem(at: file, to: archive)
            }
        }
        guard let session = decoded else { return }
        for entry in session.tabs {
            let url = (entry.externalURL ?? projectURL.appendingPathComponent(entry.relativePath)).standardizedFileURL
            guard ((trustedLocal && entry.externalURL != nil) || (entry.externalURL == nil && DocumentFileStore.contains(url, in: projectURL))),
                  FileManager.default.fileExists(atPath: url.path) || entry.draftContent != nil else { continue }
            let tab = EditorTab(fileItem: FileSystemItem(url: url, isDirectory: false), isModified: entry.draftContent != nil)
            tabs.append(tab)
            if let draft = entry.draftContent, let base = entry.baseContent {
                editStates[url] = TabEditState(content: draft, originalContent: base, cursorPosition: (entry.cursorLine, entry.cursorColumn))
            } else {
                setCachedCursorPosition(line: entry.cursorLine, column: entry.cursorColumn, for: url)
            }
        }
        selectedTabIndex = max(0, min(session.selectedTabIndex, tabs.count - 1))
        NotificationCenter.default.post(name: .editorTabsDidChange, object: nil)
    }

    // MARK: - Editor Settings Persistence

    /// 에디터 설정을 프로젝트에 저장
    func saveEditorSettings(_ settings: ProjectEditorSettings, to projectURL: URL) {
        let settingsFile = editorSettingsFileURL(for: projectURL)

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(settings)
            try data.write(to: settingsFile)
        } catch {
            print("Failed to save editor settings: \(error)")
        }
    }

    /// 프로젝트에서 에디터 설정 로드
    func loadEditorSettings(from projectURL: URL) -> ProjectEditorSettings? {
        let settingsFile = editorSettingsFileURL(for: projectURL)

        guard FileManager.default.fileExists(atPath: settingsFile.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: settingsFile)
            let settings = try JSONDecoder().decode(ProjectEditorSettings.self, from: data)
            return settings
        } catch {
            print("Failed to load editor settings: \(error)")
            return nil
        }
    }

    // MARK: - External File Change Detection

    /// 파일이 외부에서 변경되었는지 확인
    /// - Returns: 변경되었으면 true
    func checkExternalChange(for url: URL) -> Bool {
        guard let editState = editStates[url] else { return false }

        do {
            let currentDiskContent = try String(contentsOf: url, encoding: .utf8)
            return currentDiskContent != editState.originalContent
        } catch {
            return false
        }
    }

    /// 외부 변경 내용을 반영하고 변경된 줄 번호들을 반환
    /// - Returns: 변경된 줄 번호들 (1-indexed)
    func detectExternalChanges(for url: URL) -> Set<Int> {
        guard let old = editStates[url]?.originalContent,
              let new = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return DocumentFileStore.changedLines(from: old, to: new)
    }

    /// 외부 변경을 적용하고 originalContent 업데이트
    func applyExternalChanges(for url: URL) {
        do {
            let currentDiskContent = try String(contentsOf: url, encoding: .utf8)

            if editStates[url] != nil {
                // 탭이 수정되지 않은 상태면 content도 업데이트
                if !editStates[url]!.isModified {
                    editStates[url]?.content = currentDiskContent
                }
                editStates[url]?.originalContent = currentDiskContent
            } else {
                editStates[url] = TabEditState(content: currentDiskContent, originalContent: currentDiskContent)
            }
        } catch {
            print("Failed to apply external changes: \(error)")
        }
    }

    /// LCS (Longest Common Subsequence) 계산
    // Line comparison lives in DocumentFileStore and has bounded linear memory.
}
