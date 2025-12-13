# Views 디렉토리 규칙

## macOS UI 스타일 가이드 (Liquid Glass)

macOS 네이티브 앱과 일관된 UI를 위해 다음 원칙을 따릅니다.

### 색상 시스템

**색상은 `Theme/AppColors.swift`에서 중앙 관리** (상세: `Loreweave/Theme/claude.md`)

- 하드코딩 색상 대신 `AppColors` 사용
- 시스템 색상(`NSColor`) 우선 사용

### 버튼 스타일

- **네비게이션 버튼** (NavigationButtonsView 참고)
  - 각 버튼에 `Capsule()` 클립 적용 (파인더 스타일)
  - 호버: `AppColors.addButtonHover`
  - 클릭: `AppColors.addButtonPressed`
  - 버튼 사이 구분선: `Rectangle` with `.separatorColor`
  - **툴바 캡슐 동심원**: macOS 툴바의 외부 캡슐 배경과 내부 버튼 캡슐이 동심이 되도록 할 것

- **프레스 상태 감지** (simultaneousGesture 사용)
  ```swift
  .simultaneousGesture(
      DragGesture(minimumDistance: 0)
          .onChanged { _ in isPressed = true }
          .onEnded { _ in isPressed = false }
  )
  ```

- **툴바 토글 버튼** (EditorToolbar 참고)
  - 선택 시 배경: `AppColors.toolbarToggleSelected`
  - 모서리: `RoundedRectangle(cornerRadius: 4)`

### Liquid Glass 효과 (macOS 26.0+)

**`.glassEffect()` 모디파이어 사용** - macOS Tahoe의 네이티브 글래스 효과

```swift
// 기본 글래스 효과 (NavigationButtonsView)
.glassEffect()

// 캡슐 모양 글래스 효과 (TabItemView - 선택된 탭)
.glassEffect(.regular, in: .capsule)

// 조건부 적용 (선택 여부에 따라)
.background(
    Capsule()
        .fill(isSelected ? Color.clear : tabBackgroundColor)
)
.glassEffect(isSelected ? .regular : .clear, in: .capsule)
```

### 탭 스타일 (TabItemView 참고)

```swift
// 선택된 탭: Liquid Glass 효과
.glassEffect(.regular, in: .capsule)

// 선택되지 않은 탭: 불투명 배경
AppColors.tabSelectedBackground (기본)
AppColors.tabHoverBackground (호버)
```

### 텍스트 필드

- **검색 필드** (ToolbarSearchField 참고)
  - 배경: `.textBackgroundColor`
  - 포커스 시: accent color 테두리 2pt
  - 비포커스: separator 0.5pt
  - 클리어 버튼: `xmark.circle.fill`

### 공통 수치

- **모서리 반경**: 5-6pt
- **패딩**: horizontal 8pt, vertical 4-5pt
- **아이콘 크기**: 12pt (툴바), 13pt (일반)

### LoreEditor 커스텀 에디터

**Core Text 기반 행별 렌더링** - VSCode Monaco 스타일

주요 컴포넌트:
- `LoreEditorRepresentable`: SwiftUI-AppKit 브릿지 (NSViewRepresentable)
- `LoreEditorView`: 통합 에디터 (거터 + 텍스트 + 스크롤)
- `LoreTextView`: 텍스트 렌더링 및 입력 처리 (NSTextInputClient)
- `GutterView`: 줄번호 표시
- `LineRenderer`: Core Text 행 렌더링 + 캐싱

**좌표계**: `isFlipped = true` (위에서 아래로)

**Core Text 텍스트 매트릭스** (isFlipped 뷰에서 필수):
```swift
context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
context.textPosition = CGPoint(x: x, y: y + baselineOffset)
CTLineDraw(ctLine, context)
```

### 애니메이션 패턴

**패널 토글 애니메이션**
```swift
.animation(.easeInOut(duration: 0.25), value: isVisible)
```

### NSAlert 다이얼로그 설정

**⚠️ 필수: 좌우 화살표 키 네비게이션**

모든 `NSAlert` 다이얼로그는 반드시 방향키로 버튼 이동이 가능해야 합니다.

- **금지**: `alert.beginSheetModal(for:completionHandler:)` 직접 사용
- **필수**: `alert.beginSheetModalWithArrowNavigation(for:completionHandler:)` 사용

```swift
let alert = NSAlert()
alert.messageText = "제목"
alert.addButton(withTitle: "확인")
alert.addButton(withTitle: "취소")

// ✅ 올바른 사용법 - 좌우 화살표 키 네비게이션 활성화
alert.beginSheetModalWithArrowNavigation(for: window) { response in
    // 응답 처리
}

// ❌ 잘못된 사용법 - 방향키 네비게이션 불가
alert.beginSheetModal(for: window) { response in
    // ...
}
```

**파일명 입력 필드 기본 선택**
- 파일명 입력 시 확장자 앞까지만 선택 (예: `untitled.md` → `untitled` 선택)
- `NSTextField.currentEditor()?.selectedRange` 사용

```swift
let baseName = (fileName as NSString).deletingPathExtension
if !baseName.isEmpty && baseName.count < fileName.count {
    textField.currentEditor()?.selectedRange = NSRange(location: 0, length: baseName.count)
}
```

### NSTextView 한글 입력 처리

**조합 중 문자 보호**
- `hasMarkedText()`로 한글 조합 중인지 확인
- 조합 중일 때 `setAttributedString()` 호출 금지 (문자 손실 방지)

```swift
// updateNSView 또는 텍스트 변경 콜백에서
guard !textView.hasMarkedText() else { return }

// 조합이 끝난 후에만 서식 적용
textView.textStorage?.setAttributedString(attributedString)
```

---

## 뷰 계층 구조

**윈도우 단위 뷰는 최상위에, 종속 뷰는 하위 폴더에 배치합니다.**

### 배치 원칙

- 독립적으로 동작하는 윈도우 뷰는 `Views/` 루트에 배치
- 종속 뷰는 `{상위뷰명에서 View 제외}/` 폴더에 배치
- 하위 폴더 안에서도 동일한 규칙 적용 (중첩 가능)

### 파일 구조 및 계층

```
Views/
├── MainEditorView.swift                    # 메인 윈도우
│   └── MainEditor/
│       ├── Sidebar/
│       │   ├── ProjectExplorerView.swift
│       │   └── FileSystemItemRow.swift
│       ├── EditorContainerView.swift       # 에디터 컨테이너
│       │   └── EditorPanel/
│       │       ├── EditorToolbarView.swift     # 서식 툴바
│       │       └── LoreTextView/               # 커스텀 에디터
│       │           ├── LoreEditorRepresentable.swift
│       │           ├── LoreEditorView.swift
│       │           ├── LoreTextView.swift
│       │           ├── GutterView.swift
│       │           └── LineRenderer.swift
│       ├── TabBarView.swift                # 탭바
│       │   └── TabItemView
│       ├── NavigationButtonsView.swift
│       ├── SpotlightView.swift
│       └── AIAssistantView.swift           # AI 첨삭 패널
│           ├── AIAssistantHeader
│           ├── NewFeedbackRequestSection
│           └── FeedbackRequestList
├── WelcomeView.swift                       # 시작 화면 윈도우
└── SettingsView.swift                      # 설정 윈도우
```

### 컴포넌트 역할

| 컴포넌트 | 역할 |
|---------|------|
| `MainEditorView` | 메인 윈도우 - NavigationSplitView + AI패널 |
| `EditorContainerView` | 탭바 + 툴바 + 에디터 + 상태바 |
| `LoreEditorRepresentable` | SwiftUI-AppKit 브릿지 |
| `LoreEditorView` | 통합 에디터 (거터 + 텍스트 + 스크롤) |
| `LoreTextView` | 텍스트 렌더링/입력 (NSTextInputClient) |
| `GutterView` | 줄번호 표시 |
| `AIAssistantView` | AI 첨삭 패널 |

### 새 뷰 추가 시

1. 윈도우 레벨 → `Views/` 루트에 `{Name}View.swift`
2. 하위 컴포넌트 → 상위 뷰 폴더에 배치

---

## 테마 호환 배경 설정

모든 뷰는 시스템/라이트/다크/불투명 테마와 호환되도록 `ThemeAwareBackground`를 사용합니다.

### ThemeAwareBackground

테마에 따라 투명/불투명 배경을 자동 전환하는 컴포넌트:
- **시스템/라이트/다크 테마**: `VisualEffectBackground` (반투명)
- **불투명 테마**: `OpaqueTheme.background` (고정 색상)

```swift
// 사이드바 영역
.background(ThemeAwareBackground(material: .sidebar, blendingMode: .behindWindow))

// 콘텐츠 영역
.background(ThemeAwareBackground(material: .contentBackground, blendingMode: .behindWindow))
```

### 적용 대상

독립 윈도우 뷰 및 주요 영역에 적용:
- `WelcomeView` - 좌측(sidebar), 우측(contentBackground)
- `PermissionRequestView` - contentBackground
- `SettingsView` - contentBackground
- `SidebarView` - sidebar
- `AIAssistantView` - sidebar
