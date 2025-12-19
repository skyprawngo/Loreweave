//
//  EditorState+LineOps.swift
//  Loreweave
//
//  행 단위 작업 (이동, 복제)
//

import Foundation

// MARK: - Line Operations

extension EditorState {
    /// 현재 행을 위로 이동
    /// - Returns: 이동 성공 여부
    @discardableResult
    func moveLineUp() -> Bool {
        guard isEditable else { return false }

        let currentLine = selection.cursor.line
        guard currentLine > 0 else { return false }

        // Undo 액션 기록
        let currentContent = document.getLine(currentLine) ?? ""
        let aboveContent = document.getLine(currentLine - 1) ?? ""
        pushUndoAction(.swapLines(line1: currentLine - 1, line2: currentLine,
                                   content1: aboveContent, content2: currentContent))

        document.swapLines(currentLine, currentLine - 1)

        // 커서도 함께 이동
        selection.moveCursor(line: currentLine - 1, column: selection.cursor.column)
        checkModification()

        return true
    }

    /// 현재 행을 아래로 이동
    /// - Returns: 이동 성공 여부
    @discardableResult
    func moveLineDown() -> Bool {
        guard isEditable else { return false }

        let currentLine = selection.cursor.line
        guard currentLine < document.lineCount - 1 else { return false }

        // Undo 액션 기록
        let currentContent = document.getLine(currentLine) ?? ""
        let belowContent = document.getLine(currentLine + 1) ?? ""
        pushUndoAction(.swapLines(line1: currentLine, line2: currentLine + 1,
                                   content1: currentContent, content2: belowContent))

        document.swapLines(currentLine, currentLine + 1)

        // 커서도 함께 이동
        selection.moveCursor(line: currentLine + 1, column: selection.cursor.column)
        checkModification()

        return true
    }

    /// 현재 행을 위로 복제
    /// - Returns: 복제 성공 여부
    @discardableResult
    func duplicateLineUp() -> Bool {
        guard isEditable else { return false }

        let currentLine = selection.cursor.line

        // Undo 액션 기록 (삽입된 행 삭제)
        pushUndoAction(.deleteLine(at: currentLine))

        document.duplicateLine(at: currentLine)
        viewport.updateLineCount(document.lineCount)

        // 커서는 원래 위치 유지 (복제된 행이 위에 삽입되므로 현재 행 번호는 +1됨)
        checkModification()

        return true
    }

    /// 현재 행을 아래로 복제
    /// - Returns: 복제 성공 여부
    @discardableResult
    func duplicateLineDown() -> Bool {
        guard isEditable else { return false }

        let currentLine = selection.cursor.line

        // Undo 액션 기록 (삽입된 행 삭제)
        pushUndoAction(.deleteLine(at: currentLine + 1))

        document.duplicateLine(at: currentLine)
        viewport.updateLineCount(document.lineCount)

        // 커서를 복제된 행으로 이동
        selection.moveCursor(line: currentLine + 1, column: selection.cursor.column)
        checkModification()

        return true
    }
}
