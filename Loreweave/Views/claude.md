# Views 디렉토리 규칙

## macOS UI 스타일 가이드

### 색상
`Theme/AppColors.swift`에서 중앙 관리 - 하드코딩 금지

### Liquid Glass 효과 (macOS 26.0+)
`.glassEffect()` 모디파이어 사용 - macOS Tahoe 네이티브 글래스 효과

### 버튼 스타일
- 네비게이션 버튼: `Capsule()` 클립, 호버/클릭 배경색 적용
- 툴바 토글 버튼: `RoundedRectangle(cornerRadius: 4)`, 선택 시 `toolbarToggleSelected`

### 공통 수치
- 모서리 반경: 5-6pt
- 패딩: horizontal 8pt, vertical 4-5pt
- 아이콘 크기: 12pt (툴바), 13pt (일반)

### LoreEditor 커스텀 에디터
Core Text 기반 행별 렌더링 - **좌표계**: `isFlipped = true`

### NSAlert 다이얼로그
**필수**: `alert.beginSheetModalWithArrowNavigation(for:completionHandler:)` 사용 (좌우 화살표 키 네비게이션)

### NSTextView 한글 입력
조합 중(`hasMarkedText()`)일 때 `setAttributedString()` 호출 금지

## 뷰 계층 구조

**배치 원칙**: 윈도우 뷰는 `Views/` 루트에, 종속 뷰는 `{상위뷰명에서 View 제외}/` 폴더에

```
Views/
├── MainEditorView.swift          # 메인 윈도우
│   └── MainEditor/
│       ├── Sidebar/
│       ├── EditorContainerView.swift
│       │   └── EditorPanel/
│       │       └── LoreTextView/     # 커스텀 에디터
│       ├── TabBarView.swift
│       └── AIAssistantView.swift
├── WelcomeView.swift             # 시작 화면
└── SettingsView.swift            # 설정
```

## 테마 호환 배경

`ThemeAwareBackground` 사용 - 테마에 따라 투명/불투명 자동 전환
