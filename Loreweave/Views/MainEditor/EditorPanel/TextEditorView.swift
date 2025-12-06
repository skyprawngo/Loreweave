//
//  TextEditorView.swift
//  Loreweave
//
//  텍스트 에디터 뷰 - 순수 SwiftUI 버전
//  EditorPanelView의 하위 컴포넌트
//
//  주의: NavigationSplitView detail 영역에서 NSViewRepresentable 사용 금지
//  AppKit 래퍼 사용 시 컨트롤이 비활성 상태로 렌더링되는 버그 발생
//

import SwiftUI

// MARK: - Text Editor View

/// 텍스트 에디터 뷰 (줄번호 + 단일 TextEditor)
struct TextEditorView: View {
    @Binding var text: String
    @Binding var cursorLine: Int
    @Binding var selectedLineRange: ClosedRange<Int>?

    let fontSize: CGFloat
    let lineSpacing: CGFloat
    let textAlignment: NSTextAlignment
    let isEditable: Bool

    /// 서식 토글 요청
    var formatAction: MarkdownFormatType?
    /// 서식 적용 후 콜백
    var onFormatApplied: (() -> Void)?

    /// 텍스트 에디터 콘텐츠 높이
    @State private var contentHeight: CGFloat = 100
    /// 텍스트 에디터 너비 (줄바꿈 계산용)
    @State private var editorWidth: CGFloat = 0
    /// 각 줄의 렌더링 높이
    @State private var lineRenderHeights: [CGFloat] = []

    /// 텍스트 줄 배열
    private var lines: [String] {
        let result = text.components(separatedBy: "\n")
        return result.isEmpty ? [""] : result
    }

    /// 기본 단일 줄 높이
    private var singleLineHeight: CGFloat {
        let font = NSFont.systemFont(ofSize: fontSize)
        return ceil(font.ascender - font.descender + font.leading + lineSpacing)
    }

    /// 뷰 갱신을 위한 ID (폰트/줄간격 변경 시 재생성)
    private var viewId: String {
        "\(fontSize)-\(lineSpacing)"
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical, showsIndicators: true) {
                HStack(alignment: .top, spacing: 0) {
                    // 줄번호 영역
                    LineNumberGutter(
                        lineCount: lines.count,
                        lineHeights: lineRenderHeights,
                        fontSize: fontSize,
                        singleLineHeight: singleLineHeight,
                        currentLine: cursorLine
                    )
                    .frame(width: 50)

                    Divider()
                        .frame(height: contentHeight)

                    // 텍스트 에디터
                    TextEditor(text: $text)
                        .font(.system(size: fontSize))
                        .lineSpacing(lineSpacing)
                        .scrollContentBackground(.hidden)
                        .scrollDisabled(true)
                        .disabled(!isEditable)
                        .frame(height: contentHeight)
                        .background(AppColors.textEditorBackground)
                }
                .background(
                    GeometryReader { contentGeometry in
                        Color.clear
                            .onAppear {
                                updateMetrics(containerWidth: geometry.size.width - 51)
                            }
                            .onChange(of: text) { _, _ in
                                updateMetrics(containerWidth: geometry.size.width - 51)
                            }
                            .onChange(of: geometry.size.width) { _, newWidth in
                                updateMetrics(containerWidth: newWidth - 51)
                            }
                    }
                )
            }
            .id(viewId)  // 폰트/줄간격 변경 시 ScrollView 재생성
            .onChange(of: viewId) { _, _ in
                // 폰트/줄간격 변경 시 메트릭 재계산
                DispatchQueue.main.async {
                    updateMetrics(containerWidth: geometry.size.width - 51)
                }
            }
        }
        .background(AppColors.textEditorBackground)
    }

    /// 메트릭 업데이트 (콘텐츠 높이, 줄별 렌더링 높이)
    private func updateMetrics(containerWidth: CGFloat) {
        editorWidth = containerWidth

        // 각 줄의 렌더링 높이 계산
        let heights = calculateLineHeights(containerWidth: containerWidth)
        lineRenderHeights = heights

        // 전체 콘텐츠 높이 (여유 공간 추가)
        let totalHeight = heights.reduce(0, +)
        contentHeight = max(singleLineHeight, totalHeight + singleLineHeight)
    }

    /// 각 줄의 렌더링 높이 계산 (자동 줄바꿈 고려)
    private func calculateLineHeights(containerWidth: CGFloat) -> [CGFloat] {
        let font = NSFont.systemFont(ofSize: fontSize)
        // TextEditor 내부 패딩 고려
        let availableWidth = max(1, containerWidth - 10)

        return lines.map { line in
            if line.isEmpty {
                return singleLineHeight
            }

            let attributedString = NSAttributedString(
                string: line,
                attributes: [
                    .font: font,
                    .paragraphStyle: {
                        let style = NSMutableParagraphStyle()
                        style.lineSpacing = lineSpacing
                        return style
                    }()
                ]
            )

            let textStorage = NSTextStorage(attributedString: attributedString)
            let textContainer = NSTextContainer(size: NSSize(width: availableWidth, height: .greatestFiniteMagnitude))
            textContainer.lineFragmentPadding = 0
            let layoutManager = NSLayoutManager()
            layoutManager.addTextContainer(textContainer)
            textStorage.addLayoutManager(layoutManager)

            layoutManager.ensureLayout(for: textContainer)

            let glyphRange = layoutManager.glyphRange(for: textContainer)
            let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)

            // lineSpacing 추가
            let baseHeight = font.ascender - font.descender + font.leading
            let wrappedLines = max(1, ceil(rect.height / baseHeight))

            return wrappedLines * singleLineHeight
        }
    }
}

// MARK: - Line Number Gutter

/// 줄번호 표시 영역 (ScrollView 없이, 부모 ScrollView와 함께 스크롤)
private struct LineNumberGutter: View {
    let lineCount: Int
    let lineHeights: [CGFloat]
    let fontSize: CGFloat
    let singleLineHeight: CGFloat
    let currentLine: Int

    /// TextEditor 내부 상단 패딩과 동일하게 맞춤
    private var topPadding: CGFloat {
        // TextEditor의 기본 상단 패딩 (약 4pt 고정)
        4
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            ForEach(0..<lineCount, id: \.self) { index in
                let lineNumber = index + 1
                let height = index < lineHeights.count ? lineHeights[index] : singleLineHeight

                Text("\(lineNumber)")
                    .font(.system(size: fontSize - 2).monospacedDigit())
                    .foregroundStyle(lineNumber == currentLine ? AppColors.textPrimary : AppColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .frame(height: height, alignment: .top)
                    .padding(.trailing, 8)
                    .padding(.top, topPadding)
                    .background(lineNumber == currentLine ? AppColors.accent.opacity(0.1) : Color.clear)
            }
        }
        .background(AppColors.controlBackground.opacity(0.5))
    }
}

#Preview {
    TextEditorView(
        text: .constant("Hello, World!\n\nThis is a test.\nLine 4\nLine 5\nLine 6\nLine 7\nLine 8\nLine 9\nLine 10\n\n긴 텍스트 테스트입니다. 이 줄은 자동으로 줄바꿈이 되어야 합니다. 창 크기를 줄이면 여러 줄로 표시됩니다."),
        cursorLine: .constant(1),
        selectedLineRange: .constant(nil),
        fontSize: 16,
        lineSpacing: 8,
        textAlignment: .left,
        isEditable: true
    )
}
