//
//  TextlinkTextView.swift
//  TextlinkEditor
//
//  커스텀 텍스트 에디터 뷰
//  Core Text 기반 행별 렌더링
//

import AppKit

// MARK: - Lore Text View

/// 커스텀 텍스트 에디터 뷰
/// 모든 행을 직접 렌더링 (스크롤은 부모가 담당)
final class TextlinkTextView: NSView {
    // MARK: - Properties

    /// 에디터 상태
    var editorState: EditorState {
        didSet {
            syncFromState()
            needsDisplay = true
        }
    }

    /// 행 렌더러
    private let lineRenderer: LineRenderer

    /// 텍스트 영역 좌측 패딩
    private let textLeftPadding: CGFloat = 8

    /// 커서 깜빡임 타이머
    private var cursorBlinkTimer: Timer?

    /// 커서 표시 여부 (깜빡임용)
    private var showCursor: Bool = true

    /// 입력 컨텍스트 (IME 지원)
    private lazy var _inputContext: NSTextInputContext = {
        NSTextInputContext(client: self)
    }()

    /// NSView의 inputContext 오버라이드 - NSTextInputClient 동작에 필수
    override var inputContext: NSTextInputContext? {
        _inputContext
    }

    /// 마킹 텍스트 (IME 조합 중)
    private var _markedText: NSAttributedString?
    private var markedSelection = NSRange(location: 0, length: 0)

    /// 마킹 범위
    private var _markedRange: NSRange = NSRange(location: NSNotFound, length: 0)

    /// 선택 범위 (NSTextInputClient용)
    private var _selectedRange: NSRange = NSRange(location: 0, length: 0)

    // MARK: - Cursor Position Cache (Word Wrap 최적화)

    /// 커서가 있는 행의 시작 Y 좌표 (캐시)
    private var _cachedCursorLineY: CGFloat = 0

    /// 커서가 있는 래핑된 줄의 인덱스 (캐시)
    private var _cachedWrappedLineIndex: Int = 0

    /// 커서가 있는 래핑된 줄 내에서의 X 좌표 (캐시)
    private var _cachedCursorXInLine: CGFloat = 0

    /// 커서가 있는 행의 전체 높이 (캐시)
    private var _cachedCursorLineHeight: CGFloat = 0

    /// 캐시가 유효한지 확인하기 위한 키 (커서 위치 + 뷰포트 너비)
    private var _cursorCacheKey: String = ""

    // MARK: - Callbacks

    /// 텍스트 변경 콜백
    var onTextChange: ((String) -> Void)?

    /// 커서 위치 변경 콜백
    var onCursorChange: ((Int, ClosedRange<Int>?) -> Void)?

    /// 문서 구조 변경 콜백 (행 추가/삭제 시)
    var onDocumentStructureChange: (() -> Void)?

    /// 커서 이동 시 스크롤 요청 콜백 (줄 번호)
    var onScrollToCursor: ((Int) -> Void)?

    /// IME 조합 중 스크롤 시 commitMarkedText 호출 방지 플래그
    private(set) var isScrollingForIME: Bool = false

    /// IME 스크롤 플래그 클리어 (스크롤 완료 후 호출)
    func clearScrollingForIMEFlag() {
        isScrollingForIME = false
    }

    // MARK: - Initialization

    init(editorState: EditorState) {
        self.editorState = editorState
        self.lineRenderer = LineRenderer(font: editorState.configuration.font)

        super.init(frame: .zero)

        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = AppColors.nsTextEditorBackground.cgColor

        syncFromState()
        startCursorBlink()
    }

    deinit {
        layoutTask?.cancel()
        stopCursorBlink()
    }

    // MARK: - State Sync

    func syncFromState() {
        editorState.selection.clampToDocument(editorState.document)
        updateSelectedRange()
        lineRenderer.font = editorState.configuration.font
        lineRenderer.lineHeightMultiple = editorState.configuration.lineHeightMultiple
        lineRenderer.textColor = AppColors.nsEditorText
        lineRenderer.wordWrapEnabled = editorState.configuration.wordWrap
        lineRenderer.letterSpacing = editorState.configuration.letterSpacing
    }

    /// 기본 행 높이 반환
    var lineHeight: CGFloat {
        lineRenderer.lineHeight
    }

    /// 기준선 오프셋 반환
    var baselineOffset: CGFloat {
        lineRenderer.baselineOffset
    }

    /// Word Wrap 활성화 여부
    var wordWrapEnabled: Bool {
        get { lineRenderer.wordWrapEnabled }
        set {
            lineRenderer.wordWrapEnabled = newValue
            needsDisplay = true
        }
    }

    private struct LayoutChunk {
        var version: Int
        var origins: [CGFloat]
    }
    private var layoutVersion = -1
    private var heightStyleKey = ""
    private var layoutChunks: [LayoutChunk] = []
    private var chunkOrigins: [CGFloat] = [0]
    private struct LayoutSnapshot {
        let version: Int
        let chunks: [LayoutChunk]
        let origins: [CGFloat]
    }
    private var recentLayouts: [String: LayoutSnapshot] = [:]
    private var recentLayoutKeys: [String] = []
    private var measurementStyle = ""
    private var layoutWidth: CGFloat = 0
    private(set) var layoutMeasurementCount = 0
    private(set) var isLayoutPreparing = false
    var onLayoutReady: (() -> Void)?
    private var layoutTask: Task<Void, Never>?
    private var pendingLayoutKey: String?

    private func prepareLargeLayout(style: String, width: CGFloat) {
        layoutTask?.cancel()
        pendingLayoutKey = style
        isLayoutPreparing = true
        let document = editorState.document
        let version = document.version
        let font = lineRenderer.font
        let spacing = lineRenderer.letterSpacing
        let height = lineRenderer.lineHeight
        layoutTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
            let lines = document.lines.map(\.content)
            let versions = document.chunkVersions
            let worker = Task.detached(priority: .userInitiated) { () -> [[CGFloat]]? in
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineBreakMode = .byWordWrapping
                let attributes: [NSAttributedString.Key: Any] = [.font: font, .kern: spacing, .paragraphStyle: paragraph]
                var result: [[CGFloat]] = []
                for start in stride(from: 0, to: lines.count, by: TextDocument.chunkSize) {
                    if Task.isCancelled { return nil }
                    var offsets: [CGFloat] = [0]
                    for text in lines[start..<min(lines.count, start + TextDocument.chunkSize)] {
                        let attributed = NSAttributedString(string: text, attributes: attributes)
                        let typesetter = CTTypesetterCreateWithAttributedString(attributed)
                        var position = 0
                        var rows = 0
                        while position < attributed.length {
                            if Task.isCancelled { return nil }
                            let length = CTTypesetterSuggestLineBreak(typesetter, position, Double(width))
                            guard length > 0 else { break }
                            position += length
                            rows += 1
                        }
                        offsets.append(offsets.last! + CGFloat(max(1, rows)) * height)
                    }
                    result.append(offsets)
                }
                return result
            }
            let result = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            guard !Task.isCancelled, let self, let result,
                  self.pendingLayoutKey == style, self.heightStyleKey == style,
                  self.editorState.document === document, document.version == version else { return }
            self.layoutChunks = result.enumerated().map { LayoutChunk(version: versions[$0.offset], origins: $0.element) }
            self.chunkOrigins = [0]
            for offsets in result { self.chunkOrigins.append(self.chunkOrigins.last! + offsets.last!) }
            self.layoutVersion = version
            self.pendingLayoutKey = nil
            self.isLayoutPreparing = false
            self.onLayoutReady?()
        }
    }

    // Exact heights are retained separately from the bounded Core Text drawing cache.
    // A scroll never scans the document; edits remeasure only invalidated 256-line chunks.
    private func ensureLineOrigins(viewportWidth: CGFloat) {
        let document = editorState.document
        let config = editorState.configuration
        let style = "\(ObjectIdentifier(document)):\(viewportWidth):\(config.fontName):\(config.fontSize):\(config.lineHeightMultiple):\(config.letterSpacing):\(wordWrapEnabled)"
        let metrics = "\(ObjectIdentifier(document)):\(config.fontName):\(config.fontSize):\(config.lineHeightMultiple):\(config.letterSpacing):\(wordWrapEnabled)"
        var wideningChunks: [LayoutChunk]?
        if style != heightStyleKey {
            if !isLayoutPreparing, metrics == measurementStyle, viewportWidth >= layoutWidth,
               layoutVersion == document.version {
                wideningChunks = layoutChunks
            }
            if !heightStyleKey.isEmpty && !isLayoutPreparing {
                recentLayouts[heightStyleKey] = LayoutSnapshot(version: layoutVersion, chunks: layoutChunks, origins: chunkOrigins)
                recentLayoutKeys.removeAll { $0 == heightStyleKey }
                recentLayoutKeys.append(heightStyleKey)
                while recentLayoutKeys.count > 8 {
                    recentLayouts.removeValue(forKey: recentLayoutKeys.removeFirst())
                }
            }
            if let saved = recentLayouts[style] {
                layoutChunks = saved.chunks
                chunkOrigins = saved.origins
                layoutVersion = saved.version
            } else {
                layoutChunks.removeAll()
                layoutVersion = -1
            }
            heightStyleKey = style
            measurementStyle = metrics
            layoutWidth = viewportWidth
        }
        if pendingLayoutKey != nil && (pendingLayoutKey != style || layoutVersion != document.version) {
            layoutTask?.cancel()
            if pendingLayoutKey == style {
                layoutChunks.removeAll()
                layoutVersion = -1
            }
            pendingLayoutKey = nil
            isLayoutPreparing = false
        }
        guard layoutVersion != document.version else { return }
        let canReuseWidening = wideningChunks?.allSatisfy {
            $0.origins.last == CGFloat($0.origins.count - 1) * lineRenderer.lineHeight
        } ?? false
        if document.lineCount >= 5000 && layoutChunks.isEmpty && viewportWidth > 0 && !canReuseWidening {
            // Geometry is provisional only while the editor is covered by a progress view.
            // Publish exact heights in one step; never mix stale background results with edits.
            prepareLargeLayout(style: style, width: viewportWidth)
            chunkOrigins = [0]
            for start in stride(from: 0, to: document.lineCount, by: TextDocument.chunkSize) {
                let count = min(TextDocument.chunkSize, document.lineCount - start)
                let offsets = (0...count).map { CGFloat($0) * lineRenderer.lineHeight }
                layoutChunks.append(LayoutChunk(version: document.chunkVersions[start / TextDocument.chunkSize], origins: offsets))
                chunkOrigins.append(chunkOrigins.last! + offsets.last!)
            }
            layoutVersion = document.version
            return
        }
        let count = (document.lineCount + TextDocument.chunkSize - 1) / TextDocument.chunkSize
        if layoutChunks.count > count { layoutChunks.removeLast(layoutChunks.count - count) }
        chunkOrigins = [0]
        for chunk in 0..<count {
            let version = document.chunkVersions.indices.contains(chunk) ? document.chunkVersions[chunk] : document.version
            if chunk >= layoutChunks.count || layoutChunks[chunk].version != version {
                let start = chunk * TextDocument.chunkSize
                var origins: [CGFloat] = [0]
                for index in start..<min(document.lineCount, start + TextDocument.chunkSize) {
                    let local = index - start
                    let previous = wideningChunks.flatMap { chunks -> CGFloat? in
                        guard chunks.indices.contains(chunk), chunks[chunk].origins.indices.contains(local + 1) else { return nil }
                        return chunks[chunk].origins[local + 1] - chunks[chunk].origins[local]
                    }
                    // A line that fits the narrower width still fits a wider one exactly.
                    let height: CGFloat
                    if previous == lineRenderer.lineHeight {
                        height = lineRenderer.lineHeight
                    } else {
                        layoutMeasurementCount += 1
                        height = lineRenderer.calculateHeight(for: document.getLineObject(index)!, viewportWidth: viewportWidth)
                    }
                    origins.append(origins.last! + height)
                }
                let value = LayoutChunk(version: version, origins: origins)
                if chunk < layoutChunks.count { layoutChunks[chunk] = value } else { layoutChunks.append(value) }
            }
            chunkOrigins.append(chunkOrigins.last! + layoutChunks[chunk].origins.last!)
        }
        layoutVersion = document.version
    }

    func rowHeight(for lineIndex: Int, viewportWidth: CGFloat) -> CGFloat {
        ensureLineOrigins(viewportWidth: viewportWidth)
        let line = max(0, min(lineIndex, editorState.document.lineCount - 1))
        let origins = layoutChunks[line / TextDocument.chunkSize].origins
        let local = line % TextDocument.chunkSize
        return origins[local + 1] - origins[local]
    }

    func yPosition(for lineIndex: Int, viewportWidth: CGFloat) -> CGFloat {
        ensureLineOrigins(viewportWidth: viewportWidth)
        if lineIndex >= editorState.document.lineCount { return chunkOrigins.last ?? 0 }
        let line = max(0, lineIndex)
        return chunkOrigins[line / TextDocument.chunkSize] + layoutChunks[line / TextDocument.chunkSize].origins[line % TextDocument.chunkSize]
    }

    func lineIndex(atY y: CGFloat, viewportWidth: CGFloat) -> Int {
        ensureLineOrigins(viewportWidth: viewportWidth)
        func containing(_ origins: [CGFloat], _ offset: CGFloat) -> Int {
            var low = 0, high = origins.count - 1
            while low < high {
                let mid = (low + high + 1) / 2
                if origins[mid] <= offset { low = mid } else { high = mid - 1 }
            }
            return min(low, origins.count - 2)
        }
        let chunk = containing(chunkOrigins, max(0, y))
        let local = containing(layoutChunks[chunk].origins, max(0, y) - chunkOrigins[chunk])
        return chunk * TextDocument.chunkSize + local
    }

    func totalContentHeight(viewportWidth: CGFloat) -> CGFloat {
        ensureLineOrigins(viewportWidth: viewportWidth)
        return chunkOrigins.last ?? lineRenderer.lineHeight
    }

    var caretRect: CGRect {
        let cursor = editorState.selection.clampPosition(editorState.selection.cursor, in: editorState.document)
        let width = bounds.width - textLeftPadding
        return lineRenderer.caretRect(in: editorState.document.getLine(cursor.line) ?? "",
                                     column: cursor.column, viewportWidth: width)
            .offsetBy(dx: textLeftPadding, dy: yPosition(for: cursor.line, viewportWidth: width))
    }

    // MARK: - Coordinate System

    override var isFlipped: Bool { true }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // 배경
        context.setFillColor(AppColors.nsTextEditorBackground.cgColor)
        context.fill(bounds)

        let document = editorState.document
        let selection = editorState.selection
        let viewportWidth = bounds.width - textLeftPadding

        // Word Wrap 여부에 따라 렌더링 방식 결정
        if wordWrapEnabled && viewportWidth > 0 {
            drawWithDynamicHeight(dirtyRect: dirtyRect, context: context, document: document, selection: selection, viewportWidth: viewportWidth)
        } else {
            drawWithFixedHeight(dirtyRect: dirtyRect, context: context, document: document, selection: selection)
        }

        // 마킹 텍스트 렌더링은 renderLineWithMarkedText에서 처리됨
    }

    /// 고정 행 높이로 그리기 (Word Wrap 비활성화)
    private func drawWithFixedHeight(dirtyRect: NSRect, context: CGContext, document: TextDocument, selection: TextSelection) {
        let lineHeight = lineRenderer.lineHeight

        // dirtyRect 기반으로 렌더링할 행 범위 계산
        let startLine = max(0, Int(floor(dirtyRect.minY / lineHeight)))
        let endLine = min(document.lineCount - 1, Int(ceil(dirtyRect.maxY / lineHeight)))

        guard startLine <= endLine else { return }

        // 현재 줄 하이라이트
        if editorState.configuration.highlightCurrentLine && !selection.hasSelection {
            let currentLineIndex = selection.cursorLine
            if currentLineIndex >= startLine && currentLineIndex <= endLine {
                let y = CGFloat(currentLineIndex) * lineHeight
                lineRenderer.renderCurrentLineHighlight(
                    at: CGPoint(x: 0, y: y),
                    in: context,
                    viewportWidth: bounds.width
                )
            }
        }

        // 행별 렌더링
        for lineIndex in startLine...endLine {
            guard let line = document.getLineObject(lineIndex) else { continue }

            let y = CGFloat(lineIndex) * lineHeight
            let origin = CGPoint(x: textLeftPadding, y: y)

            // 선택 영역 렌더링
            if selection.hasSelection {
                lineRenderer.renderSelection(
                    line: line,
                    lineIndex: lineIndex,
                    selection: selection.range,
                    at: origin,
                    in: context,
                    viewportWidth: bounds.width - textLeftPadding
                )
            }

            // 텍스트 렌더링 (마킹 텍스트가 있는 행은 분리 렌더링)
            if lineIndex == selection.cursor.line,
               let marked = _markedText, marked.length > 0 {
                renderLineWithMarkedText(
                    line: line,
                    markedText: marked,
                    cursorColumn: selection.cursor.column,
                    at: origin,
                    in: context,
                    viewportWidth: bounds.width - textLeftPadding
                )
            } else {
                lineRenderer.render(
                    line: line,
                    at: origin,
                    in: context,
                    viewportWidth: bounds.width - textLeftPadding
                )
            }
        }

        // 커서 렌더링
        if editorState.isEditable && showCursor && !selection.hasSelection {
            let cursorLine = selection.cursor.line
            if cursorLine >= startLine && cursorLine <= endLine,
               let line = document.getLineObject(cursorLine) {
                let y = CGFloat(cursorLine) * lineHeight
                lineRenderer.renderCursor(
                    line: line,
                    column: selection.cursor.column,
                    at: CGPoint(x: textLeftPadding, y: y),
                    in: context
                )
            }
        }
    }

    /// 동적 행 높이로 그리기 (Word Wrap 활성화)
    private func drawWithDynamicHeight(dirtyRect: NSRect, context: CGContext, document: TextDocument, selection: TextSelection, viewportWidth: CGFloat) {
        let visible = dirtyRect.intersection(visibleRect)
        guard !visible.isEmpty else { return }
        let start = lineIndex(atY: visible.minY, viewportWidth: viewportWidth)
        let end = lineIndex(atY: visible.maxY, viewportWidth: viewportWidth)
        var y = yPosition(for: start, viewportWidth: viewportWidth)

        // 현재 줄 하이라이트
        let currentLineIndex = selection.cursorLine
        var currentLineY: CGFloat = 0
        var currentLineHeight: CGFloat = 0

        if editorState.configuration.highlightCurrentLine && !selection.hasSelection {
            if currentLineIndex >= start && currentLineIndex <= end {
                currentLineY = yPosition(for: currentLineIndex, viewportWidth: viewportWidth)
                currentLineHeight = rowHeight(for: currentLineIndex, viewportWidth: viewportWidth)
                lineRenderer.renderCurrentLineHighlight(
                    at: CGPoint(x: 0, y: currentLineY),
                    in: context,
                    viewportWidth: bounds.width,
                    height: currentLineHeight
                )
            }
        }

        // 행별 렌더링
        for lineIndex in start...end {
            guard let line = document.getLineObject(lineIndex) else { continue }

            let rowHeight = self.rowHeight(for: lineIndex, viewportWidth: viewportWidth)
            let origin = CGPoint(x: textLeftPadding, y: y)

            // 선택 영역 렌더링
            if selection.hasSelection {
                lineRenderer.renderSelection(
                    line: line,
                    lineIndex: lineIndex,
                    selection: selection.range,
                    at: origin,
                    in: context,
                    viewportWidth: viewportWidth
                )
            }

            // 텍스트 렌더링 (마킹 텍스트가 있는 행은 분리 렌더링)
            if lineIndex == selection.cursor.line,
               let marked = _markedText, marked.length > 0 {
                renderLineWithMarkedText(
                    line: line,
                    markedText: marked,
                    cursorColumn: selection.cursor.column,
                    at: origin,
                    in: context,
                    viewportWidth: viewportWidth
                )
            } else {
                lineRenderer.render(
                    line: line,
                    at: origin,
                    in: context,
                    viewportWidth: viewportWidth
                )
            }

            // 커서 렌더링 + 캐시 업데이트
            if lineIndex == selection.cursor.line {
                // 커서 위치 캐시 업데이트 (이 행의 Y 좌표와 높이)
                updateCursorCache(
                    line: line,
                    column: selection.cursor.column,
                    lineY: y,
                    lineHeight: rowHeight,
                    viewportWidth: viewportWidth
                )

                if editorState.isEditable && showCursor && !selection.hasSelection {
                    lineRenderer.renderCursor(
                        line: line,
                        column: selection.cursor.column,
                        at: origin,
                        in: context,
                        rowHeight: rowHeight,
                        viewportWidth: viewportWidth
                    )
                }
            }

            y += rowHeight
        }
    }

    /// 커서 위치 캐시 업데이트
    private func updateCursorCache(line: TextLine, column: Int, lineY: CGFloat, lineHeight: CGFloat, viewportWidth: CGFloat) {
        let cacheKey = "\(editorState.selection.cursor.line):\(column):\(Int(viewportWidth))"
        guard cacheKey != _cursorCacheKey else { return }

        _cachedCursorLineY = lineY
        _cachedCursorLineHeight = lineHeight
        _cursorCacheKey = cacheKey

        let rect = lineRenderer.caretRect(in: line.content, column: column, viewportWidth: viewportWidth)
        _cachedWrappedLineIndex = Int(rect.minY / lineRenderer.lineHeight)
        _cachedCursorXInLine = rect.minX
    }

    /// 마킹 텍스트가 있는 행 렌더링 (커서 위치에서 분리)
    /// 커서 전 텍스트 + 마킹 텍스트 + 커서 후 텍스트 순서로 렌더링
    private func renderLineWithMarkedText(
        line: TextLine,
        markedText: NSAttributedString,
        cursorColumn: Int,
        at origin: CGPoint,
        in context: CGContext,
        viewportWidth: CGFloat
    ) {
        let selection = editorState.selection.range.normalized
        let insertionColumn = selection.start.line == editorState.selection.cursor.line ? selection.start.column : cursorColumn
        let before = String(line.content.prefix(max(0, min(insertionColumn, line.content.count))))
        let endColumn = selection.end.line == editorState.selection.cursor.line ? selection.end.column : cursorColumn
        let after = String(line.content.dropFirst(max(0, min(endColumn, line.content.count))))
        lineRenderer.renderComposition(before: before, marked: markedText.string, after: after,
                                       at: origin, in: context, viewportWidth: viewportWidth)
    }

    // MARK: - Cursor Blink

    private func startCursorBlink() {
        stopCursorBlink()
        cursorBlinkTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.showCursor.toggle()
            self?.setNeedsDisplay(self?.cursorRect ?? .zero)
        }
    }

    private func stopCursorBlink() {
        cursorBlinkTimer?.invalidate()
        cursorBlinkTimer = nil
    }

    private func resetCursorBlink() {
        showCursor = true
        startCursorBlink()
    }

    /// 커서 영역 (최적화된 다시 그리기용)
    private var cursorRect: NSRect {
        let cursorLine = editorState.selection.cursor.line
        let viewportWidth = bounds.width - textLeftPadding

        // Word Wrap 활성화 시 캐시된 값 사용
        if wordWrapEnabled && viewportWidth > 0 {
            // 캐시가 유효한지 확인
            let cacheKey = "\(cursorLine):\(editorState.selection.cursor.column):\(Int(viewportWidth))"
            if cacheKey == _cursorCacheKey {
                // 캐시된 값 사용: 행의 Y + 래핑된 줄 내 오프셋
                let y = _cachedCursorLineY + CGFloat(_cachedWrappedLineIndex) * lineRenderer.lineHeight
                return NSRect(x: 0, y: y, width: bounds.width, height: lineRenderer.lineHeight)
            }
            // 캐시가 유효하지 않으면 폴백 (전체 행 영역 반환)
            let y = yPosition(for: cursorLine, viewportWidth: viewportWidth)
            let height = rowHeight(for: cursorLine, viewportWidth: viewportWidth)
            return NSRect(x: 0, y: y, width: bounds.width, height: height)
        }

        // 고정 높이
        let y = CGFloat(cursorLine) * lineRenderer.lineHeight
        return NSRect(x: 0, y: y, width: bounds.width, height: lineRenderer.lineHeight)
    }

    // MARK: - First Responder

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        resetCursorBlink()
        // 표준화된 Undo 시스템에 포커스 알림
        TextUndoHistoryManager.shared.setFocusedArea(.editor)
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        // 포커스를 잃을 때 조합 중인 텍스트 확정 (notifyTextChange 없이)
        // 탭 전환 시에는 EditorContainerView가 캐시를 관리하므로 여기서 콜백 호출 불필요
        commitMarkedTextIfNeeded()

        stopCursorBlink()
        showCursor = false
        needsDisplay = true
        return super.resignFirstResponder()
    }

    // MARK: - IME Helper

    /// 조합 중인 텍스트를 확정하지 않고 버림 (탭 전환 시 사용)
    func discardMarkedText() {
        _markedText = nil
        _markedRange = NSRange(location: NSNotFound, length: 0)
        inputContext?.discardMarkedText()
        // 입력 컨텍스트 완전히 무효화하여 다음 입력 시 깨끗한 상태로 시작
        inputContext?.invalidateCharacterCoordinates()
        needsDisplay = true
    }

    /// 입력 컨텍스트를 완전히 리셋 (탭 전환 후 새 탭에서 깨끗한 IME 상태로 시작)
    func resetInputContext() {
        // 마킹 상태 완전 초기화
        _markedText = nil
        _markedRange = NSRange(location: NSNotFound, length: 0)

        // 입력 컨텍스트에서 마킹 텍스트 버리기
        inputContext?.discardMarkedText()

        // 입력 소스 비활성화 후 재활성화하여 IME 상태 리셋
        inputContext?.deactivate()
        inputContext?.activate()

        // 좌표 정보 무효화
        inputContext?.invalidateCharacterCoordinates()
    }

    /// 조합 중인 텍스트를 조용히 확정 (onTextChange 콜백 없이)
    /// 포커스를 잃을 때 또는 탭 전환 시 사용 - SwiftUI 상태 충돌 방지
    func commitMarkedTextSilently() {
        guard hasMarkedText(), let marked = _markedText, marked.length > 0 else { return }

        let text = marked.string

        // 마킹 상태 클리어
        _markedText = nil
        _markedRange = NSRange(location: NSNotFound, length: 0)

        // 직접 텍스트 삽입 (콜백 없이)
        let beforeLine = editorState.selection.cursor.line
        let beforeCount = editorState.document.lineCount
        editorState.insertText(text)
        let afterCount = editorState.document.lineCount
        let currentLine = editorState.selection.cursor.line

        // 캐시 무효화 및 UI 업데이트
        invalidateRenderCache(fromLine: beforeLine, toLine: currentLine + abs(afterCount - beforeCount))
        updateSelectedRange()
        needsDisplay = true

        // notifyTextChange() 호출 안함 - 의도적
        // 탭 전환 시 EditorContainerView.onChange(of: tabManager.selectedTab?.url)에서
        // 이미 text를 캐시에 저장하기 때문

        if beforeCount != afterCount {
            onDocumentStructureChange?()
        }
    }

    /// 조합 중인 텍스트가 있으면 현재 커서 위치에서 확정
    /// 마우스 클릭 등 사용자 인터랙션 시에만 사용
    func commitMarkedTextIfNeeded() {
        guard hasMarkedText(), let marked = _markedText, marked.length > 0 else { return }

        let text = marked.string

        // 마킹 상태 먼저 클리어 (중복 호출 방지)
        _markedText = nil
        _markedRange = NSRange(location: NSNotFound, length: 0)

        // 입력 컨텍스트에게 마킹 취소 알림 (시스템이 insertText 호출하지 않도록)
        inputContext?.discardMarkedText()

        // 직접 텍스트 삽입
        let beforeLine = editorState.selection.cursor.line
        let beforeCount = editorState.document.lineCount
        editorState.insertText(text)
        let afterCount = editorState.document.lineCount
        let currentLine = editorState.selection.cursor.line

        // 캐시 무효화 및 UI 업데이트
        invalidateRenderCache(fromLine: beforeLine, toLine: currentLine + abs(afterCount - beforeCount))
        updateSelectedRange()
        needsDisplay = true
        notifyTextChange()

        if beforeCount != afterCount {
            onDocumentStructureChange?()
        }
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        // 조합 중인 텍스트가 있으면 현재 커서 위치에서 확정 (클릭 전에 처리)
        // makeFirstResponder 전에 처리해야 시스템이 잘못된 위치에 삽입하지 않음
        if hasMarkedText() {
            commitMarkedTextIfNeeded()
            inputContext?.discardMarkedText()
        }

        window?.makeFirstResponder(self)

        let location = convert(event.locationInWindow, from: nil)
        let position = textPositionAt(point: location)

        if event.modifierFlags.contains(.shift) {
            editorState.selection.extendSelection(to: position)
        } else {
            editorState.selection.moveCursor(to: position)
        }

        updateSelectedRange()
        resetCursorBlink()
        needsDisplay = true
        notifyCursorChange()
    }

    override func mouseDragged(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let position = textPositionAt(point: location)

        editorState.selection.extendSelection(to: position)

        updateSelectedRange()
        needsDisplay = true
        notifyCursorChange()
    }

    override func mouseUp(with event: NSEvent) {
        // 더블 클릭: 단어 선택, 트리플 클릭: 줄 선택
        if event.clickCount == 2 {
            selectWordAtCursor()
        } else if event.clickCount == 3 {
            selectLineAtCursor()
        }
    }

    private func textPositionAt(point: CGPoint) -> TextPosition {
        let viewportWidth = bounds.width - textLeftPadding

        // Word Wrap 활성화 시 동적 높이 기반 계산
        if wordWrapEnabled && viewportWidth > 0 {
            let index = lineIndex(atY: point.y, viewportWidth: viewportWidth)
            let content = editorState.document.getLine(index) ?? ""
            let origin = yPosition(for: index, viewportWidth: viewportWidth)
            let row = Int(floor(max(0, point.y - origin) / lineRenderer.lineHeight))
            let column = characterIndexInWrappedLine(lineContent: content, wrappedLineIndex: row,
                xPosition: point.x - textLeftPadding, viewportWidth: viewportWidth)
            return TextPosition(line: index, column: min(column, content.count))
        }

        // 고정 높이 (Word Wrap 비활성화)
        let lineHeight = lineRenderer.lineHeight
        guard lineHeight > 0 else { return .zero }
        let lineIndex = Int(floor(max(0, point.y) / lineHeight))
        let clampedLine = max(0, min(lineIndex, max(0, editorState.document.lineCount - 1)))

        let lineContent = editorState.document.getLine(clampedLine) ?? ""
        let x = point.x - textLeftPadding
        let column = lineRenderer.characterIndex(at: max(0, x), in: lineContent)

        return TextPosition(line: clampedLine, column: min(column, lineContent.count))
    }

    /// Word Wrap된 행에서 문자 인덱스 계산
    private func characterIndexInWrappedLine(
        lineContent: String,
        wrappedLineIndex: Int,
        xPosition: CGFloat,
        viewportWidth: CGFloat
    ) -> Int {
        lineRenderer.characterIndex(at: xPosition, in: lineContent,
                                    visualRow: wrappedLineIndex, viewportWidth: viewportWidth)
    }

    private func selectWordAtCursor() {
        let cursor = editorState.selection.cursor
        let text = editorState.document.getLine(cursor.line) ?? ""
        let characters = Array(text)
        guard !characters.isEmpty else { return }
        let pivot = min(cursor.column, characters.count - 1)
        let whitespace = characters[pivot].isWhitespace
        var start = pivot
        var end = pivot + 1
        while start > 0 && characters[start - 1].isWhitespace == whitespace { start -= 1 }
        while end < characters.count && characters[end].isWhitespace == whitespace { end += 1 }
        editorState.selection.select(from: TextPosition(line: cursor.line, column: start),
                                     to: TextPosition(line: cursor.line, column: end))
        updateSelectedRange()
        needsDisplay = true
        notifyCursorChange()
    }

    private func selectLineAtCursor() {
        let lineIndex = editorState.selection.cursor.line
        editorState.selection.selectLine(lineIndex, in: editorState.document)
        updateSelectedRange()
        needsDisplay = true
        notifyCursorChange()
    }

    // MARK: - Undo/Redo Actions (macOS Edit 메뉴에서 호출)

    /// macOS Edit 메뉴의 Undo (Cmd+Z)
    @objc func undo(_ sender: Any?) {
        #if DEBUG
        print("[TextlinkTextView] undo: action received")
        #endif

        // 조합 중인 텍스트가 있으면 먼저 취소
        if hasMarkedText() {
            inputContext?.discardMarkedText()
            unmarkText()
            needsDisplay = true
            return  // 조합 취소만 하고 종료 (Undo는 다음 Cmd+Z에서)
        }

        performUndo()
    }

    /// macOS Edit 메뉴의 Redo (Cmd+Shift+Z)
    @objc func redo(_ sender: Any?) {
        #if DEBUG
        print("[TextlinkTextView] redo: action received")
        #endif

        // 조합 중인 텍스트가 있으면 먼저 취소
        if hasMarkedText() {
            inputContext?.discardMarkedText()
            unmarkText()
            needsDisplay = true
            return  // 조합 취소만 하고 종료
        }

        performRedo()
    }

    // MARK: - Keyboard Events

    override func keyDown(with event: NSEvent) {
        // First Responder가 아니면 키 이벤트 무시
        guard window?.firstResponder === self else {
            super.keyDown(with: event)
            return
        }

        if let action = KeyboardShortcutManager.shared.action(matching: event), performConfiguredShortcut(action) {
            return
        }

        // Cmd 키 조합 처리
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers {
            case "a":
                // Cmd+A: 전체 선택
                editorState.selectAll()
                updateSelectedRange()
                needsDisplay = true
                notifyCursorChange()
                return

            case "c":
                // Cmd+C: 복사
                performCopy()
                return

            case "v":
                // Cmd+V: 붙여넣기
                performPaste()
                return

            case "x":
                // Cmd+X: 잘라내기
                performCut()
                return

            // Cmd+Z/Cmd+Shift+Z는 macOS 기본 Edit 메뉴에서 처리하도록 함
            // doCommand에서 undo:/redo: selector를 받아서 처리

            default:
                break
            }
        }

        // inputContext를 통해 키 이벤트 처리 (IME 및 doCommand 호출)
        if inputContext?.handleEvent(event) == true {
            return
        }
        // inputContext가 처리하지 않은 경우 기본 처리
        super.keyDown(with: event)
    }

    @discardableResult
    func performConfiguredShortcut(_ action: ShortcutAction) -> Bool {
        switch action {
        case .moveLineUp, .moveLineDown, .duplicateLineUp, .duplicateLineDown,
             .deleteWordBackward, .deleteToLineStart:
            commitMarkedTextIfNeeded()
        default: return false
        }
        switch action {
        case .moveLineUp: performMoveLineUp()
        case .moveLineDown: performMoveLineDown()
        case .duplicateLineUp: performDuplicateLineUp()
        case .duplicateLineDown: performDuplicateLineDown()
        case .deleteWordBackward: performDeleteWordBackward()
        case .deleteToLineStart: performDeleteToLineStart()
        default: return false
        }
        return true
    }

    // Native Edit menu dispatches selectors before keyDown.
    override func menu(for event: NSEvent) -> NSMenu? {
        // Keep the existing selection; right-click must not replace it with a caret.
        window?.makeFirstResponder(self)
        return selectionQuickMenu()
    }

    func selectionQuickMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let selected = editorState.selection.hasSelection
        let editable = editorState.isEditable && !isLayoutPreparing
        func add(_ key: String, _ action: Selector, _ enabled: Bool, tag: Int = 0) {
            let item = NSMenuItem(title: L10n.get(key), action: action, keyEquivalent: "")
            item.target = self
            item.isEnabled = enabled
            item.tag = tag
            menu.addItem(item)
        }
        add("shortcut.edit.cut", #selector(cut(_:)), selected && editable)
        add("shortcut.edit.copy", #selector(copy(_:)), selected)
        add("shortcut.edit.paste", #selector(paste(_:)), editable && NSPasteboard.general.canReadItem(withDataConformingToTypes: [NSPasteboard.PasteboardType.string.rawValue]))
        add("shortcut.edit.selectAll", #selector(selectAll(_:)), !editorState.document.getText().isEmpty)
        menu.addItem(.separator())
        for (index, key) in ["editor.bold", "editor.italic", "editor.underline", "editor.strikethrough"].enumerated() {
            add(key, #selector(applyQuickFormat(_:)), selected && editable, tag: index)
        }
        return menu
    }

    @objc private func applyQuickFormat(_ sender: NSMenuItem) {
        guard editorState.isEditable, editorState.selection.hasSelection else { return }
        let formats: [MarkdownFormatType] = [.bold, .italic, .underline, .strikethrough]
        guard formats.indices.contains(sender.tag) else { return }
        commitMarkedTextIfNeeded()
        performEditorCommand(EditorCommand(.format(formats[sender.tag])))
    }

    @objc func paste(_ sender: Any?) { commitMarkedTextIfNeeded(); performPaste() }
    @objc func copy(_ sender: Any?) { commitMarkedTextIfNeeded(); performCopy() }
    @objc func cut(_ sender: Any?) { commitMarkedTextIfNeeded(); performCut() }
    override func selectAll(_ sender: Any?) {
        commitMarkedTextIfNeeded()
        editorState.selectAll()
        updateSelectedRange()
        needsDisplay = true
        notifyCursorChange()
    }

    // MARK: - Clipboard Operations

    /// 복사 (Cmd+C)
    private func performCopy() {
        guard let text = editorState.copy() else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// 붙여넣기 (Cmd+V)
    private func performPaste() {
        guard editorState.isEditable else { return }

        let pasteboard = NSPasteboard.general
        guard let text = pasteboard.string(forType: .string) else { return }

        let beforeLine = editorState.selection.cursor.line
        let beforeCount = editorState.document.lineCount
        editorState.paste(text)
        let afterCount = editorState.document.lineCount
        let currentLine = editorState.selection.cursor.line

        // 변경된 행의 렌더링 캐시 무효화
        invalidateRenderCache(fromLine: beforeLine, toLine: currentLine + (afterCount - beforeCount))

        updateSelectedRange()
        resetCursorBlink()
        needsDisplay = true

        notifyTextChange()
        notifyCursorChange()

        // 붙여넣기 후 커서 위치로 스크롤
        onScrollToCursor?(currentLine)

        if beforeCount != afterCount {
            onDocumentStructureChange?()
        }
    }

    /// 잘라내기 (Cmd+X)
    private func performCut() {
        guard editorState.isEditable else { return }
        guard let text = editorState.cut() else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // 캐시 무효화 및 UI 업데이트
        let currentLine = editorState.selection.cursor.line
        invalidateRenderCache(fromLine: currentLine, toLine: currentLine)

        updateSelectedRange()
        resetCursorBlink()
        needsDisplay = true

        notifyTextChange()
        notifyCursorChange()

        // 잘라내기 후 커서 위치로 스크롤
        onScrollToCursor?(currentLine)

        onDocumentStructureChange?()
    }

    /// Option+백스페이스 - 단어 단위 삭제
    private func performDeleteWordBackward() {
        guard editorState.isEditable else { return }

        let beforeLine = editorState.selection.cursor.line
        let beforeCount = editorState.document.lineCount

        editorState.deleteWordBackward()

        let afterCount = editorState.document.lineCount
        let currentLine = editorState.selection.cursor.line

        // 캐시 무효화
        let affectedStart = min(beforeLine, currentLine)
        let affectedEnd = max(beforeLine, currentLine) + abs(afterCount - beforeCount)
        invalidateRenderCache(fromLine: affectedStart, toLine: affectedEnd)

        updateSelectedRange()
        resetCursorBlink()
        needsDisplay = true

        notifyTextChange()
        notifyCursorChange()

        // 삭제 후 커서 위치로 스크롤
        onScrollToCursor?(currentLine)

        if beforeCount != afterCount {
            onDocumentStructureChange?()
        }
    }

    /// Cmd+백스페이스 - 행 시작까지 삭제
    private func performDeleteToLineStart() {
        guard editorState.isEditable else { return }

        let beforeLine = editorState.selection.cursor.line
        let beforeCount = editorState.document.lineCount

        editorState.deleteToLineStart()

        let afterCount = editorState.document.lineCount
        let currentLine = editorState.selection.cursor.line

        // 캐시 무효화
        let affectedStart = min(beforeLine, currentLine)
        let affectedEnd = max(beforeLine, currentLine) + abs(afterCount - beforeCount)
        invalidateRenderCache(fromLine: affectedStart, toLine: affectedEnd)

        updateSelectedRange()
        resetCursorBlink()
        needsDisplay = true

        notifyTextChange()
        notifyCursorChange()

        // 삭제 후 커서 위치로 스크롤
        onScrollToCursor?(currentLine)

        if beforeCount != afterCount {
            onDocumentStructureChange?()
        }
    }

    // MARK: - Line Operations

    /// 행 위로 이동 (Option+위)
    private func performMoveLineUp() {
        guard editorState.isEditable else { return }

        let beforeLine = editorState.selection.cursor.line
        guard editorState.moveLineUp() else { return }

        let currentLine = editorState.selection.cursor.line

        // 두 행의 캐시 무효화
        invalidateRenderCache(fromLine: currentLine, toLine: beforeLine)

        updateSelectedRange()
        resetCursorBlink()
        needsDisplay = true

        notifyTextChange()
        notifyCursorChange()
    }

    /// 행 아래로 이동 (Option+아래)
    private func performMoveLineDown() {
        guard editorState.isEditable else { return }

        let beforeLine = editorState.selection.cursor.line
        guard editorState.moveLineDown() else { return }

        let currentLine = editorState.selection.cursor.line

        // 두 행의 캐시 무효화
        invalidateRenderCache(fromLine: beforeLine, toLine: currentLine)

        updateSelectedRange()
        resetCursorBlink()
        needsDisplay = true

        notifyTextChange()
        notifyCursorChange()
    }

    /// 행 위로 복제 (Option+Shift+위)
    private func performDuplicateLineUp() {
        guard editorState.isEditable else { return }

        let beforeCount = editorState.document.lineCount
        let currentLine = editorState.selection.cursor.line

        guard editorState.duplicateLineUp() else { return }

        // 현재 행부터 아래로 캐시 무효화
        invalidateRenderCache(fromLine: currentLine, toLine: editorState.document.lineCount - 1)

        updateSelectedRange()
        resetCursorBlink()
        needsDisplay = true

        notifyTextChange()
        notifyCursorChange()

        if beforeCount != editorState.document.lineCount {
            onDocumentStructureChange?()
        }
    }

    /// 행 아래로 복제 (Option+Shift+아래)
    private func performDuplicateLineDown() {
        guard editorState.isEditable else { return }

        let beforeCount = editorState.document.lineCount
        let beforeLine = editorState.selection.cursor.line

        guard editorState.duplicateLineDown() else { return }

        // 복제된 행부터 아래로 캐시 무효화
        invalidateRenderCache(fromLine: beforeLine, toLine: editorState.document.lineCount - 1)

        updateSelectedRange()
        resetCursorBlink()
        needsDisplay = true

        notifyTextChange()
        notifyCursorChange()

        if beforeCount != editorState.document.lineCount {
            onDocumentStructureChange?()
        }
    }

    // MARK: - Undo/Redo

    /// Undo 실행 (Cmd+Z)
    private func performUndo() {
        #if DEBUG
        print("[TextlinkTextView] performUndo: canUndo=\(editorState.canUndo), undoStack=\(editorState.undoCount), redoStack=\(editorState.redoCount)")
        #endif

        let beforeCount = editorState.document.lineCount
        guard editorState.undo() else {
            #if DEBUG
            print("[TextlinkTextView] performUndo: undo() returned false")
            #endif
            return
        }

        let afterCount = editorState.document.lineCount

        // 전체 캐시 무효화 (Undo는 여러 행에 영향을 줄 수 있음)
        invalidateRenderCache(fromLine: 0, toLine: max(beforeCount, afterCount) - 1)

        updateSelectedRange()
        resetCursorBlink()
        needsDisplay = true

        notifyTextChange()
        notifyCursorChange()

        if beforeCount != afterCount {
            onDocumentStructureChange?()
        }
    }

    /// Redo 실행 (Cmd+Shift+Z)
    private func performRedo() {
        #if DEBUG
        print("[TextlinkTextView] performRedo: canRedo=\(editorState.canRedo), undoStack=\(editorState.undoCount), redoStack=\(editorState.redoCount)")
        #endif

        let beforeCount = editorState.document.lineCount
        guard editorState.redo() else {
            #if DEBUG
            print("[TextlinkTextView] performRedo: redo() returned false")
            #endif
            return
        }

        let afterCount = editorState.document.lineCount

        // 전체 캐시 무효화 (Redo는 여러 행에 영향을 줄 수 있음)
        invalidateRenderCache(fromLine: 0, toLine: max(beforeCount, afterCount) - 1)

        updateSelectedRange()
        resetCursorBlink()
        needsDisplay = true

        notifyTextChange()
        notifyCursorChange()

        if beforeCount != afterCount {
            onDocumentStructureChange?()
        }
    }

    // MARK: - Helpers

    // MARK: - Cache Invalidation

    /// 지정된 행 범위의 렌더링 캐시 무효화
    private func invalidateRenderCache(fromLine start: Int, toLine end: Int) {
        for lineIndex in start...max(start, end) {
            if let line = editorState.document.getLineObject(lineIndex) {
                lineRenderer.invalidateCache(for: line.id)
            }
        }
    }

    func performEditorCommand(_ command: EditorCommand) {
        let version = editorState.document.version
        editorState.execute(command)
        lineRenderer.invalidateAllCache()
        updateSelectedRange()
        needsDisplay = true
        if editorState.document.version != version { notifyTextChange() }
        notifyCursorChange()
        onDocumentStructureChange?()
        onScrollToCursor?(editorState.selection.cursor.line)
    }

    private func notifyTextChange() {
        onTextChange?(editorState.getText())
    }

    private func notifyCursorChange() {
        onCursorChange?(
            editorState.selection.cursorLine + 1,
            editorState.selection.selectedLineRange.map { ($0.lowerBound + 1)...($0.upperBound + 1) }
        )
    }

    private func updateSelectedRange() {
        let range = editorState.selection.range.normalized
        let start = editorState.document.utf16Offset(from: range.start)
        let end = editorState.document.utf16Offset(from: range.end)
        _selectedRange = NSRange(location: start, length: end - start)
    }

}

// MARK: - NSTextInputClient

extension TextlinkTextView: NSTextInputClient {
    func insertText(_ string: Any, replacementRange: NSRange) {
        guard editorState.isEditable else { return }

        let wasComposing = hasMarkedText()
        // 마킹 텍스트 클리어
        _markedText = nil
        _markedRange = NSRange(location: NSNotFound, length: 0)

        let text: String
        if let attrString = string as? NSAttributedString {
            text = attrString.string
        } else if let str = string as? String {
            text = str
        } else {
            return
        }

        if !wasComposing && replacementRange.location != NSNotFound {
            let start = editorState.document.positionFromUTF16Offset(replacementRange.location)
            let end = editorState.document.positionFromUTF16Offset(replacementRange.location + replacementRange.length)
            editorState.selection.select(from: start, to: end)
        }
        let beforeLine = editorState.selection.cursor.line
        let beforeCount = editorState.document.lineCount
        editorState.insertText(text)
        let afterCount = editorState.document.lineCount
        let currentLine = editorState.selection.cursor.line

        // 변경된 행의 렌더링 캐시 무효화
        invalidateRenderCache(fromLine: beforeLine, toLine: currentLine + (afterCount - beforeCount))

        updateSelectedRange()
        resetCursorBlink()
        needsDisplay = true

        notifyTextChange()
        notifyCursorChange()

        // 텍스트 입력 후 커서 위치로 스크롤
        onScrollToCursor?(currentLine)

        if beforeCount != afterCount {
            onDocumentStructureChange?()
        }
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        guard editorState.isEditable else { return }
        if !hasMarkedText(), replacementRange.location != NSNotFound {
            editorState.selection.select(
                from: editorState.document.positionFromUTF16Offset(replacementRange.location),
                to: editorState.document.positionFromUTF16Offset(replacementRange.location + replacementRange.length))
            updateSelectedRange()
        }
        // 항상 에디터 폰트와 색상으로 마킹 텍스트 생성
        let markedString: String
        if let attrString = string as? NSAttributedString {
            markedString = attrString.string
        } else if let str = string as? String {
            markedString = str
        } else {
            markedString = ""
        }

        if !markedString.isEmpty {
            _markedText = NSAttributedString(string: markedString, attributes: [
                .font: editorState.configuration.font,
                .foregroundColor: AppColors.nsEditorText
            ])
            _markedRange = NSRange(location: editorState.document.utf16Offset(from: editorState.selection.range.normalized.start), length: markedString.utf16.count)
            let location = max(0, min(selectedRange.location, markedString.utf16.count))
            markedSelection = NSRange(location: location, length: min(selectedRange.length, markedString.utf16.count - location))

            // IME 조합 시작할 때 커서 위치로 스크롤 (커서가 화면 밖에 있을 경우)
            // 이 스크롤은 IME 조합의 일부이므로 commitMarkedText 호출 방지
            // isScrollingForIME는 handleScrollChange에서 리셋됨
            isScrollingForIME = true
            onScrollToCursor?(editorState.selection.cursor.line)
        } else {
            _markedText = nil
            _markedRange = NSRange(location: NSNotFound, length: 0)
        }

        needsDisplay = true
    }

    func unmarkText() {
        _markedText = nil
        _markedRange = NSRange(location: NSNotFound, length: 0)
        needsDisplay = true
    }

    func selectedRange() -> NSRange {
        if hasMarkedText() {
            return NSRange(location: _markedRange.location + markedSelection.location, length: markedSelection.length)
        }
        return _selectedRange
    }

    func markedRange() -> NSRange {
        _markedRange
    }

    func hasMarkedText() -> Bool {
        _markedText != nil && _markedText!.length > 0
    }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        var content = editorState.getText()
        if let marked = _markedText {
            let selected = editorState.selection.range.normalized
            let start = editorState.document.utf16Offset(from: selected.start)
            let end = editorState.document.utf16Offset(from: selected.end)
            content = (content as NSString).replacingCharacters(in: NSRange(location: start, length: end - start), with: marked.string)
        }
        let text = content as NSString
        guard range.location != NSNotFound, range.location >= 0,
              range.location <= text.length, range.length <= text.length - range.location else { return nil }
        actualRange?.pointee = range
        return NSAttributedString(string: text.substring(with: range), attributes: [.font: editorState.configuration.font])
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        [.font, .foregroundColor, .backgroundColor]
    }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        let position = editorState.document.positionFromUTF16Offset(range.location)
        let width = bounds.width - textLeftPadding
        let rect = lineRenderer.caretRect(in: editorState.document.getLine(position.line) ?? "",
                                         column: position.column, viewportWidth: width)
            .offsetBy(dx: textLeftPadding, dy: yPosition(for: position.line, viewportWidth: width))
        actualRange?.pointee = NSRange(location: editorState.document.utf16Offset(from: position), length: 0)
        let windowRect = convert(rect, to: nil)
        return window?.convertToScreen(windowRect) ?? windowRect
    }

    func characterIndex(for point: NSPoint) -> Int {
        let windowPoint = window?.convertPoint(fromScreen: point) ?? point
        let position = textPositionAt(point: convert(windowPoint, from: nil))
        return editorState.document.utf16Offset(from: position)
    }

    override func doCommand(by selector: Selector) {
        // First Responder가 아니면 명령 무시
        guard window?.firstResponder === self else {
            #if DEBUG
            print("[TextlinkTextView] doCommand ignored (not first responder): \(selector)")
            #endif
            return
        }

        #if DEBUG
        print("[TextlinkTextView] doCommand: \(selector)")
        #endif

        // 지원하는 명령 목록
        let supportedCommands: Set<Selector> = [
            #selector(moveLeft(_:)), #selector(moveRight(_:)),
            #selector(moveUp(_:)), #selector(moveDown(_:)),
            #selector(moveLeftAndModifySelection(_:)), #selector(moveRightAndModifySelection(_:)),
            #selector(moveUpAndModifySelection(_:)), #selector(moveDownAndModifySelection(_:)),
            #selector(moveToBeginningOfLine(_:)), #selector(moveToEndOfLine(_:)),
            #selector(moveToBeginningOfDocument(_:)), #selector(moveToEndOfDocument(_:)),
            #selector(deleteBackward(_:)), #selector(deleteForward(_:)),
            #selector(insertNewline(_:)), #selector(insertTab(_:)),
            #selector(selectAll(_:)),
            #selector(undo(_:)), #selector(redo(_:))
        ]

        // 지원하지 않는 명령은 무시 (noop 등)
        guard supportedCommands.contains(selector) else {
            #if DEBUG
            print("[TextlinkTextView] doCommand unsupported: \(selector)")
            #endif
            return
        }

        // 커서 이동 명령인 경우 조합 중인 텍스트 확정
        let isCursorMovement = [
            #selector(moveLeft(_:)), #selector(moveRight(_:)),
            #selector(moveUp(_:)), #selector(moveDown(_:)),
            #selector(moveLeftAndModifySelection(_:)), #selector(moveRightAndModifySelection(_:)),
            #selector(moveUpAndModifySelection(_:)), #selector(moveDownAndModifySelection(_:)),
            #selector(moveToBeginningOfLine(_:)), #selector(moveToEndOfLine(_:)),
            #selector(moveToBeginningOfDocument(_:)), #selector(moveToEndOfDocument(_:))
        ].contains(selector)

        if isCursorMovement {
            commitMarkedTextIfNeeded()
        }

        var textChanged = false
        var structureChanged = false
        let beforeLine = editorState.selection.cursor.line
        let beforeCount = editorState.document.lineCount

        switch selector {
        case #selector(moveLeft(_:)):
            editorState.moveCursorLeft()
        case #selector(moveRight(_:)):
            editorState.moveCursorRight()
        case #selector(moveUp(_:)):
            editorState.moveCursorUp()
        case #selector(moveDown(_:)):
            editorState.moveCursorDown()
        case #selector(moveLeftAndModifySelection(_:)):
            editorState.moveCursorLeft(extendSelection: true)
        case #selector(moveRightAndModifySelection(_:)):
            editorState.moveCursorRight(extendSelection: true)
        case #selector(moveUpAndModifySelection(_:)):
            editorState.moveCursorUp(extendSelection: true)
        case #selector(moveDownAndModifySelection(_:)):
            editorState.moveCursorDown(extendSelection: true)
        case #selector(moveToBeginningOfLine(_:)):
            editorState.moveCursorToLineStart()
        case #selector(moveToEndOfLine(_:)):
            editorState.moveCursorToLineEnd()
        case #selector(moveToBeginningOfDocument(_:)):
            editorState.moveCursorToDocumentStart()
        case #selector(moveToEndOfDocument(_:)):
            editorState.moveCursorToDocumentEnd()
        case #selector(deleteBackward(_:)):
            guard editorState.isEditable else { return }
            editorState.deleteBackward()
            textChanged = true
        case #selector(deleteForward(_:)):
            guard editorState.isEditable else { return }
            editorState.deleteForward()
            textChanged = true
        case #selector(insertNewline(_:)):
            guard editorState.isEditable else { return }
            editorState.insertNewline()
            textChanged = true
        case #selector(insertTab(_:)):
            guard editorState.isEditable else { return }
            editorState.insertTab()
            textChanged = true
        case #selector(selectAll(_:)):
            editorState.selectAll()
        case #selector(undo(_:)):
            performUndo()
            return  // 별도 처리 완료
        case #selector(redo(_:)):
            performRedo()
            return  // 별도 처리 완료
        default:
            break
        }

        let afterCount = editorState.document.lineCount
        if beforeCount != afterCount {
            structureChanged = true
        }

        // 텍스트가 변경된 경우 해당 행의 렌더링 캐시 무효화
        if textChanged {
            let currentLine = editorState.selection.cursor.line
            let affectedStart = min(beforeLine, currentLine)
            let affectedEnd = max(beforeLine, currentLine) + abs(afterCount - beforeCount)
            invalidateRenderCache(fromLine: affectedStart, toLine: affectedEnd)
        }

        updateSelectedRange()
        resetCursorBlink()
        needsDisplay = true
        notifyCursorChange()

        // 커서가 이동하거나 텍스트가 변경된 경우 스크롤 요청
        let currentLine = editorState.selection.cursor.line
        if currentLine != beforeLine || textChanged {
            onScrollToCursor?(currentLine)
        }

        if textChanged {
            notifyTextChange()
        }

        if structureChanged {
            onDocumentStructureChange?()
        }
    }
}
