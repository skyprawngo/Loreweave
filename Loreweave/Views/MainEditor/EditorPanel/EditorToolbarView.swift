import SwiftUI
import AppKit

/// Document formatting stays below navigation. Narrow editors expose the same controls in a popover.
struct EditorToolbarView: View {
    @Binding var fontSize: CGFloat
    @Binding var lineSpacingOption: LineSpacingOption
    @Binding var letterSpacing: CGFloat
    @Binding var fontName: String
    var onFormatAction: ((MarkdownFormatType) -> Void)?
    @State private var showingFormat = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                formatButtons
                Divider().frame(height: 18)
                FontPickerControl(fontName: $fontName, fontSize: $fontSize)
                FontSizeControl(fontSize: $fontSize)
                LineSpacingControl(lineSpacingOption: $lineSpacingOption)
                LetterSpacingControl(letterSpacing: $letterSpacing)
                Spacer(minLength: 8)
                aiToolsMenu
            }
            HStack(spacing: 12) {
                formatButtons
                Button { showingFormat.toggle() } label: {
                    Label(L10n.get("toolbar.format"), systemImage: "textformat")
                }
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
                Spacer(minLength: 8)
                aiToolsMenu
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
        Button { onFormatAction?(format) } label: {
            Image(systemName: icon).frame(width: 26, height: 26)
        }
        .buttonStyle(.borderless)
        .help(title)
        .accessibilityLabel(title)
    }

    private var aiToolsMenu: some View {
        Menu {
            Button(L10n.ai.refineText) { draft(L10n.ai.refineText) }
            Button(L10n.ai.styleConvert) { draft(L10n.ai.styleConvert) }
            Button(L10n.ai.continueWritingAction) { draft(L10n.ai.continueWritingAction) }
            Divider()
            Button(L10n.ai.consistencyCheck) { draft(L10n.ai.consistencyCheck) }
        } label: {
            Label(L10n.ai.tools, systemImage: "wand.and.stars")
        }
        .fixedSize()
        .help(L10n.ai.tools)
    }

    private func draft(_ action: String) {
        NotificationCenter.default.post(name: Notification.Name("aiDraftAction"), object: action)
    }
}

private struct FontSizeControl: View {
    @Binding var fontSize: CGFloat
    private var value: Binding<Double> {
        Binding(get: { Double(fontSize) }, set: { if $0.isFinite { fontSize = min(72, max(8, $0)) } })
    }
    var body: some View {
        HStack(spacing: 4) {
            TextField(L10n.editor.fontSize, value: value, format: .number.precision(.fractionLength(0...1)))
                .textFieldStyle(.roundedBorder).frame(width: 44)
            Text("pt").foregroundStyle(.secondary)
            Stepper(L10n.editor.fontSize, value: value, in: 8...72, step: 1).labelsHidden()
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
            TextField(L10n.get("editor.letterSpacing"), value: value, format: .number.precision(.fractionLength(0...1)))
                .textFieldStyle(.roundedBorder).frame(width: 44)
            Stepper(L10n.get("editor.letterSpacing"), value: value, in: -5...20, step: 0.1).labelsHidden()
        }
        .fixedSize()
        .help(L10n.get("editor.letterSpacing"))
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
        .frame(width: 76)
        .help(L10n.editor.lineSpacing)
    }
}

private struct FontPickerControl: View {
    @Binding var fontName: String
    @Binding var fontSize: CGFloat
    var body: some View {
        Button(action: showFontPanel) {
            Text(fontName.isEmpty ? "System" : fontName)
                .lineLimit(1).truncationMode(.middle).frame(width: 80)
        }
        .buttonStyle(.bordered)
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
