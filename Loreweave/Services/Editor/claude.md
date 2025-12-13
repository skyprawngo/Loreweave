# Editor Services

에디터 관련 서비스들입니다.

## 파일 목록

| 파일 | 역할 |
|------|------|
| `EditorTabManager.swift` | 에디터 탭 상태 관리 (열린 파일, 선택된 탭) |
| `TextEngine/` | 커스텀 텍스트 엔진 (상세: `TextEngine/claude.md`) |

## 프로젝트별 설정 저장

에디터 설정(폰트, 크기, 줄간격)은 프로젝트 숨김폴더 `.{projectName}.weavedata/editor-settings.json`에 저장됩니다.

---

## 탭 관리 (EditorTabManager)

에디터에서 열린 파일 탭들을 관리합니다.

### 주요 기능

- **탭 열기/닫기**: 파일을 탭으로 열고, 탭 닫기
- **탭 선택**: 현재 활성 탭 관리
- **수정 상태 추적**: 파일 수정 여부 표시 (`isModified`)
- **파일 저장**: `saveTab(at:content:)`, `saveCurrentTab(content:)`

### 사용 예시

```swift
let tabManager = EditorTabManager.shared

// 파일 열기
tabManager.openFile(fileSystemItem)

// 탭 닫기
tabManager.closeTab(at: index)

// 현재 선택된 탭
if let tab = tabManager.selectedTab {
    print("현재 파일: \(tab.title)")
}

// 새 빈 탭 생성
tabManager.createNewTab()

// 수정 상태 확인
if tabManager.isModified(url: fileURL) {
    print("파일이 수정되었습니다")
}

// 파일 저장
tabManager.saveTab(at: index, content: editorContent)
```

### 연동 뷰

- `TabBarView`: 탭바 UI 표시
- `EditorView`: 선택된 탭의 파일 내용 표시, 텍스트 변경 시 수정 상태 업데이트
- `ProjectExplorerView`: 파일 클릭 시 탭 열기, 드래그 앤 드롭 시 저장 확인

### 수정 상태 표시

- 파일 편집 시 `EditorView`에서 `setModified(true)` 호출
- `TabItemView`에서 수정된 탭은 주황색 점으로 표시
- 파일 이동(드래그 앤 드롭) 시 저장 확인 다이얼로그 표시

### 저장 완료 애니메이션

`justSaved` 플래그를 사용하여 저장 완료 시 초록색 점으로 표시 후 자동 해제:

```swift
// saveTab(at:content:) 내부
tabs[index].justSaved = true

// 일정 시간 후 justSaved 상태 해제
let tabId = tabs[index].id
DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
    if let index = self?.tabs.firstIndex(where: { $0.id == tabId }) {
        self?.tabs[index].justSaved = false
    }
}
```

- `TabItemView`에서 `justSaved`가 true면 초록색 점 표시
- 1초 후 자동으로 false로 변경되어 페이드아웃
