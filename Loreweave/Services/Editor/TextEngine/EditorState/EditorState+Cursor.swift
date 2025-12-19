//
//  EditorState+Cursor.swift
//  Loreweave
//
//  커서 이동 및 선택 작업
//

import Foundation

// MARK: - Cursor Movement

extension EditorState {
    /// 커서 왼쪽 이동
    func moveCursorLeft(extendSelection: Bool = false) {
        var newPosition = selection.cursor

        if newPosition.column > 0 {
            newPosition.column -= 1
        } else if newPosition.line > 0 {
            newPosition.line -= 1
            newPosition.column = document.getLine(newPosition.line)?.count ?? 0
        }

        if extendSelection {
            selection.extendSelection(to: newPosition)
        } else {
            selection.moveCursor(to: newPosition)
        }
        ensureCursorVisible()
    }

    /// 커서 오른쪽 이동
    func moveCursorRight(extendSelection: Bool = false) {
        var newPosition = selection.cursor
        let lineLength = document.getLine(newPosition.line)?.count ?? 0

        if newPosition.column < lineLength {
            newPosition.column += 1
        } else if newPosition.line < max(0, document.lineCount - 1) {
            newPosition.line += 1
            newPosition.column = 0
        }

        if extendSelection {
            selection.extendSelection(to: newPosition)
        } else {
            selection.moveCursor(to: newPosition)
        }
        ensureCursorVisible()
    }

    /// 커서 위로 이동
    func moveCursorUp(extendSelection: Bool = false) {
        var newPosition = selection.cursor

        if newPosition.line > 0 {
            newPosition.line -= 1
            let lineLength = document.getLine(newPosition.line)?.count ?? 0
            newPosition.column = min(newPosition.column, lineLength)
        } else {
            newPosition.column = 0
        }

        if extendSelection {
            selection.extendSelection(to: newPosition)
        } else {
            selection.moveCursor(to: newPosition)
        }
        ensureCursorVisible()
    }

    /// 커서 아래로 이동
    func moveCursorDown(extendSelection: Bool = false) {
        var newPosition = selection.cursor

        if newPosition.line < max(0, document.lineCount - 1) {
            newPosition.line += 1
            let lineLength = document.getLine(newPosition.line)?.count ?? 0
            newPosition.column = min(newPosition.column, lineLength)
        } else {
            newPosition.column = document.getLine(newPosition.line)?.count ?? 0
        }

        if extendSelection {
            selection.extendSelection(to: newPosition)
        } else {
            selection.moveCursor(to: newPosition)
        }
        ensureCursorVisible()
    }

    /// 행 시작으로 이동
    func moveCursorToLineStart(extendSelection: Bool = false) {
        let newPosition = TextPosition(line: selection.cursor.line, column: 0)

        if extendSelection {
            selection.extendSelection(to: newPosition)
        } else {
            selection.moveCursor(to: newPosition)
        }
    }

    /// 행 끝으로 이동
    func moveCursorToLineEnd(extendSelection: Bool = false) {
        let lineLength = document.getLine(selection.cursor.line)?.count ?? 0
        let newPosition = TextPosition(line: selection.cursor.line, column: lineLength)

        if extendSelection {
            selection.extendSelection(to: newPosition)
        } else {
            selection.moveCursor(to: newPosition)
        }
    }

    /// 문서 시작으로 이동
    func moveCursorToDocumentStart(extendSelection: Bool = false) {
        if extendSelection {
            selection.extendSelection(to: .zero)
        } else {
            selection.moveCursor(to: .zero)
        }
        ensureCursorVisible()
    }

    /// 문서 끝으로 이동
    func moveCursorToDocumentEnd(extendSelection: Bool = false) {
        let lastLine = max(0, document.lineCount - 1)
        let lastColumn = document.getLine(lastLine)?.count ?? 0
        let newPosition = TextPosition(line: lastLine, column: lastColumn)

        if extendSelection {
            selection.extendSelection(to: newPosition)
        } else {
            selection.moveCursor(to: newPosition)
        }
        ensureCursorVisible()
    }

    /// 전체 선택
    func selectAll() {
        selection.selectAll(document: document)
    }

    // MARK: - Scroll & Visibility

    /// 커서가 보이도록 스크롤
    func ensureCursorVisible() {
        viewport.scrollToLine(selection.cursor.line, position: .nearest)
    }

    /// 특정 행으로 스크롤
    func scrollToLine(_ lineIndex: Int) {
        viewport.scrollToLine(lineIndex, position: .center)
    }
}
