import AppKit

/// Display-only Markdown projection. No editor text storage or document mutation belongs here.
enum MarkdownPreviewRenderer {
    static func parse(_ source: String) throws -> AttributedString {
        try AttributedString(markdown: source, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
    }

    static func render(_ parsed: AttributedString, font: NSFont, color: NSColor,
                       lineHeightMultiple: CGFloat, letterSpacing: CGFloat) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = lineHeightMultiple
        let output = NSMutableAttributedString(string: "")
        let runs = parsed.runs.map { run in
            (text: String(parsed[run.range].characters), intent: run.inlinePresentationIntent ?? [], link: run.link)
        }
        var openings: [Int] = [], tags = Set<Int>()
        for (index, run) in runs.enumerated() where run.intent.contains(.inlineHTML) {
            if run.text.lowercased() == "<u>" { openings.append(index) }
            else if run.text.lowercased() == "</u>", let opening = openings.popLast() {
                tags.insert(opening); tags.insert(index)
            }
        }
        var underlineDepth = 0
        for (index, run) in runs.enumerated() {
            let text = run.text, intent = run.intent
            if tags.contains(index) {
                underlineDepth += text.lowercased() == "<u>" ? 1 : -1
                continue
            }
            var attributes: [NSAttributedString.Key: Any] = [
                .font: font, .foregroundColor: color, .paragraphStyle: paragraph, .kern: letterSpacing
            ]
            var traits: NSFontTraitMask = []
            if intent.contains(.stronglyEmphasized) { traits.insert(.boldFontMask) }
            if intent.contains(.emphasized) { traits.insert(.italicFontMask) }
            let base = intent.contains(.code) ? NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular) : font
            attributes[.font] = NSFontManager.shared.convert(base, toHaveTrait: traits)
            if intent.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if underlineDepth > 0 { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            if let link = run.link { attributes[.link] = link }
            output.append(NSAttributedString(string: text, attributes: attributes))
        }
        return output
    }
}
