//
//  ThemeManager.swift
//  Loreweave
//
//  앱 테마(다크/라이트 모드) 관리
//

import Foundation
import AppKit

/// 앱 테마 관리자
/// 시스템 테마, 라이트, 다크 모드 전환 관리
@Observable
final class ThemeManager {
    static let shared = ThemeManager()

    private init() {
        // 앱이 준비된 후 테마 적용
        DispatchQueue.main.async { [self] in
            applyTheme(UserSettings.shared.appTheme)
        }
    }

    /// 테마 적용
    func applyTheme(_ theme: AppTheme) {
        guard let app = NSApp else { return }

        switch theme {
        case .system:
            app.appearance = nil
        case .light:
            app.appearance = NSAppearance(named: .aqua)
        case .dark:
            app.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
