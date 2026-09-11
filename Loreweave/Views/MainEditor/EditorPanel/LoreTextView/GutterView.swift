//
//  GutterView.swift
//  Loreweave
//
//  거터 뷰 - 줄번호 표시 영역
//  모든 행을 직접 렌더링 (스크롤은 부모가 담당)
//

import AppKit
import CoreText

// MARK: - Gutter View

/// 줄번호 표시 뷰
final class GutterView: NSView {
    /// 줄번호 폰트
    var font: NSFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular) {
        didSet {
            calculateWidth()
            calculateMetrics()
            needsDisplay = true
        }
    }

    /// 줄번호 색상
    var textColor: NSColor = .secondaryLabelColor

    /// 현재 줄 번호 색상
    var currentLineTextColor: NSColor = .labelColor

    /// 배경 색상
    var backgroundColor: NSColor = .clear

    /// 외부에서 변경된 줄 표시 색상 (AI 수정 등)
    var modifiedLineColor: NSColor = .systemOrange

    /// 외부에서 변경된 줄 번호들 (1-indexed)
    var externallyModifiedLines: Set<Int> = [] {
        didSet { needsDisplay = true }
    }

    /// 기본 줄 높이
    var lineHeight: CGFloat = 20 {
        didSet {
            calculateMetrics()
            needsDisplay = true
        }
    }

    /// 현재 커서가 있는 줄 번호
    var currentLine: Int = 1 {
        didSet { needsDisplay = true }
    }

    /// 총 줄 수 (너비 계산용)
    var totalLineCount: Int = 1 {
        didSet {
            calculateWidth()
            needsDisplay = true
        }
    }

    /// 거터 너비 (자동 계산)
    private(set) var gutterWidth: CGFloat = 40

    /// 좌우 패딩
    private let horizontalPadding: CGFloat = 12

    /// 최소 자릿수
    private let minDigits: Int = 3

    /// 기준선 오프셋 (행 상단에서 기준선까지)
    /// 외부에서 텍스트 뷰와 동일한 값을 설정해야 함
    var baselineOffset: CGFloat = 16 {
        didSet {
            needsDisplay = true
        }
    }

    /// 각 행의 높이를 반환하는 클로저 (Word Wrap 지원)
    var rowHeightProvider: ((Int) -> CGFloat)?

    /// 특정 행까지의 Y 위치를 반환하는 클로저 (Word Wrap 지원)
    var yPositionProvider: ((Int) -> CGFloat)?

    var lineIndexProvider: ((CGFloat) -> Int)?

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        calculateWidth()
        calculateMetrics()
    }

    // MARK: - Flipped Coordinate System

    override var isFlipped: Bool { true }

    // MARK: - Metrics

    /// 기본 baselineOffset 계산 (외부에서 설정되지 않은 경우 사용)
    private func calculateMetrics() {
        // 외부에서 baselineOffset이 설정되면 이 값은 무시됨
        // 호환성을 위해 기본값 계산은 유지
        let fontHeight = font.ascender - font.descender + font.leading
        let defaultLineHeight = ceil(fontHeight * 1.5)  // 기본 lineHeightMultiple
        let defaultBaselineOffset = ceil(font.ascender + (defaultLineHeight - fontHeight) / 2)
        // baselineOffset은 외부에서 설정될 예정이므로 여기서는 업데이트하지 않음
        _ = defaultBaselineOffset
    }

    // MARK: - Width Calculation

    private func calculateWidth() {
        let digits = max(minDigits, String(totalLineCount).count)
        let sampleText = String(repeating: "9", count: digits)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let textWidth = NSAttributedString(string: sampleText, attributes: attributes).size().width
        gutterWidth = ceil(textWidth + horizontalPadding * 2)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // 배경
        context.setFillColor(backgroundColor.cgColor)
        context.fill(bounds)

        // 구분선
        context.setStrokeColor(NSColor.separatorColor.cgColor)
        context.setLineWidth(1)
        context.move(to: CGPoint(x: bounds.width - 0.5, y: 0))
        context.addLine(to: CGPoint(x: bounds.width - 0.5, y: bounds.height))
        context.strokePath()

        guard totalLineCount > 0 else { return }

        // 동적 행 높이 지원 여부에 따라 렌더링 방식 결정
        if let rowHeightProvider = rowHeightProvider, let yPositionProvider = yPositionProvider {
            drawWithDynamicHeight(dirtyRect: dirtyRect, context: context, rowHeightProvider: rowHeightProvider, yPositionProvider: yPositionProvider)
        } else {
            drawWithFixedHeight(dirtyRect: dirtyRect, context: context)
        }
    }

    /// 고정 행 높이로 줄번호 그리기
    private func drawWithFixedHeight(dirtyRect: NSRect, context: CGContext) {
        guard lineHeight > 0 else { return }

        let startLine = max(0, Int(floor(dirtyRect.minY / lineHeight)))
        let endLine = min(totalLineCount - 1, Int(ceil(dirtyRect.maxY / lineHeight)))

        guard startLine <= endLine else { return }

        for lineIndex in startLine...endLine {
            let y = CGFloat(lineIndex) * lineHeight
            drawLineNumber(lineIndex: lineIndex, y: y, context: context)
        }
    }

    /// 동적 행 높이로 줄번호 그리기 (Word Wrap 지원)
    private func drawWithDynamicHeight(dirtyRect: NSRect, context: CGContext, rowHeightProvider: (Int) -> CGFloat, yPositionProvider: (Int) -> CGFloat) {
        let visible = dirtyRect.intersection(visibleRect)
        guard !visible.isEmpty, let lineIndexProvider else { return }
        let start = lineIndexProvider(visible.minY)
        let end = lineIndexProvider(visible.maxY)

        for lineIndex in start...end {
            let y = yPositionProvider(lineIndex)
            drawLineNumber(lineIndex: lineIndex, y: y, context: context)
        }
    }

    /// 줄번호 하나 그리기
    private func drawLineNumber(lineIndex: Int, y: CGFloat, context: CGContext) {
        let lineNumber = lineIndex + 1
        let lineNumberString = "\(lineNumber)"
        let isCurrentLine = lineNumber == currentLine
        let isModified = externallyModifiedLines.contains(lineNumber)

        // 외부 변경 표시 (줄번호 오른쪽에 주황색 바)
        if isModified {
            let barWidth: CGFloat = 3
            let barX = gutterWidth - barWidth - 1  // 구분선 바로 왼쪽
            let rowHeight = rowHeightProvider?(lineIndex) ?? lineHeight
            let barRect = CGRect(x: barX, y: y, width: barWidth, height: rowHeight)

            context.setFillColor(modifiedLineColor.cgColor)
            context.fill(barRect)
        }

        let color = isCurrentLine ? currentLineTextColor : textColor

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]

        let attrString = NSAttributedString(string: lineNumberString, attributes: attributes)
        let textSize = attrString.size()

        // X 위치: 오른쪽 정렬 (변경 표시 바 공간 확보)
        let x = gutterWidth - textSize.width - horizontalPadding - (isModified ? 4 : 0)

        // Core Text로 렌더링
        context.saveGState()
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = CGPoint(x: x, y: y + baselineOffset)

        let ctLine = CTLineCreateWithAttributedString(attrString)
        CTLineDraw(ctLine, context)

        context.restoreGState()
    }

    // MARK: - Mouse Events

    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let clickedLine = lineNumberAt(y: location.y)
        NotificationCenter.default.post(
            name: .gutterLineClicked,
            object: self,
            userInfo: ["lineNumber": clickedLine]
        )
    }

    private func lineNumberAt(y: CGFloat) -> Int {
        if let lineIndexProvider { return lineIndexProvider(y) + 1 }

        // 고정 높이
        guard lineHeight > 0 else { return 1 }
        let lineIndex = Int(floor(y / lineHeight))
        return min(max(lineIndex + 1, 1), totalLineCount)
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let gutterLineClicked = Notification.Name("gutterLineClicked")
}
