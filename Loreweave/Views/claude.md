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

### 글래스모피즘 탭 스타일 (TabItemView 참고)

```swift
// 선택됨
AppColors.tabSelectedBackground + shadow(AppColors.tabSelectedShadow)

// 호버
AppColors.tabHoverBackground

// 기본 (비선택)
AppColors.tabDefaultBackground

// 테두리
Capsule().strokeBorder(AppColors.tabSelectedBorder / tabDefaultBorder)
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

### NSTextView 에디터 설정 (LineNumberedTextEditorRepresentable 참고)

**자동 줄바꿈**
```swift
// 컨테이너 너비에 맞춰 자동 줄바꿈
textView.textContainer?.widthTracksTextView = true
textView.textContainer?.heightTracksTextView = false
```

**텍스트 스타일 적용**
```swift
let paragraphStyle = NSMutableParagraphStyle()
paragraphStyle.lineSpacing = lineSpacing
paragraphStyle.alignment = textAlignment

let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: fontSize),
    .paragraphStyle: paragraphStyle,
    .foregroundColor: NSColor.textColor
]

// typingAttributes와 textStorage 모두 업데이트 필요
textView.typingAttributes = attributes
textView.textStorage?.setAttributes(attributes, range: fullRange)
```

### 애니메이션 패턴

**패널 토글 애니메이션**
```swift
.animation(.easeInOut(duration: 0.25), value: isVisible)
```

### NSAlert 다이얼로그 설정

**좌우 화살표 키 네비게이션**
- 모든 `NSAlert` 다이얼로그에서 좌우 화살표 키로 버튼 간 이동 가능
- `AlertHelper.beginSheetModal()` 또는 `alert.beginSheetModalWithArrowNavigation()` 사용

```swift
let alert = NSAlert()
alert.messageText = "제목"
alert.addButton(withTitle: "확인")
alert.addButton(withTitle: "취소")

// 좌우 화살표 키 네비게이션 활성화
alert.beginSheetModalWithArrowNavigation(for: window) { response in
    // 응답 처리
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

## 디렉토리 구조

**윈도우 단위 뷰는 최상위에, 종속 뷰는 하위 폴더에 배치합니다.**

## 배치 원칙

- 독립적으로 동작하는 윈도우 뷰 (예: MainEditorView, WelcomeView)는 Views/ 루트에 배치
- 상위 뷰에 종속된 하위 뷰들은 `{상위뷰명에서 View 제외}/` 폴더에 배치
- 폴더명은 상위 뷰 이름에서 `View` 접미사를 제외한 형태
- 하위 폴더 안에서도 동일한 규칙 적용 (중첩 가능)

## 구조 예시

```
Views/
├── MainEditorView.swift         # 메인 에디터 윈도우 (최상위)
├── MainEditor/                  # MainEditorView의 하위 뷰들
│   ├── SidebarView.swift
│   ├── Sidebar/                 # SidebarView의 하위 뷰들
│   │   ├── ProjectExplorerView.swift
│   │   └── FileSystemItemRow.swift
│   ├── TabBarView.swift
│   ├── EditorView.swift
│   ├── NavigationButtonsView.swift
│   ├── ToolbarSearchField.swift
│   └── AIAssistantView.swift
├── WelcomeView.swift            # 시작 화면 윈도우 (최상위)
└── SettingsView.swift           # 설정 윈도우 (최상위)
```

## 새 뷰 추가 시

1. 윈도우 레벨 뷰인지, 기존 뷰의 하위 컴포넌트인지 판단
2. 윈도우 레벨이면 `Views/` 루트에 `{Name}View.swift` 생성
3. 하위 컴포넌트면 해당 상위 뷰의 폴더에 배치 (폴더가 없으면 생성)
