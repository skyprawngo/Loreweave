//
//  ThemePalette.swift
//  Loreweave
//
//  테마 팔레트 프로토콜 - 모든 테마가 준수해야 할 색상 속성 정의
//  새로운 색상 속성 추가 시 이 프로토콜에 먼저 추가하고,
//  DarkTheme(기본 테마)에 구현 후, 다른 테마들도 최신화
//

import SwiftUI

/// 테마 팔레트 프로토콜
/// 모든 테마는 이 프로토콜을 준수해야 함
protocol ThemePalette {

    // MARK: - Background

    /// 윈도우/메인 배경색
    static var background: Color { get }

    /// 툴바/탭바 배경색
    static var barBackground: Color { get }

    /// 사이드바 배경색
    static var sidebarBackground: Color { get }

    /// 콘텐츠 영역 배경색
    static var contentBackground: Color { get }

    /// 텍스트 에디터 배경색
    static var textEditorBackground: Color { get }

    /// 컨트롤 배경색 (텍스트필드, 입력 영역 등)
    static var controlBackground: Color { get }

    // MARK: - Text

    /// 기본 텍스트 - 가장 높은 대비
    static var textPrimary: Color { get }

    /// 보조 텍스트 - 중간 대비
    static var textSecondary: Color { get }

    /// 3차 텍스트 - 낮은 대비 (힌트, 플레이스홀더)
    static var textTertiary: Color { get }

    /// 비활성 텍스트
    static var textDisabled: Color { get }

    // MARK: - Tab Bar

    /// 탭 배경색 (선택됨)
    static var tabSelectedBackground: Color { get }

    /// 탭 배경색 (호버)
    static var tabHoverBackground: Color { get }

    /// 탭 배경색 (기본)
    static var tabDefaultBackground: Color { get }

    /// 탭 테두리색 (선택됨)
    static var tabSelectedBorder: Color { get }

    /// 탭 테두리색 (기본)
    static var tabDefaultBorder: Color { get }

    /// 탭 텍스트색
    static var tabText: Color { get }

    /// 탭 닫기 버튼 배경 (호버)
    static var tabCloseHoverBackground: Color { get }

    /// 탭 그림자 (선택됨)
    static var tabSelectedShadow: Color { get }

    // MARK: - Toolbar

    /// 툴바 버튼 배경 (호버)
    static var toolbarButtonHover: Color { get }

    /// 툴바 버튼 배경 (클릭)
    static var toolbarButtonPressed: Color { get }

    /// 툴바 토글 버튼 배경 (선택됨)
    static var toolbarToggleSelected: Color { get }

    /// 툴바 아이콘 색상
    static var toolbarIcon: Color { get }

    /// 툴바 아이콘 색상 (활성)
    static var toolbarIconActive: Color { get }

    // MARK: - Sidebar

    /// 사이드바 아이템 (선택됨)
    static var sidebarItemSelected: Color { get }

    /// 사이드바 아이템 (호버)
    static var sidebarItemHover: Color { get }

    /// 사이드바 섹션 헤더 텍스트
    static var sidebarHeaderText: Color { get }

    // MARK: - Separators

    /// 구분선
    static var separator: Color { get }

    /// 굵은 구분선
    static var separatorOpaque: Color { get }

    /// 컨트롤 테두리
    static var controlBorder: Color { get }

    // MARK: - Selection

    /// 선택 영역 배경 (강조, 포커스됨)
    static var selectionEmphasized: Color { get }

    /// 선택 영역 배경 (비강조, 포커스 안됨)
    static var selectionUnemphasized: Color { get }

    // MARK: - Editor

    /// 현재 커서가 위치한 줄 배경
    static var currentLineBackground: Color { get }

    /// 줄번호 텍스트 색상
    static var lineNumber: Color { get }

    // MARK: - Accent & Focus

    /// 시스템 악센트 색상 (포인트 컬러)
    static var accent: Color { get }

    /// 포커스 링
    static var focusRing: Color { get }

    // MARK: - Indicators

    /// 수정됨 표시 색상
    static var modifiedIndicator: Color { get }

    /// 저장됨 표시 색상
    static var savedIndicator: Color { get }

    /// 오류 표시 색상
    static var errorIndicator: Color { get }

    /// 경고 표시 색상
    static var warningIndicator: Color { get }

    // MARK: - Shadows

    /// 드롭 섀도우
    static var shadowDrop: Color { get }

    // MARK: - Buttons

    /// 추가 버튼 아이콘 색상
    static var addButtonIcon: Color { get }

    /// 추가 버튼 배경 (호버)
    static var addButtonHover: Color { get }

    /// 추가 버튼 배경 (클릭)
    static var addButtonPressed: Color { get }

    // MARK: - Theme Metadata

    /// 테마 ID (저장용)
    static var id: String { get }

    /// 테마 표시 이름 (L10n 키)
    static var displayNameKey: String { get }

    /// 불투명 테마 여부 (VisualEffect 사용 여부 결정)
    static var isOpaque: Bool { get }
}

// MARK: - NSColor 확장 (AppKit 컴포넌트용)

import AppKit

/// AppKit 컴포넌트(NSAttributedString 등)에서 사용할 NSColor 버전
/// MarkdownFormatter 등에서 사용
protocol ThemePaletteNSColor {
    /// 에디터 기본 텍스트 색상
    static var nsEditorText: NSColor { get }

    /// 마크다운 구문 색상
    static var nsMarkdownSyntax: NSColor { get }

    /// 에디터 배경색
    static var nsEditorBackground: NSColor { get }
}
