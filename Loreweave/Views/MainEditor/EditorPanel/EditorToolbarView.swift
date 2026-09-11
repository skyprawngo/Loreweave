//
//  EditorToolbarView.swift
//  Loreweave
//
//  에디터 툴바 뷰 - 서식 버튼, 폰트 크기, 줄 간격 등
//  EditorPanelView의 하위 컴포넌트
//

import SwiftUI
import AppKit

// MARK: - Constants

private enum ToolbarConstants {
    // 레이아웃
    static let toolbarHorizontalPadding: CGFloat = 16
    static let toolbarVerticalPadding: CGFloat = 8
    static let groupSpacing: CGFloat = 16
    static let buttonSpacing: CGFloat = 4

    // 버튼 크기
    static let buttonWidth: CGFloat = 28
    static let buttonHeight: CGFloat = 24

    // 폰트 크기
    static let iconFontSize: CGFloat = 13
    static let smallIconFontSize: CGFloat = 12
    static let labelFontSize: CGFloat = 11
    static let chevronFontSize: CGFloat = 8

    // 컨트롤 스타일
    static let controlCornerRadius: CGFloat = 6
    static let controlHorizontalPadding: CGFloat = 8
    static let controlVerticalPadding: CGFloat = 5

    // 폰트 크기 범위
    static let minFontSize: CGFloat = 8
    static let maxFontSize: CGFloat = 72
    static let fontSizeDragSensitivity: CGFloat = 0.5
    static let fontSizeInputWidth: CGFloat = 18
}

// MARK: - Editor Toolbar View

struct EditorToolbarView: View {
    @Binding var fontSize: CGFloat
    @Binding var lineSpacingOption: LineSpacingOption
    @Binding var letterSpacing: CGFloat
    @Binding var fontName: String
    var onFormatAction: ((MarkdownFormatType) -> Void)?

    var body: some View {
        HStack(spacing: ToolbarConstants.groupSpacing) {
            formatButtonGroup
            FontPickerControl(fontName: $fontName, fontSize: $fontSize)
            FontSizeControl(fontSize: $fontSize)
            LineSpacingControl(lineSpacingOption: $lineSpacingOption)
            LetterSpacingControl(letterSpacing: $letterSpacing)
            Spacer()
            aiToolsMenu
        }
        .padding(.horizontal, ToolbarConstants.toolbarHorizontalPadding)
        .padding(.vertical, ToolbarConstants.toolbarVerticalPadding)
    }

    // MARK: - Subviews

    private var formatButtonGroup: some View {
        HStack(spacing: ToolbarConstants.buttonSpacing) {
            ToolbarIconButton(icon: "bold", tooltip: L10n.editor.bold) {
                onFormatAction?(.bold)
            }
            ToolbarIconButton(icon: "italic", tooltip: L10n.editor.italic) {
                onFormatAction?(.italic)
            }
            ToolbarIconButton(icon: "underline", tooltip: L10n.editor.underline) {
                onFormatAction?(.underline)
            }
            ToolbarIconButton(icon: "strikethrough", tooltip: L10n.editor.strikethrough) {
                onFormatAction?(.strikethrough)
            }
        }
    }

    private var aiToolsMenu: some View {
        Menu {
            Button(L10n.ai.refineText) { NotificationCenter.default.post(name: Notification.Name("aiDraftAction"), object: L10n.ai.refineText) }
            Button(L10n.ai.styleConvert) { NotificationCenter.default.post(name: Notification.Name("aiDraftAction"), object: L10n.ai.styleConvert) }
            Button(L10n.ai.continueWritingAction) { NotificationCenter.default.post(name: Notification.Name("aiDraftAction"), object: L10n.ai.continueWritingAction) }
            Divider()
            Button(L10n.ai.consistencyCheck) { NotificationCenter.default.post(name: Notification.Name("aiDraftAction"), object: L10n.ai.consistencyCheck) }
        } label: {
            Label(L10n.ai.tools, systemImage: "wand.and.stars")
                .font(.system(size: ToolbarConstants.smallIconFontSize))
                .foregroundStyle(AppColors.toolbarIcon)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

// MARK: - Toolbar Icon Button

private struct ToolbarIconButton: View {
    let icon: String
    let tooltip: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: ToolbarConstants.iconFontSize))
                .foregroundStyle(AppColors.toolbarIcon)
                .frame(
                    width: ToolbarConstants.buttonWidth,
                    height: ToolbarConstants.buttonHeight
                )
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }
}

// MARK: - Control Background Style

private struct ControlBackgroundStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, ToolbarConstants.controlHorizontalPadding)
            .padding(.vertical, ToolbarConstants.controlVerticalPadding)
            .background(
                RoundedRectangle(cornerRadius: ToolbarConstants.controlCornerRadius)
                    .fill(AppColors.controlBackground)
            )
    }
}

private extension View {
    func controlBackground() -> some View {
        modifier(ControlBackgroundStyle())
    }
}

// MARK: - Font Size Control

private struct FontSizeControl: View {
    @Binding var fontSize: CGFloat
    @State private var inputText: String = ""
    @State private var dragState = DragState()
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 4) {
            TextField("", text: $inputText)
                .textFieldStyle(.plain)
                .font(.system(size: ToolbarConstants.labelFontSize))
                .foregroundStyle(AppColors.textPrimary)
                .frame(width: ToolbarConstants.fontSizeInputWidth)
                .multilineTextAlignment(.leading)
                .focused($isFocused)
                .onSubmit(applyFontSize)
                .onChange(of: isFocused) { _, focused in
                    handleFocusChange(focused)
                }

            Text("pt")
                .font(.system(size: ToolbarConstants.labelFontSize))
                .foregroundStyle(AppColors.textSecondary)
        }
        .controlBackground()
        .fixedSize()  // 크기 고정하여 레이아웃 변동 방지
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .onHover(perform: handleHover)
        .onAppear { syncInputText() }
        .onChange(of: fontSize) { _, _ in
            if !dragState.isDragging && !isFocused {
                syncInputText()
            }
        }
        .help(L10n.editor.fontSize)
    }

    // MARK: - Gestures

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if !dragState.isDragging {
                    dragState.startDragging(from: fontSize)
                }
                let delta = value.translation.width * ToolbarConstants.fontSizeDragSensitivity
                let newValue = clampFontSize(dragState.startValue + delta)
                fontSize = newValue
                inputText = "\(Int(newValue))"
            }
            .onEnded { _ in
                dragState.endDragging()
            }
    }

    // MARK: - Actions

    private func handleFocusChange(_ focused: Bool) {
        if focused {
            inputText = "\(Int(fontSize))"
        } else {
            applyFontSize()
        }
    }

    private func handleHover(_ hovering: Bool) {
        guard !dragState.isDragging else { return }

        if hovering {
            NSCursor.resizeLeftRight.push()
        } else {
            NSCursor.pop()
        }
    }

    private func applyFontSize() {
        if let value = Int(inputText) {
            fontSize = clampFontSize(CGFloat(value))
        }
        syncInputText()
    }

    private func syncInputText() {
        inputText = "\(Int(fontSize))"
    }

    private func clampFontSize(_ value: CGFloat) -> CGFloat {
        min(ToolbarConstants.maxFontSize, max(ToolbarConstants.minFontSize, round(value)))
    }
}

// MARK: - Drag State

private extension FontSizeControl {
    struct DragState {
        var isDragging = false
        var startValue: CGFloat = 0

        mutating func startDragging(from value: CGFloat) {
            isDragging = true
            startValue = value
            NSCursor.resizeLeftRight.push()
        }

        mutating func endDragging() {
            isDragging = false
            NSCursor.pop()
        }
    }
}

// MARK: - Font Picker Control

private struct FontPickerControl: View {
    @Binding var fontName: String
    @Binding var fontSize: CGFloat

    var body: some View {
        Button {
            showFontPanel()
        } label: {
            HStack(spacing: 4) {
                Text(displayFontName)
                    .font(.system(size: ToolbarConstants.labelFontSize))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                    .frame(width: 80, alignment: .leading)  // maxWidth → width 고정

                Image(systemName: "chevron.down")
                    .font(.system(size: ToolbarConstants.chevronFontSize))
                    .foregroundStyle(AppColors.textSecondary)
            }
            .controlBackground()
        }
        .buttonStyle(.plain)
        .fixedSize()  // 크기 고정하여 레이아웃 변동 방지
        .help(L10n.get("settings.editor.fontName"))
    }

    /// 표시용 폰트 이름 (너무 길면 축약)
    private var displayFontName: String {
        let name = fontName.isEmpty ? "System" : fontName
        return name.count > 12 ? String(name.prefix(10)) + "..." : name
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

// MARK: - Line Spacing Control

private struct LineSpacingControl: View {
    @Binding var lineSpacingOption: LineSpacingOption

    var body: some View {
        Menu {
            ForEach(LineSpacingOption.allCases) { option in
                Button {
                    lineSpacingOption = option
                } label: {
                    HStack {
                        Text(option.displayName)
                        if lineSpacingOption == option {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            menuLabel
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(L10n.editor.lineSpacing)
    }

    private var menuLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.up.and.down.text.horizontal")
                .font(.system(size: ToolbarConstants.smallIconFontSize))
                .foregroundStyle(AppColors.toolbarIcon)

            Text(lineSpacingOption.displayName)
                .font(.system(size: ToolbarConstants.labelFontSize))
                .foregroundStyle(AppColors.textPrimary)

            Image(systemName: "chevron.down")
                .font(.system(size: ToolbarConstants.chevronFontSize))
                .foregroundStyle(AppColors.textSecondary)
        }
        .controlBackground()
    }
}

// MARK: - Line Spacing Option

/// 줄간격 옵션 - lineHeightMultiple 값 사용
/// 100%가 기본값(추가 간격 없음), 그 이상은 줄 높이 배수 증가
/// 참고: 200%는 STTextView 라이브러리 버그로 인해 175%로 대체
/// https://github.com/krzyzanowskim/STTextView/issues/XXX
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

// MARK: - Letter Spacing Control

private struct LetterSpacingControl: View {
    @Binding var letterSpacing: CGFloat
    @State private var inputText: String = ""
    @State private var dragState = LetterSpacingDragState()
    @FocusState private var isFocused: Bool

    // 문자 간격 범위
    private static let minSpacing: CGFloat = -5
    private static let maxSpacing: CGFloat = 20
    private static let dragSensitivity: CGFloat = 0.2
    private static let inputWidth: CGFloat = 22

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "character.textbox")
                .font(.system(size: ToolbarConstants.smallIconFontSize))
                .foregroundStyle(AppColors.toolbarIcon)

            TextField("", text: $inputText)
                .textFieldStyle(.plain)
                .font(.system(size: ToolbarConstants.labelFontSize))
                .foregroundStyle(AppColors.textPrimary)
                .frame(width: Self.inputWidth)
                .multilineTextAlignment(.trailing)
                .focused($isFocused)
                .onSubmit(applyValue)
                .onChange(of: isFocused) { _, focused in
                    handleFocusChange(focused)
                }
        }
        .controlBackground()
        .fixedSize()  // 크기 고정하여 레이아웃 변동 방지
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .onHover(perform: handleHover)
        .onAppear { syncInputText() }
        .onChange(of: letterSpacing) { _, _ in
            if !dragState.isDragging && !isFocused {
                syncInputText()
            }
        }
        .help(L10n.get("editor.letterSpacing"))
    }

    // MARK: - Gestures

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if !dragState.isDragging {
                    dragState.startDragging(from: letterSpacing)
                }
                let delta = value.translation.width * Self.dragSensitivity
                let newValue = clampSpacing(dragState.startValue + delta)
                letterSpacing = newValue
                inputText = formatValue(newValue)
            }
            .onEnded { _ in
                dragState.endDragging()
            }
    }

    // MARK: - Actions

    private func handleFocusChange(_ focused: Bool) {
        if focused {
            inputText = formatValue(letterSpacing)
        } else {
            applyValue()
        }
    }

    private func handleHover(_ hovering: Bool) {
        guard !dragState.isDragging else { return }

        if hovering {
            NSCursor.resizeLeftRight.push()
        } else {
            NSCursor.pop()
        }
    }

    private func applyValue() {
        if let value = Double(inputText) {
            letterSpacing = clampSpacing(CGFloat(value))
        }
        syncInputText()
    }

    private func syncInputText() {
        inputText = formatValue(letterSpacing)
    }

    private func formatValue(_ value: CGFloat) -> String {
        if value == 0 {
            return "0"
        } else if value == floor(value) {
            return "\(Int(value))"
        } else {
            return String(format: "%.1f", value)
        }
    }

    private func clampSpacing(_ value: CGFloat) -> CGFloat {
        let clamped = min(Self.maxSpacing, max(Self.minSpacing, value))
        return (clamped * 10).rounded() / 10  // 0.1 단위로 반올림
    }
}

// MARK: - Letter Spacing Drag State

private struct LetterSpacingDragState {
    var isDragging = false
    var startValue: CGFloat = 0

    mutating func startDragging(from value: CGFloat) {
        isDragging = true
        startValue = value
        NSCursor.resizeLeftRight.push()
    }

    mutating func endDragging() {
        isDragging = false
        NSCursor.pop()
    }
}

// MARK: - Preview

#Preview {
    EditorToolbarView(
        fontSize: .constant(14),
        lineSpacingOption: .constant(.normal),
        letterSpacing: .constant(0),
        fontName: .constant("SF Pro")
    )
    .padding()
    .background(Color(nsColor: .windowBackgroundColor))
}
