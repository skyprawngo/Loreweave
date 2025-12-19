//
//  EditorState+Clipboard.swift
//  Loreweave
//
//  클립보드 작업 (복사, 잘라내기, 붙여넣기)
//

import Foundation

// MARK: - Clipboard Operations

extension EditorState {
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
}
