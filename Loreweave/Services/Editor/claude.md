# Editor Services

에디터 관련 서비스들입니다.

## 파일 목록

| 파일 | 역할 |
|------|------|
| `EditorTabManager.swift` | 에디터 탭 상태 관리 (열린 파일, 선택된 탭) |
| `TextEngine/` | 커스텀 텍스트 엔진 (상세: `TextEngine/claude.md`) |

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
