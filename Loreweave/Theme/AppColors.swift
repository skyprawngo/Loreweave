//
//  AppColors.swift
//  Loreweave
//
//  앱 전역 색상 라우터
//  현재 선택된 테마에서 색상을 가져와 반환
//  뷰에서는 AppColors를 통해 색상에 접근하고, 테마 변경 시 자동으로 반영됨
//

import SwiftUI
import AppKit

/// 앱 전역 색상 라우터
/// 현재 테마에서 색상을 가져옴
enum AppColors {

    // MARK: - Current Theme

    /// 현재 적용 중인 테마 타입 반환
    private static var currentTheme: any ThemePalette.Type {
        switch ThemeManager.shared.appliedTheme {
        case .system:
            return SystemTheme.self
        case .light:
            return LightTheme.self
        case .dark:
            return DarkTheme.self
        case .opaque:
            return OpaqueTheme.self
        }
    }

    /// 현재 테마가 불투명 테마인지 여부
    static var isOpaqueTheme: Bool {
        currentTheme.isOpaque
    }

    // MARK: - Background

    static var background: Color { currentTheme.background }
    static var barBackground: Color { currentTheme.barBackground }
    static var sidebarBackground: Color { currentTheme.sidebarBackground }
    static var contentBackground: Color { currentTheme.contentBackground }
    static var textEditorBackground: Color { currentTheme.textEditorBackground }
    static var controlBackground: Color { currentTheme.controlBackground }

    // MARK: - Text

    static var textPrimary: Color { currentTheme.textPrimary }
    static var textSecondary: Color { currentTheme.textSecondary }
    static var textTertiary: Color { currentTheme.textTertiary }
    static var textDisabled: Color { currentTheme.textDisabled }

    // MARK: - Tab Bar

    static var tabInactiveBackground: Color { currentTheme.tabInactiveBackground }
    static var tabHoverBackground: Color { currentTheme.tabHoverBackground }
    static var tabDefaultBackground: Color { currentTheme.tabDefaultBackground }
    static var tabActiveBorder: Color { currentTheme.tabActiveBorder }
    static var tabInactiveBorder: Color { currentTheme.tabInactiveBorder }
    static var tabText: Color { currentTheme.tabText }
    static var tabCloseHoverBackground: Color { currentTheme.tabCloseHoverBackground }
    static var tabSelectedShadow: Color { currentTheme.tabSelectedShadow }

    // MARK: - Toolbar

    static var toolbarButtonHover: Color { currentTheme.toolbarButtonHover }
    static var toolbarButtonPressed: Color { currentTheme.toolbarButtonPressed }
    static var toolbarToggleSelected: Color { currentTheme.toolbarToggleSelected }
    static var toolbarIcon: Color { currentTheme.toolbarIcon }
    static var toolbarIconActive: Color { currentTheme.toolbarIconActive }

    // MARK: - Sidebar

    static var sidebarItemSelected: Color { currentTheme.sidebarItemSelected }
    static var sidebarItemHover: Color { currentTheme.sidebarItemHover }
    static var sidebarHeaderText: Color { currentTheme.sidebarHeaderText }

    // MARK: - Separators

    static var separator: Color { currentTheme.separator }
    static var separatorOpaque: Color { currentTheme.separatorOpaque }
    static var controlBorder: Color { currentTheme.controlBorder }

    // MARK: - Selection

    static var selectionEmphasized: Color { currentTheme.selectionEmphasized }
    static var selectionUnemphasized: Color { currentTheme.selectionUnemphasized }

    // MARK: - Editor

    static var currentLineBackground: Color { currentTheme.currentLineBackground }
    static var lineNumber: Color { currentTheme.lineNumber }

    // MARK: - Accent & Focus

    static var accent: Color { currentTheme.accent }
    static var focusRing: Color { currentTheme.focusRing }

    // MARK: - Indicators

    static var modifiedIndicator: Color { currentTheme.modifiedIndicator }
    static var savedIndicator: Color { currentTheme.savedIndicator }
    static var errorIndicator: Color { currentTheme.errorIndicator }
    static var warningIndicator: Color { currentTheme.warningIndicator }

    // MARK: - Shadows

    static var shadowDrop: Color { currentTheme.shadowDrop }

    // MARK: - Buttons

    static var addButtonIcon: Color { currentTheme.addButtonIcon }
    static var addButtonHover: Color { currentTheme.addButtonHover }
    static var addButtonPressed: Color { currentTheme.addButtonPressed }

    // MARK: - NSColor (AppKit용)

    /// 현재 테마의 NSColor 버전 (MarkdownFormatter 등에서 사용)
    private static var currentNSColorTheme: (any ThemePaletteNSColor.Type)? {
        currentTheme as? any ThemePaletteNSColor.Type
    }

    static var nsEditorText: NSColor {
        currentNSColorTheme?.nsEditorText ?? .labelColor
    }

    static var nsMarkdownSyntax: NSColor {
        currentNSColorTheme?.nsMarkdownSyntax ?? .tertiaryLabelColor
    }

    static var nsEditorBackground: NSColor {
        currentNSColorTheme?.nsEditorBackground ?? .textBackgroundColor
    }

    static var nsTextEditorBackground: NSColor {
        currentNSColorTheme?.nsTextEditorBackground ?? .textBackgroundColor
    }

    static var nsCurrentLineHighlight: NSColor {
        currentNSColorTheme?.nsCurrentLineHighlight ?? NSColor.selectedTextBackgroundColor.withAlphaComponent(0.1)
    }

    static var nsEditorCursor: NSColor {
        currentNSColorTheme?.nsEditorCursor ?? .labelColor
    }
}
