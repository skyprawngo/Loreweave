//
//  ViewportManager.swift
//  Loreweave
//
//  뷰포트 관리 - 화면에 보이는 행 범위 계산
//  VSCode Monaco 스타일의 가상 스크롤 지원
//

import Foundation

// MARK: - Viewport Manager

/// 뷰포트(화면에 보이는 영역) 관리자
final class ViewportManager {
    /// 뷰포트 높이 (픽셀)
    var viewportHeight: CGFloat = 0

    /// 뷰포트 너비 (픽셀)
    var viewportWidth: CGFloat = 0

    /// 현재 스크롤 오프셋 (Y)
    var scrollOffsetY: CGFloat = 0

    /// 행 높이 (픽셀)
    var lineHeight: CGFloat = 20

    /// 문서 총 행 수
    var totalLineCount: Int = 1

    /// 렌더링 버퍼 (뷰포트 위아래로 추가 렌더링할 행 수)
    var renderBuffer: Int = 5

    // MARK: - Computed Properties

    /// 화면에 보이는 첫 번째 행 인덱스
    var firstVisibleLine: Int {
        guard lineHeight > 0 else { return 0 }
        return max(0, Int(floor(scrollOffsetY / lineHeight)) - renderBuffer)
    }

    /// 화면에 보이는 마지막 행 인덱스
    var lastVisibleLine: Int {
        guard lineHeight > 0 else { return max(0, totalLineCount - 1) }
        let visibleLines = Int(ceil(viewportHeight / lineHeight))
        let lastLine = Int(floor(scrollOffsetY / lineHeight)) + visibleLines + renderBuffer
        return min(max(0, totalLineCount - 1), lastLine)
    }

    /// 실제 렌더링할 행 범위
    var visibleLineRange: ClosedRange<Int> {
        guard totalLineCount > 0 else { return 0...0 }
        let first = max(0, min(firstVisibleLine, totalLineCount - 1))
        let last = max(first, min(lastVisibleLine, totalLineCount - 1))
        return first...last
    }

    /// 뷰포트에 표시되는 행 수 (버퍼 제외)
    var visibleLineCount: Int {
        guard lineHeight > 0 else { return 0 }
        return Int(ceil(viewportHeight / lineHeight))
    }

    /// 문서 전체 콘텐츠 높이
    var contentHeight: CGFloat {
        CGFloat(totalLineCount) * lineHeight
    }

    /// 추가 스크롤 영역 (마지막 줄 이후 빈 공간)
    var extraScrollHeight: CGFloat {
        max(0, viewportHeight - lineHeight - 20)
    }

    /// 전체 스크롤 가능 높이
    var totalScrollHeight: CGFloat {
        contentHeight + extraScrollHeight
    }

    // MARK: - Methods

    /// 뷰포트 크기 업데이트
    func updateViewport(width: CGFloat, height: CGFloat) {
        viewportWidth = width
        viewportHeight = height
    }

    /// 행 높이 업데이트 (폰트 크기 변경 시)
    func updateLineHeight(_ height: CGFloat) {
        lineHeight = height
    }

    /// 문서 행 수 업데이트
    func updateLineCount(_ count: Int) {
        totalLineCount = max(1, count)
    }

    /// 스크롤 위치 업데이트
    func scroll(to offsetY: CGFloat) {
        scrollOffsetY = max(0, min(offsetY, totalScrollHeight - viewportHeight))
    }

    /// 특정 행이 뷰포트에 보이도록 스크롤
    func scrollToLine(_ lineIndex: Int, position: ScrollPosition = .nearest) {
        let lineTop = CGFloat(lineIndex) * lineHeight
        let lineBottom = lineTop + lineHeight

        switch position {
        case .top:
            scroll(to: lineTop)
        case .center:
            scroll(to: lineTop - (viewportHeight - lineHeight) / 2)
        case .bottom:
            scroll(to: lineBottom - viewportHeight)
        case .nearest:
            if lineTop < scrollOffsetY {
                // 행이 뷰포트 위에 있음 → 위로 스크롤
                scroll(to: lineTop)
            } else if lineBottom > scrollOffsetY + viewportHeight {
                // 행이 뷰포트 아래에 있음 → 아래로 스크롤
                scroll(to: lineBottom - viewportHeight)
            }
            // 이미 보이는 경우 스크롤하지 않음
        }
    }

    /// 특정 행이 현재 뷰포트에 보이는지 확인
    func isLineVisible(_ lineIndex: Int) -> Bool {
        visibleLineRange.contains(lineIndex)
    }

    /// 행 인덱스 → Y 좌표 변환
    func yPositionForLine(_ lineIndex: Int) -> CGFloat {
        CGFloat(lineIndex) * lineHeight
    }

    /// Y 좌표 → 행 인덱스 변환
    func lineIndexAtY(_ y: CGFloat) -> Int {
        let index = Int(floor((y + scrollOffsetY) / lineHeight))
        return max(0, min(index, totalLineCount - 1))
    }

    /// 뷰포트 내 상대 Y 좌표 → 행 인덱스
    func lineIndexAtViewportY(_ viewportY: CGFloat) -> Int {
        lineIndexAtY(viewportY)
    }
}

// MARK: - Scroll Position

/// 스크롤 대상 위치
enum ScrollPosition {
    case top      // 뷰포트 상단에 배치
    case center   // 뷰포트 중앙에 배치
    case bottom   // 뷰포트 하단에 배치
    case nearest  // 가장 가까운 위치로 최소 스크롤
}
