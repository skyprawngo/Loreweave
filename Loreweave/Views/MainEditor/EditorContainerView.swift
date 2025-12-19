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
    @State private var fontSize: CGFloat = UserSettings.shared.editorFontSize
    @State private var fontName: String = UserSettings.shared.editorFontName
    @State private var lineSpacingOption: LineSpacingOption = .normal
    @State private var letterSpacing: CGFloat = 0
    @State private var cursorLine: Int = 1
    @State private var pendingFormatAction: MarkdownFormatType?
    @State private var selectedLineRange: ClosedRange<Int>?
    @State private var currentFileURL: URL?
    @State private var isLoading: Bool = false
    @State private var originalContent: String = ""
    @State private var isLoadingSettings: Bool = false

    // 자동 저장 타이머
    @State private var autoSaveTimer: Timer?
    @State private var autoSaveOption: AutoSaveOption = UserSettings.shared.autoSaveOption

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
                        pendingFormatAction = formatType
                    }
                )

                Divider()

                // 코드 에디터 (커스텀 LoreEditor)
                LoreEditorRepresentable(
                    text: $text,
                    cursorLine: $cursorLine,
                    selectedLineRange: $selectedLineRange,
                    fontSize: fontSize,
                    fontName: fontName,
                    lineHeightMultiple: lineSpacingOption.rawValue,
                    letterSpacing: letterSpacing,
                    isEditable: currentFileExists
                )
                .background(AppColors.textEditorBackground)
                .clipped()

                // 상태바
                EditorStatusBarView(
                    wordCount: wordCount,
                    characterCount: text.count,
                    lineCount: lineCount,
                    selectedLineRange: selectedLineRange
                )
            }
        }
        .onChange(of: tabManager.selectedTab?.url) { oldURL, newURL in
            if let oldURL = oldURL {
                tabManager.setCachedContent(text, for: oldURL)

                // 탭 변경 시 자동 저장 옵션인 경우 저장
                if autoSaveOption == .onTabChange {
                    autoSaveIfModified(for: oldURL)
                }
            }
            loadFileContent(from: newURL)
        }
        .onChange(of: text) { oldValue, newValue in
            guard oldValue != newValue,
                  currentFileURL != nil,
                  !isLoading else { return }
            let isModified = newValue != originalContent
            tabManager.setModified(isModified, at: tabManager.selectedTabIndex)
            tabManager.setCachedContent(newValue, for: currentFileURL!)
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
        }
        .onDisappear {
            stopAutoSaveTimer()
        }
        .onChange(of: autoSaveOption) { _, newValue in
            UserSettings.shared.autoSaveOption = newValue
            setupAutoSaveTimer()
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
            text = ""
            originalContent = ""
            currentFileURL = nil
            return
        }

        guard url != currentFileURL else { return }

        currentFileURL = url
        isLoading = true

        let fileContent: String
        do {
            fileContent = try String(contentsOf: url, encoding: .utf8)
        } catch {
            print("Failed to load file: \(error)")
            fileContent = ""
        }
        originalContent = fileContent

        if let cachedContent = tabManager.getCachedContent(for: url) {
            text = cachedContent
        } else {
            text = fileContent
            tabManager.setCachedContent(fileContent, for: url)
        }

        isLoading = false
    }

    // MARK: - Save

    private func handleSave() {
        guard let url = currentFileURL else { return }

        if tabManager.saveCurrentTab(content: text) {
            originalContent = text
            tabManager.setCachedContent(text, for: url)
            print("File saved: \(url.lastPathComponent)")
        }
    }

    // MARK: - Computed Properties

    private var wordCount: Int {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count
    }

    private var lineCount: Int {
        text.isEmpty ? 1 : text.components(separatedBy: .newlines).count
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
        // 현재 편집 중인 탭 저장
        if let url = currentFileURL, tabManager.isModified(url: url) {
            if tabManager.saveCurrentTab(content: text) {
                originalContent = text
            }
        }

        // 다른 수정된 탭들도 캐시에서 저장
        for (index, tab) in tabManager.tabs.enumerated() {
            guard tab.isModified, tab.url != currentFileURL else { continue }
            if let cachedContent = tabManager.getCachedContent(for: tab.url) {
                _ = tabManager.saveTab(at: index, content: cachedContent)
            }
        }
    }

    /// 특정 URL의 탭이 수정되었으면 저장
    private func autoSaveIfModified(for url: URL) {
        guard let index = tabManager.findTab(with: url),
              tabManager.tabs[index].isModified else { return }

        if let cachedContent = tabManager.getCachedContent(for: url) {
            _ = tabManager.saveTab(at: index, content: cachedContent)
        }
    }
}

// MARK: - Editor Status Bar View

struct EditorStatusBarView: View {
    let wordCount: Int
    let characterCount: Int
    let lineCount: Int
    let selectedLineRange: ClosedRange<Int>?

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

            Text(L10n.editor.autoSaved)
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
