//
//  EditorState.swift
//  Loreweave
//
//  에디터 통합 상태 관리
//  TextDocument, TextSelection, ViewportManager를 통합
//

import Foundation
import AppKit

// MARK: - Editor Configuration

/// 에디터 설정
struct EditorConfiguration {
    var fontSize: CGFloat = 14
    var lineHeightMultiple: CGFloat = 1.5
    var fontName: String = "Menlo"
    var tabWidth: Int = 4
    var insertSpacesForTab: Bool = true
    var wordWrap: Bool = true
    var showLineNumbers: Bool = true
    var highlightCurrentLine: Bool = true

    /// 실제 행 높이 계산
    var lineHeight: CGFloat {
        fontSize * lineHeightMultiple
    }

    /// 에디터 폰트
    var font: NSFont {
        NSFont(name: fontName, size: fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }
}

// MARK: - Editor State

/// 에디터 전체 상태
final class EditorState {
    /// 문서
    let document: TextDocument

    /// 선택 상태
    let selection: TextSelection

    /// 뷰포트 관리자
    let viewport: ViewportManager

    /// 에디터 설정
    var configuration: EditorConfiguration {
        didSet {
            applyConfiguration()
        }
    }

    /// 편집 가능 여부
    var isEditable: Bool = true

    /// 문서 수정 여부
    var isModified: Bool = false

    /// 문서 버전 (변경 감지용)
    private var lastKnownVersion: Int = 0

    // MARK: - Undo/Redo

    /// Undo 스택
    private var undoStack: [UndoAction] = []

    /// Redo 스택
    private var redoStack: [UndoAction] = []

    /// Undo 가능 여부
    var canUndo: Bool { !undoStack.isEmpty }

    /// Redo 가능 여부
    var canRedo: Bool { !redoStack.isEmpty }

    // MARK: - Initialization

    init(
        text: String = "",
        configuration: EditorConfiguration = EditorConfiguration()
    ) {
        self.document = TextDocument(text: text)
        self.selection = TextSelection()
        self.viewport = ViewportManager()
        self.configuration = configuration

        applyConfiguration()
    }

    // MARK: - Configuration

    private func applyConfiguration() {
        viewport.updateLineHeight(configuration.lineHeight)
    }

    /// 폰트 크기 변경
    func setFontSize(_ size: CGFloat) {
        configuration.fontSize = size
    }

    /// 줄 높이 배수 변경
    func setLineHeightMultiple(_ multiple: CGFloat) {
        configuration.lineHeightMultiple = multiple
    }

    /// 폰트 이름 변경
    func setFontName(_ name: String) {
        configuration.fontName = name
    }

    // MARK: - Document Operations

    /// 텍스트 로드
    func loadText(_ text: String) {
        document.loadText(text)
        viewport.updateLineCount(document.lineCount)
        selection.moveCursor(to: .zero)
        isModified = false
        lastKnownVersion = document.version
    }

    /// 텍스트 추출
    func getText() -> String {
        document.getText()
    }

    /// 문서 변경 여부 확인 및 업데이트
    func checkModification() {
        if document.version != lastKnownVersion {
            isModified = true
            lastKnownVersion = document.version
        }
    }

    // MARK: - Editing Operations

    /// 현재 커서 위치에 텍스트 삽입
    func insertText(_ text: String) {
        guard isEditable else { return }

        #if DEBUG
        print("[EditorState] insertText: '\(text.debugDescription)' at line:\(selection.cursor.line) col:\(selection.cursor.column)")
        print("[EditorState] before lineCount: \(document.lineCount)")
        #endif

        // 선택 영역이 있으면 먼저 삭제
        if selection.hasSelection {
            deleteSelection()
        }

        let cursor = selection.cursor
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
            newColumn = cursor.column + text.count
        } else {
            newLine = cursor.line + insertedLines.count - 1
            newColumn = insertedLines.last?.count ?? 0
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

        if selection.hasSelection {
            deleteSelection()
            return
        }

        let cursor = selection.cursor
        let lineLength = document.getLine(cursor.line)?.count ?? 0

        if cursor.column < lineLength {
            // 같은 행 내 삭제
            document.delete(
                fromLine: cursor.line, column: cursor.column,
                toLine: cursor.line, column: cursor.column + 1
            )
        } else if cursor.line < max(0, document.lineCount - 1) {
            // 다음 행과 합침
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

        if selection.hasSelection {
            deleteSelection()
            return
        }

        let cursor = selection.cursor

        // 커서가 이미 행 시작에 있으면 이전 행과 합침
        if cursor.column == 0 {
            if cursor.line > 0 {
                let prevLineLength = document.getLine(cursor.line - 1)?.count ?? 0
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

        // 커서 앞쪽의 모든 내용 삭제
        document.delete(
            fromLine: cursor.line, column: 0,
            toLine: cursor.line, column: cursor.column
        )
        selection.moveCursor(line: cursor.line, column: 0)

        checkModification()
    }

    /// 단어 경계를 뒤로 찾기 (Option+백스페이스용)
    private func findWordBoundaryBackward(in text: String, from column: Int) -> Int {
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
    private func isWordSeparator(_ char: Character) -> Bool {
        char.isWhitespace || char.isPunctuation
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

    // MARK: - Cursor Movement

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

    // MARK: - Clipboard

    /// 선택 영역 복사
    func copy() -> String? {
        guard selection.hasSelection else { return nil }

        let range = selection.range.normalized
        var result = ""

        for lineIndex in range.start.line...range.end.line {
            guard let lineContent = document.getLine(lineIndex) else { continue }

            let startCol = (lineIndex == range.start.line) ? range.start.column : 0
            let endCol = (lineIndex == range.end.line) ? range.end.column : lineContent.count

            let startIndex = lineContent.index(lineContent.startIndex, offsetBy: min(startCol, lineContent.count))
            let endIndex = lineContent.index(lineContent.startIndex, offsetBy: min(endCol, lineContent.count))

            result += String(lineContent[startIndex..<endIndex])

            if lineIndex < range.end.line {
                result += "\n"
            }
        }

        return result
    }

    /// 잘라내기
    func cut() -> String? {
        let copied = copy()
        if copied != nil {
            deleteSelection()
        }
        return copied
    }

    /// 붙여넣기
    func paste(_ text: String) {
        insertText(text)
    }

    // MARK: - Line Operations

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

    // MARK: - Undo/Redo Operations

    /// Undo 실행
    @discardableResult
    func undo() -> Bool {
        guard canUndo else { return false }

        let action = undoStack.removeLast()
        applyUndoAction(action, isRedo: false)

        return true
    }

    /// Redo 실행
    @discardableResult
    func redo() -> Bool {
        guard canRedo else { return false }

        let action = redoStack.removeLast()
        applyUndoAction(action, isRedo: true)

        return true
    }

    /// Undo 스택에 액션 추가
    private func pushUndoAction(_ action: UndoAction) {
        undoStack.append(action)
        redoStack.removeAll()  // 새 액션이 추가되면 Redo 스택 초기화
    }

    /// Undo/Redo 액션 적용
    private func applyUndoAction(_ action: UndoAction, isRedo: Bool) {
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
        undoStack.removeAll()
        redoStack.removeAll()
    }
}

// MARK: - Undo Action

/// Undo/Redo 액션 타입
enum UndoAction {
    /// 두 행 교환
    case swapLines(line1: Int, line2: Int, content1: String, content2: String)
    /// 행 삭제
    case deleteLine(at: Int)
    /// 행 삽입
    case insertLine(at: Int, content: String)
    /// 텍스트 대체
    case replaceText(startLine: Int, startColumn: Int, endLine: Int, endColumn: Int, oldText: String, newText: String)
}
