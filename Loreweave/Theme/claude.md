# Theme 디렉토리 규칙

## 개요

앱 전역 테마 및 색상 시스템을 관리합니다.

## 아키텍처

```
Theme/
├── AppColors.swift        # 색상 라우터 (NSColor 시스템 색상 사용)
├── FinderDarkTheme.swift  # 참조용: macOS Finder 다크모드 RGB 색상값
└── (향후 추가 예정)
    ├── AppFonts.swift     # 폰트 시스템
    └── ThemeManager.swift # 커스텀 테마 전환 관리
```

## 색상 사용 규칙

**색상은 반드시 `AppColors`를 통해 사용** (하드코딩 금지)

```swift
// 올바른 사용
.foregroundStyle(AppColors.toolbarIcon)
.background(AppColors.tabSelectedBackground)

// 잘못된 사용 (금지)
.foregroundStyle(.secondary)
.foregroundStyle(Color(red: 0.5, green: 0.5, blue: 0.5))
```

## AppColors (색상 라우터)

NSColor 시스템 색상을 사용하여 다크/라이트 모드, 윈도우 활성/비활성 상태에 자동 대응.

```swift
// 탭바
AppColors.tabSelectedBackground  // controlBackgroundColor
AppColors.tabHoverBackground     // controlAccentColor 12%
AppColors.tabText                // labelColor

// 툴바
AppColors.toolbarIcon            // secondaryLabelColor
AppColors.toolbarIconActive      // labelColor
AppColors.toolbarToggleSelected  // accentColor 20%

// 텍스트
AppColors.textPrimary            // labelColor
AppColors.textSecondary          // secondaryLabelColor

// 상태 표시
AppColors.modifiedIndicator      // systemOrange
AppColors.savedIndicator         // systemGreen
```

## NSColor 시스템 색상 사용 이유

1. **다크/라이트 모드 자동 대응**: 시스템 설정 변경 시 자동 반영
2. **윈도우 활성/비활성 상태**: 포커스 변경 시 색상 자동 조정
3. **접근성 지원**: 고대비 모드 등 시스템 설정 존중
4. **일관성**: macOS 네이티브 앱과 동일한 색상 사용

## FinderDarkTheme (참조용)

Digital Color Meter로 측정한 macOS Finder 다크모드의 실제 RGB 색상값.
커스텀 테마 구현 시 참고용으로 사용.

## 새 색상 추가 시

1. `AppColors.swift`에 NSColor 시스템 색상으로 정의
2. 의미론적 이름 사용 (예: `toolbarIcon`, `tabText`)
3. 뷰에서 `AppColors.xxx`로 사용
