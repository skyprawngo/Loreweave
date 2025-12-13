# 테마 시스템

## 파일 구조

```
Theme/
├── ThemePalette.swift    # 테마 프로토콜 정의
├── AppColors.swift       # 색상 라우터 (현재 테마에서 색상 가져옴)
├── DarkTheme.swift       # 다크 테마 (기본 테마) ⭐
├── SystemTheme.swift     # 시스템 테마 (라이트/다크 자동)
├── LightTheme.swift      # 라이트 테마
└── OpaqueTheme.swift     # 불투명 테마 (고정 배경색)
```

## 핵심 개념

### ThemePalette 프로토콜
모든 테마가 준수해야 하는 색상 속성을 정의. 새로운 색상이 필요하면 이 프로토콜에 먼저 추가.

### AppColors (라우터)
뷰에서 색상에 접근할 때 사용. `UserSettings.shared.appTheme`에 따라 적절한 테마에서 색상을 가져옴.

```swift
// 사용 예시
Text("Hello")
    .foregroundStyle(AppColors.textPrimary)
    .background(AppColors.background)
```

### 기본 테마: DarkTheme
일반 작업 시 `DarkTheme.swift`만 수정. 다른 테마들은 테마 최신화 요청 시 DarkTheme 기준으로 동기화.

## 테마 최신화 규칙

### 일반 작업 시
- 새로운 UI 컴포넌트 추가 시 → `DarkTheme.swift`에만 색상 추가
- `ThemePalette` 프로토콜에 새 속성 추가하면 컴파일 에러로 다른 테마도 수정 필요

### 테마 전체 최신화 요청 시
1. `DarkTheme.swift`의 모든 속성을 기준으로 삼음
2. 다른 테마 파일들(`SystemTheme`, `LightTheme`, `OpaqueTheme`)과 비교
3. 누락된 속성 추가, 불필요한 속성 제거
4. 각 테마 특성에 맞게 색상값 조정

### 새 테마 추가 시
1. 기존 테마 파일 복사 (예: `DarkTheme.swift` → `NewTheme.swift`)
2. `ThemePalette` 프로토콜 준수 확인
3. `AppColors.swift`의 switch문에 새 케이스 추가
4. `UserSettings.swift`의 `AppTheme` enum에 새 케이스 추가
5. 다국어 번역 키 추가

## 테마 종류

| 테마 | ID | 설명 | 불투명 |
|------|-----|------|--------|
| SystemTheme | `system` | macOS 시스템 설정 따름 | ❌ |
| LightTheme | `light` | 항상 라이트 모드 | ❌ |
| DarkTheme | `dark` | 항상 다크 모드 | ❌ |
| OpaqueTheme | `opaque` | 불투명 다크 + 파란색 포인트 | ✅ |

### 불투명 테마 (isOpaque = true)
- `VisualEffectBackground` 대신 고정 배경색 사용
- 뷰에서 `AppColors.isOpaqueTheme`으로 분기 가능

## NSColor (AppKit용)

`MarkdownFormatter` 등 AppKit 컴포넌트에서 사용하는 NSColor는 `ThemePaletteNSColor` 프로토콜로 정의.

```swift
// AppColors를 통해 접근
let textColor = AppColors.nsEditorText
let syntaxColor = AppColors.nsMarkdownSyntax
```

## 색상 속성 목록

### Background
- `background` - 윈도우/메인 배경
- `barBackground` - 툴바/탭바 배경
- `sidebarBackground` - 사이드바 배경
- `contentBackground` - 콘텐츠 영역 배경
- `textEditorBackground` - 텍스트 에디터 배경
- `controlBackground` - 컨트롤 배경 (텍스트필드 등)

### Text
- `textPrimary` - 기본 텍스트 (가장 높은 대비)
- `textSecondary` - 보조 텍스트 (중간 대비)
- `textTertiary` - 3차 텍스트 (힌트, 플레이스홀더)
- `textDisabled` - 비활성 텍스트

### Tab Bar
- `tabSelectedBackground` - 탭 배경 (선택됨)
- `tabHoverBackground` - 탭 배경 (호버)
- `tabDefaultBackground` - 탭 배경 (기본)
- `tabSelectedBorder` - 탭 테두리 (선택됨)
- `tabDefaultBorder` - 탭 테두리 (기본)
- `tabText` - 탭 텍스트
- `tabCloseHoverBackground` - 탭 닫기 버튼 배경 (호버)
- `tabSelectedShadow` - 탭 그림자 (선택됨)

### Toolbar
- `toolbarButtonHover` - 툴바 버튼 배경 (호버)
- `toolbarButtonPressed` - 툴바 버튼 배경 (클릭)
- `toolbarToggleSelected` - 툴바 토글 버튼 배경 (선택됨)
- `toolbarIcon` - 툴바 아이콘
- `toolbarIconActive` - 툴바 아이콘 (활성)

### Sidebar
- `sidebarItemSelected` - 사이드바 아이템 (선택됨)
- `sidebarItemHover` - 사이드바 아이템 (호버)
- `sidebarHeaderText` - 사이드바 섹션 헤더 텍스트

### Separators
- `separator` - 구분선
- `separatorOpaque` - 굵은 구분선
- `controlBorder` - 컨트롤 테두리

### Selection
- `selectionEmphasized` - 선택 영역 (포커스됨)
- `selectionUnemphasized` - 선택 영역 (포커스 안됨)

### Accent & Focus
- `accent` - 포인트 컬러
- `focusRing` - 포커스 링

### Indicators
- `modifiedIndicator` - 수정됨 표시 (주황색)
- `savedIndicator` - 저장됨 표시 (녹색)
- `errorIndicator` - 오류 표시 (빨간색)
- `warningIndicator` - 경고 표시 (노란색)

### Shadows
- `shadowDrop` - 드롭 섀도우

### Buttons
- `addButtonIcon` - 추가 버튼 아이콘
- `addButtonHover` - 추가 버튼 배경 (호버)
- `addButtonPressed` - 추가 버튼 배경 (클릭)

### Theme Metadata
- `id` - 테마 ID (저장용)
- `displayNameKey` - 테마 표시 이름 (L10n 키)
- `isOpaque` - 불투명 테마 여부
