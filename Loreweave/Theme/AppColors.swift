//
//  AppColors.swift
//  Loreweave
//
//  앱 전역 색상 라우터 - NSColor 시스템 색상을 의미론적 이름으로 제공
//  시스템 색상을 사용하여 다크/라이트 모드, 윈도우 활성/비활성 상태 자동 대응
//
//  NSColor 시스템 색상 참고:
//  - windowBackgroundColor: 윈도우 배경 (라이트: 밝은 회색, 다크: 어두운 회색)
//  - controlBackgroundColor: 컨트롤 배경 (텍스트필드, 리스트 등)
//  - textBackgroundColor: 텍스트 영역 배경 (라이트: 흰색, 다크: 어두운 색)
//  - underPageBackgroundColor: 스크롤 영역 밖 배경
//  - labelColor: 기본 텍스트 (가장 높은 대비)
//  - secondaryLabelColor: 보조 텍스트 (중간 대비)
//  - tertiaryLabelColor: 3차 텍스트 (낮은 대비, 힌트/플레이스홀더)
//  - quaternaryLabelColor: 4차 텍스트 (매우 낮은 대비)
//  - separatorColor: 구분선
//  - selectedContentBackgroundColor: 선택된 콘텐츠 배경 (포커스됨)
//  - unemphasizedSelectedContentBackgroundColor: 선택된 콘텐츠 배경 (포커스 안됨)
//

import SwiftUI

/// 앱 전역 색상 팔레트 (라우터)
/// NSColor 시스템 색상을 사용하여 모든 상태 변화에 자동 대응
enum AppColors {

    // MARK: - Bar Background

    /// 툴바/탭바 배경색 - 윈도우 배경과 동일
    static var barBackground: Color {
        Color(nsColor: .windowBackgroundColor)
    }

    // MARK: - Tab Bar

    /// 탭 배경색 (선택됨) - 약간 밝은/어두운 배경으로 구분
    static var tabSelectedBackground: Color {
        Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
    }

    /// 탭 배경색 (호버) - 선택 배경의 투명한 버전
    static var tabHoverBackground: Color {
        Color(nsColor: .unemphasizedSelectedContentBackgroundColor).opacity(0.5)
    }

    /// 탭 배경색 (기본) - 투명
    static var tabDefaultBackground: Color {
        Color.clear
    }

    /// 탭 테두리색 (선택됨)
    static var tabSelectedBorder: Color {
        Color(nsColor: .separatorColor)
    }

    /// 탭 테두리색 (기본)
    static var tabDefaultBorder: Color {
        Color(nsColor: .separatorColor).opacity(0.3)
    }

    /// 탭 텍스트색 - 기본 라벨 색상
    static var tabText: Color {
        Color(nsColor: .labelColor)
    }

    /// 탭 닫기 버튼 배경 (호버)
    static var tabCloseHoverBackground: Color {
        Color(nsColor: .quaternaryLabelColor)
    }

    // MARK: - Toolbar

    /// 툴바 버튼 배경 (호버) - 악센트 색상의 투명한 버전
    static var toolbarButtonHover: Color {
        Color(nsColor: .controlAccentColor).opacity(0.1)
    }

    /// 툴바 버튼 배경 (클릭)
    static var toolbarButtonPressed: Color {
        Color(nsColor: .controlAccentColor).opacity(0.2)
    }

    /// 툴바 토글 버튼 배경 (선택됨)
    static var toolbarToggleSelected: Color {
        Color(nsColor: .controlAccentColor).opacity(0.15)
    }

    /// 툴바 아이콘 색상 - 보조 라벨 (낮은 강조)
    static var toolbarIcon: Color {
        Color(nsColor: .secondaryLabelColor)
    }

    /// 툴바 아이콘 색상 (활성) - 기본 라벨 (높은 강조)
    static var toolbarIconActive: Color {
        Color(nsColor: .labelColor)
    }

    // MARK: - Add Button (탭바 + 버튼)

    /// 추가 버튼 아이콘 색상
    static var addButtonIcon: Color {
        Color(nsColor: .secondaryLabelColor)
    }

    /// 추가 버튼 배경 (호버)
    static var addButtonHover: Color {
        Color(nsColor: .controlAccentColor).opacity(0.1)
    }

    /// 추가 버튼 배경 (클릭)
    static var addButtonPressed: Color {
        Color(nsColor: .controlAccentColor).opacity(0.2)
    }

    // MARK: - Sidebar

    /// 사이드바 배경 - 윈도우 배경
    static var sidebarBackground: Color {
        Color(nsColor: .windowBackgroundColor)
    }

    /// 사이드바 툴바 그라데이션
    static var sidebarToolbarGradient: LinearGradient {
        LinearGradient(
            colors: [Color(nsColor: .windowBackgroundColor), Color(nsColor: .windowBackgroundColor)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// 사이드바 아이템 (선택됨) - 선택된 콘텐츠 배경
    static var sidebarItemSelected: Color {
        Color(nsColor: .selectedContentBackgroundColor)
    }

    /// 사이드바 아이템 (호버) - 비강조 선택 배경의 투명 버전
    static var sidebarItemHover: Color {
        Color(nsColor: .unemphasizedSelectedContentBackgroundColor).opacity(0.5)
    }

    /// 사이드바 섹션 헤더 텍스트 - 보조 라벨
    static var sidebarHeaderText: Color {
        Color(nsColor: .secondaryLabelColor)
    }

    // MARK: - Content Area

    /// 콘텐츠 영역 배경 - 텍스트 배경
    static var contentBackground: Color {
        Color(nsColor: .textBackgroundColor)
    }

    /// 텍스트 에디터 배경 - 텍스트 배경 (라이트: 흰색, 다크: 어두운 색)
    static var textEditorBackground: Color {
        Color(nsColor: .textBackgroundColor)
    }

    // MARK: - Text

    /// 기본 텍스트 - 가장 높은 대비
    static var textPrimary: Color {
        Color(nsColor: .labelColor)
    }

    /// 보조 텍스트 - 중간 대비 (부가 정보)
    static var textSecondary: Color {
        Color(nsColor: .secondaryLabelColor)
    }

    /// 3차 텍스트 - 낮은 대비 (힌트, 플레이스홀더)
    static var textTertiary: Color {
        Color(nsColor: .tertiaryLabelColor)
    }

    /// 비활성 텍스트
    static var textDisabled: Color {
        Color(nsColor: .disabledControlTextColor)
    }

    // MARK: - Controls

    /// 컨트롤 배경 - 텍스트필드, 입력 영역 등
    static var controlBackground: Color {
        Color(nsColor: .controlBackgroundColor)
    }

    /// 컨트롤 테두리
    static var controlBorder: Color {
        Color(nsColor: .separatorColor)
    }

    // MARK: - Separators

    /// 구분선
    static var separator: Color {
        Color(nsColor: .separatorColor)
    }

    /// 굵은 구분선 (gridColor 사용)
    static var separatorOpaque: Color {
        Color(nsColor: .gridColor)
    }

    // MARK: - Selection

    /// 선택 영역 배경 (강조, 포커스됨)
    static var selectionEmphasized: Color {
        Color(nsColor: .selectedContentBackgroundColor)
    }

    /// 선택 영역 배경 (비강조, 포커스 안됨)
    static var selectionUnemphasized: Color {
        Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
    }

    // MARK: - Indicators

    /// 수정됨 표시 색상
    static var modifiedIndicator: Color {
        Color(nsColor: .systemOrange)
    }

    /// 저장됨 표시 색상
    static var savedIndicator: Color {
        Color(nsColor: .systemGreen)
    }

    /// 오류 표시 색상
    static var errorIndicator: Color {
        Color(nsColor: .systemRed)
    }

    /// 경고 표시 색상
    static var warningIndicator: Color {
        Color(nsColor: .systemYellow)
    }

    // MARK: - Shadows

    /// 탭 그림자 (선택됨)
    static var tabSelectedShadow: Color {
        Color(nsColor: .shadowColor).opacity(0.3)
    }

    /// 드롭 섀도우
    static var shadowDrop: Color {
        Color(nsColor: .shadowColor).opacity(0.2)
    }

    // MARK: - Focus

    /// 포커스 링 - 악센트 색상의 투명 버전
    static var focusRing: Color {
        Color(nsColor: .keyboardFocusIndicatorColor).opacity(0.5)
    }

    // MARK: - Accent

    /// 시스템 악센트 색상
    static var accent: Color {
        Color(nsColor: .controlAccentColor)
    }
}
