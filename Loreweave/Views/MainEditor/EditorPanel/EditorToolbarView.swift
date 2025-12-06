//
//  EditorToolbarView.swift
//  Loreweave
//
//  에디터 툴바 뷰 - 서식 버튼, 폰트 크기, 줄 간격 등
//  EditorPanelView의 하위 컴포넌트
//

import SwiftUI
import AppKit

// MARK: - Editor Toolbar View

struct EditorToolbarView: View {
    @Binding var fontSize: CGFloat
    @Binding var lineSpacingOption: LineSpacingOption
    @Binding var textAlignment: TextAlignmentOption
    var onFormatAction: ((MarkdownFormatType) -> Void)?

    var body: some View {
        HStack(spacing: 16) {
            // 서식 버튼 그룹
            HStack(spacing: 4) {
                ToolbarButton(icon: "bold", tooltip: L10n.editor.bold, action: { onFormatAction?(.bold) })
                ToolbarButton(icon: "italic", tooltip: L10n.editor.italic, action: { onFormatAction?(.italic) })
                ToolbarButton(icon: "underline", tooltip: L10n.editor.underline, action: { onFormatAction?(.underline) })
                ToolbarButton(icon: "strikethrough", tooltip: L10n.editor.strikethrough, action: { onFormatAction?(.strikethrough) })
            }

            // 텍스트 정렬 버튼
            HStack(spacing: 2) {
                ForEach(TextAlignmentOption.allCases) { alignment in
                    ToolbarToggleButton(
                        icon: alignment.icon,
                        tooltip: alignment.tooltip,
                        isSelected: textAlignment == alignment,
                        action: { textAlignment = alignment }
                    )
                }
            }

            // 폰트 크기 슬라이더 및 입력 필드
            HStack(spacing: 4) {
                Image(systemName: "textformat.size")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.toolbarIcon)

                Slider(value: $fontSize, in: 12...24, step: 1)
                    .frame(width: 80)
                    .controlSize(.small)
                    .tint(AppColors.accent)

                FontSizeInputField(fontSize: $fontSize)
            }
            .help(L10n.editor.fontSize)

            // 줄 간격 드롭다운
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.and.down.text.horizontal")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.toolbarIcon)

                Picker("", selection: $lineSpacingOption) {
                    ForEach(LineSpacingOption.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 70)
            }
            .help(L10n.editor.lineSpacing)

            Spacer()

            // AI 도구 메뉴
            Menu {
                Button(L10n.ai.refineText, action: {})
                Button(L10n.ai.styleConvert, action: {})
                Button(L10n.ai.continueWritingAction, action: {})
                Divider()
                Button(L10n.ai.consistencyCheck, action: {})
            } label: {
                Label(L10n.ai.tools, systemImage: "wand.and.stars")
                    .font(.system(size: 12))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .environment(\.controlActiveState, .key)
    }
}

// MARK: - Toolbar Button

struct ToolbarButton: View {
    let icon: String
    let tooltip: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(AppColors.toolbarIcon)
                .frame(width: 28, height: 24)
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }
}

// MARK: - Toolbar Toggle Button

struct ToolbarToggleButton: View {
    let icon: String
    let tooltip: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(isSelected ? AppColors.toolbarIconActive : AppColors.toolbarIcon)
                .frame(width: 28, height: 24)
                .background(isSelected ? AppColors.toolbarToggleSelected : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }
}

// MARK: - Font Size Input Field

struct FontSizeInputField: View {
    @Binding var fontSize: CGFloat
    @State private var inputText: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            TextField("", text: $inputText)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .frame(width: 24)
                .multilineTextAlignment(.trailing)
                .focused($isFocused)
                .onSubmit {
                    applyFontSize()
                }
                .onChange(of: isFocused) { _, focused in
                    if focused {
                        inputText = "\(Int(fontSize))"
                    } else {
                        inputText = "\(Int(fontSize))"
                    }
                }

            Text("pt")
                .font(.system(size: 11))
                .foregroundStyle(AppColors.textSecondary)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isFocused ? AppColors.controlBackground : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(isFocused ? AppColors.accent : Color.clear, lineWidth: 1)
        )
        .onAppear {
            inputText = "\(Int(fontSize))"
        }
        .onChange(of: fontSize) { _, newValue in
            if !isFocused {
                inputText = "\(Int(newValue))"
            }
        }
    }

    private func applyFontSize() {
        if let value = Int(inputText), value >= 8, value <= 72 {
            fontSize = CGFloat(value)
        }
        inputText = "\(Int(fontSize))"
        isFocused = false
    }
}

// MARK: - Text Alignment Option

enum TextAlignmentOption: CaseIterable, Identifiable {
    case left
    case center
    case right
    case justified

    var id: Self { self }

    var icon: String {
        switch self {
        case .left: return "text.alignleft"
        case .center: return "text.aligncenter"
        case .right: return "text.alignright"
        case .justified: return "text.justify"
        }
    }

    var nsTextAlignment: NSTextAlignment {
        switch self {
        case .left: return .left
        case .center: return .center
        case .right: return .right
        case .justified: return .justified
        }
    }

    var tooltip: String {
        switch self {
        case .left: return L10n.editor.alignLeft
        case .center: return L10n.editor.alignCenter
        case .right: return L10n.editor.alignRight
        case .justified: return L10n.editor.alignJustified
        }
    }
}

// MARK: - Line Spacing Option

enum LineSpacingOption: CGFloat, CaseIterable, Identifiable {
    case compact = 4      // 80%
    case normal = 8       // 100%
    case relaxed = 12     // 125%
    case loose = 16       // 150%
    case extraLoose = 20  // 200%

    var id: CGFloat { rawValue }

    var displayName: String {
        switch self {
        case .compact: return "80%"
        case .normal: return "100%"
        case .relaxed: return "125%"
        case .loose: return "150%"
        case .extraLoose: return "200%"
        }
    }
}

#Preview {
    EditorToolbarView(
        fontSize: .constant(16),
        lineSpacingOption: .constant(.normal),
        textAlignment: .constant(.left)
    )
}
