//
//  EditorState+Editing.swift
//  TextlinkEditor
//
//  텍스트 편집 작업 (삽입, 삭제)
//

import Foundation

// MARK: - Editing Operations

extension EditorState {
    /// 현재 커서 위치에 텍스트 삽입
    func insertText(_ text: String) {
        guard isEditable else { return }
        selection.clampToDocument(document)

        #if DEBUG
        print("[EditorState] insertText: '\(text.debugDescription)' at line:\(selection.cursor.line) col:\(selection.cursor.column)")
        print("[EditorState] before lineCount: \(document.lineCount)")
        #endif

        // 선택 영역이 있으면 먼저 삭제 (Undo 기록 포함)
        if selection.hasSelection {
            replaceSelection(with: text)
            return
        }

        let cursor = selection.cursor
        let startLine = cursor.line
        let startColumn = cursor.column
        let oldLine = document.getLine(cursor.line) ?? ""
        let insertionUTF16 = oldLine.utf16Offset(atCharacter: cursor.column)

        document.insert(text, atLine: cursor.line, column: cursor.column)

        #if DEBUG
        print("[EditorState] after lineCount: \(document.lineCount)")
        #endif

        // 커서 이동 계산
        let insertedLines = text.components(separatedBy: "\n")
        let newLine: Int
        let newColumn: Int

        if insertedLines.count == 1 {
            newLine = cursor.line
            newColumn = (document.getLine(cursor.line) ?? "").characterOffset(atUTF16: insertionUTF16 + text.utf16.count)
        } else {
            newLine = cursor.line + insertedLines.count - 1
            newColumn = insertedLines.last?.count ?? 0
        }

        // Undo 기록 (그룹화)
        let updatedLine = document.getLine(startLine) ?? ""
        if insertedLines.count == 1 && updatedLine.count != oldLine.count + text.count {
            // A combining scalar/ZWJ can merge adjacent graphemes. Preserve the entire line
            // because the inserted scalars cannot be undone with grapheme-column deletion.
            pushUndoAction(.replaceText(startLine: startLine, startColumn: 0,
                                       endLine: startLine, endColumn: oldLine.count,
                                       oldText: oldLine, newText: updatedLine))
        } else {
            addToTextGroup(text: text, atLine: startLine, column: startColumn, newEndLine: newLine, newEndColumn: newColumn)
        }

        #if DEBUG
        print("[EditorState] cursor move: (\(cursor.line),\(cursor.column)) -> (\(newLine),\(newColumn))")
        #endif

        selection.moveCursor(line: newLine, column: newColumn)
        viewport.updateLineCount(document.lineCount)
        ensureCursorVisible()
        checkModification()
    }

    /// 선택 영역 삭제
    func deleteSelection() {
        guard selection.hasSelection else { return }

        let range = selection.range.normalized

        // 삭제될 텍스트 저장 (Undo용)
        let deletedText = getTextInRange(range)

        // Undo 기록
        recordDeleteAction(
            fromLine: range.start.line, fromColumn: range.start.column,
            toLine: range.end.line, toColumn: range.end.column,
            deletedText: deletedText
        )

        document.delete(
            fromLine: range.start.line, column: range.start.column,
            toLine: range.end.line, column: range.end.column
        )

        selection.moveCursor(to: range.start)
        viewport.updateLineCount(document.lineCount)
        checkModification()
    }

    /// 백스페이스 (커서 앞 문자 삭제)
    func deleteBackward() {
        guard isEditable else { return }
        selection.clampToDocument(document)

        #if DEBUG
        print("[EditorState] deleteBackward at line:\(selection.cursor.line) col:\(selection.cursor.column)")
        #endif

        if selection.hasSelection {
            deleteSelection()
            return
        }

        let cursor = selection.cursor

        if cursor.column > 0 {
            // 같은 행 내 삭제
            #if DEBUG
            print("[EditorState] deleting character at col:\(cursor.column - 1)")
            #endif

            // 삭제될 문자 저장
            if let lineContent = document.getLine(cursor.line) {
                let charIndex = lineContent.index(lineContent.startIndex, offsetBy: cursor.column - 1)
                let deletedChar = String(lineContent[charIndex])
                recordDeleteAction(
                    fromLine: cursor.line, fromColumn: cursor.column - 1,
                    toLine: cursor.line, toColumn: cursor.column,
                    deletedText: deletedChar
                )
            }

            document.delete(
                fromLine: cursor.line, column: cursor.column - 1,
                toLine: cursor.line, column: cursor.column
            )
            selection.moveCursor(line: cursor.line, column: cursor.column - 1)
        } else if cursor.line > 0 {
            // 이전 행과 합침
            let prevLineLength = document.getLine(cursor.line - 1)?.count ?? 0
            #if DEBUG
            print("[EditorState] merging with previous line")
            #endif

            // 삭제될 줄바꿈 기록
            recordDeleteAction(
                fromLine: cursor.line - 1, fromColumn: prevLineLength,
                toLine: cursor.line, toColumn: 0,
                deletedText: "\n"
            )

            document.delete(
                fromLine: cursor.line - 1, column: prevLineLength,
                toLine: cursor.line, column: 0
            )
            selection.moveCursor(line: cursor.line - 1, column: prevLineLength)
        }

        viewport.updateLineCount(document.lineCount)
        ensureCursorVisible()
        checkModification()
    }

    /// Delete 키 (커서 뒤 문자 삭제)
    func deleteForward() {
        guard isEditable else { return }
        selection.clampToDocument(document)

        if selection.hasSelection {
            deleteSelection()
            return
        }

        let cursor = selection.cursor
        let lineLength = document.getLine(cursor.line)?.count ?? 0

        if cursor.column < lineLength {
            // 같은 행 내 삭제
            if let lineContent = document.getLine(cursor.line) {
                let charIndex = lineContent.index(lineContent.startIndex, offsetBy: cursor.column)
                let deletedChar = String(lineContent[charIndex])
                recordDeleteAction(
                    fromLine: cursor.line, fromColumn: cursor.column,
                    toLine: cursor.line, toColumn: cursor.column + 1,
                    deletedText: deletedChar
                )
            }

            document.delete(
                fromLine: cursor.line, column: cursor.column,
                toLine: cursor.line, column: cursor.column + 1
            )
        } else if cursor.line < max(0, document.lineCount - 1) {
            // 다음 행과 합침
            recordDeleteAction(
                fromLine: cursor.line, fromColumn: lineLength,
                toLine: cursor.line + 1, toColumn: 0,
                deletedText: "\n"
            )

            document.delete(
                fromLine: cursor.line, column: lineLength,
                toLine: cursor.line + 1, column: 0
            )
        }

        viewport.updateLineCount(document.lineCount)
        checkModification()
    }

    /// Option+백스페이스 (단어 단위 삭제)
    func deleteWordBackward() {
        guard isEditable else { return }
        selection.clampToDocument(document)

        if selection.hasSelection {
            deleteSelection()
            return
        }

        let cursor = selection.cursor
        guard let lineContent = document.getLine(cursor.line) else { return }

        // 커서가 행 시작에 있으면 이전 행과 합침
        if cursor.column == 0 {
            if cursor.line > 0 {
                let prevLineLength = document.getLine(cursor.line - 1)?.count ?? 0

                // 삭제될 줄바꿈 기록
                recordDeleteAction(
                    fromLine: cursor.line - 1, fromColumn: prevLineLength,
                    toLine: cursor.line, toColumn: 0,
                    deletedText: "\n"
                )

                document.delete(
                    fromLine: cursor.line - 1, column: prevLineLength,
                    toLine: cursor.line, column: 0
                )
                selection.moveCursor(line: cursor.line - 1, column: prevLineLength)
            }
            viewport.updateLineCount(document.lineCount)
            checkModification()
            return
        }

        // 단어 경계 찾기 (커서 앞쪽으로)
        let wordStart = findWordBoundaryBackward(in: lineContent, from: cursor.column)

        // 삭제될 텍스트 추출
        let startIndex = lineContent.index(lineContent.startIndex, offsetBy: wordStart)
        let endIndex = lineContent.index(lineContent.startIndex, offsetBy: cursor.column)
        let deletedText = String(lineContent[startIndex..<endIndex])

        // Undo 기록
        recordDeleteAction(
            fromLine: cursor.line, fromColumn: wordStart,
            toLine: cursor.line, toColumn: cursor.column,
            deletedText: deletedText
        )

        document.delete(
            fromLine: cursor.line, column: wordStart,
            toLine: cursor.line, column: cursor.column
        )
        selection.moveCursor(line: cursor.line, column: wordStart)

        viewport.updateLineCount(document.lineCount)
        checkModification()
    }

    /// Cmd+백스페이스 (행 시작까지 삭제)
    func deleteToLineStart() {
        guard isEditable else { return }
        selection.clampToDocument(document)

        if selection.hasSelection {
            deleteSelection()
            return
        }

        let cursor = selection.cursor

        // 커서가 이미 행 시작에 있으면 이전 행과 합침
        if cursor.column == 0 {
            if cursor.line > 0 {
                let prevLineLength = document.getLine(cursor.line - 1)?.count ?? 0

                // 삭제될 줄바꿈 기록
                recordDeleteAction(
                    fromLine: cursor.line - 1, fromColumn: prevLineLength,
                    toLine: cursor.line, toColumn: 0,
                    deletedText: "\n"
                )

                document.delete(
                    fromLine: cursor.line - 1, column: prevLineLength,
                    toLine: cursor.line, column: 0
                )
                selection.moveCursor(line: cursor.line - 1, column: prevLineLength)
            }
            viewport.updateLineCount(document.lineCount)
            checkModification()
            return
        }

        // 삭제될 텍스트 추출
        if let lineContent = document.getLine(cursor.line) {
            let endIndex = lineContent.index(lineContent.startIndex, offsetBy: min(cursor.column, lineContent.count))
            let deletedText = String(lineContent[lineContent.startIndex..<endIndex])

            // Undo 기록
            recordDeleteAction(
                fromLine: cursor.line, fromColumn: 0,
                toLine: cursor.line, toColumn: cursor.column,
                deletedText: deletedText
            )
        }

        // 커서 앞쪽의 모든 내용 삭제
        document.delete(
            fromLine: cursor.line, column: 0,
            toLine: cursor.line, column: cursor.column
        )
        selection.moveCursor(line: cursor.line, column: 0)

        checkModification()
    }

    /// 줄바꿈 삽입
    func insertNewline() {
        insertText("\n")
    }

    /// 탭 삽입
    func insertTab() {
        if configuration.insertSpacesForTab {
            let spaces = String(repeating: " ", count: configuration.tabWidth)
            insertText(spaces)
        } else {
            insertText("\t")
        }
    }

    // MARK: - Private Helpers

    /// 단어 경계를 뒤로 찾기 (Option+백스페이스용)
    func findWordBoundaryBackward(in text: String, from column: Int) -> Int {
        guard column > 0 && column <= text.count else { return 0 }

        let chars = Array(text)
        var pos = column - 1

        // 1. 먼저 공백/구두점을 건너뛰기
        while pos > 0 && isWordSeparator(chars[pos]) {
            pos -= 1
        }

        // 2. 단어 문자를 건너뛰기
        while pos > 0 && !isWordSeparator(chars[pos - 1]) {
            pos -= 1
        }

        return pos
    }

    /// 단어 구분자 여부 확인
    func isWordSeparator(_ char: Character) -> Bool {
        char.isWhitespace || char.isPunctuation
    }

    /// 범위 내 텍스트 추출
    func getTextInRange(_ range: TextRange) -> String {
        let normalized = range.normalized
        var result = ""

        for lineIndex in normalized.start.line...normalized.end.line {
            guard let lineContent = document.getLine(lineIndex) else { continue }

            let startCol = (lineIndex == normalized.start.line) ? normalized.start.column : 0
            let endCol = (lineIndex == normalized.end.line) ? normalized.end.column : lineContent.count

            let safeStartCol = min(startCol, lineContent.count)
            let safeEndCol = min(endCol, lineContent.count)

            if safeStartCol <= safeEndCol {
                let startIndex = lineContent.index(lineContent.startIndex, offsetBy: safeStartCol)
                let endIndex = lineContent.index(lineContent.startIndex, offsetBy: safeEndCol)
                result += String(lineContent[startIndex..<endIndex])
            }

            if lineIndex < normalized.end.line {
                result += "\n"
            }
        }

        return result
    }
}
