# Editor Services

에디터 관련 서비스들입니다.

## 파일 목록

| 파일/폴더 | 역할 |
|-----------|------|
| `EditorTabManager.swift` | 에디터 탭 상태 관리 (열린 파일, 선택된 탭) |
| `TextEngine/` | 커스텀 텍스트 엔진 (상세: `TextEngine/claude.md`) |
| `TextEngine/EditorState/` | EditorState 기능별 확장 (Undo/Redo, 편집, 커서 등) |

## 프로젝트별 설정 저장

에디터 설정(폰트, 크기, 줄간격)은 `.{projectName}.weavedata/editor-settings.json`에 저장

## 탭 관리 (EditorTabManager)

에디터에서 열린 파일 탭들을 관리합니다.

### 주요 기능
- **탭 열기/닫기**: `openFile()`, `closeTab(at:)`
- **탭 선택**: `selectTab(at:)`
- **수정 상태 추적**: `isModified`, `setModified()`
- **파일 저장**: `saveTab(at:content:)`, `saveCurrentTab(content:)`

### 저장 완료 애니메이션
`justSaved` 플래그로 저장 완료 시 초록색 점 표시 후 1초 후 자동 해제

### 연동 뷰
- `TabBarView`: 탭바 UI 표시
- `EditorContainerView`: 선택된 탭의 파일 내용 표시
- `ProjectExplorerView`: 파일 클릭 시 탭 열기

## Undo/Redo 시스템

에디터의 Undo/Redo는 `TextEngine/EditorState/`에서 관리됩니다.

- **탭별 독립 히스토리**: 각 탭(EditorState)마다 별도 Undo 스택
- **최대 100개**: 히스토리 제한, 초과 시 오래된 항목 제거
- **파일 로드 시 초기화**: 탭 전환/새 파일 로드 시 히스토리 클리어
- **연속 타이핑 그룹화**: 같은 문자 타입(한글/영문/일본어 등) 연속 입력은 하나의 Undo 단위

상세 구현: `TextEngine/claude.md` 참조
