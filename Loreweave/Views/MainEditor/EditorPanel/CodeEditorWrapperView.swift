//
//  CodeEditorWrapperView.swift
//  Loreweave
//
//  코드 에디터 뷰 - STTextView 라이브러리 기반
//  EditorContainerView의 하위 컴포넌트
//
//  줄번호, 현재 줄 하이라이트 지원
//

import SwiftUI
import STTextView
import AppKit

// MARK: - Extended STTextView (Scroll Beyond Last Line 지원)

/// STTextView를 확장하여 마지막 줄 이후 추가 스크롤 영역 제공
/// VSCode의 "Editor: Scroll Beyond Last Line" 기능과 동일
private class ExtendedSTTextView: STTextView {
    /// 추가 스크롤 높이 (뷰포트 높이 기준)
    var extraScrollHeight: CGFloat = 0

    /// 실제 텍스트 콘텐츠 높이 (추가 높이 제외)
    private var actualContentHeight: CGFloat = 0

    override func setFrameSize(_ newSize: NSSize) {
        // 실제 텍스트 콘텐츠 높이 저장
        actualContentHeight = newSize.height

        // 추가 스크롤 높이를 더한 크기로 설정
        var extendedSize = newSize
        extendedSize.height += extraScrollHeight

        super.setFrameSize(extendedSize)
    }

    override func mouseDown(with event: NSEvent) {
        // 클릭 위치 확인
        let locationInView = convert(event.locationInWindow, from: nil)

        // 클릭이 원래 텍스트 영역 밖(추가된 빈 영역)인 경우
        // STTextView는 flipped 좌표계 사용 (y가 위에서 아래로 증가)
        if locationInView.y > actualContentHeight {
            // 커서를 텍스트 끝으로 이동
            if let textLength = attributedText?.length {
                selectAndShow(NSRange(location: textLength, length: 0))
            }
            return
        }

        super.mouseDown(with: event)
    }
}

// MARK: - Code Editor Wrapper View

/// 코드 에디터 뷰 (STTextView 라이브러리 래퍼)
struct CodeEditorWrapperView: View {
    @Binding var text: String
    @Binding var cursorLine: Int
    @Binding var selectedLineRange: ClosedRange<Int>?

    /// 폰트 크기 (외부에서 전달받아 변경 감지)
    let fontSize: CGFloat
    /// 줄 높이 배수 (1.0 = 100%, 1.5 = 150%)
    let lineHeightMultiple: CGFloat
    let isEditable: Bool

    /// 서식 토글 요청
    var formatAction: MarkdownFormatType?
    /// 서식 적용 후 콜백
    var onFormatApplied: (() -> Void)?

    var body: some View {
        GeometryReader { geometry in
            STTextViewRepresentable(
                text: $text,
                cursorLine: $cursorLine,
                selectedLineRange: $selectedLineRange,
                fontSize: fontSize,
                lineHeightMultiple: lineHeightMultiple,
                isEditable: isEditable,
                viewportHeight: geometry.size.height
            )
        }
    }
}

// MARK: - STTextView NSViewRepresentable

/// STTextView를 직접 감싸는 NSViewRepresentable
private struct STTextViewRepresentable: NSViewRepresentable {
    @Binding var text: String
    @Binding var cursorLine: Int
    @Binding var selectedLineRange: ClosedRange<Int>?

    /// 폰트 크기 (SwiftUI에서 전달받아 변경 감지)
    let fontSize: CGFloat
    /// 줄 높이 배수 (1.0 = 100%, 1.5 = 150%)
    let lineHeightMultiple: CGFloat
    let isEditable: Bool

    /// 에디터 뷰포트 높이 (스크롤 패딩 계산용)
    let viewportHeight: CGFloat

    /// 현재 설정에 맞는 폰트 생성
    private var currentFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    func makeNSView(context: Context) -> NSScrollView {
        // ExtendedSTTextView 사용 (Scroll Beyond Last Line 지원)
        let scrollView = ExtendedSTTextView.scrollableTextView()
        let textView = scrollView.documentView as! ExtendedSTTextView

        // 기본 설정
        textView.textDelegate = context.coordinator
        textView.highlightSelectedLine = true
        textView.isHorizontallyResizable = false  // 줄 바꿈 활성화
        textView.showsLineNumbers = true
        textView.isEditable = isEditable
        textView.isSelectable = true

        // 폰트 설정 (UserSettings에서 가져온 값 사용)
        let font = currentFont
        textView.font = font
        textView.gutterView?.font = font
        textView.gutterView?.textColor = .secondaryLabelColor

        // 거터 최소 너비 설정 (4자리 숫자 기준)
        let gutterMinWidth = calculateGutterWidth(for: font, digits: 4)
        textView.gutterView?.minimumThickness = gutterMinWidth

        // 줄 높이 배수 설정 - defaultParagraphStyle을 먼저 설정해야 새로 입력하는 텍스트에도 적용됨
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineHeightMultiple = lineHeightMultiple
        textView.defaultParagraphStyle = paragraphStyle

        scrollView.automaticallyAdjustsContentInsets = false

        // Scroll Beyond Last Line: 뷰포트 높이에서 한 줄 높이를 뺀 만큼 추가
        let lineHeight = font.pointSize * lineHeightMultiple
        textView.extraScrollHeight = max(0, viewportHeight - lineHeight - 20)

        // Coordinator에 textView 및 lineHeightMultiple 참조 저장
        context.coordinator.textView = textView
        context.coordinator.lineHeightMultiple = lineHeightMultiple

        // 초기 텍스트 설정
        context.coordinator.isUpdating = true
        textView.attributedText = styledAttributedString(from: text)
        context.coordinator.isUpdating = false

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let textView = scrollView.documentView as! ExtendedSTTextView
        let font = currentFont

        // 폰트 또는 줄 높이 배수 변경 시 기존 텍스트에도 z적용
        let fontChanged = textView.font.pointSize != font.pointSize
        let lineHeightChanged = context.coordinator.lineHeightMultiple != lineHeightMultiple

        if fontChanged || lineHeightChanged {
            // 폰트 업데이트
            textView.font = font
            textView.gutterView?.font = font

            // 거터 최소 너비 업데이트 (폰트 크기 변경 시)
            let gutterMinWidth = calculateGutterWidth(for: font, digits: 4)
            textView.gutterView?.minimumThickness = gutterMinWidth

            // 줄 높이 배수 업데이트
            context.coordinator.lineHeightMultiple = lineHeightMultiple
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineHeightMultiple = lineHeightMultiple
            textView.defaultParagraphStyle = paragraphStyle

            // 기존 텍스트에도 새 폰트/줄 높이 적용
            context.coordinator.isUpdating = true
            textView.attributedText = styledAttributedString(from: text)
            context.coordinator.isUpdating = false
        }

        // Scroll Beyond Last Line: 뷰포트 높이나 폰트 크기 변경 시 업데이트
        let lineHeight = font.pointSize * lineHeightMultiple
        let newExtraScrollHeight = max(0, viewportHeight - lineHeight - 20)
        if textView.extraScrollHeight != newExtraScrollHeight {
            textView.extraScrollHeight = newExtraScrollHeight
            // setFrameSize가 다시 호출되도록 레이아웃 요청
            textView.needsLayout = true
        }

        // editable 상태 업데이트
        if textView.isEditable != isEditable {
            textView.isEditable = isEditable
        }

        // 텍스트 동기화 (외부에서 변경된 경우만)
        if !context.coordinator.isUserEditing {
            let currentText = textView.attributedText?.string ?? ""
            if currentText != text {
                context.coordinator.isUpdating = true
                textView.attributedText = styledAttributedString(from: text)
                context.coordinator.isUpdating = false
            }
        }
        context.coordinator.isUserEditing = false

        textView.needsLayout = true
        textView.needsDisplay = true
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            cursorLine: $cursorLine,
            selectedLineRange: $selectedLineRange
        )
    }

    /// 거터(줄번호 영역) 최소 너비 계산
    /// - Parameters:
    ///   - font: 거터에 사용되는 폰트
    ///   - digits: 표시할 최소 자릿수 (기본 4자리 = 9999까지)
    /// - Returns: 계산된 최소 너비
    private func calculateGutterWidth(for font: NSFont, digits: Int) -> CGFloat {
        // 자릿수에 맞는 샘플 텍스트 생성 (예: 4자리 -> "9999")
        let sampleText = String(repeating: "9", count: digits)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let attributedString = NSAttributedString(string: sampleText, attributes: attributes)
        let textWidth = attributedString.size().width

        // 좌우 패딩 추가 (STTextView 기본 패딩 고려)
        let horizontalPadding: CGFloat = 16
        return textWidth + horizontalPadding
    }

    /// foreground color와 줄 높이 배수가 적용된 NSAttributedString 생성
    private func styledAttributedString(from plainText: String) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineHeightMultiple = lineHeightMultiple

        let attributes: [NSAttributedString.Key: Any] = [
            .font: currentFont,
            .foregroundColor: AppColors.nsEditorText,
            .paragraphStyle: paragraphStyle
        ]

        return NSAttributedString(string: plainText, attributes: attributes)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, STTextViewDelegate {
        @Binding var text: String
        @Binding var cursorLine: Int
        @Binding var selectedLineRange: ClosedRange<Int>?

        weak var textView: STTextView?

        var isUpdating: Bool = false
        var isUserEditing: Bool = false
        var lineHeightMultiple: CGFloat = 1.0  // 기본 줄 높이 배수

        init(text: Binding<String>, cursorLine: Binding<Int>, selectedLineRange: Binding<ClosedRange<Int>?>) {
            self._text = text
            self._cursorLine = cursorLine
            self._selectedLineRange = selectedLineRange
        }

        // MARK: - STTextViewDelegate

        func textViewDidChangeText(_ notification: Notification) {
            guard let textView = notification.object as? STTextView else { return }
            guard !isUpdating else { return }

            isUserEditing = true
            text = textView.attributedText?.string ?? ""
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? STTextView else { return }

            let range = textView.selectedRange()
            updateCursorInfo(from: range, in: textView)
        }

        private func updateCursorInfo(from selection: NSRange, in textView: STTextView) {
            let plainText = textView.attributedText?.string ?? ""
            let location = selection.location

            // 커서 위치까지의 줄 번호 계산
            let selectedText = plainText.prefix(min(location, plainText.count))
            let lineNumber = selectedText.components(separatedBy: .newlines).count

            cursorLine = lineNumber

            if selection.length > 0 {
                // 선택 범위가 있는 경우
                let endLocation = selection.location + selection.length
                let endText = plainText.prefix(min(endLocation, plainText.count))
                let endLineNumber = endText.components(separatedBy: .newlines).count

                let minLine = min(lineNumber, endLineNumber)
                let maxLine = max(lineNumber, endLineNumber)
                selectedLineRange = minLine...maxLine
            } else {
                selectedLineRange = nil
            }
        }
    }
}

// MARK: - Preview

#Preview {
    CodeEditorWrapperView(
        text: .constant("# Hello, World!\n\nThis is a test.\nLine 4\nLine 5\nLine 6\nLine 7\nLine 8\nLine 9\nLine 10\n\n긴 텍스트 테스트입니다. 이 줄은 자동으로 줄바꿈이 되어야 합니다."),
        cursorLine: .constant(1),
        selectedLineRange: .constant(nil),
        fontSize: 14,
        lineHeightMultiple: 1.0,
        isEditable: true
    )
    .frame(width: 600, height: 400)
}
