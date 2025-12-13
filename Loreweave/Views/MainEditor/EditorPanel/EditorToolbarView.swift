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

            // 폰트 크기 드래그 입력 필드
            FontSizeControl(fontSize: $fontSize)
                .help(L10n.editor.fontSize)

            // 줄 간격 드롭다운
            LineSpacingControl(lineSpacingOption: $lineSpacingOption)
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
                    .foregroundStyle(AppColors.toolbarIcon)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
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

// MARK: - Font Size Control

struct FontSizeControl: View {
    @Binding var fontSize: CGFloat
    @State private var inputText: String = ""
    @State private var isDragging: Bool = false
    @State private var dragStartValue: CGFloat = 0
    @FocusState private var isFocused: Bool

    private let minSize: CGFloat = 8
    private let maxSize: CGFloat = 72
    private let dragSensitivity: CGFloat = 0.5

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "textformat.size")
                .font(.system(size: 12))
                .foregroundStyle(AppColors.toolbarIcon)

            TextField("", text: $inputText)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(AppColors.textPrimary)
                .frame(width: 18)
                .multilineTextAlignment(.leading)
                .focused($isFocused)
                .onSubmit {
                    applyFontSize()
                }
                .onChange(of: isFocused) { _, focused in
                    if focused {
                        inputText = "\(Int(fontSize))"
                    } else {
                        applyFontSize()
                    }
                }

            Text("pt")
                .font(.system(size: 11))
                .foregroundStyle(AppColors.textSecondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(AppColors.controlBackground)
        )
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        dragStartValue = fontSize
                        NSCursor.resizeLeftRight.push()
                    }
                    let delta = value.translation.width * dragSensitivity
                    let newValue = dragStartValue + delta
                    let clampedValue = min(maxSize, max(minSize, round(newValue)))
                    fontSize = clampedValue
                    inputText = "\(Int(clampedValue))"
                }
                .onEnded { _ in
                    isDragging = false
                    NSCursor.pop()
                }
        )
        .onHover { hovering in
            if hovering && !isDragging {
                NSCursor.resizeLeftRight.push()
            } else if !hovering && !isDragging {
                NSCursor.pop()
            }
        }
        .onAppear {
            inputText = "\(Int(fontSize))"
        }
        .onChange(of: fontSize) { _, newValue in
            // 외부에서 fontSize가 변경된 경우 inputText 동기화
            if !isDragging && !isFocused {
                inputText = "\(Int(newValue))"
            }
        }
    }

    private func applyFontSize() {
        if let value = Int(inputText), value >= Int(minSize), value <= Int(maxSize) {
            fontSize = CGFloat(value)
        }
        inputText = "\(Int(fontSize))"
    }
}

// MARK: - Line Spacing Control (아이콘 포함 드롭다운)

struct LineSpacingControl: View {
    @Binding var lineSpacingOption: LineSpacingOption

    var body: some View {
        Menu {
            ForEach(LineSpacingOption.allCases) { option in
                Button(action: { lineSpacingOption = option }) {
                    HStack {
                        Text(option.displayName)
                        if lineSpacingOption == option {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.and.down.text.horizontal")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.toolbarIcon)

                Text(lineSpacingOption.displayName)
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.textPrimary)

                Image(systemName: "chevron.down")
                    .font(.system(size: 8))
                    .foregroundStyle(AppColors.textSecondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(AppColors.controlBackground)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

// MARK: - Line Spacing Option

/// 줄간격 옵션 - lineHeightMultiple 값 사용
/// 100%가 기본값(추가 간격 없음), 그 이상은 줄 높이 배수 증가
enum LineSpacingOption: CGFloat, CaseIterable, Identifiable {
    case normal = 1.0       // 100% - 기본 줄 높이 (추가 간격 없음)
    case relaxed = 1.25     // 125%
    case loose = 1.5        // 150%
    case extraLoose = 2.0   // 200%

    var id: CGFloat { rawValue }

    var displayName: String {
        switch self {
        case .normal: return "100%"
        case .relaxed: return "125%"
        case .loose: return "150%"
        case .extraLoose: return "200%"
        }
    }
}

#Preview {
    EditorToolbarView(
        fontSize: .constant(14),
        lineSpacingOption: .constant(.normal)
    )
}
