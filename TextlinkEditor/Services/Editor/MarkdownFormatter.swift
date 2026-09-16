//
//  MarkdownFormatter.swift
//  TextlinkEditor
//
//  마크다운 텍스트 서식 파싱 및 적용
//

import Foundation
import AppKit

/// 마크다운 서식 유형
enum MarkdownFormatType {
    case bold           // **text** or __text__
    case italic         // *text* or _text_
    case boldItalic     // ***text*** or ___text___
    case strikethrough  // ~~text~~
    case underline      // <u>text</u>
}

/// 마크다운 서식 범위
struct MarkdownFormatRange {
    let type: MarkdownFormatType
    let range: NSRange           // 전체 범위 (마크다운 구문 포함)
    let contentRange: NSRange    // 내용만의 범위 (마크다운 구문 제외)
}

/// 마크다운 서식 파서 및 적용기
final class MarkdownFormatter {

    // MARK: - Colors (NSColor for NSTextView)

    /// 에디터 기본 텍스트 색상
    private static var editorTextColor: NSColor { AppColors.nsEditorText }

    /// 마크다운 구문 색상
    private static var markdownSyntaxColor: NSColor { AppColors.nsMarkdownSyntax }

    // MARK: - Parsing

    /// 텍스트에서 마크다운 서식 범위들을 찾아 반환
    static func parseFormattingRanges(in text: String) -> [MarkdownFormatRange] {
        var ranges: [MarkdownFormatRange] = []
        let nsString = text as NSString

        // Bold italic (***text*** or ___text___) - 가장 먼저 체크
        ranges.append(contentsOf: findPatternRanges(
            in: nsString,
            pattern: "\\*{3}(.+?)\\*{3}",
            type: .boldItalic,
            markerLength: 3
        ))
        ranges.append(contentsOf: findPatternRanges(
            in: nsString,
            pattern: "_{3}(.+?)_{3}",
            type: .boldItalic,
            markerLength: 3
        ))

        // Bold (**text** or __text__)
        ranges.append(contentsOf: findPatternRanges(
            in: nsString,
            pattern: "(?<!\\*)\\*{2}(?!\\*)(.+?)(?<!\\*)\\*{2}(?!\\*)",
            type: .bold,
            markerLength: 2
        ))
        ranges.append(contentsOf: findPatternRanges(
            in: nsString,
            pattern: "(?<!_)_{2}(?!_)(.+?)(?<!_)_{2}(?!_)",
            type: .bold,
            markerLength: 2
        ))

        // Italic (*text* or _text_)
        ranges.append(contentsOf: findPatternRanges(
            in: nsString,
            pattern: "(?<!\\*)\\*(?!\\*)(.+?)(?<!\\*)\\*(?!\\*)",
            type: .italic,
            markerLength: 1
        ))
        ranges.append(contentsOf: findPatternRanges(
            in: nsString,
            pattern: "(?<!_)_(?!_)(.+?)(?<!_)_(?!_)",
            type: .italic,
            markerLength: 1
        ))

        // Strikethrough (~~text~~)
        ranges.append(contentsOf: findPatternRanges(
            in: nsString,
            pattern: "~~(.+?)~~",
            type: .strikethrough,
            markerLength: 2
        ))

        // Underline (<u>text</u>)
        ranges.append(contentsOf: findUnderlineRanges(in: nsString))

        return ranges
    }

    private static func findPatternRanges(
        in nsString: NSString,
        pattern: String,
        type: MarkdownFormatType,
        markerLength: Int
    ) -> [MarkdownFormatRange] {
        var ranges: [MarkdownFormatRange] = []

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return ranges
        }

        let matches = regex.matches(
            in: nsString as String,
            options: [],
            range: NSRange(location: 0, length: nsString.length)
        )

        for match in matches {
            let fullRange = match.range
            let contentRange = NSRange(
                location: fullRange.location + markerLength,
                length: fullRange.length - (markerLength * 2)
            )

            ranges.append(MarkdownFormatRange(
                type: type,
                range: fullRange,
                contentRange: contentRange
            ))
        }

        return ranges
    }

    private static func findUnderlineRanges(in nsString: NSString) -> [MarkdownFormatRange] {
        var ranges: [MarkdownFormatRange] = []
        let pattern = "<u>(.+?)</u>"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return ranges
        }

        let matches = regex.matches(
            in: nsString as String,
            options: [],
            range: NSRange(location: 0, length: nsString.length)
        )

        for match in matches {
            let fullRange = match.range
            // <u> = 3, </u> = 4
            let contentRange = NSRange(
                location: fullRange.location + 3,
                length: fullRange.length - 7
            )

            ranges.append(MarkdownFormatRange(
                type: .underline,
                range: fullRange,
                contentRange: contentRange
            ))
        }

        return ranges
    }

    // MARK: - Attributed String Creation

    /// 마크다운 텍스트를 NSAttributedString으로 변환
    static func attributedString(
        from text: String,
        fontSize: CGFloat,
        lineSpacing: CGFloat,
        alignment: NSTextAlignment
    ) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = lineSpacing
        paragraphStyle.alignment = alignment

        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize),
            .paragraphStyle: paragraphStyle,
            .foregroundColor: editorTextColor
        ]

        let attributedString = NSMutableAttributedString(string: text, attributes: baseAttributes)
        let formatRanges = parseFormattingRanges(in: text)

        // 서식 적용 (마크다운 구문은 유지하면서 내용에 스타일 적용)
        for formatRange in formatRanges {
            applyFormat(to: attributedString, formatRange: formatRange, fontSize: fontSize)
        }

        return attributedString
    }

    private static func applyFormat(
        to attributedString: NSMutableAttributedString,
        formatRange: MarkdownFormatRange,
        fontSize: CGFloat
    ) {
        let contentRange = formatRange.contentRange

        // 범위 유효성 검사
        guard contentRange.location >= 0,
              contentRange.location + contentRange.length <= attributedString.length else {
            return
        }

        switch formatRange.type {
        case .bold:
            attributedString.addAttribute(
                .font,
                value: NSFont.boldSystemFont(ofSize: fontSize),
                range: contentRange
            )

        case .italic:
            let italicFont = NSFontManager.shared.font(
                withFamily: NSFont.systemFont(ofSize: fontSize).familyName ?? "System",
                traits: .italicFontMask,
                weight: 5,
                size: fontSize
            ) ?? NSFont.systemFont(ofSize: fontSize)
            attributedString.addAttribute(.font, value: italicFont, range: contentRange)

        case .boldItalic:
            let boldItalicFont = NSFontManager.shared.font(
                withFamily: NSFont.systemFont(ofSize: fontSize).familyName ?? "System",
                traits: [.boldFontMask, .italicFontMask],
                weight: 9,
                size: fontSize
            ) ?? NSFont.boldSystemFont(ofSize: fontSize)
            attributedString.addAttribute(.font, value: boldItalicFont, range: contentRange)

        case .strikethrough:
            attributedString.addAttribute(
                .strikethroughStyle,
                value: NSUnderlineStyle.single.rawValue,
                range: contentRange
            )

        case .underline:
            attributedString.addAttribute(
                .underlineStyle,
                value: NSUnderlineStyle.single.rawValue,
                range: contentRange
            )
        }

        // 마크다운 구문 색상을 연하게 표시
        let fullRange = formatRange.range
        let prefixLength: Int
        let suffixLength: Int

        switch formatRange.type {
        case .boldItalic:
            prefixLength = 3
            suffixLength = 3
        case .bold, .strikethrough:
            prefixLength = 2
            suffixLength = 2
        case .italic:
            prefixLength = 1
            suffixLength = 1
        case .underline:
            prefixLength = 3  // <u>
            suffixLength = 4  // </u>
        }

        // 앞쪽 마크다운 구문
        if prefixLength > 0 {
            let prefixRange = NSRange(location: fullRange.location, length: prefixLength)
            attributedString.addAttribute(.foregroundColor, value: markdownSyntaxColor, range: prefixRange)
        }

        // 뒤쪽 마크다운 구문
        if suffixLength > 0 {
            let suffixRange = NSRange(
                location: fullRange.location + fullRange.length - suffixLength,
                length: suffixLength
            )
            attributedString.addAttribute(.foregroundColor, value: markdownSyntaxColor, range: suffixRange)
        }
    }

    // MARK: - Format Toggle

    /// 선택된 텍스트에 서식 토글 (마크다운 구문 추가/제거)
    static func toggleFormat(
        _ type: MarkdownFormatType,
        in text: String,
        selectedRange: NSRange
    ) -> (newText: String, newSelectedRange: NSRange) {
        guard selectedRange.length > 0 else {
            return (text, selectedRange)
        }

        let nsString = text as NSString
        let selectedText = nsString.substring(with: selectedRange)

        let (prefix, suffix) = markdownMarkers(for: type)

        // 이미 서식이 적용되어 있는지 확인
        if selectedText.hasPrefix(prefix) && selectedText.hasSuffix(suffix) {
            // 서식 제거
            let newText = String(selectedText.dropFirst(prefix.count).dropLast(suffix.count))
            let resultText = nsString.replacingCharacters(in: selectedRange, with: newText)
            let newRange = NSRange(location: selectedRange.location, length: newText.count)
            return (resultText, newRange)
        } else {
            // 서식 추가
            let formattedText = prefix + selectedText + suffix
            let resultText = nsString.replacingCharacters(in: selectedRange, with: formattedText)
            let newRange = NSRange(location: selectedRange.location, length: formattedText.count)
            return (resultText, newRange)
        }
    }

    private static func markdownMarkers(for type: MarkdownFormatType) -> (prefix: String, suffix: String) {
        switch type {
        case .bold:
            return ("**", "**")
        case .italic:
            return ("*", "*")
        case .boldItalic:
            return ("***", "***")
        case .strikethrough:
            return ("~~", "~~")
        case .underline:
            return ("<u>", "</u>")
        }
    }
}
