//
//  EditorState+UndoRedo.swift
//  Loreweave
//
//  Undo/Redo 작업 처리
//

import Foundation

// MARK: - Undo/Redo Operations

extension EditorState {
    /// Undo 실행
    @discardableResult
    func undo() -> Bool {
        // 대기 중인 그룹이 있으면 먼저 커밋
        commitPendingTextGroup()

        guard canUndo else { return false }

        let action = undoStack.removeLast()
        applyUndoAction(action, isRedo: false)

        return true
    }

    /// Redo 실행
    @discardableResult
    func redo() -> Bool {
        // 대기 중인 그룹이 있으면 먼저 커밋
        commitPendingTextGroup()

        guard canRedo else { return false }

        let action = redoStack.removeLast()
        applyUndoAction(action, isRedo: true)

        return true
    }

    /// Undo 스택에 액션 추가
    func pushUndoAction(_ action: UndoAction) {
        // 대기 중인 텍스트 그룹이 있으면 먼저 커밋
        commitPendingTextGroup()

        undoStack.append(action)
        redoStack.removeAll()  // 새 액션이 추가되면 Redo 스택 초기화

        // 100개 제한 적용
        trimUndoStackIfNeeded()
    }

    /// Undo 스택이 100개를 초과하면 오래된 항목 제거
    func trimUndoStackIfNeeded() {
        while undoStack.count > maxUndoHistoryCount {
            undoStack.removeFirst()
        }
    }

    /// 대기 중인 텍스트 그룹을 Undo 스택에 커밋
    func commitPendingTextGroup() {
        guard let group = pendingTextGroup else { return }

        let action = UndoAction.replaceText(
            startLine: group.startLine,
            startColumn: group.startColumn,
            endLine: group.startLine,  // 삽입 전 위치이므로 시작 위치와 동일
            endColumn: group.startColumn,
            oldText: "",
            newText: group.insertedText
        )
        undoStack.append(action)
        pendingTextGroup = nil

        trimUndoStackIfNeeded()
    }

    /// 텍스트 입력을 그룹에 추가 (연속 타이핑 그룹화)
    func addToTextGroup(text: String, atLine line: Int, column: Int, newEndLine: Int, newEndColumn: Int) {
        guard let firstChar = text.first else { return }
        let charType = CharacterType.from(firstChar)

        // 기존 그룹이 있고, 같은 타입이며, 연속된 위치라면 그룹에 추가
        if var group = pendingTextGroup,
           group.lastCharacterType.canGroupWith(charType),
           group.endLine == line,
           group.endColumn == column {
            group.insertedText += text
            group.endLine = newEndLine
            group.endColumn = newEndColumn
            group.lastCharacterType = CharacterType.from(text.last ?? firstChar)
            pendingTextGroup = group
        } else {
            // 기존 그룹 커밋 후 새 그룹 시작
            commitPendingTextGroup()

            pendingTextGroup = PendingTextGroup(
                startLine: line,
                startColumn: column,
                endLine: newEndLine,
                endColumn: newEndColumn,
                insertedText: text,
                lastCharacterType: CharacterType.from(text.last ?? firstChar)
            )
        }

        redoStack.removeAll()
    }

    /// 삭제 작업을 위한 Undo 액션 기록
    func recordDeleteAction(
        fromLine: Int, fromColumn: Int,
        toLine: Int, toColumn: Int,
        deletedText: String
    ) {
        // 대기 중인 그룹 커밋
        commitPendingTextGroup()

        let action = UndoAction.replaceText(
            startLine: fromLine,
            startColumn: fromColumn,
            endLine: toLine,
            endColumn: toColumn,
            oldText: deletedText,
            newText: ""
        )
        pushUndoAction(action)
    }

    /// Undo/Redo 액션 적용
    func applyUndoAction(_ action: UndoAction, isRedo: Bool) {
        switch action {
        case .swapLines(let line1, let line2, let content1, let content2):
            // Swap은 역연산도 동일 (다시 swap)
            document.swapLines(line1, line2)

            // 역액션을 반대 스택에 추가
            let reverseAction = UndoAction.swapLines(line1: line1, line2: line2,
                                                      content1: content2, content2: content1)
            if isRedo {
                undoStack.append(reverseAction)
            } else {
                redoStack.append(reverseAction)
            }

            // 커서 위치 조정 (스왑된 행 중 하나에 있었다면)
            if selection.cursor.line == line1 {
                selection.moveCursor(line: line2, column: selection.cursor.column)
            } else if selection.cursor.line == line2 {
                selection.moveCursor(line: line1, column: selection.cursor.column)
            }

        case .deleteLine(let index):
            // 행 삭제 (복제 Undo 시)
            let deletedContent = document.getLine(index) ?? ""
            document.removeLine(at: index)
            viewport.updateLineCount(document.lineCount)

            // 역액션: 해당 위치에 행 삽입
            let reverseAction = UndoAction.insertLine(at: index, content: deletedContent)
            if isRedo {
                undoStack.append(reverseAction)
            } else {
                redoStack.append(reverseAction)
            }

            // 커서 위치 조정
            if selection.cursor.line >= index {
                let newLine = max(0, selection.cursor.line - 1)
                let lineLength = document.getLine(newLine)?.count ?? 0
                selection.moveCursor(line: newLine, column: min(selection.cursor.column, lineLength))
            }

        case .insertLine(let index, let content):
            // 행 삽입 (복제 Redo 시)
            document.insertLine(content, at: index)
            viewport.updateLineCount(document.lineCount)

            // 역액션: 해당 행 삭제
            let reverseAction = UndoAction.deleteLine(at: index)
            if isRedo {
                undoStack.append(reverseAction)
            } else {
                redoStack.append(reverseAction)
            }

            // 커서 위치 조정
            if selection.cursor.line >= index {
                selection.moveCursor(line: selection.cursor.line + 1, column: selection.cursor.column)
            }

        case .replaceText(let startLine, let startColumn, let endLine, let endColumn, let oldText, let newText):
            // 텍스트 대체
            let textToRestore = isRedo ? newText : oldText

            // 현재 텍스트 삭제 후 복원
            document.delete(fromLine: startLine, column: startColumn, toLine: endLine, column: endColumn)
            document.insert(textToRestore, atLine: startLine, column: startColumn)
            viewport.updateLineCount(document.lineCount)

            // 역액션
            let reverseAction = UndoAction.replaceText(
                startLine: startLine, startColumn: startColumn,
                endLine: endLine, endColumn: endColumn,
                oldText: newText, newText: oldText
            )
            if isRedo {
                undoStack.append(reverseAction)
            } else {
                redoStack.append(reverseAction)
            }

            // 커서를 변경된 텍스트 끝으로 이동
            let insertedLines = textToRestore.components(separatedBy: "\n")
            if insertedLines.count == 1 {
                selection.moveCursor(line: startLine, column: startColumn + textToRestore.count)
            } else {
                let lastLine = startLine + insertedLines.count - 1
                selection.moveCursor(line: lastLine, column: insertedLines.last?.count ?? 0)
            }
        }

        checkModification()
    }

    /// Undo 스택 초기화
    func clearUndoHistory() {
        pendingTextGroup = nil
        undoStack.removeAll()
        redoStack.removeAll()
    }
}
