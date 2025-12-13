# TextEngine - 커스텀 텍스트 엔진

Loreweave의 커스텀 텍스트 에디터 엔진입니다. VSCode Monaco 스타일의 행 기반 구조를 채택합니다.

## 아키텍처

```
EditorState (통합 관리자)
├── TextDocument (문서 모델)
├── TextSelection (선택/커서)
└── ViewportManager (가상 스크롤)
```

## 파일 목록

| 파일 | 역할 |
|------|------|
| `EditorState.swift` | 에디터 통합 상태 (문서 + 선택 + 뷰포트 + Undo/Redo) |
| `TextDocument.swift` | 행 기반 문서 모델 (`TextLine` 배열) |
| `TextSelection.swift` | 커서/선택 상태 (`TextPosition`, `TextRange`) |
| `ViewportManager.swift` | 가상 스크롤, 보이는 행 범위 계산 |

## 핵심 개념

### TextDocument

- **행 기반**: `lines: [TextLine]` - 각 행은 `id`, `content`, `cachedWidth` 보유
- **버전 관리**: `version` 프로퍼티로 변경 감지
- **캐시 무효화**: 행 변경 시 `needsRender = true`

### TextSelection

- **TextPosition**: `(line, column)` 좌표
- **TextRange**: `start...end` 범위, `isEmpty`면 커서 상태

### ViewportManager

- **가상 스크롤**: `firstVisibleLine`, `lastVisibleLine` 계산
- **렌더 버퍼**: 뷰포트 위아래 5행 추가 렌더링

### EditorState

- `EditorConfiguration`으로 폰트/줄간격 설정
- Undo/Redo 스택 내장
- `isEditable`, `isModified` 상태 관리

## 뷰 레이어

뷰 컴포넌트는 `Views/MainEditor/EditorPanel/LoreTextView/`에 위치:

| 파일 | 역할 |
|------|------|
| `LoreEditorRepresentable.swift` | SwiftUI ↔ NSView 브릿지 |
| `LoreEditorView.swift` | 메인 NSView (스크롤뷰 + 거터 + 텍스트) |
| `LoreTextView.swift` | 텍스트 렌더링/입력 처리 |
| `GutterView.swift` | 줄번호 표시 |
| `LineRenderer.swift` | 행 단위 렌더링 |

## TODO

- [ ] 마크다운 신택스 하이라이팅
- [ ] 검색/치환 기능
- [ ] 멀티 커서 지원
- [ ] 코드 접기(folding)
