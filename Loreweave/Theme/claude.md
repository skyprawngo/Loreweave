# 테마 시스템

## 파일 구조

| 파일 | 역할 |
|------|------|
| `ThemePalette.swift` | 테마 프로토콜 정의 |
| `AppColors.swift` | 색상 라우터 (현재 테마에서 색상 가져옴) |
| `DarkTheme.swift` | 다크 테마 (기본 테마) |
| `SystemTheme.swift` | 시스템 테마 (라이트/다크 자동) |
| `LightTheme.swift` | 라이트 테마 |
| `OpaqueTheme.swift` | 불투명 테마 |

## 핵심 개념

- **ThemePalette**: 모든 테마가 준수해야 하는 색상 속성 정의
- **AppColors**: 뷰에서 색상 접근 시 사용 (`AppColors.textPrimary`)
- **기본 테마**: DarkTheme - 일반 작업 시 이 파일만 수정

## 테마 최신화 규칙

### 일반 작업 시
새 UI 컴포넌트 추가 시 → `DarkTheme.swift`에만 색상 추가

### 테마 전체 최신화 요청 시
1. DarkTheme 기준으로 다른 테마 파일과 비교
2. 누락된 속성 추가, 불필요한 속성 제거
3. 각 테마 특성에 맞게 색상값 조정

## 테마 종류

| 테마 | ID | 불투명 |
|------|----|--------|
| SystemTheme | `system` | ❌ |
| LightTheme | `light` | ❌ |
| DarkTheme | `dark` | ❌ |
| OpaqueTheme | `opaque` | ✅ |

**불투명 테마**: `VisualEffectBackground` 대신 고정 배경색 사용

## 색상 속성 카테고리

- **Background**: background, barBackground, sidebarBackground, contentBackground, textEditorBackground, controlBackground
- **Text**: textPrimary, textSecondary, textTertiary, textDisabled
- **Tab Bar**: tabSelectedBackground, tabHoverBackground, tabDefaultBackground, tabText 등
- **Toolbar**: toolbarButtonHover, toolbarButtonPressed, toolbarToggleSelected, toolbarIcon 등
- **Sidebar**: sidebarItemSelected, sidebarItemHover, sidebarHeaderText
- **Separators**: separator, separatorOpaque, controlBorder
- **Indicators**: modifiedIndicator, savedIndicator, errorIndicator, warningIndicator
