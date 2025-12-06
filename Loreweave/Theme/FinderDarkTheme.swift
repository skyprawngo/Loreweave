//
//  FinderDarkTheme.swift
//  Loreweave
//
//  macOS Finder 다크모드 색상 팔레트
//  시스템 다크모드의 실제 색상값을 정의
//

import SwiftUI
import AppKit

/// macOS Finder 다크모드 색상 테마
/// 참고: Digital Color Meter로 측정한 실제 Finder 색상값 기반
enum FinderDarkTheme {

    // MARK: - Window & Background

    /// 윈도우 배경 (사이드바, 콘텐츠 영역)
    /// Finder 다크모드: #1E1E1E (RGB: 30, 30, 30)
    static let windowBackground = Color(red: 30/255, green: 30/255, blue: 30/255)

    /// 툴바/타이틀바 배경 (비브랜시 적용 전 기본색)
    /// Finder 다크모드: #323232 (RGB: 50, 50, 50)
    static let toolbarBackground = Color(red: 50/255, green: 50/255, blue: 50/255)

    /// 사이드바 배경 (비브랜시 적용 전 기본색)
    /// Finder 다크모드: #2D2D2D (RGB: 45, 45, 45)
    static let sidebarBackground = Color(red: 45/255, green: 45/255, blue: 45/255)

    /// 콘텐츠 영역 배경
    /// Finder 다크모드: #1E1E1E (RGB: 30, 30, 30)
    static let contentBackground = Color(red: 30/255, green: 30/255, blue: 30/255)

    /// 텍스트 에디터 배경
    /// TextEdit 다크모드: #1E1E1E (RGB: 30, 30, 30)
    static let textEditorBackground = Color(red: 30/255, green: 30/255, blue: 30/255)

    // MARK: - Text Colors

    /// 에디터 기본 텍스트 (밝고 선명한 흰색)
    /// #EBEBEB (RGB: 235, 235, 235) - 가독성 최적화
    static let editorText = Color(red: 235/255, green: 235/255, blue: 235/255)

    /// 기본 텍스트 (labelColor)
    /// 다크모드: #FFFFFF (RGB: 255, 255, 255) with 85% opacity
    static let textPrimary = Color(red: 255/255, green: 255/255, blue: 255/255).opacity(0.85)

    /// 보조 텍스트 (secondaryLabelColor)
    /// 다크모드: #FFFFFF with 55% opacity
    static let textSecondary = Color(red: 255/255, green: 255/255, blue: 255/255).opacity(0.55)

    /// 3차 텍스트 (tertiaryLabelColor)
    /// 다크모드: #FFFFFF with 25% opacity
    static let textTertiary = Color(red: 255/255, green: 255/255, blue: 255/255).opacity(0.25)

    /// 4차 텍스트 (quaternaryLabelColor)
    /// 다크모드: #FFFFFF with 10% opacity
    static let textQuaternary = Color(red: 255/255, green: 255/255, blue: 255/255).opacity(0.10)

    /// 비활성 텍스트
    /// 다크모드: #7F7F7F (RGB: 127, 127, 127)
    static let textDisabled = Color(red: 127/255, green: 127/255, blue: 127/255)

    /// 줄번호 텍스트 (비선택)
    /// 다크모드: #6E6E6E (RGB: 110, 110, 110)
    static let lineNumberText = Color(red: 110/255, green: 110/255, blue: 110/255)

    /// 줄번호 텍스트 (선택됨)
    /// 다크모드: #B0B0B0 (RGB: 176, 176, 176)
    static let lineNumberTextActive = Color(red: 176/255, green: 176/255, blue: 176/255)

    // MARK: - Icon Colors

    /// 기본 아이콘 색상
    /// 다크모드: #CCCCCC (RGB: 204, 204, 204)
    static let iconPrimary = Color(red: 204/255, green: 204/255, blue: 204/255)

    /// 보조 아이콘 색상 (secondaryLabelColor 기반)
    /// 다크모드: #8E8E93 (RGB: 142, 142, 147)
    static let iconSecondary = Color(red: 142/255, green: 142/255, blue: 147/255)

    /// 비활성 아이콘
    /// 다크모드: #5A5A5E (RGB: 90, 90, 94)
    static let iconDisabled = Color(red: 90/255, green: 90/255, blue: 94/255)

    // MARK: - Accent & Selection

    /// 시스템 악센트 색상 (기본: 블루)
    /// macOS 기본 블루: #007AFF (RGB: 0, 122, 255)
    static let accentBlue = Color(red: 0/255, green: 122/255, blue: 255/255)

    /// 선택 영역 배경 (강조)
    /// Finder 선택: #0058D0 (RGB: 0, 88, 208)
    static let selectionEmphasized = Color(red: 0/255, green: 88/255, blue: 208/255)

    /// 선택 영역 배경 (비강조, 윈도우 비활성)
    /// Finder 비강조 선택: #464646 (RGB: 70, 70, 70)
    static let selectionUnemphasized = Color(red: 70/255, green: 70/255, blue: 70/255)

    /// 호버 배경
    /// 다크모드 호버: #3A3A3C (RGB: 58, 58, 60)
    static let hoverBackground = Color(red: 58/255, green: 58/255, blue: 60/255)

    // MARK: - Controls

    /// 컨트롤 배경 (버튼, 텍스트필드 등)
    /// 다크모드: #3A3A3C (RGB: 58, 58, 60)
    static let controlBackground = Color(red: 58/255, green: 58/255, blue: 60/255)

    /// 컨트롤 배경 (호버)
    /// 다크모드: #48484A (RGB: 72, 72, 74)
    static let controlBackgroundHover = Color(red: 72/255, green: 72/255, blue: 74/255)

    /// 컨트롤 배경 (눌림)
    /// 다크모드: #545456 (RGB: 84, 84, 86)
    static let controlBackgroundPressed = Color(red: 84/255, green: 84/255, blue: 86/255)

    /// 컨트롤 테두리
    /// 다크모드: #545456 (RGB: 84, 84, 86)
    static let controlBorder = Color(red: 84/255, green: 84/255, blue: 86/255)

    // MARK: - Separators & Dividers

    /// 구분선 (separatorColor)
    /// 다크모드: #545458 with 65% opacity (RGB: 84, 84, 88)
    static let separator = Color(red: 84/255, green: 84/255, blue: 88/255).opacity(0.65)

    /// 굵은 구분선
    /// 다크모드: #545458 (RGB: 84, 84, 88)
    static let separatorOpaque = Color(red: 84/255, green: 84/255, blue: 88/255)

    // MARK: - Tab Bar

    /// 탭 배경 (선택됨)
    /// Finder 탭바 선택: #48494B (RGB: 72, 73, 75)
    static let tabSelectedBackground = Color(red: 72/255, green: 73/255, blue: 75/255)

    /// 탭 배경 (호버)
    /// 다크모드: #2C2C2E (RGB: 44, 44, 46)
    static let tabHoverBackground = Color(red: 44/255, green: 44/255, blue: 46/255)

    /// 탭 배경 (기본)
    /// 다크모드: 투명 또는 매우 옅은 색
    static let tabDefaultBackground = Color.clear

    /// 탭 테두리 (선택됨)
    /// 다크모드: #545458 (RGB: 84, 84, 88)
    static let tabSelectedBorder = Color(red: 84/255, green: 84/255, blue: 88/255)

    /// 탭 테두리 (기본)
    /// 다크모드: #3A3A3C (RGB: 58, 58, 60)
    static let tabDefaultBorder = Color(red: 58/255, green: 58/255, blue: 60/255)

    // MARK: - Sidebar

    /// 사이드바 배경 (비활성 윈도우)
    /// Finder 사이드바 비활성: #2C2D2F (RGB: 44, 45, 47)
    static let sidebarBackgroundInactive = Color(red: 44/255, green: 45/255, blue: 47/255)

    /// 사이드바 툴바 그라데이션 상단
    /// Finder 스타일 그라데이션
    static let sidebarToolbarGradientTop = Color(red: 56/255, green: 56/255, blue: 58/255)

    /// 사이드바 툴바 그라데이션 하단
    static let sidebarToolbarGradientBottom = Color(red: 44/255, green: 45/255, blue: 47/255)

    /// 사이드바 아이템 배경 (선택됨)
    /// Finder 사이드바 선택: #0058D0 (RGB: 0, 88, 208)
    static let sidebarItemSelected = Color(red: 0/255, green: 88/255, blue: 208/255)

    /// 사이드바 아이템 배경 (호버)
    /// 다크모드: #3A3A3C (RGB: 58, 58, 60)
    static let sidebarItemHover = Color(red: 58/255, green: 58/255, blue: 60/255)

    /// 사이드바 섹션 헤더 텍스트
    /// 다크모드: #8E8E93 (RGB: 142, 142, 147)
    static let sidebarHeaderText = Color(red: 142/255, green: 142/255, blue: 147/255)

    // MARK: - Indicators & Status

    /// 수정됨 표시 (주황색 점)
    /// macOS 표준: #FF9500 (RGB: 255, 149, 0)
    static let modifiedIndicator = Color(red: 255/255, green: 149/255, blue: 0/255)

    /// 저장됨 표시 (녹색)
    /// macOS 표준: #30D158 (RGB: 48, 209, 88)
    static let savedIndicator = Color(red: 48/255, green: 209/255, blue: 88/255)

    /// 오류 표시 (빨간색)
    /// macOS 표준: #FF3B30 (RGB: 255, 59, 48)
    static let errorIndicator = Color(red: 255/255, green: 59/255, blue: 48/255)

    /// 경고 표시 (노란색)
    /// macOS 표준: #FFD60A (RGB: 255, 214, 10)
    static let warningIndicator = Color(red: 255/255, green: 214/255, blue: 10/255)

    // MARK: - Shadows

    /// 드롭 섀도우
    /// 다크모드: 검정 20% opacity
    static let shadowDrop = Color.black.opacity(0.20)

    /// 내부 섀도우 (인셋)
    /// 다크모드: 검정 30% opacity
    static let shadowInner = Color.black.opacity(0.30)

    /// 글로우 (호버 등)
    /// 다크모드: 흰색 5% opacity
    static let glowSubtle = Color.white.opacity(0.05)

    // MARK: - Scrollbar

    /// 스크롤바 놉 (기본)
    /// 다크모드: #5A5A5E (RGB: 90, 90, 94)
    static let scrollbarKnob = Color(red: 90/255, green: 90/255, blue: 94/255)

    /// 스크롤바 놉 (호버)
    /// 다크모드: #747478 (RGB: 116, 116, 120)
    static let scrollbarKnobHover = Color(red: 116/255, green: 116/255, blue: 120/255)

    // MARK: - Focus Ring

    /// 포커스 링 색상
    /// macOS 표준: 악센트 색상 기반, 50% opacity
    static let focusRing = accentBlue.opacity(0.50)
}
