//
//  EditorView.swift
//  Loreweave
//
//  에디터 뷰 - 줄번호 표시 포함, EditorTabManager와 연동
//

import SwiftUI
import AppKit

struct EditorView: View {
    @EnvironmentObject var appCommands: AppCommands
    @State private var tabManager = EditorTabManager.shared
    @State private var text: String = ""
    @State private var fontSize: CGFloat = 16
    @State private var lineSpacingOption: LineSpacingOption = .normal
    @State private var textAlignment: TextAlignmentOption = .left
    @State private var cursorLine: Int = 1
    /// 현재 요청된 서식 토글 액션
    @State private var pendingFormatAction: MarkdownFormatType?
    @State private var selectedLineRange: ClosedRange<Int>?
    @State private var currentFileURL: URL?
    @State private var isLoading: Bool = false
    /// 원본 파일 내용 (저장 시점 기준)
    @State private var originalContent: String = ""

    /// 현재 선택된 탭의 파일이 존재하는지 확인
    private var currentFileExists: Bool {
        tabManager.selectedTab?.fileExists ?? true
    }

    // 찾기/바꾸기 상태 (MainEditorView에서 전달)
    @Binding var showFindReplace: Bool
    @Binding var findSearchText: String
    @Binding var replaceText: String
    @Binding var searchScope: SearchScope
    @Binding var searchOptions: SearchOptions
    @Binding var showReplaceField: Bool
    @Binding var matchCount: Int

    init(
        showFindReplace: Binding<Bool> = .constant(false),
        findSearchText: Binding<String> = .constant(""),
        replaceText: Binding<String> = .constant(""),
        searchScope: Binding<SearchScope> = .constant(.currentFile),
        searchOptions: Binding<SearchOptions> = .constant(SearchOptions()),
        showReplaceField: Binding<Bool> = .constant(false),
        matchCount: Binding<Int> = .constant(0)
    ) {
        self._showFindReplace = showFindReplace
        self._findSearchText = findSearchText
        self._replaceText = replaceText
        self._searchScope = searchScope
        self._searchOptions = searchOptions
        self._showReplaceField = showReplaceField
        self._matchCount = matchCount
    }

    var body: some View {
        VStack(spacing: 0) {
            if tabManager.isEmpty {
                // 탭이 없을 때 빈 상태 표시
                emptyStateView
            } else {
                EditorToolbar(
                    fontSize: $fontSize,
                    lineSpacingOption: $lineSpacingOption,
                    textAlignment: $textAlignment,
                    onFormatAction: { formatType in
                        pendingFormatAction = formatType
                    }
                )

                Divider()

                // 통합 에디터 (줄번호 + 텍스트 에디터)
                LineNumberedTextEditorRepresentable(
                    text: $text,
                    fontSize: fontSize,
                    lineSpacing: lineSpacingOption.rawValue,
                    textAlignment: textAlignment.nsTextAlignment,
                    isEditable: currentFileExists,
                    cursorLine: $cursorLine,
                    selectedLineRange: $selectedLineRange,
                    formatAction: pendingFormatAction,
                    onFormatApplied: { pendingFormatAction = nil }
                )
                .background(AppColors.textEditorBackground)

                EditorStatusBar(
                    wordCount: wordCount,
                    characterCount: text.count,
                    lineCount: lineCount,
                    selectedLineRange: selectedLineRange
                )
            }
        }
        .onChange(of: tabManager.selectedTab?.url) { oldURL, newURL in
            // 이전 탭의 내용을 캐시에 저장
            if let oldURL = oldURL {
                tabManager.setCachedContent(text, for: oldURL)
            }
            loadFileContent(from: newURL)
        }
        .onChange(of: text) { oldValue, newValue in
            // 파일 로드 직후가 아닌, 실제 사용자 편집인 경우에만 수정 상태로 표시
            guard oldValue != newValue,
                  currentFileURL != nil,
                  !isLoading else { return }
            // 원본과 비교하여 실제로 변경된 경우에만 수정 표시
            let isModified = newValue != originalContent
            tabManager.setModified(isModified, at: tabManager.selectedTabIndex)
            // 수정된 내용을 캐시에 저장
            tabManager.setCachedContent(newValue, for: currentFileURL!)
        }
        .onAppear {
            loadFileContent(from: tabManager.selectedTab?.url)
        }
        // 저장 커맨드 핸들링
        .onReceive(appCommands.$saveRequested) { requested in
            if requested {
                handleSave()
                appCommands.saveRequested = false
            }
        }
        // 찾기/바꾸기 커맨드 핸들링
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

        // 이미 로드된 파일이면 스킵
        guard url != currentFileURL else { return }

        currentFileURL = url
        isLoading = true

        // 파일에서 원본 내용 읽기
        let fileContent: String
        do {
            fileContent = try String(contentsOf: url, encoding: .utf8)
        } catch {
            print("Failed to load file: \(error)")
            fileContent = ""
        }
        originalContent = fileContent

        // 캐시에서 먼저 확인 (수정된 내용이 있을 수 있음)
        if let cachedContent = tabManager.getCachedContent(for: url) {
            text = cachedContent
        } else {
            // 캐시에 없으면 원본 사용
            text = fileContent
            // 초기 내용을 캐시에 저장
            tabManager.setCachedContent(fileContent, for: url)
        }

        isLoading = false
    }

    // MARK: - Save

    /// 현재 파일 저장
    private func handleSave() {
        guard let url = currentFileURL else { return }

        if tabManager.saveCurrentTab(content: text) {
            // 저장 성공 시 원본 및 캐시 업데이트
            originalContent = text
            tabManager.setCachedContent(text, for: url)
            print("File saved: \(url.lastPathComponent)")
        }
    }

    private var wordCount: Int {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count
    }

    private var lineCount: Int {
        text.isEmpty ? 1 : text.components(separatedBy: .newlines).count
    }

    // MARK: - Find/Replace Functions

    /// 찾기 토글
    func toggleFindReplace(showReplace: Bool = false) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if showFindReplace && showReplaceField == showReplace {
                // 이미 열려있고 같은 모드면 닫기
                showFindReplace = false
            } else {
                showFindReplace = true
                showReplaceField = showReplace
            }
        }
    }

    /// 찾기 수행
    func performFind() {
        guard !findSearchText.isEmpty else {
            matchCount = 0
            return
        }

        let options = buildSearchOptions()

        switch searchScope {
        case .currentFile:
            // 현재 파일에서 검색
            let matches = findMatches(in: text, searchText: findSearchText, options: options)
            matchCount = matches.count

        case .openTabs:
            // 열린 모든 탭에서 검색
            var totalMatches = 0
            for tab in tabManager.tabs {
                if let content = loadFileContentSync(from: tab.url) {
                    let matches = findMatches(in: content, searchText: findSearchText, options: options)
                    totalMatches += matches.count
                }
            }
            matchCount = totalMatches

        case .project:
            // 프로젝트 전체에서 검색 (현재는 열린 탭으로 제한)
            // TODO: FileSystemManager를 통해 프로젝트 전체 파일 검색 구현
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

    /// 파일 내용 동기 로드 (검색용)
    private func loadFileContentSync(from url: URL) -> String? {
        // 현재 열린 파일이면 현재 텍스트 반환
        if url == currentFileURL {
            return text
        }
        // 다른 파일은 디스크에서 읽기
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// 다음 찾기
    func findNext() {
        performFind()
        // TODO: NSTextView에서 다음 일치 항목으로 이동 구현
    }

    /// 이전 찾기
    func findPrevious() {
        performFind()
        // TODO: NSTextView에서 이전 일치 항목으로 이동 구현
    }

    /// 하나 바꾸기
    func replaceOne() {
        guard !findSearchText.isEmpty, matchCount > 0 else { return }
        // TODO: 현재 선택된 일치 항목 바꾸기 구현
    }

    /// 모두 바꾸기
    func replaceAll() {
        guard !findSearchText.isEmpty, matchCount > 0 else { return }

        let searchOptions = buildSearchOptions()
        text = replaceAllMatches(in: text, searchText: findSearchText, replaceText: replaceText, options: searchOptions)
        performFind()
    }

    /// 검색 옵션 생성
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

    /// 일치 항목 찾기
    private func findMatches(in text: String, searchText: String, options: NSString.CompareOptions) -> [Range<String.Index>] {
        var matches: [Range<String.Index>] = []
        var searchRange = text.startIndex..<text.endIndex

        while let range = text.range(of: searchText, options: options, range: searchRange) {
            // 전체 단어 일치 확인
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

    /// 모든 일치 항목 바꾸기
    private func replaceAllMatches(in text: String, searchText: String, replaceText: String, options: NSString.CompareOptions) -> String {
        if searchOptions.wholeWord {
            // 전체 단어 일치 시 수동 처리
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
}

// MARK: - Line Number Ruler View (NSRulerView 기반 - 스크롤 자동 동기화)

/// NSRulerView를 상속하여 스크롤과 자동 동기화되는 줄번호 뷰
final class LineNumberRulerView: NSRulerView {
    var fontSize: CGFloat = 16 {
        didSet { needsDisplay = true }
    }
    var lineSpacing: CGFloat = 8 {
        didSet { needsDisplay = true }
    }
    var currentLine: Int = 1 {
        didSet { needsDisplay = true }
    }

    private let horizontalPadding: CGFloat = 8

    init(textView: NSTextView) {
        super.init(scrollView: textView.enclosingScrollView!, orientation: .verticalRuler)
        self.clientView = textView
        self.ruleThickness = 50
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = clientView as? NSTextView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        // 배경색
        NSColor.controlBackgroundColor.withAlphaComponent(0.5).setFill()
        rect.fill()

        let text = textView.string as NSString
        let textContainerInset = textView.textContainerInset

        // 보이는 영역 계산
        let visibleRect = scrollView?.documentVisibleRect ?? rect

        // 폰트 설정
        let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize - 2, weight: .regular)
        // 줄번호 색상 (시스템 색상 사용)
        let normalAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColorTheme.lineNumber
        ]
        let currentLineAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColorTheme.lineNumberActive
        ]

        var lineNumber = 1
        var glyphIndex = 0
        let numberOfGlyphs = layoutManager.numberOfGlyphs

        while glyphIndex < numberOfGlyphs {
            let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
            let lineRange = text.lineRange(for: NSRange(location: charIndex, length: 0))

            // 줄의 첫 번째 글리프 위치에서 라인 프래그먼트 정보 가져오기
            var effectiveRange = NSRange()
            let firstFragmentRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &effectiveRange)

            // 줄의 마지막 글리프 인덱스 계산
            let lineEndCharIndex = lineRange.location + lineRange.length
            let lineEndGlyphIndex = lineEndCharIndex < text.length
                ? layoutManager.glyphIndexForCharacter(at: lineEndCharIndex)
                : numberOfGlyphs

            // 전체 줄의 높이 계산 (여러 시각적 줄 포함)
            var lineHeight: CGFloat = firstFragmentRect.height
            var currentGlyph = effectiveRange.upperBound
            while currentGlyph < lineEndGlyphIndex && currentGlyph < numberOfGlyphs {
                var nextEffectiveRange = NSRange()
                let fragmentRect = layoutManager.lineFragmentRect(forGlyphAt: currentGlyph, effectiveRange: &nextEffectiveRange)
                lineHeight = fragmentRect.maxY - firstFragmentRect.origin.y
                currentGlyph = nextEffectiveRange.upperBound
            }

            // 실제 Y 위치 (textContainerInset 적용)
            let yPosition = firstFragmentRect.origin.y + textContainerInset.height

            // 줄 영역이 보이는 영역과 겹치는지 확인
            let lineRect = NSRect(x: 0, y: yPosition, width: ruleThickness, height: lineHeight)
            if lineRect.intersects(visibleRect) {
                let lineNumberString = "\(lineNumber)"
                let attributes = lineNumber == currentLine ? currentLineAttributes : normalAttributes

                // 현재 줄 하이라이트 배경
                if lineNumber == currentLine {
                    NSColor.controlAccentColor.withAlphaComponent(0.1).setFill()
                    lineRect.fill()
                }

                // 줄번호 텍스트 그리기
                let attributedString = NSAttributedString(string: lineNumberString, attributes: attributes)
                let stringSize = attributedString.size()

                // 줄번호를 첫 번째 시각적 줄의 중앙에 배치
                let firstLineHeight = firstFragmentRect.height
                let drawPoint = NSPoint(
                    x: ruleThickness - horizontalPadding - stringSize.width,
                    y: yPosition + (firstLineHeight - stringSize.height) / 2
                )
                attributedString.draw(at: drawPoint)
            }

            // 다음 줄로 이동
            lineNumber += 1
            glyphIndex = lineEndGlyphIndex
        }

        // 빈 파일인 경우 줄번호 1 표시
        if numberOfGlyphs == 0 {
            let lineNumberString = "1"
            let attributes = currentLine == 1 ? currentLineAttributes : normalAttributes
            let lineHeight = fontSize + lineSpacing

            if currentLine == 1 {
                NSColor.controlAccentColor.withAlphaComponent(0.1).setFill()
                let highlightRect = NSRect(x: 0, y: textContainerInset.height, width: ruleThickness, height: lineHeight)
                highlightRect.fill()
            }

            let attributedString = NSAttributedString(string: lineNumberString, attributes: attributes)
            let stringSize = attributedString.size()
            let drawPoint = NSPoint(
                x: ruleThickness - horizontalPadding - stringSize.width,
                y: textContainerInset.height + (lineHeight - stringSize.height) / 2
            )
            attributedString.draw(at: drawPoint)
        }

        // 구분선 그리기 (보이는 영역에만 그림)
        NSColor.separatorColor.setStroke()
        let linePath = NSBezierPath()
        linePath.move(to: NSPoint(x: ruleThickness - 0.5, y: rect.minY))
        linePath.line(to: NSPoint(x: ruleThickness - 0.5, y: rect.maxY))
        linePath.lineWidth = 0.5
        linePath.stroke()
    }
}

// MARK: - NSTextView Representable with Integrated Line Numbers

struct LineNumberedTextEditorRepresentable: NSViewRepresentable {
    @Binding var text: String
    let fontSize: CGFloat
    let lineSpacing: CGFloat
    let textAlignment: NSTextAlignment
    let isEditable: Bool
    @Binding var cursorLine: Int
    @Binding var selectedLineRange: ClosedRange<Int>?
    /// 서식 토글 요청 (format type)
    var formatAction: MarkdownFormatType?
    /// 서식 적용 후 콜백
    var onFormatApplied: (() -> Void)?

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView

        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 16, height: 8)
        textView.isEditable = isEditable

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        // textContainer 설정
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false

        // 줄번호 Ruler 설정
        let rulerView = LineNumberRulerView(textView: textView)
        rulerView.fontSize = fontSize
        rulerView.lineSpacing = lineSpacing
        scrollView.verticalRulerView = rulerView
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true

        // NSTextView 참조 저장
        context.coordinator.textView = textView
        context.coordinator.rulerView = rulerView

        updateTextView(textView, forceUpdate: true)

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView,
              let rulerView = context.coordinator.rulerView else { return }

        // 서식 토글 액션 처리
        if let formatType = formatAction {
            applyFormatToggle(textView: textView, formatType: formatType)
            DispatchQueue.main.async {
                onFormatApplied?()
            }
            rulerView.needsDisplay = true
            return
        }

        // 한글 조합 중이면 업데이트 스킵 (조합 중 텍스트 손실 방지)
        guard !textView.hasMarkedText() else {
            textView.isEditable = isEditable
            return
        }

        // 줄번호 뷰 설정 업데이트
        rulerView.fontSize = fontSize
        rulerView.lineSpacing = lineSpacing
        rulerView.currentLine = cursorLine

        // 텍스트 변경 시에만 업데이트
        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            context.coordinator.isUpdatingFromBinding = true
            textView.string = text
            updateTextView(textView, forceUpdate: true)
            textView.selectedRanges = selectedRanges
            context.coordinator.isUpdatingFromBinding = false
        } else {
            // 스타일만 업데이트
            updateTextView(textView, forceUpdate: false)
        }

        // 파일 존재 여부에 따라 편집 가능 상태 업데이트
        textView.isEditable = isEditable

        // 줄번호 뷰 갱신
        rulerView.needsDisplay = true
    }

    private func updateTextView(_ textView: NSTextView, forceUpdate: Bool) {
        guard !text.isEmpty else { return }

        let selectedRanges = textView.selectedRanges

        // 마크다운 서식이 적용된 AttributedString 생성
        let attributedString = MarkdownFormatter.attributedString(
            from: text,
            fontSize: fontSize,
            lineSpacing: lineSpacing,
            alignment: textAlignment
        )

        // textStorage 업데이트
        textView.textStorage?.setAttributedString(attributedString)

        // 선택 범위 복원
        textView.selectedRanges = selectedRanges

        // 기본 타이핑 속성 설정
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = lineSpacing
        paragraphStyle.alignment = textAlignment

        textView.typingAttributes = [
            .font: NSFont.systemFont(ofSize: fontSize),
            .paragraphStyle: paragraphStyle,
            .foregroundColor: NSColorTheme.editorText
        ]
    }

    private func applyFormatToggle(textView: NSTextView, formatType: MarkdownFormatType) {
        let selectedRange = textView.selectedRange()
        guard selectedRange.length > 0 else { return }

        let (newText, newRange) = MarkdownFormatter.toggleFormat(
            formatType,
            in: textView.string,
            selectedRange: selectedRange
        )

        // 텍스트 업데이트
        textView.string = newText

        // 바인딩 업데이트
        DispatchQueue.main.async {
            self.text = newText
        }

        // 마크다운 서식 재적용
        updateTextView(textView, forceUpdate: true)

        // 새 선택 범위 설정
        textView.setSelectedRange(newRange)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: LineNumberedTextEditorRepresentable
        weak var textView: NSTextView?
        weak var rulerView: LineNumberRulerView?
        var isUpdatingFromBinding = false

        init(_ parent: LineNumberedTextEditorRepresentable) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView,
                  !isUpdatingFromBinding else { return }

            let newText = textView.string
            parent.text = newText
            updateCursorLine(textView)

            // 줄번호 뷰 즉시 업데이트
            rulerView?.needsDisplay = true

            // 텍스트 변경 후 마크다운 서식 재적용 (debounce)
            // 한글 조합 중이 아닐 때만 적용
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self = self,
                      let tv = self.textView,
                      tv.string == newText,
                      !tv.hasMarkedText() else { return }  // 조합 중이면 스킵
                self.reapplyMarkdownFormatting(textView: tv)
            }
        }

        private func reapplyMarkdownFormatting(textView: NSTextView) {
            // 한글 조합 중이면 스킵 (조합 중 setAttributedString 호출 시 문자 손실)
            guard !textView.string.isEmpty,
                  !textView.hasMarkedText() else { return }

            let selectedRanges = textView.selectedRanges

            let attributedString = MarkdownFormatter.attributedString(
                from: textView.string,
                fontSize: parent.fontSize,
                lineSpacing: parent.lineSpacing,
                alignment: parent.textAlignment
            )

            isUpdatingFromBinding = true
            textView.textStorage?.setAttributedString(attributedString)
            textView.selectedRanges = selectedRanges
            isUpdatingFromBinding = false

            // 서식 적용 후 줄번호 갱신
            rulerView?.needsDisplay = true
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            updateCursorLine(textView)
            updateSelectedLineRange(textView)
            rulerView?.needsDisplay = true
        }

        private func updateCursorLine(_ textView: NSTextView) {
            let cursorPosition = textView.selectedRange().location
            let textBeforeCursor = (textView.string as NSString).substring(to: min(cursorPosition, textView.string.count))
            let lineNumber = textBeforeCursor.components(separatedBy: .newlines).count
            let newCursorLine = max(1, lineNumber)
            DispatchQueue.main.async {
                self.parent.cursorLine = newCursorLine
            }
        }

        private func updateSelectedLineRange(_ textView: NSTextView) {
            let selectedRange = textView.selectedRange()
            guard selectedRange.length > 0 else {
                DispatchQueue.main.async {
                    self.parent.selectedLineRange = nil
                }
                return
            }

            let text = textView.string as NSString
            let startLine = text.substring(to: selectedRange.location).components(separatedBy: .newlines).count
            let endLocation = min(selectedRange.location + selectedRange.length, text.length)
            let endLine = text.substring(to: endLocation).components(separatedBy: .newlines).count
            let newRange = startLine...endLine

            DispatchQueue.main.async {
                self.parent.selectedLineRange = newRange
            }
        }
    }
}

// MARK: - Text Alignment Option

/// 텍스트 정렬 옵션
enum TextAlignmentOption: CaseIterable, Identifiable {
    case left
    case center
    case right
    case justified

    var id: Self { self }

    var icon: String {
        switch self {
        case .left: return "text.alignleft"
        case .center: return "text.aligncenter"
        case .right: return "text.alignright"
        case .justified: return "text.justify"
        }
    }

    var nsTextAlignment: NSTextAlignment {
        switch self {
        case .left: return .left
        case .center: return .center
        case .right: return .right
        case .justified: return .justified
        }
    }

    var tooltip: String {
        switch self {
        case .left: return L10n.editor.alignLeft
        case .center: return L10n.editor.alignCenter
        case .right: return L10n.editor.alignRight
        case .justified: return L10n.editor.alignJustified
        }
    }
}

// MARK: - Line Spacing Option

/// 줄 간격 옵션
enum LineSpacingOption: CGFloat, CaseIterable, Identifiable {
    case compact = 4      // 80%
    case normal = 8       // 100%
    case relaxed = 12     // 125%
    case loose = 16       // 150%
    case extraLoose = 20  // 200%

    var id: CGFloat { rawValue }

    var displayName: String {
        switch self {
        case .compact: return "80%"
        case .normal: return "100%"
        case .relaxed: return "125%"
        case .loose: return "150%"
        case .extraLoose: return "200%"
        }
    }
}

// MARK: - Font Size Input Field

/// 폰트 크기 입력 필드 (엔터로 확정)
struct FontSizeInputField: View {
    @Binding var fontSize: CGFloat
    @State private var inputText: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            TextField("", text: $inputText)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .frame(width: 24)
                .multilineTextAlignment(.trailing)
                .focused($isFocused)
                .onSubmit {
                    applyFontSize()
                }
                .onChange(of: isFocused) { _, focused in
                    if focused {
                        // 포커스 시 현재 값으로 초기화
                        inputText = "\(Int(fontSize))"
                    } else {
                        // 포커스 해제 시 원래 값으로 복원
                        inputText = "\(Int(fontSize))"
                    }
                }

            Text("pt")
                .font(.system(size: 11))
                .foregroundStyle(AppColors.textSecondary)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isFocused ? AppColors.controlBackground : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(isFocused ? AppColors.accent : Color.clear, lineWidth: 1)
        )
        .onAppear {
            inputText = "\(Int(fontSize))"
        }
        .onChange(of: fontSize) { _, newValue in
            // 외부에서 fontSize가 변경되면 (슬라이더 등) 입력 텍스트도 업데이트
            if !isFocused {
                inputText = "\(Int(newValue))"
            }
        }
    }

    private func applyFontSize() {
        if let value = Int(inputText), value >= 8, value <= 72 {
            fontSize = CGFloat(value)
        }
        // 입력값이 범위를 벗어나거나 유효하지 않으면 현재 fontSize로 복원
        inputText = "\(Int(fontSize))"
        isFocused = false
    }
}

// MARK: - Editor Toolbar

struct EditorToolbar: View {
    @Binding var fontSize: CGFloat
    @Binding var lineSpacingOption: LineSpacingOption
    @Binding var textAlignment: TextAlignmentOption
    var onFormatAction: ((MarkdownFormatType) -> Void)?

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 4) {
                ToolbarButton(icon: "bold", tooltip: L10n.editor.bold, action: { onFormatAction?(.bold) })
                ToolbarButton(icon: "italic", tooltip: L10n.editor.italic, action: { onFormatAction?(.italic) })
                ToolbarButton(icon: "underline", tooltip: L10n.editor.underline, action: { onFormatAction?(.underline) })
                ToolbarButton(icon: "strikethrough", tooltip: L10n.editor.strikethrough, action: { onFormatAction?(.strikethrough) })
            }

            // 텍스트 정렬 버튼
            HStack(spacing: 2) {
                ForEach(TextAlignmentOption.allCases) { alignment in
                    ToolbarToggleButton(
                        icon: alignment.icon,
                        tooltip: alignment.tooltip,
                        isSelected: textAlignment == alignment,
                        action: { textAlignment = alignment }
                    )
                }
            }

            // 폰트 크기 슬라이더 및 입력 필드
            HStack(spacing: 4) {
                Image(systemName: "textformat.size")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.toolbarIcon)

                Slider(value: $fontSize, in: 12...24, step: 1)
                    .frame(width: 80)

                FontSizeInputField(fontSize: $fontSize)
            }
            .help(L10n.editor.fontSize)

            // 줄 간격 드롭다운
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.and.down.text.horizontal")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.toolbarIcon)

                Picker("", selection: $lineSpacingOption) {
                    ForEach(LineSpacingOption.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 70)
            }
            .help(L10n.editor.lineSpacing)

            Spacer()

            Menu {
                Button(L10n.ai.refineText, action: {})
                Button(L10n.ai.styleConvert, action: {})
                Button(L10n.ai.continueWritingAction, action: {})
                Divider()
                Button(L10n.ai.consistencyCheck, action: {})
            } label: {
                Label(L10n.ai.tools, systemImage: "wand.and.stars")
                    .font(.system(size: 12))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(AppColors.barBackground)
    }
}

struct ToolbarButton: View {
    let icon: String
    let tooltip: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(AppColors.toolbarIcon)
                .frame(width: 28, height: 24)
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }
}

struct ToolbarToggleButton: View {
    let icon: String
    let tooltip: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(isSelected ? AppColors.toolbarIconActive : AppColors.toolbarIcon)
                .frame(width: 28, height: 24)
                .background(isSelected ? AppColors.toolbarToggleSelected : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }
}

// MARK: - Editor Status Bar

struct EditorStatusBar: View {
    let wordCount: Int
    let characterCount: Int
    let lineCount: Int
    let selectedLineRange: ClosedRange<Int>?

    var body: some View {
        HStack {
            Text(L10n.get("editor.lines") + " \(lineCount)")
            Text("•")
                .foregroundStyle(AppColors.textTertiary)
            Text("\(wordCount) \(L10n.editor.words)")
            Text("•")
                .foregroundStyle(AppColors.textTertiary)
            Text("\(characterCount) \(L10n.editor.characters)")

            if let range = selectedLineRange {
                Text("•")
                    .foregroundStyle(.quaternary)
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
                .foregroundStyle(AppColors.textSecondary)
        }
        .font(.system(size: 11))
        .foregroundStyle(AppColors.textSecondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(AppColors.barBackground)
    }
}

#Preview {
    EditorView()
        .environmentObject(AppCommands.shared)
}
