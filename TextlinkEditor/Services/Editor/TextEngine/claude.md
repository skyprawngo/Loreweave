# 커스텀 텍스트 엔진

`TextDocument`의 행 모델, `TextSelection`의 위치·범위, `EditorState`의 편집·Undo 상태, `ViewportManager`의 표시 영역이 분리되어 있다. 실제 렌더링과 IME 입력은 `Views/MainEditor/EditorPanel/TextlinkTextView/`에 있다.

`EditorState/`의 확장 파일은 Editing, Cursor, Clipboard, LineOps, UndoRedo로 나뉜다. 새 편집 연산은 텍스트 결과뿐 아니라 선택 범위와 `UndoTypes.swift`의 액션 표현이 왕복하는지 확인한다. 연속 타이핑은 `CharacterType` 기반 그룹을 사용한다.

Core Text/AppKit 범위와 Swift 문자열 인덱스를 혼용하지 않는다. 범위 관련 변경은 한글 조합, 결합 문자, 이모지와 여러 행 선택이 경계를 드러낸다. 문서 로드와 편집은 이력 초기화 의미가 다르다(`EditorState.loadText`).
