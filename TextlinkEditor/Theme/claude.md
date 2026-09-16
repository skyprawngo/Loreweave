# 테마 계약

`ThemePalette.swift`는 색상 계약, `AppColors.swift`는 현재 테마 라우터다. SwiftUI 색상과 AppKit의 `ThemePaletteNSColor` 경로가 함께 있다. `DarkTheme`, `LightTheme`, `SystemTheme`, `OpaqueTheme`가 이 계약을 구현한다.

기존 색상이 목적에 맞으면 `AppColors`를 재사용한다. 새 공통 색상은 프로토콜·라우터·각 테마 구현을 함께 맞춘다. DarkTheme만 수정하는 방식은 다른 테마의 계약 또는 표시를 누락시킬 수 있다.

`ThemeAwareBackground.swift`는 `isOpaque`에 따른 배경 분기를 제공한다. 배경 변경은 불투명 모드와 시스템 밝기 전환에서 텍스트·선택 영역의 대비도 확인한다.

`AppColors`, 배경, AppKit appearance는 시작 시 선택된 `ThemeManager.appliedTheme`를 기준으로 한다. `UserSettings.appTheme`에 저장한 새 선택은 다음 앱 시작에 적용된다. 즉시 테마 전환을 추가한다면 색상 라우터와 배경·appearance의 수명을 함께 바꿔야 한다.
