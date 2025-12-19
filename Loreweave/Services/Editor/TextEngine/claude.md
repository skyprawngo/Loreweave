# TextEngine - 커스텀 텍스트 엔진

VSCode Monaco 스타일의 행 기반 텍스트 에디터 엔진입니다.

## 파일 구조

| 파일 | 역할 |
|------|------|
| `EditorState.swift` | 코어 상태 (프로퍼티, 설정, 문서 로드) |
| `TextDocument.swift` | 행 기반 문서 모델 (`TextLine` 배열) |
| `TextSelection.swift` | 커서/선택 상태 (`TextPosition`, `TextRange`) |
| `ViewportManager.swift` | 가상 스크롤, 보이는 행 범위 계산 |

### EditorState/ (기능별 확장)

| 파일 | 역할 |
|------|------|
| `EditorState+Editing.swift` | 텍스트 편집 (삽입, 삭제) |
| `EditorState+Cursor.swift` | 커서 이동 및 선택 |
| `EditorState+Clipboard.swift` | 복사, 잘라내기, 붙여넣기 |
| `EditorState+LineOps.swift` | 행 단위 작업 (이동, 복제) |
| `EditorState+UndoRedo.swift` | Undo/Redo 처리 |
| `UndoTypes.swift` | Undo 타입 (`UndoAction`, `CharacterType`) |

## 뷰 레이어

`Views/MainEditor/EditorPanel/LoreTextView/` 참조

## Undo/Redo 확장 방법

새 작업 타입 추가 시:
1. `UndoTypes.swift`의 `UndoAction` enum에 case 추가
2. `EditorState+UndoRedo.swift`의 `applyUndoAction()`에 처리 로직 추가
3. 작업 수행 지점에서 `pushUndoAction()` 호출

연속 타이핑은 `CharacterType`에 따라 자동 그룹화 (한글/영문/일본어 등)
