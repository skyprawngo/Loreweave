import SwiftUI
import AppKit

/// Document formatting stays below navigation. Narrow editors expose the same controls in a popover.
struct EditorToolbarView: View {
    @Binding var fontSize: CGFloat
    @Binding var lineSpacingOption: LineSpacingOption
    @Binding var letterSpacing: CGFloat
    @Binding var fontName: String
    var onToolAction: ((String) -> Void)?
    @Binding var presentedTool: String?
    @State private var showingFormat = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                formatButtons
                Divider().frame(height: 18)
                FontPickerControl(fontName: $fontName, fontSize: $fontSize)
                FontSizeControl(fontSize: $fontSize)
                LineSpacingControl(lineSpacingOption: $lineSpacingOption)
                LetterSpacingControl(letterSpacing: $letterSpacing)
                aiToolsMenu
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                formatButtons
                Button { showingFormat.toggle() } label: {
                    Label(L10n.get("toolbar.format"), systemImage: "textformat")
                }
                .buttonStyle(.borderless)
                .popover(isPresented: $showingFormat) {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                        GridRow {
                            Text(L10n.get("settings.editor.fontName"))
                            FontPickerControl(fontName: $fontName, fontSize: $fontSize)
                        }
                        GridRow {
                            Text(L10n.editor.fontSize)
                            FontSizeControl(fontSize: $fontSize)
                        }
                        GridRow {
                            Text(L10n.editor.lineSpacing)
                            LineSpacingControl(lineSpacingOption: $lineSpacingOption)
                        }
                        GridRow {
                            Text(L10n.get("editor.letterSpacing"))
                            LetterSpacingControl(letterSpacing: $letterSpacing)
                        }
                    }.padding(16)
                }
                aiToolsMenu
                Spacer(minLength: 0)
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
        .popover(isPresented: Binding(get: { presentedTool != nil }, set: { if !$0 { presentedTool = nil } })) {
            VStack(alignment: .leading, spacing: 12) {
                if presentedTool == "font" {
                    Text(L10n.get("settings.editor.fontName"))
                    FontPickerControl(fontName: $fontName, fontSize: $fontSize)
                } else if presentedTool == "fontSize" {
                    Text(L10n.editor.fontSize)
                    FontSizeControl(fontSize: $fontSize)
                } else if presentedTool == "lineSpacing" {
                    Text(L10n.editor.lineSpacing)
                    LineSpacingControl(lineSpacingOption: $lineSpacingOption)
                } else if presentedTool == "letterSpacing" {
                    Text(L10n.get("editor.letterSpacing"))
                    LetterSpacingControl(letterSpacing: $letterSpacing)
                }
            }.padding(16)
        }
    }

    private var formatButtons: some View {
        HStack(spacing: 2) {
            formatButton("bold", L10n.editor.bold, .bold)
            formatButton("italic", L10n.editor.italic, .italic)
            formatButton("underline", L10n.editor.underline, .underline)
            formatButton("strikethrough", L10n.editor.strikethrough, .strikethrough)
        }.fixedSize()
    }

    private func formatButton(_ icon: String, _ title: String, _ format: MarkdownFormatType) -> some View {
        Button { onToolAction?("format.\(format)") } label: {
            Image(systemName: icon).frame(width: 26, height: 26)
        }
        .buttonStyle(.borderless)
        .help(title)
        .accessibilityLabel(title)
    }

    private var aiToolsMenu: some View {
        Menu {
            ForEach(EditorToolRegistry.tools.filter { $0.category == .ai }) { tool in
                Button(L10n.get(tool.titleKey)) { onToolAction?(tool.id) }
            }
        } label: {
            Image(systemName: "wand.and.stars").frame(width: 26, height: 26)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(L10n.ai.tools)
        .help(L10n.ai.tools)
    }

}

private struct FontSizeControl: View {
    @Binding var fontSize: CGFloat
    private var value: Binding<Double> {
        Binding(get: { Double(fontSize) }, set: { if $0.isFinite { fontSize = min(72, max(8, $0)) } })
    }
    var body: some View {
        HStack(spacing: 4) {
            ScrubbableNumberField(title: L10n.editor.fontSize, value: value, range: 8...72, step: 1)
            Text("pt").foregroundStyle(.secondary)
        }
        .fixedSize()
        .help(L10n.editor.fontSize)
    }
}

private struct LetterSpacingControl: View {
    @Binding var letterSpacing: CGFloat
    private var value: Binding<Double> {
        Binding(get: { Double(letterSpacing) }, set: { if $0.isFinite { letterSpacing = min(20, max(-5, $0)) } })
    }
    var body: some View {
        HStack(spacing: 4) {
            Text("AV").font(.caption).kerning(2).accessibilityHidden(true)
            ScrubbableNumberField(title: L10n.get("editor.letterSpacing"), value: value, range: -5...20, step: 0.1)
        }
        .fixedSize()
        .help(L10n.get("editor.letterSpacing"))
    }
}

/// Click to type; drag the displayed value horizontally to scrub without selecting text.
private struct ScrubbableNumberField: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    @State private var dragStartValue: Double?
    @State private var isEditing = false
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    private var formattedValue: String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    private var fieldWidth: CGFloat {
        let text = isEditing ? draft : formattedValue
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        return max(18, ceil((text as NSString).size(withAttributes: [.font: font]).width) + 4)
    }

    var body: some View {
        Group {
            if isEditing {
                TextField(title, text: $draft)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .onSubmit { finishEditing() }
                    .onExitCommand {
                        isEditing = false
                        isFocused = false
                    }
                    .onChange(of: isFocused) { _, focused in
                        if !focused { finishEditing() }
                    }
                    .onAppear { isFocused = true }
            } else {
                Text(formattedValue)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .global)
                        .onChanged { gesture in
                            if dragStartValue == nil { dragStartValue = value }
                            let steps = (gesture.translation.width / 4).rounded(.towardZero)
                            setValue((dragStartValue ?? value) + steps * step)
                        }
                        .onEnded { _ in dragStartValue = nil })
                    .onTapGesture {
                        draft = formattedValue
                        isEditing = true
                    }
                    .accessibilityLabel(title)
                    .accessibilityValue(formattedValue)
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: setValue(value + step)
                        case .decrement: setValue(value - step)
                        @unknown default: break
                        }
                    }
            }
        }
        .font(.system(size: NSFont.smallSystemFontSize).monospacedDigit())
        .multilineTextAlignment(.trailing)
        .frame(width: fieldWidth, height: 22)
        .help(title)
    }

    private func setValue(_ candidate: Double) {
        guard candidate.isFinite else { return }
        value = min(range.upperBound, max(range.lowerBound, (candidate * 10).rounded() / 10))
    }

    private func finishEditing() {
        guard isEditing else { return }
        if let number = try? Double(draft, format: .number) { setValue(number) }
        isEditing = false
        isFocused = false
    }
}

private struct LineSpacingControl: View {
    @Binding var lineSpacingOption: LineSpacingOption
    var body: some View {
        Picker(L10n.editor.lineSpacing, selection: $lineSpacingOption) {
            ForEach(LineSpacingOption.allCases) { option in
                Text(option.displayName).tag(option)
            }
        }
        .labelsHidden()
        .buttonStyle(.borderless)
        .fixedSize(horizontal: true, vertical: false)
        .help(L10n.editor.lineSpacing)
    }
}

private struct FontPickerControl: View {
    @Binding var fontName: String
    @Binding var fontSize: CGFloat

    private var displayName: String { fontName.isEmpty ? "System" : fontName }
    private var labelWidth: CGFloat {
        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let measured = (displayName as NSString).size(withAttributes: [.font: font]).width
        return min(120, max(40, ceil(measured)))
    }

    var body: some View {
        Button(action: showFontPanel) {
            Text(displayName)
                .font(.system(size: NSFont.smallSystemFontSize))
                .lineLimit(1).truncationMode(.middle)
                .frame(width: labelWidth, alignment: .leading)
        }
        .buttonStyle(.borderless)
        .help(L10n.get("settings.editor.fontName"))
        .accessibilityLabel(L10n.get("settings.editor.fontName"))
        .accessibilityValue(fontName)
    }

    /// 시스템 폰트 패널 표시
    private func showFontPanel() {
        let fontPanel = NSFontPanel.shared
        let fontManager = NSFontManager.shared

        // 현재 폰트 설정
        let currentFont: NSFont
        if fontName.isEmpty || fontName == "System" || fontName == "SF Pro" {
            currentFont = NSFont.systemFont(ofSize: fontSize)
        } else {
            currentFont = NSFont(name: fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        }

        fontManager.setSelectedFont(currentFont, isMultiple: false)
        fontManager.target = FontPanelDelegate.shared
        fontManager.action = #selector(FontPanelDelegate.changeFont(_:))

        // 폰트 변경 콜백 설정
        FontPanelDelegate.shared.onFontChange = { newFont in
            fontName = newFont.fontName
            fontSize = newFont.pointSize
        }

        fontPanel.orderFront(nil)
    }
}

// MARK: - Font Panel Delegate

/// NSFontPanel 이벤트를 처리하는 델리게이트
private class FontPanelDelegate: NSObject {
    static let shared = FontPanelDelegate()

    var onFontChange: ((NSFont) -> Void)?

    @objc func changeFont(_ sender: NSFontManager?) {
        guard let fontManager = sender else { return }

        // 현재 선택된 폰트를 기반으로 새 폰트 가져오기
        let currentFont = fontManager.selectedFont ?? NSFont.systemFont(ofSize: 14)
        let newFont = fontManager.convert(currentFont)

        onFontChange?(newFont)
    }
}

enum LineSpacingOption: CGFloat, CaseIterable, Identifiable {
    case normal = 1.0       // 100%
    case relaxed = 1.25     // 125%
    case loose = 1.5        // 150%
    case extraLoose = 1.75  // 175%

    var id: CGFloat { rawValue }

    var displayName: String {
        switch self {
        case .normal: return "100%"
        case .relaxed: return "125%"
        case .loose: return "150%"
        case .extraLoose: return "175%"
        }
    }
}
