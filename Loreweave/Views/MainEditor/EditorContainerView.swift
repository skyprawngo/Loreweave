//
//  EditorContainerView.swift
//  Loreweave
//
//  에디터 컨테이너 뷰 - TabBar + Toolbar + TextEditor + StatusBar
//  MainEditorView의 하위 컴포넌트
//

import SwiftUI

// MARK: - Editor Container View

/// 에디터 컨테이너 (탭바 + 툴바 + 텍스트 에디터 + 상태바)
struct EditorContainerView: View {
    @EnvironmentObject var appCommands: AppCommands
    let projectManager: ProjectManager

    @State private var tabManager = EditorTabManager.shared

    // 에디터 상태
    @State private var text: String = ""
    @State private var wordCount = 0
    @State private var characterCount = 0
    @State private var lineCount = 1
    @State private var fontSize: CGFloat = UserSettings.shared.editorFontSize
    @State private var fontName: String = UserSettings.shared.editorFontName
    @State private var lineSpacingOption: LineSpacingOption = .normal
    @State private var letterSpacing: CGFloat = 0
    @State private var cursorLine: Int = 1
    @State private var cursorColumn: Int = 0
    @State private var editCommand: EditorCommand?
    @State private var currentDocumentID: UUID?
    @State private var contentRevision = UUID()
    @State private var loadError: String?
    @State private var showingFind = false
    @State private var showingReplace = false
    @State private var findText = ""
    @State private var replacementText = ""
    @State private var selectedLineRange: ClosedRange<Int>?
    @State private var currentFileURL: URL?
    @State private var previousFileURL: URL?  // 탭 전환 시 이전 파일 URL 추적
    @State private var isLoading: Bool = false
    @State private var isLoadingSettings: Bool = false
    @State private var initialCursorPosition: (line: Int, column: Int)? = nil
    @State private var externallyModifiedLines: Set<Int> = []  // AI가 수정한 줄 번호들

    // 자동 저장 타이머
    @State private var autoSaveTimer: Timer?
    @State private var autoSaveOption: AutoSaveOption = UserSettings.shared.autoSaveOption

    // 외부 파일 변경 감시
    @State private var fileWatchTimer: Timer?

    private var currentFileExists: Bool {
        tabManager.selectedTab?.fileExists ?? true
    }

    var body: some View {
        VStack(spacing: 0) {
            if tabManager.isEmpty {
                emptyStateView
            } else {
                // 탭바
                TabBarView()

                // 툴바
                EditorToolbarView(
                    fontSize: $fontSize,
                    lineSpacingOption: $lineSpacingOption,
                    letterSpacing: $letterSpacing,
                    fontName: $fontName,
                    onFormatAction: { formatType in
                        editCommand = EditorCommand(.format(formatType))
                    }
                )

                Divider()

                if showingFind {
                    HStack {
                        TextField(L10n.get("search.find"), text: $findText)
                            .onSubmit { editCommand = EditorCommand(.find(findText, forward: true)) }
                        Button(L10n.get("search.previous")) { editCommand = EditorCommand(.find(findText, forward: false)) }
                        Button(L10n.get("search.next")) { editCommand = EditorCommand(.find(findText, forward: true)) }
                        if showingReplace {
                            TextField(L10n.get("search.replacement"), text: $replacementText)
                            Button(L10n.get("search.replace")) { editCommand = EditorCommand(.replace(findText, replacement: replacementText, all: false)) }
                            Button(L10n.get("search.replaceAll")) { editCommand = EditorCommand(.replace(findText, replacement: replacementText, all: true)) }
                        }
                        Button(L10n.get("common.close")) { showingFind = false }
                    }
                    .textFieldStyle(.roundedBorder)
                    .padding(8)
                }
                if let message = loadError ?? currentFileURL.flatMap({ tabManager.saveErrors[$0] }) ?? tabManager.recoveryError {
                    HStack {
                        Text(message).foregroundStyle(AppColors.errorIndicator)
                        Spacer()
                        Button(L10n.get("shortcut.file.saveAs")) { tabManager.saveAs() }
                        if loadError != nil {
                            Button(L10n.get("storage.retry")) {
                                let url = currentFileURL
                                currentFileURL = nil
                                loadFileContent(from: url)
                            }
                        }
                    }.padding(8)
                }

                // 코드 에디터 (커스텀 LoreEditor)
                LoreEditorRepresentable(
                    text: $text,
                    cursorLine: $cursorLine,
                    cursorColumn: $cursorColumn,
                    selectedLineRange: $selectedLineRange,
                    externallyModifiedLines: $externallyModifiedLines,
                    fontSize: fontSize,
                    fontName: fontName,
                    lineHeightMultiple: lineSpacingOption.rawValue,
                    letterSpacing: letterSpacing,
                    isEditable: loadError == nil,
                    initialCursorPosition: initialCursorPosition,
                    onContentWillChange: { ownerURL, finalText, cursorLine, cursorColumn in
                        // 탭 전환 직전: 이전 파일의 최종 텍스트(조합 확정 후)와 커서 위치를 캐시에 저장
                        if let prevURL = ownerURL, tabManager.findTab(with: prevURL) != nil,
                           !(prevURL == currentFileURL && loadError != nil) {
                            if tabManager.getCachedContent(for: prevURL) != finalText { clearModifiedLinesOnEdit() }
                            tabManager.setCachedContent(finalText, for: prevURL)
                            // 조합 확정 후의 커서 위치 저장 (이미 0-based)
                            tabManager.setCachedCursorPosition(line: cursorLine, column: cursorColumn, for: prevURL)
                        }
                    },
                    documentID: currentDocumentID,
                    documentURL: currentFileURL,
                    editCommand: editCommand,
                    contentRevision: contentRevision,
                    isDocumentActive: { id, url, revision in
                        tabManager.selectedTab?.id == id && tabManager.selectedTab?.url == url && contentRevision == revision
                    }
                )
                .background(AppColors.textEditorBackground)
                .clipped()

                // 상태바
                EditorStatusBarView(
                    wordCount: wordCount,
                    characterCount: characterCount,
                    lineCount: lineCount,
                    selectedLineRange: selectedLineRange,
                    saveStatus: saveStatus
                )
            }
        }
        .onChange(of: tabManager.selectedTab?.id) { _, _ in
            loadFileContent(from: tabManager.selectedTab?.url)
        }
        .onChange(of: tabManager.selectedTab?.url) { oldURL, newURL in
            tabManager.flushEditor()
            if let oldURL, autoSaveOption == .onTabChange { autoSaveIfModified(for: oldURL) }
            loadFileContent(from: newURL)
        }
        .onChange(of: text) { _, value in
            updateStatistics(value)
        }
        .onChange(of: cursorLine) { _, _ in
            // 커서 위치 변경 시 바로 캐시에 저장 (앱 종료 시 누락 방지)
            // cursorLine은 1-based, 캐시는 0-based로 저장
            guard let url = currentFileURL, !isLoading, loadError == nil, tabManager.findTab(with: url) != nil else { return }
            tabManager.setCachedCursorPosition(line: cursorLine - 1, column: cursorColumn, for: url)
        }
        .onChange(of: cursorColumn) { _, _ in
            // 커서 위치 변경 시 바로 캐시에 저장 (앱 종료 시 누락 방지)
            // cursorLine은 1-based, 캐시는 0-based로 저장
            guard let url = currentFileURL, !isLoading, loadError == nil, tabManager.findTab(with: url) != nil else { return }
            tabManager.setCachedCursorPosition(line: cursorLine - 1, column: cursorColumn, for: url)
        }
        .onChange(of: fontSize) { _, newValue in
            // 폰트 크기 변경 시 프로젝트 설정에 저장
            guard !isLoadingSettings else { return }
            saveEditorSettingsToProject()
        }
        .onChange(of: fontName) { _, newValue in
            // 폰트 이름 변경 시 프로젝트 설정에 저장
            guard !isLoadingSettings else { return }
            saveEditorSettingsToProject()
        }
        .onChange(of: lineSpacingOption) { _, newValue in
            // 줄간격 변경 시 프로젝트 설정에 저장
            guard !isLoadingSettings else { return }
            saveEditorSettingsToProject()
        }
        .onChange(of: projectManager.currentProject?.path) { oldPath, newPath in
            // 프로젝트가 변경되면 해당 프로젝트의 에디터 설정 로드
            if oldPath != newPath {
                loadEditorSettingsFromProject()
            }
        }
        .onAppear {
            loadFileContent(from: tabManager.selectedTab?.url)
            loadEditorSettingsFromProject()
            setupAutoSaveTimer()
            startFileWatchTimer()
        }
        .onDisappear {
            stopAutoSaveTimer()
            stopFileWatchTimer()
        }
        .onChange(of: autoSaveOption) { _, newValue in
            UserSettings.shared.autoSaveOption = newValue
            setupAutoSaveTimer()
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            let updated = UserSettings.shared.autoSaveOption
            if autoSaveOption != updated { autoSaveOption = updated }
        }
        .onReceive(appCommands.$saveAsRequested) { requested in
            if requested { appCommands.saveAsRequested = false; tabManager.saveAs() }
        }
        .onReceive(appCommands.$resetZoomRequested) { requested in
            if requested { appCommands.resetZoomRequested = false; fontSize = UserSettings.shared.editorFontSize }
        }
        .onReceive(appCommands.$findRequested) { requested in
            if requested { appCommands.findRequested = false; showingFind = true; showingReplace = false }
        }
        .onReceive(appCommands.$findAndReplaceRequested) { requested in
            if requested { appCommands.findAndReplaceRequested = false; showingFind = true; showingReplace = true }
        }
        .onReceive(appCommands.$searchInDocument) { query in
            guard let query else { return }
            appCommands.searchInDocument = nil
            findText = query
            showingFind = true
            DispatchQueue.main.async { editCommand = EditorCommand(.find(query, forward: true)) }
        }
        .onReceive(appCommands.$saveRequested) { requested in
            if requested {
                handleSave()
                appCommands.saveRequested = false
            }
        }
        .onReceive(appCommands.$zoomInRequested) { requested in
            if requested {
                increaseFontSize()
                appCommands.zoomInRequested = false
            }
        }
        .onReceive(appCommands.$zoomOutRequested) { requested in
            if requested {
                decreaseFontSize()
                appCommands.zoomOutRequested = false
            }
        }
    }

    // MARK: - Font Size

    /// 폰트 크기 증가 (최대 72pt)
    private func increaseFontSize() {
        let newSize = min(fontSize + 2, 72)
        fontSize = newSize
    }

    /// 폰트 크기 축소 (최소 8pt)
    private func decreaseFontSize() {
        let newSize = max(fontSize - 2, 8)
        fontSize = newSize
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundStyle(AppColors.toolbarIcon)

            Text(L10n.get("explorer.selectSection"))
                .font(.system(size: 14))
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.textEditorBackground)
    }

    // MARK: - File Loading

    private func loadFileContent(from url: URL?) {
        guard let url = url else {
            currentDocumentID = nil
            loadError = nil
            text = ""
            currentFileURL = nil
            initialCursorPosition = nil
            externallyModifiedLines = []
            return
        }

        guard url != currentFileURL || currentDocumentID != tabManager.selectedTab?.id else { return }

        currentFileURL = url
        contentRevision = UUID()
        currentDocumentID = tabManager.selectedTab?.id
        loadError = nil
        isLoading = true
        defer { isLoading = false }
        if let state = tabManager.getEditState(for: url), state.isModified {
            text = state.content
            initialCursorPosition = state.cursorPosition
            externallyModifiedLines = []
            return
        }

        // 디스크에서 파일 읽기
        let fileContent: String
        do {
            fileContent = try String(contentsOf: url, encoding: .utf8)
        } catch {
            loadError = L10n.get("storage.readFailed") + " " + error.localizedDescription
            text = ""
            return
        }

        // 기존 캐시된 커서 위치 먼저 가져오기 (덮어쓰기 전에)
        let cachedCursor = tabManager.getCachedCursorPosition(for: url)

        // 탭이 수정된 상태인 경우에만 캐시 사용
        // 수정되지 않은 탭은 항상 디스크에서 읽음 (외부 변경 반영)
        if let editState = tabManager.getEditState(for: url), editState.isModified {
            // 수정된 탭: 캐시된 내용 사용
            text = editState.content
            externallyModifiedLines = []
        } else {
            // 수정되지 않은 탭: 디스크에서 읽은 내용 사용
            text = fileContent
            // 편집 상태 초기화 (커서 위치는 유지)
            tabManager.setEditState(
                TabEditState(
                    content: fileContent,
                    originalContent: fileContent,
                    cursorPosition: cachedCursor ?? (0, 0)
                ),
                for: url
            )
            externallyModifiedLines = []
        }

        // 커서 위치 복원 (설정이 활성화된 경우에만)
        // 탭 전환 시 커서 위치로 스크롤됨 (LoreEditorRepresentable에서 처리)
        if UserSettings.shared.rememberCursorPosition, let cursor = cachedCursor {
            initialCursorPosition = cursor
        } else {
            initialCursorPosition = nil
        }

        isLoading = false
    }

    // MARK: - Save

    private func handleSave() {
        guard loadError == nil else { return }
        tabManager.saveCurrentTab()
    }

    private var saveStatus: String {
        guard let url = currentFileURL else { return "" }
        if loadError != nil || tabManager.saveErrors[url] != nil { return L10n.get("storage.saveFailed") }
        if tabManager.isModified(url: url) { return L10n.get("storage.unsaved") }
        if let time = tabManager.lastSavedAt[url] {
            return L10n.get("storage.saved") + " " + time.formatted(date: .omitted, time: .shortened)
        }
        return L10n.get("storage.saved")
    }

    // MARK: - Computed Properties

    // Count once per content revision, not on cursor or layout updates.
    private func updateStatistics(_ value: String) {
        var words = 0
        var characters = 0
        var lines = 1
        var inWord = false
        for character in value {
            characters += 1
            if character.isNewline { lines += 1 }
            if character.isWhitespace { inWord = false }
            else if !inWord { words += 1; inWord = true }
        }
        wordCount = words
        characterCount = characters
        lineCount = lines
    }

    // MARK: - Project Editor Settings

    /// 프로젝트에서 에디터 설정 로드
    private func loadEditorSettingsFromProject() {
        guard let projectPath = projectManager.currentProject?.path else { return }

        isLoadingSettings = true

        if let settings = tabManager.loadEditorSettings(from: projectPath) {
            fontName = settings.fontName
            fontSize = settings.fontSize
            // lineSpacing을 LineSpacingOption으로 변환
            lineSpacingOption = LineSpacingOption(rawValue: settings.lineSpacing) ?? .normal
        } else {
            // 프로젝트에 설정이 없으면 UserSettings의 기본값 사용
            fontName = UserSettings.shared.editorFontName
            fontSize = UserSettings.shared.editorFontSize
            lineSpacingOption = LineSpacingOption(rawValue: UserSettings.shared.editorLineSpacing) ?? .normal
        }

        isLoadingSettings = false
    }

    /// 에디터 설정을 프로젝트에 저장
    private func saveEditorSettingsToProject() {
        guard let projectPath = projectManager.currentProject?.path else { return }

        let settings = ProjectEditorSettings(
            fontName: fontName,
            fontSize: fontSize,
            lineSpacing: lineSpacingOption.rawValue
        )

        tabManager.saveEditorSettings(settings, to: projectPath)
    }

    // MARK: - Auto Save

    /// 자동 저장 타이머 설정
    private func setupAutoSaveTimer() {
        stopAutoSaveTimer()

        // 타이머 기반 자동 저장이 아닌 경우 (없음, 탭 변경 시) 타이머 사용 안 함
        guard autoSaveOption.intervalSeconds > 0 else { return }

        let interval = TimeInterval(autoSaveOption.intervalSeconds)
        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            autoSaveAllModifiedTabs()
        }
    }

    /// 자동 저장 타이머 정지
    private func stopAutoSaveTimer() {
        autoSaveTimer?.invalidate()
        autoSaveTimer = nil
    }

    /// 수정된 모든 탭 자동 저장
    private func autoSaveAllModifiedTabs() {
        tabManager.flushEditor()

        // 수정된 모든 탭을 캐시에서 저장
        for (index, tab) in tabManager.tabs.enumerated() {
            guard tabManager.isModified(url: tab.url) else { continue }
            if let cachedContent = tabManager.getCachedContent(for: tab.url) {
                _ = tabManager.saveTab(at: index, content: cachedContent)
            }
        }
    }

    /// 특정 URL의 탭이 수정되었으면 저장
    private func autoSaveIfModified(for url: URL) {
        guard let index = tabManager.findTab(with: url),
              tabManager.isModified(url: url) else { return }


        if let cachedContent = tabManager.getCachedContent(for: url) {
            _ = tabManager.saveTab(at: index, content: cachedContent)
        }
    }

    // MARK: - External File Change Detection

    /// 외부 파일 변경 감시 타이머 시작
    private func startFileWatchTimer() {
        stopFileWatchTimer()

        // 1초마다 파일 변경 확인
        fileWatchTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            checkForExternalFileChanges()
        }
    }

    /// 외부 파일 변경 감시 타이머 정지
    private func stopFileWatchTimer() {
        fileWatchTimer?.invalidate()
        fileWatchTimer = nil
    }

    /// 현재 열린 파일의 외부 변경 확인
    private func checkForExternalFileChanges() {
        guard let url = currentFileURL, loadError == nil,
              let base = tabManager.getEditState(for: url)?.originalContent,
              let newContent = try? String(contentsOf: url, encoding: .utf8), newContent != base else { return }
        // Commit IME only when there is a competing disk revision, not on every timer tick.
        tabManager.flushEditor()
        guard currentFileURL == url else { return }
        if tabManager.isModified(url: url) {
            tabManager.saveErrors[url] = L10n.get("storage.conflict")
            return
        }
        let cursor = tabManager.getCachedCursorPosition(for: url) ?? (0, 0)
        tabManager.setEditState(TabEditState(content: newContent, originalContent: newContent, cursorPosition: cursor), for: url)
        contentRevision = UUID()
        text = newContent
        externallyModifiedLines = DocumentFileStore.changedLines(from: base, to: newContent)
    }

    /// 사용자 편집 시 수정된 줄 표시 초기화
    private func clearModifiedLinesOnEdit() {
        if !externallyModifiedLines.isEmpty {
            externallyModifiedLines = []
        }
    }
}

// MARK: - Editor Status Bar View

struct EditorStatusBarView: View {
    let wordCount: Int
    let characterCount: Int
    let lineCount: Int
    let selectedLineRange: ClosedRange<Int>?
    let saveStatus: String

    var body: some View {
        HStack {
            Text(L10n.get("editor.lines") + " \(lineCount)")
            Text("•")
            Text("\(wordCount) \(L10n.editor.words)")
            Text("•")
            Text("\(characterCount) \(L10n.editor.characters)")

            if let range = selectedLineRange {
                Text("•")
                if range.lowerBound == range.upperBound {
                    Text(L10n.get("editor.selectedLine") + " \(range.lowerBound)")
                        .foregroundStyle(Color.accentColor)
                } else {
                    Text(L10n.get("editor.selectedLines") + " \(range.lowerBound)-\(range.upperBound)")
                        .foregroundStyle(Color.accentColor)
                }
            }

            Spacer()

            Text(saveStatus)
        }
        .font(.system(size: 11))
        .foregroundStyle(AppColors.textPrimary)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}

#Preview {
    EditorContainerView(projectManager: ProjectManager.shared)
        .environmentObject(AppCommands.shared)
}
