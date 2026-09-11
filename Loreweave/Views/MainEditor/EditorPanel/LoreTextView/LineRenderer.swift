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
    var wrappedLines: [CTLine] = []
    var wrappedKey: Int?
    var lastUse: UInt64 = 0
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
        wrappedLines.removeAll()
        wrappedKey = nil
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

    /// 문자 간격 (kern)
    var letterSpacing: CGFloat = 0 {
        didSet {
            if letterSpacing != oldValue {
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
    private let maxCacheSize = 768
    private var cacheClock: UInt64 = 0

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
        let cache = getOrCreateCache(for: line)
        let key = computeCacheKey(content: line.content, width: viewportWidth)
        if cache.wrappedKey != key {
            let attributed = createAttributedString(line.content)
            let typesetter = CTTypesetterCreateWithAttributedString(attributed)
            var offset = 0
            cache.wrappedLines.removeAll(keepingCapacity: true)
            while offset < attributed.length {
                let length = CTTypesetterSuggestLineBreak(typesetter, offset, Double(viewportWidth))
                guard length > 0 else { break }
                cache.wrappedLines.append(CTTypesetterCreateLine(typesetter, CFRange(location: offset, length: length)))
                offset += length
            }
            cache.wrappedKey = key
        }
        for (row, ctLine) in cache.wrappedLines.enumerated() {
            drawLine(ctLine, at: CGPoint(x: origin.x, y: origin.y + CGFloat(row) * lineHeight), in: context)
        }
    }

    func renderComposition(before: String, marked: String, after: String,
                           at origin: CGPoint, in context: CGContext, viewportWidth: CGFloat) {
        let attributed = NSMutableAttributedString(attributedString: createAttributedString(before + marked + after))
        attributed.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue,
                                range: NSRange(location: before.utf16.count, length: marked.utf16.count))
        let typesetter = CTTypesetterCreateWithAttributedString(attributed)
        var offset = 0
        var row = 0
        while offset < attributed.length {
            let length = wordWrapEnabled && viewportWidth > 0
                ? CTTypesetterSuggestLineBreak(typesetter, offset, Double(viewportWidth))
                : attributed.length
            guard length > 0 else { break }
            let line = CTTypesetterCreateLine(typesetter, CFRange(location: offset, length: length))
            drawLine(line, at: CGPoint(x: origin.x, y: origin.y + CGFloat(row) * lineHeight), in: context)
            offset += length
            row += 1
        }
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

        let startOffset = content.utf16Offset(atCharacter: startCol)
        let endOffset = content.utf16Offset(atCharacter: endCol)
        let typesetter = CTTypesetterCreateWithAttributedString(createAttributedString(content))
        var offset = 0
        var visualRow = 0
        repeat {
            let length = wordWrapEnabled && viewportWidth > 0
                ? CTTypesetterSuggestLineBreak(typesetter, offset, Double(viewportWidth))
                : content.utf16.count
            let end = offset + length
            let selectedStart = max(offset, startOffset)
            let selectedEnd = min(end, endOffset)
            if selectedStart < selectedEnd || (lineIndex < normalized.end.line && end == content.utf16.count) {
                let ctLine = CTTypesetterCreateLine(typesetter, CFRange(location: offset, length: length))
                let x1 = CTLineGetOffsetForStringIndex(ctLine, selectedStart, nil)
                let x2 = lineIndex < normalized.end.line && end == content.utf16.count
                    ? viewportWidth : CTLineGetOffsetForStringIndex(ctLine, selectedEnd, nil)
                context.setFillColor(NSColor.selectedTextBackgroundColor.cgColor)
                context.fill(CGRect(x: origin.x + x1, y: origin.y + CGFloat(visualRow) * lineHeight,
                                    width: max(0, x2 - x1), height: lineHeight))
            }
            if length == 0 { break }
            offset = end
            visualRow += 1
        } while offset < content.utf16.count
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
        let rect = caretRect(in: line.content, column: column, viewportWidth: viewportWidth ?? 0)
        context.setFillColor(AppColors.nsEditorCursor.cgColor)
        context.fill(rect.offsetBy(dx: origin.x, dy: origin.y))
    }

    func caretRect(in content: String, column: Int, viewportWidth: CGFloat) -> CGRect {
        let utf16Column = content.utf16Offset(atCharacter: column)
        let typesetter = CTTypesetterCreateWithAttributedString(createAttributedString(content))
        var offset = 0
        var row = 0
        repeat {
            let length = wordWrapEnabled && viewportWidth > 0
                ? CTTypesetterSuggestLineBreak(typesetter, offset, Double(viewportWidth))
                : content.utf16.count
            let end = offset + length
            if utf16Column < end || end >= content.utf16.count || length == 0 {
                let line = CTTypesetterCreateLine(typesetter, CFRange(location: offset, length: length))
                let x = CTLineGetOffsetForStringIndex(line, utf16Column, nil)
                return CGRect(x: x, y: CGFloat(row) * lineHeight + 2, width: 2, height: max(1, lineHeight - 4))
            }
            offset = end
            row += 1
        } while offset <= content.utf16.count
        return CGRect(x: 0, y: 2, width: 2, height: max(1, lineHeight - 4))
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
        return text.characterOffset(atUTF16: index)
    }

    func characterIndex(at x: CGFloat, in text: String, visualRow: Int, viewportWidth: CGFloat) -> Int {
        guard !text.isEmpty, viewportWidth > 0 else { return characterIndex(at: x, in: text) }
        let typesetter = CTTypesetterCreateWithAttributedString(createAttributedString(text))
        var offset = 0
        var row = 0
        while offset < text.utf16.count {
            let length = CTTypesetterSuggestLineBreak(typesetter, offset, Double(viewportWidth))
            guard length > 0 else { break }
            if row >= max(0, visualRow) || offset + length >= text.utf16.count {
                let line = CTTypesetterCreateLine(typesetter, CFRange(location: offset, length: length))
                let hit = CTLineGetStringIndexForPosition(line, CGPoint(x: max(0, x), y: 0))
                return text.characterOffset(atUTF16: hit == kCFNotFound ? offset + length : hit)
            }
            offset += length
            row += 1
        }
        return text.count
    }

    // MARK: - Helpers

    private func createAttributedString(_ text: String) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = wordWrapEnabled ? .byWordWrapping : .byClipping

        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle
        ]

        // 문자 간격 적용 (0이 아닌 경우)
        if letterSpacing != 0 {
            attributes[.kern] = letterSpacing
        }

        return NSAttributedString(string: text, attributes: attributes)
    }

    private func computeCacheKey(content: String, width: CGFloat = 0) -> Int {
        var hasher = Hasher()
        hasher.combine(content)
        hasher.combine(font.pointSize)
        hasher.combine(textColor)
        hasher.combine(width)
        hasher.combine(wordWrapEnabled)
        hasher.combine(letterSpacing)
        return hasher.finalize()
    }

    // MARK: - Cache Management

    private func getOrCreateCache(for line: TextLine) -> LineRenderCache {
        cacheClock &+= 1
        if let cache = lineCache[line.id] {
            cache.lastUse = cacheClock
            return cache
        }

        // 캐시 크기 제한
        if lineCache.count >= maxCacheSize {
            let keysToRemove = lineCache.sorted { $0.value.lastUse < $1.value.lastUse }.prefix(maxCacheSize / 4).map { $0.key }
            for key in keysToRemove {
                lineCache.removeValue(forKey: key)
            }
        }

        let cache = LineRenderCache()
        cache.lastUse = cacheClock
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
