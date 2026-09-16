# 전역 상태와 AppKit 연동

- `UserSettings.swift`: UserDefaults 기반 전역 설정과 CLI 경로 문자열. 에디터의 프로젝트별 설정은 `EditorTabManager`에도 있으므로 저장 범위를 구별한다.
- `PermissionManager.swift`: 디렉토리 접근 권한. 프로젝트 접근 수명은 `ProjectManager`의 bookmark 처리와 함께 확인한다.
- `KeyboardShortcutManager.swift`와 `AppCommands.swift`: 사용자 단축키 정의·저장 및 메뉴 동작 연결. 사용자 변경이 가능한 액션은 뷰의 고정 키로 우회하지 않는다. 저장 파일은 `~/Library/Application Support/TextlinkEditor/shortcuts.json`이다.
- `ThemeManager.swift`, `WindowStateManager.swift`: 테마 적용과 창 상태. 색상 계약은 [Theme](../../Theme/claude.md)에 있다.
- `AlertHelper.swift`: `beginSheetModalWithArrowNavigation`으로 시트의 화살표 탐색을 제공한다. 기존 파일 작업 다이얼로그와 일관된 키보드 동작을 유지한다.

## Undo 소유권

원고는 문서 ID별 `EditorState` 자체 이력을 사용한다. AI 입력은 `AIChatView`의 `NSTextView` 기본 UndoManager를 사용하며, 외부에서 입력 내용을 바꿀 때 이력을 초기화한다. 남아 있는 `UndoSystem.swift`를 현재 AI 입력의 실행 경로로 가정하지 않는다.

Edit 메뉴의 `undo:`/`redo:`가 실제 first responder에 도달해야 한다. 조합 중 IME 처리와 편집 알림을 통해 화면·binding·전송 문자열이 함께 갱신되는지도 확인한다. 원고 Undo의 액션 표현은 [Editor](../Editor/claude.md)와 텍스트 엔진에 있다.
