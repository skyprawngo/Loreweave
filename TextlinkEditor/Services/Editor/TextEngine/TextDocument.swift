//
//  TextDocument.swift
//  TextlinkEditor
//
//  텍스트 문서 모델 - 행 기반 텍스트 저장 및 편집
//  VSCode Monaco 스타일의 행별 관리 구조
//

import Foundation

// MARK: - Text Line

/// 개별 텍스트 행
/// 각 행은 독립적으로 렌더링 캐시를 가질 수 있음
final class TextLine {
    /// 행 고유 ID (행 이동/삭제 시에도 추적 가능)
    let id: UUID
    /// 행 내용 (줄바꿈 문자 제외)
    var content: String
    /// 렌더링 캐시 무효화 플래그
    var needsRender: Bool = true
    /// 캐시된 너비 (nil이면 재계산 필요)
    var cachedWidth: CGFloat?

    init(content: String) {
        self.id = UUID()
        self.content = content
    }

    /// 행 내용 변경 시 캐시 무효화
    func invalidateCache() {
        needsRender = true
        cachedWidth = nil
    }
}

// MARK: - Text Document

/// 텍스트 문서
/// 행 기반으로 텍스트를 관리하며 효율적인 편집 작업 지원
final class TextDocument {
    /// 문서의 모든 행
    private(set) var lines: [TextLine] = [TextLine(content: "")]

    /// 문서 수정 버전 (변경 감지용)
    private(set) var version: Int = 0

    static let chunkSize = 256
    private(set) var chunkVersions: [Int] = []
    private var serializedChunks: [Int: String] = [:]
    private var serializedText: String?

    private func changed(from line: Int, through end: Int? = nil) {
        version += 1
        let count = (lines.count + Self.chunkSize - 1) / Self.chunkSize
        if chunkVersions.count < count { chunkVersions += Array(repeating: version, count: count - chunkVersions.count) }
        if chunkVersions.count > count { chunkVersions.removeLast(chunkVersions.count - count) }
        let first = max(0, min(line / Self.chunkSize, count - 1))
        let last = min(count - 1, (end ?? (lines.count - 1)) / Self.chunkSize)
        if first <= last {
            for chunk in first...last { chunkVersions[chunk] = version; serializedChunks[chunk] = nil }
        }
        serializedChunks = serializedChunks.filter { $0.key < count }
        serializedText = nil
    }

    /// 총 행 수
    var lineCount: Int { lines.count }

    /// 총 문자 수
    var characterCount: Int {
        lines.reduce(0) { $0 + $1.content.count } + max(0, lines.count - 1)
    }

    /// 총 단어 수
    var wordCount: Int {
        lines.reduce(0) { count, line in
            count + line.content.components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }.count
        }
    }

    // MARK: - Initialization

    init() {}

    init(text: String) {
        loadText(text)
    }

    // MARK: - Text Loading

    /// 전체 텍스트 로드 (기존 내용 대체)
    func loadText(_ text: String) {
        let lineContents = text.components(separatedBy: "\n")
        lines = lineContents.map { TextLine(content: $0) }
        if lines.isEmpty {
            lines = [TextLine(content: "")]
        }
        changed(from: 0)
    }

    /// 전체 텍스트 추출
    func getText() -> String {
        if let serializedText { return serializedText }
        var chunks: [String] = []
        for chunk in 0..<((lines.count + Self.chunkSize - 1) / Self.chunkSize) {
            if serializedChunks[chunk] == nil {
                let start = chunk * Self.chunkSize
                serializedChunks[chunk] = lines[start..<min(lines.count, start + Self.chunkSize)].map { $0.content }.joined(separator: "\n")
            }
            chunks.append(serializedChunks[chunk]!)
        }
        let value = chunks.joined(separator: "\n")
        serializedText = value
        return value
    }

    // MARK: - Line Access

    /// 특정 행 내용 가져오기
    func getLine(_ index: Int) -> String? {
        guard index >= 0 && index < lines.count else { return nil }
        return lines[index].content
    }

    /// 특정 행 객체 가져오기
    func getLineObject(_ index: Int) -> TextLine? {
        guard index >= 0 && index < lines.count else { return nil }
        return lines[index]
    }

    /// 행 범위 내용 가져오기
    func getLines(from start: Int, to end: Int) -> [String] {
        let safeStart = max(0, start)
        let safeEnd = min(lines.count - 1, end)
        guard safeStart <= safeEnd else { return [] }
        return (safeStart...safeEnd).map { lines[$0].content }
    }

    // MARK: - Position Conversion

    /// 문서 오프셋 → (행, 열) 변환
    func positionFromOffset(_ offset: Int) -> (line: Int, column: Int) {
        guard !lines.isEmpty else { return (0, 0) }
        guard offset >= 0 else { return (0, 0) }

        var remaining = offset
        for (lineIndex, line) in lines.enumerated() {
            let lineLength = line.content.count
            if remaining <= lineLength {
                return (lineIndex, remaining)
            }
            remaining -= lineLength + 1 // +1 for newline
        }
        // 오프셋이 문서 끝을 넘으면 마지막 위치 반환
        let lastLine = max(0, lines.count - 1)
        return (lastLine, lines[lastLine].content.count)
    }

    /// (행, 열) → 문서 오프셋 변환
    func offsetFromPosition(line: Int, column: Int) -> Int {
        var offset = 0
        for i in 0..<max(0, min(line, lines.count)) {
            offset += lines[i].content.count + 1 // +1 for newline
        }
        if line >= 0 && line < lines.count {
            offset += max(0, min(column, lines[line].content.count))
        }
        return offset
    }

    // MARK: - Editing Operations

    /// 특정 위치에 텍스트 삽입
    func insert(_ text: String, at offset: Int) {
        let pos = positionFromOffset(offset)
        insert(text, atLine: pos.line, column: pos.column)
    }

    /// 특정 행/열에 텍스트 삽입
    func insert(_ text: String, atLine lineIndex: Int, column: Int) {
        guard lineIndex >= 0 && lineIndex < lines.count else { return }

        let line = lines[lineIndex]
        let insertedLines = text.components(separatedBy: "\n")

        if insertedLines.count == 1 {
            // 단일 행 삽입 (줄바꿈 없음)
            let content = line.content
            let index = content.index(content.startIndex, offsetBy: max(0, min(column, content.count)))
            var newContent = content
            newContent.insert(contentsOf: text, at: index)

            #if DEBUG
            print("[TextDocument] insert '\(text)' at col \(column): '\(content)' -> '\(newContent)'")
            #endif

            line.content = newContent
            line.invalidateCache()
        } else {
            // 다중 행 삽입 (줄바꿈 포함)
            let content = line.content
            let safeColumn = max(0, min(column, content.count))
            let beforeCursor = String(content.prefix(safeColumn))
            let afterCursor = String(content.suffix(content.count - safeColumn))

            // 첫 번째 행: 기존 내용 + 첫 삽입 행
            line.content = beforeCursor + insertedLines[0]
            line.invalidateCache()

            // 중간 행들: 새로 삽입
            var newLines: [TextLine] = []
            for i in 1..<insertedLines.count - 1 {
                newLines.append(TextLine(content: insertedLines[i]))
            }

            // 마지막 행: 마지막 삽입 행 + 기존 나머지
            let lastInserted = insertedLines.last ?? ""
            newLines.append(TextLine(content: lastInserted + afterCursor))

            lines.insert(contentsOf: newLines, at: lineIndex + 1)
        }

        changed(from: lineIndex, through: insertedLines.count == 1 ? lineIndex : nil)
    }

    /// 범위 삭제
    func delete(from startOffset: Int, to endOffset: Int) {
        let startPos = positionFromOffset(startOffset)
        let endPos = positionFromOffset(endOffset)
        delete(fromLine: startPos.line, column: startPos.column,
               toLine: endPos.line, column: endPos.column)
    }

    /// 행/열 범위 삭제
    func delete(fromLine startLine: Int, column startColumn: Int,
                toLine endLine: Int, column endColumn: Int) {
        guard startLine >= 0 && endLine < lines.count else { return }
        guard startLine < endLine || (startLine == endLine && startColumn < endColumn) else { return }

        if startLine == endLine {
            // 같은 행 내 삭제
            let line = lines[startLine]
            let content = line.content
            let safeStart = max(0, min(startColumn, content.count))
            let safeEnd = max(0, min(endColumn, content.count))
            let before = String(content.prefix(safeStart))
            let after = String(content.suffix(content.count - safeEnd))
            line.content = before + after
            line.invalidateCache()
        } else {
            // 다중 행 삭제
            let firstLine = lines[startLine]
            let lastLine = lines[endLine]

            let beforeContent = String(firstLine.content.prefix(min(startColumn, firstLine.content.count)))
            let afterContent = String(lastLine.content.suffix(max(0, lastLine.content.count - endColumn)))

            // 첫 행에 합침
            firstLine.content = beforeContent + afterContent
            firstLine.invalidateCache()

            // 중간 행들 삭제
            lines.removeSubrange((startLine + 1)...endLine)
        }

        changed(from: startLine, through: startLine == endLine ? startLine : nil)
    }

    /// 특정 범위 텍스트 대체
    func replace(from startOffset: Int, to endOffset: Int, with text: String) {
        delete(from: startOffset, to: endOffset)
        insert(text, at: startOffset)
    }

    /// 행 삽입
    func insertLine(_ content: String, at index: Int) {
        let safeIndex = max(0, min(index, lines.count))
        lines.insert(TextLine(content: content), at: safeIndex)
        changed(from: safeIndex)
    }

    /// 행 삭제
    func removeLine(at index: Int) {
        guard index >= 0 && index < lines.count else { return }
        lines.remove(at: index)
        if lines.isEmpty {
            lines = [TextLine(content: "")]
        }
        changed(from: index)
    }

    /// 행 교환 (두 행의 위치를 바꿈)
    func swapLines(_ index1: Int, _ index2: Int) {
        guard index1 >= 0 && index1 < lines.count else { return }
        guard index2 >= 0 && index2 < lines.count else { return }
        guard index1 != index2 else { return }

        lines.swapAt(index1, index2)
        lines[index1].invalidateCache()
        lines[index2].invalidateCache()
        changed(from: min(index1, index2), through: max(index1, index2))
    }

    /// 행 복제 (지정된 행을 복사하여 바로 아래에 삽입)
    func duplicateLine(at index: Int) {
        guard index >= 0 && index < lines.count else { return }

        let originalContent = lines[index].content
        let newLine = TextLine(content: originalContent)
        lines.insert(newLine, at: index + 1)
        changed(from: index)
    }

    // MARK: - Cache Management

    /// 모든 행의 렌더링 캐시 무효화
    func invalidateAllCache() {
        for line in lines {
            line.invalidateCache()
        }
    }

    /// 특정 범위 행의 캐시 무효화
    func invalidateCache(from startLine: Int, to endLine: Int) {
        guard !lines.isEmpty else { return }
        let safeStart = max(0, startLine)
        let safeEnd = min(lines.count - 1, endLine)
        guard safeStart <= safeEnd else { return }
        for i in safeStart...safeEnd {
            lines[i].invalidateCache()
        }
    }
}

// Cocoa and Core Text expose UTF-16 offsets; editor columns count grapheme clusters.
extension String {
    func utf16Offset(atCharacter column: Int) -> Int {
        let index = index(startIndex, offsetBy: max(0, min(column, count)))
        return index.utf16Offset(in: self)
    }

    func characterOffset(atUTF16 offset: Int) -> Int {
        let target = max(0, min(offset, utf16.count))
        var column = 0
        var units = 0
        for character in self {
            let next = units + String(character).utf16.count
            if next > target { break }
            units = next
            column += 1
        }
        return column
    }
}

extension TextDocument {
    func utf16Offset(from position: TextPosition) -> Int {
        let line = max(0, min(position.line, lineCount - 1))
        var result = 0
        for index in 0..<line { result += (getLine(index) ?? "").utf16.count + 1 }
        return result + (getLine(line) ?? "").utf16Offset(atCharacter: position.column)
    }

    func positionFromUTF16Offset(_ offset: Int) -> TextPosition {
        var remaining = max(0, offset)
        for index in 0..<lineCount {
            let content = getLine(index) ?? ""
            if remaining <= content.utf16.count {
                return TextPosition(line: index, column: content.characterOffset(atUTF16: remaining))
            }
            remaining -= content.utf16.count + 1
        }
        return TextPosition(line: lineCount - 1, column: getLine(lineCount - 1)?.count ?? 0)
    }
}
