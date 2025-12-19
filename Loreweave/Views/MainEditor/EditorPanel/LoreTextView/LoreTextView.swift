//
//  LoreTextView.swift
//  Loreweave
//
//  커스텀 텍스트 에디터 뷰
//  Core Text 기반 행별 렌더링
//

import AppKit

// MARK: - Lore Text View

/// 커스텀 텍스트 에디터 뷰
/// 모든 행을 직접 렌더링 (스크롤은 부모가 담당)
final class LoreTextView: NSView {
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
        stopCursorBlink()
    }

    // MARK: - State Sync

    func syncFromState() {
        lineRenderer.font = editorState.configuration.font
        lineRenderer.lineHeightMultiple = editorState.configuration.lineHeightMultiple
        lineRenderer.textColor = AppColors.nsEditorText
        lineRenderer.wordWrapEnabled = editorState.configuration.wordWrap
        lineRenderer.letterSpacing = editorState.configuration.letterSpacing

        #if DEBUG
        print("[LoreTextView] syncFromState - wordWrap: \(editorState.configuration.wordWrap), lineHeight: \(lineRenderer.lineHeight), letterSpacing: \(lineRenderer.letterSpacing)")
        #endif
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

    /// 특정 행의 실제 높이 반환 (Word Wrap 포함)
    func rowHeight(for lineIndex: Int, viewportWidth: CGFloat) -> CGFloat {
        guard let line = editorState.document.getLineObject(lineIndex) else {
            return lineRenderer.lineHeight
        }
        return lineRenderer.calculateHeight(for: line, viewportWidth: viewportWidth)
    }

    /// 특정 행까지의 누적 Y 위치 계산
    func yPosition(for lineIndex: Int, viewportWidth: CGFloat) -> CGFloat {
        guard wordWrapEnabled && viewportWidth > 0 else {
            return CGFloat(lineIndex) * lineRenderer.lineHeight
        }

        var y: CGFloat = 0
        for i in 0..<lineIndex {
            y += rowHeight(for: i, viewportWidth: viewportWidth)
        }
        return y
    }

    /// 전체 콘텐츠 높이 계산 (Word Wrap 포함)
    func totalContentHeight(viewportWidth: CGFloat) -> CGFloat {
        guard wordWrapEnabled && viewportWidth > 0 else {
            return CGFloat(editorState.document.lineCount) * lineRenderer.lineHeight
        }

        var totalHeight: CGFloat = 0
        for i in 0..<editorState.document.lineCount {
            totalHeight += rowHeight(for: i, viewportWidth: viewportWidth)
        }
        return totalHeight
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

        // 마킹 텍스트 렌더링 (IME)
        if let marked = _markedText, marked.length > 0 {
            drawMarkedText(marked, in: context)
        }
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

            // 텍스트 렌더링
            lineRenderer.render(
                line: line,
                at: origin,
                in: context,
                viewportWidth: bounds.width - textLeftPadding
            )
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
        // 각 행의 Y 위치와 높이를 계산하면서 dirtyRect 범위 내의 행만 렌더링
        var currentY: CGFloat = 0
        var startLine: Int?
        var endLine: Int?

        // 먼저 dirtyRect 범위에 해당하는 행 찾기
        for lineIndex in 0..<document.lineCount {
            let rowHeight = self.rowHeight(for: lineIndex, viewportWidth: viewportWidth)
            let lineBottom = currentY + rowHeight

            // dirtyRect와 겹치는지 확인
            if lineBottom > dirtyRect.minY && currentY < dirtyRect.maxY {
                if startLine == nil {
                    startLine = lineIndex
                }
                endLine = lineIndex
            }

            // dirtyRect를 지나쳤으면 중단
            if currentY > dirtyRect.maxY {
                break
            }

            currentY = lineBottom
        }

        guard let start = startLine, let end = endLine else { return }

        // 시작 행까지의 Y 위치 계산
        var y: CGFloat = 0
        for i in 0..<start {
            y += rowHeight(for: i, viewportWidth: viewportWidth)
        }

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

            // 텍스트 렌더링
            lineRenderer.render(
                line: line,
                at: origin,
                in: context,
                viewportWidth: viewportWidth
            )

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

        // 래핑된 줄 내에서의 위치 계산
        let content = line.content
        let cursorColumn = min(column, content.count)

        if wordWrapEnabled && viewportWidth > 0 && !content.isEmpty {
            let attributedString = NSAttributedString(string: content, attributes: [
                .font: editorState.configuration.font,
                .foregroundColor: AppColors.nsEditorText
            ])
            let typesetter = CTTypesetterCreateWithAttributedString(attributedString)
            let stringLength = attributedString.length

            var tempStart = 0
            var wrappedLineIndex = 0

            while tempStart < stringLength {
                let lineLength = CTTypesetterSuggestLineBreak(typesetter, tempStart, Double(viewportWidth))
                guard lineLength > 0 else { break }

                let lineEnd = tempStart + lineLength
                let isLastLine = (lineEnd >= stringLength)

                let inRange: Bool
                if isLastLine {
                    inRange = cursorColumn >= tempStart && cursorColumn <= lineEnd
                } else {
                    inRange = cursorColumn >= tempStart && cursorColumn < lineEnd
                }

                if inRange {
                    _cachedWrappedLineIndex = wrappedLineIndex
                    let offsetInLine = cursorColumn - tempStart
                    let lineText = String(content.dropFirst(tempStart).prefix(offsetInLine))
                    _cachedCursorXInLine = lineRenderer.measureWidth(of: lineText)
                    return
                }

                tempStart = lineEnd
                wrappedLineIndex += 1
            }

            // 찾지 못한 경우 마지막 줄 끝
            _cachedWrappedLineIndex = max(0, wrappedLineIndex - 1)
            _cachedCursorXInLine = lineRenderer.measureWidth(of: content)
        } else {
            _cachedWrappedLineIndex = 0
            _cachedCursorXInLine = lineRenderer.measureWidth(of: String(content.prefix(cursorColumn)))
        }
    }

    private func drawMarkedText(_ markedText: NSAttributedString, in context: CGContext) {
        let cursorLine = editorState.selection.cursor.line
        let cursorColumn = editorState.selection.cursor.column

        guard let line = editorState.document.getLineObject(cursorLine) else { return }

        let singleLineHeight = lineRenderer.lineHeight
        let viewportWidth = bounds.width - textLeftPadding

        // Word Wrap 활성화 시 캐시된 값 사용
        let y: CGFloat
        let cursorX: CGFloat

        if wordWrapEnabled && viewportWidth > 0 {
            // 캐시가 유효한지 확인
            let cacheKey = "\(cursorLine):\(cursorColumn):\(Int(viewportWidth))"
            if cacheKey == _cursorCacheKey {
                // 캐시된 값 사용: 행의 Y + 래핑된 줄 내 오프셋
                y = _cachedCursorLineY + CGFloat(_cachedWrappedLineIndex) * singleLineHeight
                cursorX = _cachedCursorXInLine
            } else {
                // 캐시가 유효하지 않으면 폴백 계산
                var lineY = yPosition(for: cursorLine, viewportWidth: viewportWidth)
                var xInLine: CGFloat = 0
                let content = line.content

                if !content.isEmpty {
                    let attributedString = NSAttributedString(string: content, attributes: [
                        .font: editorState.configuration.font,
                        .foregroundColor: AppColors.nsEditorText
                    ])
                    let typesetter = CTTypesetterCreateWithAttributedString(attributedString)
                    let stringLength = attributedString.length

                    var tempStart = 0
                    let safeColumn = min(cursorColumn, content.count)

                    while tempStart < stringLength {
                        let lineLength = CTTypesetterSuggestLineBreak(typesetter, tempStart, Double(viewportWidth))
                        guard lineLength > 0 else { break }

                        let lineEnd = tempStart + lineLength
                        let isLastLine = (lineEnd >= stringLength)

                        let inRange: Bool
                        if isLastLine {
                            inRange = safeColumn >= tempStart && safeColumn <= lineEnd
                        } else {
                            inRange = safeColumn >= tempStart && safeColumn < lineEnd
                        }

                        if inRange {
                            let offsetInLine = safeColumn - tempStart
                            let lineText = String(content.dropFirst(tempStart).prefix(offsetInLine))
                            xInLine = lineRenderer.measureWidth(of: lineText)
                            break
                        }

                        lineY += singleLineHeight
                        tempStart = lineEnd
                    }
                }

                y = lineY
                cursorX = xInLine
            }
        } else {
            y = CGFloat(cursorLine) * singleLineHeight
            let safeColumn = min(cursorColumn, line.content.count)
            cursorX = lineRenderer.measureWidth(of: String(line.content.prefix(safeColumn)))
        }

        let origin = CGPoint(x: textLeftPadding + cursorX, y: y)

        // 마킹 텍스트 배경
        let textSize = markedText.size()
        let bgRect = CGRect(
            x: origin.x,
            y: origin.y,
            width: textSize.width,
            height: singleLineHeight
        )
        context.setFillColor(NSColor.selectedTextBackgroundColor.withAlphaComponent(0.3).cgColor)
        context.fill(bgRect)

        // 마킹 텍스트 그리기
        context.saveGState()

        // isFlipped = true인 NSView에서 Core Text 사용 시 텍스트 매트릭스 반전 필요
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = CGPoint(x: origin.x, y: origin.y + lineRenderer.baselineOffset)

        let ctLine = CTLineCreateWithAttributedString(markedText)
        CTLineDraw(ctLine, context)

        // 밑줄
        context.setStrokeColor(NSColor.labelColor.cgColor)
        context.setLineWidth(1)
        context.move(to: CGPoint(x: origin.x, y: origin.y + singleLineHeight - 2))
        context.addLine(to: CGPoint(x: origin.x + textSize.width, y: origin.y + singleLineHeight - 2))
        context.strokePath()

        context.restoreGState()
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
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        stopCursorBlink()
        showCursor = false
        needsDisplay = true
        return super.resignFirstResponder()
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
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
            var currentY: CGFloat = 0
            for lineIndex in 0..<editorState.document.lineCount {
                let rowHeight = self.rowHeight(for: lineIndex, viewportWidth: viewportWidth)
                if point.y >= currentY && point.y < currentY + rowHeight {
                    // 해당 행 내에서 클릭 위치 계산
                    let lineContent = editorState.document.getLine(lineIndex) ?? ""
                    let x = point.x - textLeftPadding

                    // Word Wrap된 행에서 클릭한 줄 위치 계산
                    let wrappedLineIndex = Int(floor((point.y - currentY) / lineRenderer.lineHeight))
                    let column = characterIndexInWrappedLine(
                        lineContent: lineContent,
                        wrappedLineIndex: wrappedLineIndex,
                        xPosition: x,
                        viewportWidth: viewportWidth
                    )

                    return TextPosition(line: lineIndex, column: min(column, lineContent.count))
                }
                currentY += rowHeight
            }
            // 문서 끝을 넘어간 경우
            let lastLine = max(0, editorState.document.lineCount - 1)
            let lastLineLength = editorState.document.getLine(lastLine)?.count ?? 0
            return TextPosition(line: lastLine, column: lastLineLength)
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
        guard !lineContent.isEmpty else { return 0 }

        // CTFramesetter로 래핑된 줄 정보 가져오기
        let attributedString = NSAttributedString(string: lineContent, attributes: [
            .font: editorState.configuration.font,
            .foregroundColor: AppColors.nsEditorText
        ])
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString)

        let path = CGPath(rect: CGRect(x: 0, y: 0, width: viewportWidth, height: .greatestFiniteMagnitude), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)

        guard let lines = CTFrameGetLines(frame) as? [CTLine], !lines.isEmpty else {
            return lineRenderer.characterIndex(at: max(0, xPosition), in: lineContent)
        }

        // 클릭한 래핑된 줄이 유효한지 확인
        let targetLineIndex = min(wrappedLineIndex, lines.count - 1)
        let ctLine = lines[targetLineIndex]

        // 해당 줄에서 문자 인덱스 계산
        let index = CTLineGetStringIndexForPosition(ctLine, CGPoint(x: max(0, xPosition), y: 0))
        return max(0, min(index, lineContent.count))
    }

    private func selectWordAtCursor() {
        // TODO: 단어 경계 찾기 구현
    }

    private func selectLineAtCursor() {
        let lineIndex = editorState.selection.cursor.line
        editorState.selection.selectLine(lineIndex, in: editorState.document)
        updateSelectedRange()
        needsDisplay = true
        notifyCursorChange()
    }

    // MARK: - Keyboard Events

    override func keyDown(with event: NSEvent) {
        // keyCode 51 = 백스페이스
        if event.keyCode == 51 {
            if event.modifierFlags.contains(.command) {
                // Cmd+백스페이스: 행 시작까지 삭제
                // 조합 중인 문자가 있으면 취소
                if hasMarkedText() {
                    unmarkText()
                }
                performDeleteToLineStart()
                return
            } else if event.modifierFlags.contains(.option) {
                // Option+백스페이스: 단어 단위 삭제
                // 조합 중인 문자가 있으면 취소
                if hasMarkedText() {
                    unmarkText()
                }
                performDeleteWordBackward()
                return
            }
        }

        // Option+방향키: 행 이동/복제
        // keyCode 126 = 위, 125 = 아래
        if event.modifierFlags.contains(.option) {
            let isShiftPressed = event.modifierFlags.contains(.shift)

            if event.keyCode == 126 {  // 위 화살표
                if isShiftPressed {
                    // Option+Shift+위: 행 위로 복제
                    performDuplicateLineUp()
                } else {
                    // Option+위: 행 위로 이동
                    performMoveLineUp()
                }
                return
            } else if event.keyCode == 125 {  // 아래 화살표
                if isShiftPressed {
                    // Option+Shift+아래: 행 아래로 복제
                    performDuplicateLineDown()
                } else {
                    // Option+아래: 행 아래로 이동
                    performMoveLineDown()
                }
                return
            }
        }

        // Cmd 키 조합 처리
        if event.modifierFlags.contains(.command) {
            let isShiftPressed = event.modifierFlags.contains(.shift)

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

            case "z":
                if isShiftPressed {
                    // Cmd+Shift+Z: Redo
                    performRedo()
                } else {
                    // Cmd+Z: Undo
                    performUndo()
                }
                return

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

        let cursorLine = editorState.selection.cursor.line
        let beforeCount = editorState.document.lineCount
        editorState.paste(text)
        let afterCount = editorState.document.lineCount

        // 변경된 행의 렌더링 캐시 무효화
        invalidateRenderCache(fromLine: cursorLine, toLine: cursorLine + (afterCount - beforeCount))

        updateSelectedRange()
        resetCursorBlink()
        needsDisplay = true

        notifyTextChange()
        notifyCursorChange()

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
        let cursorLine = editorState.selection.cursor.line
        invalidateRenderCache(fromLine: cursorLine, toLine: cursorLine)

        updateSelectedRange()
        resetCursorBlink()
        needsDisplay = true

        notifyTextChange()
        notifyCursorChange()
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
        let beforeCount = editorState.document.lineCount
        guard editorState.undo() else { return }

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
        let beforeCount = editorState.document.lineCount
        guard editorState.redo() else { return }

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
        let selection = editorState.selection
        let start = editorState.document.offsetFromPosition(
            line: selection.range.normalized.start.line,
            column: selection.range.normalized.start.column
        )
        let end = editorState.document.offsetFromPosition(
            line: selection.range.normalized.end.line,
            column: selection.range.normalized.end.column
        )
        _selectedRange = NSRange(location: start, length: end - start)
    }
}

// MARK: - NSTextInputClient

extension LoreTextView: NSTextInputClient {
    func insertText(_ string: Any, replacementRange: NSRange) {
        guard editorState.isEditable else { return }

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

        let cursorLine = editorState.selection.cursor.line
        let beforeCount = editorState.document.lineCount
        editorState.insertText(text)
        let afterCount = editorState.document.lineCount

        // 변경된 행의 렌더링 캐시 무효화
        invalidateRenderCache(fromLine: cursorLine, toLine: cursorLine + (afterCount - beforeCount))

        updateSelectedRange()
        resetCursorBlink()
        needsDisplay = true

        notifyTextChange()
        notifyCursorChange()

        if beforeCount != afterCount {
            onDocumentStructureChange?()
        }
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
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
            _markedRange = NSRange(location: self._selectedRange.location, length: markedString.count)
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
        _selectedRange
    }

    func markedRange() -> NSRange {
        _markedRange
    }

    func hasMarkedText() -> Bool {
        _markedText != nil && _markedText!.length > 0
    }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        let text = editorState.getText()
        guard range.location != NSNotFound,
              range.location >= 0,
              range.location + range.length <= text.count else {
            return nil
        }

        let start = text.index(text.startIndex, offsetBy: range.location)
        let end = text.index(start, offsetBy: range.length)
        let substring = String(text[start..<end])

        return NSAttributedString(string: substring, attributes: [
            .font: editorState.configuration.font
        ])
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        [.font, .foregroundColor, .backgroundColor]
    }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        let position = editorState.document.positionFromOffset(range.location)
        let singleLineHeight = lineRenderer.lineHeight
        let viewportWidth = bounds.width - textLeftPadding

        let lineContent = editorState.document.getLine(position.line) ?? ""
        let safeColumn = min(position.column, lineContent.count)

        // Word Wrap 활성화 시 캐시된 값 사용
        var y: CGFloat
        var cursorX: CGFloat

        if wordWrapEnabled && viewportWidth > 0 {
            // 현재 커서 위치와 일치하는 경우 캐시 사용
            let cursorLine = editorState.selection.cursor.line
            let cursorColumn = editorState.selection.cursor.column
            let cacheKey = "\(cursorLine):\(cursorColumn):\(Int(viewportWidth))"

            if position.line == cursorLine && safeColumn == cursorColumn && cacheKey == _cursorCacheKey {
                // 캐시된 값 사용: 행의 Y + 래핑된 줄 내 오프셋
                y = _cachedCursorLineY + CGFloat(_cachedWrappedLineIndex) * singleLineHeight
                cursorX = _cachedCursorXInLine
            } else if !lineContent.isEmpty {
                // 폴백: 직접 계산
                y = yPosition(for: position.line, viewportWidth: viewportWidth)

                let attributedString = NSAttributedString(string: lineContent, attributes: [
                    .font: editorState.configuration.font,
                    .foregroundColor: AppColors.nsEditorText
                ])
                let typesetter = CTTypesetterCreateWithAttributedString(attributedString)
                let stringLength = attributedString.length

                var tempStart = 0
                var offsetInLine = safeColumn

                while tempStart < stringLength {
                    let lineLength = CTTypesetterSuggestLineBreak(typesetter, tempStart, Double(viewportWidth))
                    guard lineLength > 0 else { break }

                    let lineEnd = tempStart + lineLength
                    let isLastLine = (lineEnd >= stringLength)

                    let inRange: Bool
                    if isLastLine {
                        inRange = safeColumn >= tempStart && safeColumn <= lineEnd
                    } else {
                        inRange = safeColumn >= tempStart && safeColumn < lineEnd
                    }

                    if inRange {
                        offsetInLine = safeColumn - tempStart
                        break
                    }

                    y += singleLineHeight
                    tempStart = lineEnd
                }

                let lineText = String(lineContent.dropFirst(tempStart).prefix(offsetInLine))
                cursorX = lineRenderer.measureWidth(of: lineText)
            } else {
                y = yPosition(for: position.line, viewportWidth: viewportWidth)
                cursorX = 0
            }
        } else {
            y = CGFloat(position.line) * singleLineHeight
            cursorX = lineRenderer.measureWidth(of: String(lineContent.prefix(safeColumn)))
        }

        let localPoint = CGPoint(x: textLeftPadding + cursorX, y: y + singleLineHeight)
        let screenPoint = window?.convertPoint(toScreen: convert(localPoint, to: nil)) ?? .zero

        return NSRect(x: screenPoint.x, y: screenPoint.y, width: 0, height: singleLineHeight)
    }

    func characterIndex(for point: NSPoint) -> Int {
        let localPoint = convert(point, from: nil)
        let position = textPositionAt(point: localPoint)
        return editorState.document.offsetFromPosition(line: position.line, column: position.column)
    }

    override func doCommand(by selector: Selector) {
        #if DEBUG
        print("[LoreTextView] doCommand: \(selector)")
        #endif

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

        if textChanged {
            notifyTextChange()
        }

        if structureChanged {
            onDocumentStructureChange?()
        }
    }
}
