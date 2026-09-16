import AppKit

/// NSTextView owns input, selection, key bindings and undo. Only manuscript commands
/// and the line-number accessory are app-specific. Layout remains viewport-driven.
final class NativeManuscriptTextView: NSTextView, NSLayoutManagerDelegate {
    private(set) var inlinePanel: NSView?
    private var inlineAnchor = 0
    private let inlineHeight: CGFloat = 100

    private let documentUndoManager = UndoManager()
    override var undoManager: UndoManager? { documentUndoManager }
    @objc func undo(_ sender: Any?) { commitComposition(); undoManager?.undo() }
    @objc func redo(_ sender: Any?) { commitComposition(); undoManager?.redo() }
    var lineStarts = [0]
    var styleKey = ""
    var modifiedLines: Set<Int> = []

    init() {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        layout.allowsNonContiguousLayout = true
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 600, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)
        super.init(frame: NSRect(x: 0, y: 0, width: 600, height: 400), textContainer: container)
        layout.delegate = self
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        minSize = .zero
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textContainerInset = NSSize(width: 8, height: 8)
        usesFindPanel = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        backgroundColor = AppColors.nsTextEditorBackground
        insertionPointColor = AppColors.nsEditorCursor
        textColor = AppColors.nsEditorText
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func rebuildLineIndex() {
        let value = string as NSString
        var starts = [0]
        var offset = 0
        while offset < value.length {
            let next = NSMaxRange(value.lineRange(for: NSRange(location: offset, length: 0)))
            guard next > offset else { break }
            if next < value.length { starts.append(next) }
            else if value.length > 0, let scalar = UnicodeScalar(value.character(at: value.length - 1)), CharacterSet.newlines.contains(scalar) {
                starts.append(next)
            }
            offset = next
        }
        lineStarts = starts
        enclosingScrollView?.verticalRulerView?.needsDisplay = true
    }
    func line(at offset: Int) -> Int {
        var low = 0, high = lineStarts.count
        while low < high {
            let mid = (low + high) / 2
            if lineStarts[mid] <= offset { low = mid + 1 } else { high = mid }
        }
        return max(0, low - 1)
    }
    func position(at offset: Int) -> (line: Int, column: Int) {
        let value = string as NSString
        let offset = min(max(0, offset), value.length)
        let row = line(at: offset)
        return (row, value.substring(with: NSRange(location: lineStarts[row], length: offset - lineStarts[row])).count)
    }
    func offset(line: Int, column: Int) -> Int {
        let row = min(max(0, line), lineStarts.count - 1)
        let value = string as NSString
        let start = lineStarts[row]
        var end = row + 1 < lineStarts.count ? lineStarts[row + 1] : value.length
        while end > start, let scalar = UnicodeScalar(value.character(at: end - 1)), CharacterSet.newlines.contains(scalar) { end -= 1 }
        let content = value.substring(with: NSRange(location: start, length: end - start))
        return start + content.prefix(max(0, column)).utf16.count
    }
    func commitComposition() {
        if hasMarkedText() { unmarkText(); inputContext?.discardMarkedText() }
        breakUndoCoalescing()
    }
    func load(_ value: String) {
        closeInlinePanel()
        commitComposition()
        string = value
        styleKey = ""
        undoManager?.removeAllActions()
        rebuildLineIndex()
    }
    func replace(_ range: NSRange, with replacement: String, selectReplacement: Bool = false) {
        guard isEditable, shouldChangeText(in: range, replacementString: replacement) else { return }
        breakUndoCoalescing()
        textStorage?.replaceCharacters(in: range, with: replacement)
        didChangeText()
        setSelectedRange(NSRange(location: selectReplacement ? range.location : range.location + replacement.utf16.count,
                                 length: selectReplacement ? replacement.utf16.count : 0))
    }
    func execute(_ command: EditorCommand) {
        commitComposition()
        switch command.action {
        case .locate(let line, let query):
            let start = offset(line: line, column: 0)
            let source = string as NSString
            let lineRange = source.lineRange(for: NSRange(location: start, length: 0))
            let match = source.range(of: query, options: .caseInsensitive, range: lineRange)
            setSelectedRange(match.location == NSNotFound ? NSRange(location: start, length: 0) : match)
        case .find(let query, let forward): find(query, forward: forward)
        case .replace(let query, let replacement, let all):
            guard !query.isEmpty, isEditable else { return }
            if all {
                let result = string.replacingOccurrences(of: query, with: replacement)
                if result != string { replace(NSRange(location: 0, length: (string as NSString).length), with: result) }
            } else {
                if (string as NSString).substring(with: selectedRange()) != query { find(query, forward: true) }
                if (string as NSString).substring(with: selectedRange()) == query { replace(selectedRange(), with: replacement) }
            }
        case .format(let type):
            guard selectedRange().length > 0 else { return }
            let markers: (String, String)
            switch type {
            case .bold: markers = ("**", "**")
            case .italic: markers = ("*", "*")
            case .boldItalic: markers = ("***", "***")
            case .underline: markers = ("<u>", "</u>")
            case .strikethrough: markers = ("~~", "~~")
            }
            let selected = (string as NSString).substring(with: selectedRange())
            let result = selected.hasPrefix(markers.0) && selected.hasSuffix(markers.1) && selected.count >= markers.0.count + markers.1.count
                ? String(selected.dropFirst(markers.0.count).dropLast(markers.1.count)) : markers.0 + selected + markers.1
            replace(selectedRange(), with: result, selectReplacement: true)
        }
        scrollRangeToVisible(selectedRange())
    }
    private func find(_ query: String, forward: Bool) {
        guard !query.isEmpty else { return }
        let value = string as NSString
        let selection = selectedRange()
        let offset = forward ? NSMaxRange(selection) : selection.location
        let first = forward ? NSRange(location: offset, length: value.length - offset) : NSRange(location: 0, length: offset)
        let options: NSString.CompareOptions = forward ? [] : [.backwards]
        var match = value.range(of: query, options: options, range: first)
        if match.location == NSNotFound { match = value.range(of: query, options: options) }
        if match.location != NSNotFound { setSelectedRange(match) }
    }
    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard selectedRange().length == 0, let layout = layoutManager else { return }
        let offset = selectedRange().location
        var lineRect: NSRect
        if offset == (string as NSString).length { lineRect = layout.extraLineFragmentRect }
        else {
            let glyph = layout.glyphIndexForCharacter(at: offset)
            lineRect = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil, withoutAdditionalLayout: true)
        }
        lineRect = manuscriptRect(lineRect)
        lineRect.origin.y += textContainerOrigin.y
        lineRect.origin.x = 0
        lineRect.size.width = bounds.width
        if lineRect.intersects(rect) { AppColors.nsCurrentLineHighlight.setFill(); lineRect.intersection(rect).fill() }
    }

    private func isInlineShortcut(_ event: NSEvent) -> Bool {
        event.keyCode == 34 && event.modifierFlags.intersection([.command, .option, .shift, .control]) == [.command, .option]
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if window?.firstResponder === self, isInlineShortcut(event) { openInlineAI(nil); return true }
        return super.performKeyEquivalent(with: event)
    }
    override func keyDown(with event: NSEvent) {
        if isInlineShortcut(event) { openInlineAI(nil); return }
        if let action = KeyboardShortcutManager.shared.action(matching: event) {
            switch action {
            case .deleteWordBackward: deleteWordBackward(nil); return
            case .deleteToLineStart: deleteToBeginningOfLine(nil); return
            case .moveLineUp, .moveLineDown, .duplicateLineUp, .duplicateLineDown:
                guard isEditable else { return }
                commitComposition()
                let state = EditorState(text: string)
                let range = selectedRange()
                state.selection.select(from: state.document.positionFromUTF16Offset(range.location),
                                       to: state.document.positionFromUTF16Offset(NSMaxRange(range)))
                let changed: Bool
                switch action {
                case .moveLineUp: changed = state.moveLineUp()
                case .moveLineDown: changed = state.moveLineDown()
                case .duplicateLineUp: changed = state.duplicateLineUp()
                default: changed = state.duplicateLineDown()
                }
                if changed {
                    replace(NSRange(location: 0, length: (string as NSString).length), with: state.getText())
                    let selection = state.selection.range.normalized
                    let start = state.document.utf16Offset(from: selection.start)
                    setSelectedRange(NSRange(location: start, length: state.document.utf16Offset(from: selection.end) - start))
                    scrollRangeToVisible(selectedRange())
                }
                return
            default: break
            }
        }
        super.keyDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        menu.addItem(.separator())
        for (index, key) in ["editor.bold", "editor.italic", "editor.underline", "editor.strikethrough"].enumerated() {
            let item = NSMenuItem(title: L10n.get(key), action: #selector(formatSelection(_:)), keyEquivalent: "")
            item.target = self; item.tag = index
            menu.addItem(item)
        }
        let attach = NSMenuItem(title: L10n.get("ai.context.attachSelection"), action: #selector(attachSelectionToAI(_:)), keyEquivalent: "")
        attach.target = self
        menu.addItem(attach)
        let inline = NSMenuItem(title: L10n.get("ai.inline.open"), action: #selector(openInlineAI(_:)), keyEquivalent: "i")
        inline.keyEquivalentModifierMask = [.command, .option]
        inline.target = self
        menu.addItem(inline)
        return menu
    }
    @objc private func openInlineAI(_ sender: Any?) {
        guard isEditable else { return }
        commitComposition()
        NotificationCenter.default.post(name: Notification.Name("editorInlineAI"), object: self)
    }

    func installInlinePanel(_ panel: NSView) {
        closeInlinePanel()
        let source = string as NSString
        let selection = selectedRange()
        let end = min(source.length, selection.length > 0 ? NSMaxRange(selection) - 1 : selection.location)
        let lineRange = source.lineRange(for: NSRange(location: end, length: 0))
        inlineAnchor = max(0, min(source.length - 1, NSMaxRange(lineRange) - 1))
        inlinePanel = panel
        addSubview(panel)
        invalidateInlineLayout()
        scrollToVisible(panel.frame)
    }

    func closeInlinePanel() {
        guard let panel = inlinePanel else { return }
        panel.removeFromSuperview()
        inlinePanel = nil
        invalidateInlineLayout()
    }

    private func invalidateInlineLayout() {
        guard let manager = layoutManager, let container = textContainer else { return }
        manager.invalidateLayout(forCharacterRange: NSRange(location: 0, length: (string as NSString).length), actualCharacterRange: nil)
        // Only the anchor's layout is required; the rest remains noncontiguous.
        if inlinePanel != nil, !string.isEmpty {
            manager.ensureLayout(forCharacterRange: NSRange(location: inlineAnchor, length: 1))
        }
        manager.ensureLayout(forBoundingRect: visibleRect, in: container)
        needsLayout = true
        layoutSubtreeIfNeeded()
        enclosingScrollView?.verticalRulerView?.needsDisplay = true
        needsDisplay = true
    }

    func manuscriptRect(_ rect: NSRect) -> NSRect {
        guard inlinePanel != nil, rect.height >= inlineHeight else { return rect }
        var result = rect
        result.size.height -= inlineHeight
        return result
    }

    override func layout() {
        super.layout()
        guard let panel = inlinePanel, let manager = layoutManager else { return }
        var y = textContainerOrigin.y
        if !string.isEmpty {
            let glyph = manager.glyphIndexForCharacter(at: min(inlineAnchor, (string as NSString).length - 1))
            let rect = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            y += rect.maxY - inlineHeight
        }
        panel.frame = NSRect(x: textContainerOrigin.x, y: y, width: max(100, bounds.width - 2 * textContainerOrigin.x), height: inlineHeight - 8)
        if string.isEmpty { setFrameSize(NSSize(width: frame.width, height: max(enclosingScrollView?.contentSize.height ?? 0, inlineHeight + 24))) }
    }

    func layoutManager(_ layoutManager: NSLayoutManager, shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<NSRect>, lineFragmentUsedRect: UnsafeMutablePointer<NSRect>, baselineOffset: UnsafeMutablePointer<CGFloat>, in textContainer: NSTextContainer, forGlyphRange glyphRange: NSRange) -> Bool {
        guard inlinePanel != nil, !string.isEmpty else { return false }
        let characters = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        guard NSLocationInRange(min(inlineAnchor, (string as NSString).length - 1), characters) else { return false }
        lineFragmentRect.pointee.size.height += inlineHeight
        lineFragmentUsedRect.pointee.size.height += inlineHeight
        return true
    }

    override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        guard super.shouldChangeText(in: affectedCharRange, replacementString: replacementString) else { return false }
        if inlinePanel != nil, let replacementString {
            if NSMaxRange(affectedCharRange) <= inlineAnchor {
                inlineAnchor += replacementString.utf16.count - affectedCharRange.length
            } else if affectedCharRange.location <= inlineAnchor {
                inlineAnchor = affectedCharRange.location + replacementString.utf16.count
            }
        }
        return true
    }

    override func didChangeText() {
        super.didChangeText()
        if inlinePanel != nil {
            inlineAnchor = min(max(0, inlineAnchor), max(0, (string as NSString).length - 1))
            invalidateInlineLayout()
        }
    }

    @objc private func attachSelectionToAI(_ sender: Any?) {
        commitComposition()
        guard selectedRange().length > 0 else { return }
        NotificationCenter.default.post(name: Notification.Name("aiAttachSelection"), object: (string as NSString).substring(with: selectedRange()))
    }
    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(openInlineAI(_:)) { return isEditable }
        if menuItem.action == #selector(attachSelectionToAI(_:)) { return selectedRange().length > 0 }
        if menuItem.action == #selector(undo(_:)) { return isEditable && documentUndoManager.canUndo }
        if menuItem.action == #selector(redo(_:)) { return isEditable && documentUndoManager.canRedo }
        if menuItem.action == #selector(formatSelection(_:)) { return isEditable && selectedRange().length > 0 }
        return super.validateMenuItem(menuItem)
    }
    @objc private func formatSelection(_ sender: NSMenuItem) {
        let types: [MarkdownFormatType] = [.bold, .italic, .underline, .strikethrough]
        guard types.indices.contains(sender.tag) else { return }
        execute(EditorCommand(.format(types[sender.tag])))
    }
}

final class NativeManuscriptRuler: NSRulerView {
    init(scrollView: NSScrollView) {
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        ruleThickness = 58
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let view = scrollView?.documentView as? NativeManuscriptTextView,
              let manager = view.layoutManager, let container = view.textContainer else { return }
        NSColor.windowBackgroundColor.setFill(); bounds.fill()
        let visible = view.visibleRect.offsetBy(dx: -view.textContainerOrigin.x, dy: -view.textContainerOrigin.y)
        let glyphs = manager.glyphRange(forBoundingRect: visible, in: container)
        let chars = manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        let first = view.line(at: chars.location)
        let last = view.line(at: NSMaxRange(chars))
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular), .foregroundColor: NSColor.secondaryLabelColor]
        for row in first...last {
            let offset = view.lineStarts[row]
            var fragment: NSRect
            if offset == (view.string as NSString).length { fragment = manager.extraLineFragmentRect }
            else {
                let glyph = manager.glyphIndexForCharacter(at: offset)
                fragment = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil, withoutAdditionalLayout: true)
            }
            fragment = view.manuscriptRect(fragment)
            let point = convert(NSPoint(x: 0, y: fragment.minY + view.textContainerOrigin.y), from: view)
            let label = "\(row + 1)" as NSString
            label.draw(at: NSPoint(x: ruleThickness - label.size(withAttributes: attributes).width - 8, y: point.y + max(0, (fragment.height - label.size(withAttributes: attributes).height) / 2)), withAttributes: attributes)
            if view.modifiedLines.contains(row) {
                NSColor.systemOrange.setFill()
                NSRect(x: 2, y: point.y, width: 3, height: max(12, fragment.height)).fill()
            }
        }
    }
}

final class NativeManuscriptHost: NSScrollView {
    var textView: NativeManuscriptTextView { documentView as! NativeManuscriptTextView }
    override func accessibilityChildren() -> [Any]? {
        var children = super.accessibilityChildren() ?? []
        if let panel = (documentView as? NativeManuscriptTextView)?.inlinePanel { children.append(panel) }
        return children
    }
    init(textView: NativeManuscriptTextView) {
        super.init(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        hasVerticalScroller = true
        autohidesScrollers = true
        borderType = .noBorder
        drawsBackground = false
        documentView = textView
        verticalRulerView = NativeManuscriptRuler(scrollView: self)
        hasVerticalRuler = true
        rulersVisible = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
