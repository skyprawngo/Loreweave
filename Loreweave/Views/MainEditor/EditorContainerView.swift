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

    private var tabManager: EditorTabManager { EditorTabManager.shared }

    // 에디터 상태
    @State private var text: String = ""
    @State private var fontSize: CGFloat = UserSettings.shared.editorFontSize
    @State private var lineSpacingOption: LineSpacingOption = .normal
    @State private var cursorLine: Int = 1
    @State private var pendingFormatAction: MarkdownFormatType?
    @State private var selectedLineRange: ClosedRange<Int>?
    @State private var currentFileURL: URL?
    @State private var isLoading: Bool = false
    @State private var originalContent: String = ""

    /// AI 패널 공간 확보를 위한 우측 패딩 (텍스트 에디터 영역에만 적용)
    var trailingPadding: CGFloat = 0

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
                    .padding(.trailing, trailingPadding)

                // 툴바
                EditorToolbarView(
                    fontSize: $fontSize,
                    lineSpacingOption: $lineSpacingOption,
                    onFormatAction: { formatType in
                        pendingFormatAction = formatType
                    }
                )
                .padding(.trailing, trailingPadding)

                Divider()
                    .padding(.trailing, trailingPadding)

                // 코드 에디터
                CodeEditorWrapperView(
                    text: $text,
                    cursorLine: $cursorLine,
                    selectedLineRange: $selectedLineRange,
                    fontSize: fontSize,
                    lineHeightMultiple: lineSpacingOption.rawValue,
                    isEditable: currentFileExists,
                    formatAction: pendingFormatAction,
                    onFormatApplied: { pendingFormatAction = nil }
                )
                .background(AppColors.textEditorBackground)
                .clipped()  // gutter가 에디터 영역 밖으로 나가지 않도록 클리핑
                .padding(.trailing, trailingPadding)

                // 상태바
                EditorStatusBarView(
                    wordCount: wordCount,
                    characterCount: text.count,
                    lineCount: lineCount,
                    selectedLineRange: selectedLineRange
                )
                .padding(.trailing, trailingPadding)
            }
        }
        .onChange(of: tabManager.selectedTab?.url) { oldURL, newURL in
            if let oldURL = oldURL {
                tabManager.setCachedContent(text, for: oldURL)
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
            // 폰트 크기 변경 시 UserSettings에 저장
            UserSettings.shared.editorFontSize = newValue
        }
        .onAppear {
            loadFileContent(from: tabManager.selectedTab?.url)
        }
        .onReceive(appCommands.$saveRequested) { requested in
            if requested {
                handleSave()
                appCommands.saveRequested = false
            }
        }
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
    EditorContainerView(trailingPadding: 0)
        .environmentObject(AppCommands.shared)
}
