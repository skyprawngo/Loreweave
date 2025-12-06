//
//  EditorPanelView.swift
//  Loreweave
//
//  에디터 패널 뷰 - 단일 에디터 영역 (TabBar + Toolbar + TextEditor + StatusBar)
//  EditorContainerView의 하위 컴포넌트
//

import SwiftUI

// MARK: - Editor Panel View

/// 단일 에디터 패널 (탭바 + 툴바 + 텍스트 에디터 + 상태바)
struct EditorPanelView: View {
    @EnvironmentObject var appCommands: AppCommands

    private var tabManager: EditorTabManager { EditorTabManager.shared }

    // 에디터 상태
    @State private var text: String = ""
    @State private var fontSize: CGFloat = 16
    @State private var lineSpacingOption: LineSpacingOption = .normal
    @State private var textAlignment: TextAlignmentOption = .left
    @State private var cursorLine: Int = 1
    @State private var pendingFormatAction: MarkdownFormatType?
    @State private var selectedLineRange: ClosedRange<Int>?
    @State private var currentFileURL: URL?
    @State private var isLoading: Bool = false
    @State private var originalContent: String = ""

    // 찾기/바꾸기 상태
    @Binding var showFindReplace: Bool
    @Binding var findSearchText: String
    @Binding var replaceText: String
    @Binding var searchScope: SearchScope
    @Binding var searchOptions: SearchOptions
    @Binding var showReplaceField: Bool
    @Binding var matchCount: Int

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
                // 탭바 (AI 패널 공간 확보를 위해 우측 패딩 적용)
                TabBarView()
                    .padding(.trailing, trailingPadding)
                    .background(.ultraThinMaterial)
                    .environment(\.controlActiveState, .key)

                // 툴바 (AI 패널 공간 확보를 위해 우측 패딩 적용)
                EditorToolbarView(
                    fontSize: $fontSize,
                    lineSpacingOption: $lineSpacingOption,
                    textAlignment: $textAlignment,
                    onFormatAction: { formatType in
                        pendingFormatAction = formatType
                    }
                )
                .padding(.trailing, trailingPadding)
                .background(.ultraThinMaterial)
                .environment(\.controlActiveState, .key)

                Divider()

                // 텍스트 에디터 (AI 패널 공간 확보를 위해 우측 패딩 적용)
                TextEditorView(
                    text: $text,
                    cursorLine: $cursorLine,
                    selectedLineRange: $selectedLineRange,
                    fontSize: fontSize,
                    lineSpacing: lineSpacingOption.rawValue,
                    textAlignment: textAlignment.nsTextAlignment,
                    isEditable: currentFileExists,
                    formatAction: pendingFormatAction,
                    onFormatApplied: { pendingFormatAction = nil }
                )
                .padding(.trailing, trailingPadding)
                .background(AppColors.textEditorBackground)
                .environment(\.controlActiveState, .key)

                // 상태바 (AI 패널 공간 확보를 위해 우측 패딩 적용)
                EditorStatusBarView(
                    wordCount: wordCount,
                    characterCount: text.count,
                    lineCount: lineCount,
                    selectedLineRange: selectedLineRange
                )
                .padding(.trailing, trailingPadding)
                .background(AppColors.barBackground)
                .environment(\.controlActiveState, .key)
            }
        }
        .environment(\.controlActiveState, .key)
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
        .onAppear {
            loadFileContent(from: tabManager.selectedTab?.url)
        }
        .onReceive(appCommands.$saveRequested) { requested in
            if requested {
                handleSave()
                appCommands.saveRequested = false
            }
        }
        .onReceive(appCommands.$findRequested) { requested in
            if requested {
                toggleFindReplace(showReplace: false)
                appCommands.findRequested = false
            }
        }
        .onReceive(appCommands.$findAndReplaceRequested) { requested in
            if requested {
                toggleFindReplace(showReplace: true)
                appCommands.findAndReplaceRequested = false
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

    // MARK: - Find/Replace

    func toggleFindReplace(showReplace: Bool = false) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if showFindReplace && showReplaceField == showReplace {
                showFindReplace = false
            } else {
                showFindReplace = true
                showReplaceField = showReplace
            }
        }
    }

    func performFind() {
        guard !findSearchText.isEmpty else {
            matchCount = 0
            return
        }

        let options = buildSearchOptions()

        switch searchScope {
        case .currentFile:
            let matches = findMatches(in: text, searchText: findSearchText, options: options)
            matchCount = matches.count

        case .openTabs:
            var totalMatches = 0
            for tab in tabManager.tabs {
                if let content = loadFileContentSync(from: tab.url) {
                    let matches = findMatches(in: content, searchText: findSearchText, options: options)
                    totalMatches += matches.count
                }
            }
            matchCount = totalMatches

        case .project:
            var totalMatches = 0
            for tab in tabManager.tabs {
                if let content = loadFileContentSync(from: tab.url) {
                    let matches = findMatches(in: content, searchText: findSearchText, options: options)
                    totalMatches += matches.count
                }
            }
            matchCount = totalMatches
        }
    }

    private func loadFileContentSync(from url: URL) -> String? {
        if url == currentFileURL {
            return text
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    func findNext() {
        performFind()
    }

    func findPrevious() {
        performFind()
    }

    func replaceOne() {
        guard !findSearchText.isEmpty, matchCount > 0 else { return }
    }

    func replaceAll() {
        guard !findSearchText.isEmpty, matchCount > 0 else { return }

        let searchOptions = buildSearchOptions()
        text = replaceAllMatches(in: text, searchText: findSearchText, replaceText: replaceText, options: searchOptions)
        performFind()
    }

    private func buildSearchOptions() -> NSString.CompareOptions {
        var options: NSString.CompareOptions = []
        if !searchOptions.matchCase {
            options.insert(.caseInsensitive)
        }
        if searchOptions.useRegex {
            options.insert(.regularExpression)
        }
        return options
    }

    private func findMatches(in text: String, searchText: String, options: NSString.CompareOptions) -> [Range<String.Index>] {
        var matches: [Range<String.Index>] = []
        var searchRange = text.startIndex..<text.endIndex

        while let range = text.range(of: searchText, options: options, range: searchRange) {
            if searchOptions.wholeWord {
                let isWordBoundaryStart = range.lowerBound == text.startIndex ||
                    !text[text.index(before: range.lowerBound)].isLetter
                let isWordBoundaryEnd = range.upperBound == text.endIndex ||
                    !text[range.upperBound].isLetter

                if isWordBoundaryStart && isWordBoundaryEnd {
                    matches.append(range)
                }
            } else {
                matches.append(range)
            }

            searchRange = range.upperBound..<text.endIndex
        }

        return matches
    }

    private func replaceAllMatches(in text: String, searchText: String, replaceText: String, options: NSString.CompareOptions) -> String {
        if searchOptions.wholeWord {
            var result = text
            let matches = findMatches(in: text, searchText: searchText, options: options)
            for range in matches.reversed() {
                result.replaceSubrange(range, with: replaceText)
            }
            return result
        } else {
            return text.replacingOccurrences(of: searchText, with: replaceText, options: options)
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
        .background(AppColors.barBackground)
    }
}

#Preview {
    EditorPanelView(
        showFindReplace: .constant(false),
        findSearchText: .constant(""),
        replaceText: .constant(""),
        searchScope: .constant(.currentFile),
        searchOptions: .constant(SearchOptions()),
        showReplaceField: .constant(false),
        matchCount: .constant(0),
        trailingPadding: 0
    )
    .environmentObject(AppCommands.shared)
}
