import Foundation

/// A user command is consumed once by the active document, including repeated identical searches.
struct EditorCommand: Identifiable {
    let id = UUID()
    let action: Action

    enum Action {
        case format(MarkdownFormatType)
        case find(String, forward: Bool)
        case replace(String, replacement: String, all: Bool)
    }

    init(_ action: Action) { self.action = action }
}

extension EditorState {
    /// One replacement is one undo operation, including replacing the current selection.
    func replaceSelection(with value: String) {
        guard isEditable else { return }
        selection.clampToDocument(document)
        let range = selection.range.normalized
        let old = getTextInRange(range)
        guard old != value else { return }
        let before = getText()
        let insertionOffset = document.utf16Offset(from: range.start)
        commitPendingTextGroup()
        document.delete(fromLine: range.start.line, column: range.start.column,
                        toLine: range.end.line, column: range.end.column)
        document.insert(value, atLine: range.start.line, column: range.start.column)
        let after = getText()
        if after.count != before.count - old.count + value.count {
            pushUndoAction(.replaceText(startLine: 0, startColumn: 0,
                                       endLine: range.end.line, endColumn: range.end.column,
                                       oldText: before, newText: after))
        } else {
            pushUndoAction(.replaceText(startLine: range.start.line, startColumn: range.start.column,
                                       endLine: range.end.line, endColumn: range.end.column,
                                       oldText: old, newText: value))
        }
        selection.moveCursor(to: document.positionFromUTF16Offset(insertionOffset + value.utf16.count))
        selection.clampToDocument(document)
        viewport.updateLineCount(document.lineCount)
        checkModification()
    }

    @discardableResult
    func find(_ query: String, forward: Bool) -> Bool {
        guard !query.isEmpty else { return false }
        let text = getText() as NSString
        let position = forward ? selection.range.normalized.end : selection.range.normalized.start
        let offset = document.utf16Offset(from: position)
        let options: NSString.CompareOptions = forward ? [] : [.backwards]
        let first = forward ? NSRange(location: offset, length: text.length - offset) : NSRange(location: 0, length: offset)
        var match = text.range(of: query, options: options, range: first)
        if match.location == NSNotFound {
            let wrapped = forward ? NSRange(location: 0, length: offset) : NSRange(location: offset, length: text.length - offset)
            match = text.range(of: query, options: options, range: wrapped)
        }
        guard match.location != NSNotFound else { return false }
        selection.select(from: document.positionFromUTF16Offset(match.location),
                         to: document.positionFromUTF16Offset(NSMaxRange(match)))
        return true
    }

    func execute(_ command: EditorCommand) {
        switch command.action {
        case .find(let query, let forward):
            _ = find(query, forward: forward)
        case .replace(let query, let replacement, let all):
            guard isEditable, !query.isEmpty else { return }
            if all {
                let old = getText()
                let new = old.replacingOccurrences(of: query, with: replacement)
                guard old != new else { return }
                selectAll()
                replaceSelection(with: new)
            } else {
                if getTextInRange(selection.range) != query, !find(query, forward: true) { return }
                replaceSelection(with: replacement)
            }
        case .format(let type):
            guard isEditable, selection.hasSelection else { return }
            let markers: (String, String)
            switch type {
            case .bold: markers = ("**", "**")
            case .italic: markers = ("*", "*")
            case .boldItalic: markers = ("***", "***")
            case .strikethrough: markers = ("~~", "~~")
            case .underline: markers = ("<u>", "</u>")
            }
            let value = getTextInRange(selection.range)
            let result: String
            if value.hasPrefix(markers.0), value.hasSuffix(markers.1), value.count >= markers.0.count + markers.1.count {
                result = String(value.dropFirst(markers.0.count).dropLast(markers.1.count))
            } else {
                result = markers.0 + value + markers.1
            }
            let start = selection.range.normalized.start
            replaceSelection(with: result)
            selection.select(from: start, to: selection.cursor)
        }
    }
}
