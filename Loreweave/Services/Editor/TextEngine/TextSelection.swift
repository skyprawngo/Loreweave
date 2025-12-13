//
//  TextSelection.swift
//  Loreweave
//
//  텍스트 선택 및 커서 관리
//

import Foundation

// MARK: - Text Position

/// 문서 내 위치 (행, 열)
struct TextPosition: Equatable, Comparable {
    var line: Int
    var column: Int

    static func < (lhs: TextPosition, rhs: TextPosition) -> Bool {
        if lhs.line != rhs.line {
            return lhs.line < rhs.line
        }
        return lhs.column < rhs.column
    }

    static let zero = TextPosition(line: 0, column: 0)
}

// MARK: - Text Range

/// 문서 내 범위 (시작 ~ 끝)
struct TextRange: Equatable {
    var start: TextPosition
    var end: TextPosition

    /// 범위가 비어있는지 (커서만 있는 상태)
    var isEmpty: Bool {
        start == end
    }

    /// 정규화된 범위 (start가 항상 end보다 앞)
    var normalized: TextRange {
        if start > end {
            return TextRange(start: end, end: start)
        }
        return self
    }

    /// 단일 위치 (커서)
    static func cursor(at position: TextPosition) -> TextRange {
        TextRange(start: position, end: position)
    }

    /// 단일 위치 (행, 열)
    static func cursor(line: Int, column: Int) -> TextRange {
        let pos = TextPosition(line: line, column: column)
        return TextRange(start: pos, end: pos)
    }
}

// MARK: - Text Selection

/// 텍스트 선택 상태
final class TextSelection {
    /// 현재 선택 범위 (커서 위치 포함)
    var range: TextRange = .cursor(at: .zero)

    /// 선택 앵커 (Shift+방향키 선택 시 고정점)
    var anchor: TextPosition?

    /// 커서 위치 (선택 범위의 끝점)
    var cursor: TextPosition {
        get { range.end }
        set { range = .cursor(at: newValue) }
    }

    /// 선택 영역이 있는지
    var hasSelection: Bool {
        !range.isEmpty
    }

    /// 선택된 행 범위 (시작 행 ~ 끝 행)
    var selectedLineRange: ClosedRange<Int>? {
        guard hasSelection else { return nil }
        let normalized = range.normalized
        return normalized.start.line...normalized.end.line
    }

    /// 커서가 있는 행
    var cursorLine: Int {
        cursor.line
    }

    // MARK: - Selection Operations

    /// 커서 이동 (선택 해제)
    func moveCursor(to position: TextPosition) {
        range = .cursor(at: position)
        anchor = nil
    }

    /// 커서 이동 (행, 열)
    func moveCursor(line: Int, column: Int) {
        moveCursor(to: TextPosition(line: line, column: column))
    }

    /// 선택 확장 (Shift+이동)
    func extendSelection(to position: TextPosition) {
        if anchor == nil {
            anchor = range.start
        }
        range = TextRange(start: anchor!, end: position)
    }

    /// 범위 선택
    func select(from start: TextPosition, to end: TextPosition) {
        range = TextRange(start: start, end: end)
        anchor = start
    }

    /// 전체 선택
    func selectAll(document: TextDocument) {
        guard document.lineCount > 0 else {
            moveCursor(to: .zero)
            return
        }
        let lastLine = max(0, document.lineCount - 1)
        let lastColumn = document.getLine(lastLine)?.count ?? 0
        select(
            from: .zero,
            to: TextPosition(line: lastLine, column: lastColumn)
        )
    }

    /// 행 선택
    func selectLine(_ lineIndex: Int, in document: TextDocument) {
        guard lineIndex >= 0 && lineIndex < document.lineCount else { return }
        let lineLength = document.getLine(lineIndex)?.count ?? 0
        select(
            from: TextPosition(line: lineIndex, column: 0),
            to: TextPosition(line: lineIndex, column: lineLength)
        )
    }

    /// 선택 해제
    func clearSelection() {
        if hasSelection {
            range = .cursor(at: range.normalized.end)
        }
        anchor = nil
    }

    // MARK: - Position Validation

    /// 위치를 문서 범위 내로 제한
    func clampPosition(_ position: TextPosition, in document: TextDocument) -> TextPosition {
        guard document.lineCount > 0 else { return .zero }

        var clamped = position

        // 행 범위 제한
        clamped.line = max(0, min(position.line, document.lineCount - 1))

        // 열 범위 제한
        let lineLength = document.getLine(clamped.line)?.count ?? 0
        clamped.column = max(0, min(position.column, lineLength))

        return clamped
    }

    /// 현재 선택을 문서 범위 내로 조정
    func clampToDocument(_ document: TextDocument) {
        range.start = clampPosition(range.start, in: document)
        range.end = clampPosition(range.end, in: document)
        if let a = anchor {
            anchor = clampPosition(a, in: document)
        }
    }
}
