//
//  NSColorTheme.swift
//  Loreweave
//
//  NSColor 시스템 색상 테마
//  NSTextView 등 AppKit 컴포넌트에서 사용
//  라이트/다크 모드에 자동 대응하는 시스템 색상 사용
//
//  NSColor 시스템 색상 참고:
//  - textColor: 텍스트 색상 (라이트: 검정, 다크: 흰색)
//  - textBackgroundColor: 텍스트 배경 (라이트: 흰색, 다크: 어두운 색)
//  - labelColor: 기본 라벨 (가장 높은 대비)
//  - secondaryLabelColor: 보조 라벨 (중간 대비)
//  - tertiaryLabelColor: 3차 라벨 (낮은 대비)
//  - placeholderTextColor: 플레이스홀더 텍스트
//

import AppKit

/// NSColor 기반 테마 (AppKit 컴포넌트용)
/// 시스템 색상을 사용하여 라이트/다크 모드 자동 대응
enum NSColorTheme {

    // MARK: - Text Colors

    /// 에디터 기본 텍스트 - 텍스트 색상 사용
    static var editorText: NSColor { .textColor }

    /// 기본 텍스트 - 가장 높은 대비
    static var textPrimary: NSColor { .labelColor }

    /// 보조 텍스트 - 중간 대비
    static var textSecondary: NSColor { .secondaryLabelColor }

    /// 3차 텍스트 - 낮은 대비 (힌트)
    static var textTertiary: NSColor { .tertiaryLabelColor }

    /// 비활성 텍스트
    static var textDisabled: NSColor { .disabledControlTextColor }

    /// 플레이스홀더 텍스트
    static var textPlaceholder: NSColor { .placeholderTextColor }

    // MARK: - Line Numbers

    /// 줄번호 텍스트 (비선택) - 3차 라벨 (희미함)
    static var lineNumber: NSColor { .tertiaryLabelColor }

    /// 줄번호 텍스트 (선택됨) - 보조 라벨 (좀 더 밝음)
    static var lineNumberActive: NSColor { .secondaryLabelColor }

    // MARK: - Markdown Syntax

    /// 마크다운 구문 색상 - 3차 라벨 (희미하게 표시)
    static var markdownSyntax: NSColor { .tertiaryLabelColor }

    // MARK: - Background Colors

    /// 에디터 배경 - 텍스트 배경 색상
    static var editorBackground: NSColor { .textBackgroundColor }

    /// 줄번호 영역 배경 - 컨트롤 배경의 투명 버전
    static var lineNumberBackground: NSColor {
        .unemphasizedSelectedContentBackgroundColor.withAlphaComponent(0.3)
    }

    /// 현재 줄 하이라이트 - 악센트 색상의 투명 버전
    static var currentLineHighlight: NSColor {
        .controlAccentColor.withAlphaComponent(0.08)
    }

    // MARK: - Accent & Selection

    /// 악센트 색상
    static var accent: NSColor { .controlAccentColor }

    /// 선택 영역 배경
    static var selection: NSColor { .selectedTextBackgroundColor }

    // MARK: - Separators

    /// 구분선
    static var separator: NSColor { .separatorColor }

    // MARK: - Icon Colors

    /// 기본 아이콘 - 기본 라벨
    static var iconPrimary: NSColor { .labelColor }

    /// 보조 아이콘 - 보조 라벨
    static var iconSecondary: NSColor { .secondaryLabelColor }
}
