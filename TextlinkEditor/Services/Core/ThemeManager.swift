//
//  ThemeManager.swift
//  TextlinkEditor
//
//  앱 테마(다크/라이트 모드) 관리
//  테마는 앱 시작 시에만 적용되며, 변경 시 앱 재시작 필요
//

import Foundation
import AppKit

/// 앱 테마 관리자
/// 시스템 테마, 라이트, 다크 모드 전환 관리
/// 테마 변경은 앱 재시작 후 적용됨
@Observable
final class ThemeManager {
    static let shared = ThemeManager()

    /// 앱 시작 시 적용된 테마 (런타임 중 변경되지 않음)
    let appliedTheme: AppTheme

    private init() {
        // 앱 시작 시 현재 설정된 테마를 캐시
        self.appliedTheme = UserSettings.shared.appTheme

        // 앱이 준비된 후 테마 적용
        DispatchQueue.main.async { [self] in
            applyTheme(appliedTheme)
        }
    }

    /// 테마 적용 (앱 시작 시에만 호출)
    private func applyTheme(_ theme: AppTheme) {
        guard let app = NSApp else { return }

        switch theme {
        case .system:
            app.appearance = nil
        case .light:
            app.appearance = NSAppearance(named: .aqua)
        case .dark, .opaque:
            // opaque도 다크 모드 기반
            app.appearance = NSAppearance(named: .darkAqua)
        }
    }

    /// 현재 적용된 테마가 불투명 테마인지 확인
    var isOpaqueTheme: Bool {
        appliedTheme == .opaque
    }
}
