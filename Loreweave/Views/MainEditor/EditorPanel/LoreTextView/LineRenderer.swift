//
//  LineRenderer.swift
//  Loreweave
//
//  행 렌더링 - 개별 텍스트 행을 Core Text로 렌더링
//  Word Wrap 지원
//

import AppKit
import CoreText

// MARK: - Line Render Cache

/// 행 렌더링 캐시
final class LineRenderCache {
    /// CTFrame 캐시 (Word Wrap 지원)
    var ctFrame: CTFrame?
    /// CTLine 캐시 (단일 행)
    var ctLine: CTLine?
    /// 렌더링된 너비
    var width: CGFloat = 0
    /// 렌더링된 높이 (Word Wrap 시 여러 줄 높이)
    var height: CGFloat = 0
    /// 래핑된 줄 수
    var wrappedLineCount: Int = 1
    /// 캐시 키 (내용 + 설정 + 너비 해시)
    var cacheKey: Int = 0

    func invalidate() {
        ctFrame = nil
        ctLine = nil
        cacheKey = 0
        wrappedLineCount = 1
    }
}

// MARK: - Line Renderer

/// 행 렌더링 담당
final class LineRenderer {
    /// 폰트
    var font: NSFont {
        didSet {
            if font != oldValue {
                invalidateAllCache()
                calculateMetrics()
            }
        }
    }

    /// 텍스트 색상
    var textColor: NSColor = AppColors.nsEditorText

    /// 줄 높이 배수
    var lineHeightMultiple: CGFloat = 1.5 {
        didSet {
            if lineHeightMultiple != oldValue {
                invalidateAllCache()
                calculateMetrics()
            }
        }
    }

    /// Word Wrap 활성화
    var wordWrapEnabled: Bool = true {
        didSet {
            if wordWrapEnabled != oldValue {
                invalidateAllCache()
            }
        }
    }

    /// 계산된 기본 행 높이 (단일 줄)
    private(set) var lineHeight: CGFloat = 20

    /// 기준선 오프셋 (행 상단에서 기준선까지)
    private(set) var baselineOffset: CGFloat = 16

    /// 행별 렌더링 캐시
    private var lineCache: [UUID: LineRenderCache] = [:]

    /// 최대 캐시 크기
    private let maxCacheSize = 500

    // MARK: - Initialization

    init(font: NSFont) {
        self.font = font
        calculateMetrics()
    }

    // MARK: - Metrics

    private func calculateMetrics() {
        let fontHeight = font.ascender - font.descender + font.leading
        lineHeight = ceil(fontHeight * lineHeightMultiple)
        baselineOffset = ceil(font.ascender + (lineHeight - fontHeight) / 2)
    }

    // MARK: - Height Calculation

    /// 행의 실제 높이 계산 (Word Wrap 포함)
    func calculateHeight(for line: TextLine, viewportWidth: CGFloat) -> CGFloat {
        guard wordWrapEnabled, viewportWidth > 0 else {
            return lineHeight
        }

        let cache = getOrCreateCache(for: line)
        let cacheKey = computeCacheKey(content: line.content, width: viewportWidth)

        // 캐시가 유효하면 재사용
        if cache.cacheKey == cacheKey && cache.height > 0 {
            return cache.height
        }

        // 빈 줄은 기본 높이
        guard !line.content.isEmpty else {
            cache.height = lineHeight
            cache.wrappedLineCount = 1
            cache.cacheKey = cacheKey
            return lineHeight
        }

        // CTTypesetter로 래핑된 줄 수 계산 (렌더링과 동일한 방식)
        let attributedString = createAttributedString(line.content)
        let typesetter = CTTypesetterCreateWithAttributedString(attributedString)
        let stringLength = attributedString.length

        var startIndex = 0
        var wrappedLines = 0

        while startIndex < stringLength {
            let lineLength = CTTypesetterSuggestLineBreak(typesetter, startIndex, Double(viewportWidth))
            guard lineLength > 0 else { break }
            startIndex += lineLength
            wrappedLines += 1
        }

        wrappedLines = max(1, wrappedLines)

        let totalHeight = CGFloat(wrappedLines) * lineHeight

        cache.height = totalHeight
        cache.wrappedLineCount = wrappedLines
        cache.cacheKey = cacheKey

        return totalHeight
    }

    // MARK: - Rendering

    /// 행 렌더링 (Word Wrap 지원)
    func render(
        line: TextLine,
        at origin: CGPoint,
        in context: CGContext,
        viewportWidth: CGFloat
    ) {
        let content = line.content

        // 빈 줄은 렌더링 불필요
        guard !content.isEmpty else { return }

        if wordWrapEnabled && viewportWidth > 0 {
            renderWrapped(line: line, at: origin, in: context, viewportWidth: viewportWidth)
        } else {
            renderSingleLine(line: line, at: origin, in: context)
        }
    }

    /// 단일 행 렌더링
    private func renderSingleLine(line: TextLine, at origin: CGPoint, in context: CGContext) {
        let cache = getOrCreateCache(for: line)
        let cacheKey = computeCacheKey(content: line.content, width: 0)

        var ctLine: CTLine

        if cache.cacheKey == cacheKey, let cached = cache.ctLine {
            ctLine = cached
        } else {
            let attributedString = createAttributedString(line.content)
            ctLine = CTLineCreateWithAttributedString(attributedString)
            cache.ctLine = ctLine
            cache.cacheKey = cacheKey
            cache.height = lineHeight
            cache.wrappedLineCount = 1
        }

        drawLine(ctLine, at: origin, in: context)
    }

    /// Word Wrap 렌더링
    private func renderWrapped(
        line: TextLine,
        at origin: CGPoint,
        in context: CGContext,
        viewportWidth: CGFloat
    ) {
        let attributedString = createAttributedString(line.content)

        // CTTypesetter를 사용하여 각 줄을 직접 생성
        let typesetter = CTTypesetterCreateWithAttributedString(attributedString)
        let stringLength = attributedString.length

        context.saveGState()
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)

        var startIndex = 0
        var wrappedLineIndex = 0

        while startIndex < stringLength {
            // 해당 너비에 맞는 줄 길이 계산
            let lineLength = CTTypesetterSuggestLineBreak(typesetter, startIndex, Double(viewportWidth))
            guard lineLength > 0 else { break }

            // CTLine 생성
            let ctLine = CTTypesetterCreateLine(typesetter, CFRange(location: startIndex, length: lineLength))

            // 해당 줄 그리기
            let lineY = origin.y + CGFloat(wrappedLineIndex) * lineHeight + baselineOffset
            context.textPosition = CGPoint(x: origin.x, y: lineY)
            CTLineDraw(ctLine, context)

            startIndex += lineLength
            wrappedLineIndex += 1
        }

        context.restoreGState()
    }

    /// CTLine 그리기
    private func drawLine(_ ctLine: CTLine, at origin: CGPoint, in context: CGContext) {
        context.saveGState()

        // 기준선 위치 계산
        let textY = origin.y + baselineOffset

        // isFlipped = true인 NSView에서 Core Text 사용 시 텍스트 매트릭스 반전 필요
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = CGPoint(x: origin.x, y: textY)
        CTLineDraw(ctLine, context)

        context.restoreGState()
    }

    /// 선택 영역 렌더링
    func renderSelection(
        line: TextLine,
        lineIndex: Int,
        selection: TextRange,
        at origin: CGPoint,
        in context: CGContext,
        viewportWidth: CGFloat
    ) {
        let normalized = selection.normalized
        guard lineIndex >= normalized.start.line && lineIndex <= normalized.end.line else { return }

        let content = line.content
        let lineLength = content.count
        let rowHeight = wordWrapEnabled ? calculateHeight(for: line, viewportWidth: viewportWidth) : lineHeight

        // 이 행에서 선택된 범위 계산
        let startCol: Int
        let endCol: Int

        if lineIndex == normalized.start.line && lineIndex == normalized.end.line {
            startCol = min(normalized.start.column, lineLength)
            endCol = min(normalized.end.column, lineLength)
        } else if lineIndex == normalized.start.line {
            startCol = min(normalized.start.column, lineLength)
            endCol = lineLength
        } else if lineIndex == normalized.end.line {
            startCol = 0
            endCol = min(normalized.end.column, lineLength)
        } else {
            startCol = 0
            endCol = lineLength
        }

        guard startCol < endCol || (lineIndex != normalized.end.line && startCol == endCol) else { return }

        // 선택 영역 x 좌표 계산
        let startX = measureWidth(of: String(content.prefix(startCol)))
        let endX: CGFloat

        if endCol >= lineLength && lineIndex < normalized.end.line {
            endX = max(measureWidth(of: content), viewportWidth)
        } else {
            endX = measureWidth(of: String(content.prefix(endCol)))
        }

        // 선택 영역 그리기
        let selectionRect = CGRect(
            x: origin.x + startX,
            y: origin.y,
            width: max(0, endX - startX),
            height: rowHeight
        )

        context.setFillColor(NSColor.selectedTextBackgroundColor.cgColor)
        context.fill(selectionRect)
    }

    /// 현재 줄 하이라이트 렌더링
    func renderCurrentLineHighlight(
        at origin: CGPoint,
        in context: CGContext,
        viewportWidth: CGFloat,
        height: CGFloat? = nil
    ) {
        let highlightHeight = height ?? lineHeight
        let highlightRect = CGRect(
            x: 0,
            y: origin.y,
            width: viewportWidth,
            height: highlightHeight
        )

        context.setFillColor(AppColors.nsCurrentLineHighlight.cgColor)
        context.fill(highlightRect)
    }

    /// 커서 렌더링 (Word Wrap 지원)
    func renderCursor(
        line: TextLine,
        column: Int,
        at origin: CGPoint,
        in context: CGContext,
        rowHeight: CGFloat? = nil,
        viewportWidth: CGFloat? = nil
    ) {
        let content = line.content

        // Word Wrap 활성화 시, 커서가 위치한 래핑된 줄을 찾아야 함
        if wordWrapEnabled, let vw = viewportWidth, vw > 0, !content.isEmpty {
            let attributedString = createAttributedString(content)
            let typesetter = CTTypesetterCreateWithAttributedString(attributedString)
            let stringLength = attributedString.length

            // CTTypesetter로 각 래핑된 줄의 범위 계산
            let cursorColumn = min(column, content.count)
            var wrappedLineIndex = 0
            var cursorXInLine: CGFloat = 0
            var found = false

            // 모든 래핑된 줄의 범위를 먼저 계산
            var lineRanges: [(start: Int, end: Int)] = []
            var tempStart = 0
            while tempStart < stringLength {
                let lineLength = CTTypesetterSuggestLineBreak(typesetter, tempStart, Double(vw))
                guard lineLength > 0 else { break }
                lineRanges.append((start: tempStart, end: tempStart + lineLength))
                tempStart += lineLength
            }

            // 커서가 위치한 래핑된 줄 찾기
            for (index, range) in lineRanges.enumerated() {
                let isLastLine = (index == lineRanges.count - 1)

                // 마지막 줄이면 끝 위치 포함, 아니면 끝 위치 제외
                // (줄 끝에서 Enter나 타이핑 시 다음 래핑된 줄의 시작으로 이동)
                let inRange: Bool
                if isLastLine {
                    inRange = cursorColumn >= range.start && cursorColumn <= range.end
                } else {
                    inRange = cursorColumn >= range.start && cursorColumn < range.end
                }

                if inRange {
                    wrappedLineIndex = index
                    // 해당 줄 내에서 커서 X 위치 계산
                    let offsetInLine = cursorColumn - range.start
                    let lineText = String(content.dropFirst(range.start).prefix(offsetInLine))
                    cursorXInLine = measureWidth(of: lineText)
                    found = true
                    break
                }
            }

            // 커서 위치를 찾지 못한 경우 (문자열 끝) - 마지막 줄의 끝에 배치
            if !found {
                if let lastRange = lineRanges.last {
                    wrappedLineIndex = lineRanges.count - 1
                    let offsetInLine = cursorColumn - lastRange.start
                    let lineText = String(content.dropFirst(lastRange.start).prefix(max(0, offsetInLine)))
                    cursorXInLine = measureWidth(of: lineText)
                } else {
                    // 줄이 없으면 원점에 커서 표시
                    cursorXInLine = 0
                }
            }

            // 커서 Y 위치: 래핑된 줄 인덱스에 따라 오프셋
            let cursorY = origin.y + CGFloat(wrappedLineIndex) * lineHeight

            let cursorRect = CGRect(
                x: origin.x + cursorXInLine,
                y: cursorY + 2,
                width: 2,
                height: lineHeight - 4
            )

            context.setFillColor(AppColors.nsEditorCursor.cgColor)
            context.fill(cursorRect)
        } else {
            // Word Wrap 비활성화 또는 빈 줄: 기존 로직
            let cursorX = measureWidth(of: String(content.prefix(min(column, content.count))))
            let height = rowHeight ?? lineHeight

            let cursorRect = CGRect(
                x: origin.x + cursorX,
                y: origin.y + 2,
                width: 2,
                height: height - 4
            )

            context.setFillColor(AppColors.nsEditorCursor.cgColor)
            context.fill(cursorRect)
        }
    }

    // MARK: - Measurement

    /// 텍스트 너비 측정
    func measureWidth(of text: String) -> CGFloat {
        guard !text.isEmpty else { return 0 }

        let attributedString = createAttributedString(text)
        let ctLine = CTLineCreateWithAttributedString(attributedString)
        let bounds = CTLineGetBoundsWithOptions(ctLine, [])
        return ceil(bounds.width)
    }

    /// 특정 x 좌표에서 문자 인덱스 찾기
    func characterIndex(at xPosition: CGFloat, in text: String) -> Int {
        guard !text.isEmpty else { return 0 }

        let attributedString = createAttributedString(text)
        let ctLine = CTLineCreateWithAttributedString(attributedString)

        let index = CTLineGetStringIndexForPosition(ctLine, CGPoint(x: xPosition, y: 0))
        return max(0, min(index, text.count))
    }

    // MARK: - Helpers

    private func createAttributedString(_ text: String) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = wordWrapEnabled ? .byWordWrapping : .byClipping

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle
        ]
        return NSAttributedString(string: text, attributes: attributes)
    }

    private func computeCacheKey(content: String, width: CGFloat = 0) -> Int {
        var hasher = Hasher()
        hasher.combine(content)
        hasher.combine(font.pointSize)
        hasher.combine(textColor)
        hasher.combine(Int(width))
        hasher.combine(wordWrapEnabled)
        return hasher.finalize()
    }

    // MARK: - Cache Management

    private func getOrCreateCache(for line: TextLine) -> LineRenderCache {
        if let cache = lineCache[line.id] {
            return cache
        }

        // 캐시 크기 제한
        if lineCache.count >= maxCacheSize {
            let keysToRemove = Array(lineCache.keys.prefix(maxCacheSize / 2))
            for key in keysToRemove {
                lineCache.removeValue(forKey: key)
            }
        }

        let cache = LineRenderCache()
        lineCache[line.id] = cache
        return cache
    }

    func invalidateCache(for lineId: UUID) {
        lineCache[lineId]?.invalidate()
    }

    func invalidateAllCache() {
        lineCache.removeAll()
    }

    func removeCache(for lineId: UUID) {
        lineCache.removeValue(forKey: lineId)
    }
}
