import Foundation

/// Pure location policy. Layout, persistence and document mutation belong to callers.
enum EditorViewportResolver {
    struct Resolution {
        let firstRow: Int
        let cursorRow: Int?
        let cursorColumn: Int?
        let firstTextMatched: Bool
    }

    static func resolve(_ saved: EditorViewportPosition, lineCount: Int,
                        lineText: (Int) -> String) -> Resolution {
        guard lineCount > 0 else {
            return Resolution(firstRow: 0, cursorRow: nil, cursorColumn: nil, firstTextMatched: false)
        }
        func row(_ number: Int) -> Int { min(max(1, number) - 1, lineCount - 1) }
        let oldFirst = row(saved.firstVisibleLine)
        let oldCursor = saved.cursorLine.map(row)
        var firstMatches: [Int] = []
        var cursorMatches: [(row: Int, column: Int)] = []
        // An unchanged document needs only its two anchor lines, not a full scan.
        if !saved.firstLineText.isEmpty, lineText(oldFirst) == saved.firstLineText,
           let oldCursor, let cursorText = saved.cursorLineText,
           !cursorText.isEmpty, lineText(oldCursor) == cursorText {
            return Resolution(firstRow: oldFirst, cursorRow: oldCursor,
                cursorColumn: min(max(0, saved.cursorOffsetWithinLine ?? 0), cursorText.count), firstTextMatched: true)
        }
        for index in 0..<lineCount {
            let text = lineText(index)
            if !saved.firstLineText.isEmpty, text == saved.firstLineText { firstMatches.append(index) }
            if let cursorText = saved.cursorLineText, !cursorText.isEmpty, text == cursorText {
                cursorMatches.append((index, min(max(0, saved.cursorOffsetWithinLine ?? 0), text.count)))
            }
        }
        // Exact cursor line was edited: try its bounded before/after context.
        if cursorMatches.isEmpty {
            let before = saved.cursorTextBefore ?? "", after = saved.cursorTextAfter ?? ""
            let context = before + after
            if !context.isEmpty {
                for index in 0..<lineCount {
                    let text = lineText(index)
                    if let match = text.range(of: context),
                       text.range(of: context, range: match.upperBound..<text.endIndex) == nil {
                        cursorMatches.append((index, text.distance(from: text.startIndex, to: match.lowerBound) + before.count))
                    }
                }
            }
        }
        let cursor = cursorMatches.min { abs($0.row - (oldCursor ?? oldFirst)) < abs($1.row - (oldCursor ?? oldFirst)) }
        // Use the saved distance (not clamped old rows) when falling back to the cursor.
        let delta = Double(max(1, saved.cursorLine ?? saved.firstVisibleLine)) - Double(max(1, saved.firstVisibleLine))
        let predicted = cursor.map { Int(min(Double(lineCount - 1), max(0, Double($0.row) - delta))) } ?? oldFirst
        let first = firstMatches.min { abs($0 - predicted) < abs($1 - predicted) } ?? predicted
        return Resolution(firstRow: first, cursorRow: cursor?.row, cursorColumn: cursor?.column,
                          firstTextMatched: !firstMatches.isEmpty)
    }
}
