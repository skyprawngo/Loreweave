//
//  EditorTabManager.swift
//  Loreweave
//
//  에디터 탭 관리 (열린 파일 탭 상태 관리)
//

import Foundation

// MARK: - Notification Names

extension Notification.Name {
    /// 에디터 탭이 변경됨 (추가, 삭제, 선택 변경 등)
    static let editorTabsDidChange = Notification.Name("editorTabsDidChange")
}

// MARK: - Tab State (저장용)

/// 탭 상태 저장을 위한 Codable 구조체
struct TabState: Codable {
    let relativePath: String  // 프로젝트 폴더 기준 상대 경로
    let isModified: Bool

    init(relativePath: String, isModified: Bool = false) {
        self.relativePath = relativePath
        self.isModified = isModified
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

/// 에디터에서 열린 파일 탭
struct EditorTab: Identifiable, Equatable {
    let id: UUID
    let fileItem: FileSystemItem
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

/// 에디터 탭 관리자
@Observable
final class EditorTabManager {
    static let shared = EditorTabManager()

    /// 현재 열린 탭들
    private(set) var tabs: [EditorTab] = []

    /// 탭별 텍스트 캐시 (URL -> 편집 중인 텍스트)
    private var textCache: [URL: String] = [:]

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
    private func autoSaveSessionIfNeeded() {
        guard !isSavingSession else { return }
        guard let projectPath = ProjectManager.shared.currentProject?.path else { return }
        isSavingSession = true
        saveSession(to: projectPath)
        isSavingSession = false
    }

    /// 현재 선택된 탭
    var selectedTab: EditorTab? {
        guard selectedTabIndex >= 0 && selectedTabIndex < tabs.count else { return nil }
        return tabs[selectedTabIndex]
    }

    private init() {}

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
    func closeTab(at index: Int) {
        guard index >= 0 && index < tabs.count else { return }

        // TODO: 수정된 파일이면 저장 여부 묻기

        // 캐시에서 해당 탭 내용 삭제
        let tabURL = tabs[index].url
        removeCachedContent(for: tabURL)

        tabs.remove(at: index)

        // 선택된 탭 인덱스 조정
        if tabs.isEmpty {
            selectedTabIndex = 0
        } else if selectedTabIndex >= tabs.count {
            selectedTabIndex = tabs.count - 1
        } else if index < selectedTabIndex {
            selectedTabIndex -= 1
        }

        notifyTabsChanged()
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
        guard index >= 0 && index < tabs.count else { return false }

        let tab = tabs[index]
        let url = tab.url

        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            tabs[index].isModified = false
            tabs[index].justSaved = true

            // 일정 시간 후 justSaved 상태 해제
            let tabId = tabs[index].id
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                if let index = self?.tabs.firstIndex(where: { $0.id == tabId }) {
                    self?.tabs[index].justSaved = false
                }
            }
            return true
        } catch {
            print("Failed to save file: \(error)")
            return false
        }
    }

    /// URL로 탭의 수정 상태 확인
    func isModified(url: URL) -> Bool {
        guard let index = findTab(with: url) else { return false }
        return tabs[index].isModified
    }

    /// URL로 캐시된 탭 내용 가져오기
    func getCachedContent(for url: URL) -> String? {
        return textCache[url]
    }

    /// 탭 내용을 캐시에 저장
    func setCachedContent(_ content: String, for url: URL) {
        textCache[url] = content
    }

    /// 캐시에서 탭 내용 삭제
    func removeCachedContent(for url: URL) {
        textCache.removeValue(forKey: url)
    }

    /// 모든 탭 닫기
    func closeAllTabs() {
        // TODO: 수정된 파일들 저장 여부 묻기
        textCache.removeAll()
        tabs.removeAll()
        selectedTabIndex = 0
        notifyTabsChanged()
    }

    /// 현재 탭 외 모든 탭 닫기
    func closeOtherTabs(except index: Int) {
        guard index >= 0 && index < tabs.count else { return }
        let tabToKeep = tabs[index]

        // 유지할 탭 외의 캐시 삭제
        for tab in tabs where tab.url != tabToKeep.url {
            removeCachedContent(for: tab.url)
        }

        tabs = [tabToKeep]
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

    /// 현재 탭 닫기
    func closeCurrentTab() {
        closeTab(at: selectedTabIndex)
    }

    /// 현재 탭 저장 (EditorView에서 내용을 전달받아 저장)
    /// 주의: EditorView와 연동 필요
    func saveCurrentTab() {
        // TODO: EditorView의 현재 텍스트 내용을 가져와서 저장해야 함
        // 현재는 수정 플래그만 초기화
        guard selectedTabIndex >= 0 && selectedTabIndex < tabs.count else { return }
        // EditorView에서 직접 saveTab(at:content:) 호출하도록 구현 필요
    }

    // MARK: - Notifications

    /// 탭 변경 알림 전송 (AppKit 컴포넌트 업데이트용)
    private func notifyTabsChanged() {
        NotificationCenter.default.post(name: .editorTabsDidChange, object: nil)
        // 탭 변경 시 세션 자동 저장
        autoSaveSessionIfNeeded()
    }

    // MARK: - Session Persistence

    /// 세션 상태 파일명
    private static let sessionFileName = "editor-session.json"

    /// 프로젝트의 세션 파일 경로
    private func sessionFileURL(for projectURL: URL) -> URL {
        let projectName = projectURL.deletingPathExtension().lastPathComponent
        let dataFolderName = ".\(projectName).\(ProjectManager.dataFolderExtension)"
        let dataFolder = projectURL.appendingPathComponent(dataFolderName)
        return dataFolder.appendingPathComponent(Self.sessionFileName)
    }

    /// 현재 탭 상태를 프로젝트에 저장
    func saveSession(to projectURL: URL) {
        // 탭 상태를 상대 경로로 변환
        let tabStates = tabs.compactMap { tab -> TabState? in
            let filePath = tab.url.path
            let projectPath = projectURL.path

            // 프로젝트 폴더 내 파일인지 확인
            guard filePath.hasPrefix(projectPath) else { return nil }

            // 상대 경로 계산
            let relativePath = String(filePath.dropFirst(projectPath.count + 1))
            return TabState(relativePath: relativePath, isModified: tab.isModified)
        }

        let sessionState = EditorSessionState(
            tabs: tabStates,
            selectedTabIndex: selectedTabIndex
        )

        let sessionFile = sessionFileURL(for: projectURL)

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(sessionState)
            try data.write(to: sessionFile)
        } catch {
            print("Failed to save editor session: \(error)")
        }
    }

    /// 프로젝트에서 탭 상태 복원
    func restoreSession(from projectURL: URL) {
        let sessionFile = sessionFileURL(for: projectURL)

        guard FileManager.default.fileExists(atPath: sessionFile.path) else {
            return
        }

        do {
            let data = try Data(contentsOf: sessionFile)
            let sessionState = try JSONDecoder().decode(EditorSessionState.self, from: data)

            // 기존 탭 모두 닫기
            closeAllTabs()

            // 저장된 탭 복원
            for tabState in sessionState.tabs {
                let fileURL = projectURL.appendingPathComponent(tabState.relativePath)

                // 파일이 존재하는지 확인
                guard FileManager.default.fileExists(atPath: fileURL.path) else {
                    continue
                }

                // FileSystemItem 생성
                let fileItem = FileSystemItem(url: fileURL, isDirectory: false)

                // 탭 열기
                let newTab = EditorTab(fileItem: fileItem, isModified: tabState.isModified)
                tabs.append(newTab)
            }

            // 선택된 탭 인덱스 복원
            if !tabs.isEmpty {
                selectedTabIndex = min(sessionState.selectedTabIndex, tabs.count - 1)
            }

            notifyTabsChanged()
        } catch {
            print("Failed to restore editor session: \(error)")
        }
    }
}
