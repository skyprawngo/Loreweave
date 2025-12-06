# FileSystem Services

파일 시스템 관련 서비스들입니다.

## 파일 목록

| 파일 | 역할 |
|------|------|
| `FileSystemManager.swift` | 파일/폴더 CRUD 및 변경 감시 |

---

## FileSystemManager

프로젝트 탐색기의 파일/폴더 작업을 담당합니다.

### 주요 기능

- **디렉토리 로드**: `loadChildren(of:)` - 동기적으로 하위 항목 로드
- **펼침/접기**: `toggleExpand(_:)` - 폴더 확장 상태 토글
- **CRUD**: `createFolder`, `createFile`, `rename`, `delete`, `move`, `copy`
- **파일 감시**: `startWatching(at:)` - DispatchSource로 변경 감지
- **드래그 앤 드롭**: `move(_:to:)` - 항목 이동, `showSaveConfirmationBeforeMove` - 저장 확인 다이얼로그

### 사용 예시

```swift
// 프로젝트 초기화
FileSystemManager.shared.initializeProject(at: projectURL)

// 폴더 펼치기/접기
FileSystemManager.shared.toggleExpand(folderItem)

// 새 파일 생성
FileSystemManager.shared.createFile(named: "chapter1.md", in: parentFolder)

// Finder에서 열기
FileSystemManager.shared.revealInFinder(item)

// 항목 이동 (드래그 앤 드롭)
FileSystemManager.shared.move(sourceItem, to: destinationFolder)

// 저장 확인 다이얼로그 (이동 전)
FileSystemManager.shared.showSaveConfirmationBeforeMove(fileName: "chapter1.md") { result in
    switch result {
    case .save: // 저장 후 이동
    case .dontSave: // 저장 없이 이동
    case .cancel: // 취소
    }
}
```

### 설계 원칙

- **동기적 실행**: 파일 I/O는 메인 스레드에서 동기적으로 실행 (로컬 파일 시스템은 충분히 빠름)
- **객체 재사용**: 기존 `FileSystemItem` 객체를 재사용하여 SwiftUI 상태 안정성 유지
- **Lazy Loading**: 폴더 클릭 시 해당 폴더의 직접 자식만 로드

### 드래그 앤 드롭

사이드바에서 파일/폴더를 드래그하여 다른 폴더로 이동할 수 있습니다.

- **드래그 소스**: `FileSystemItemRow`에서 `.draggable()` 수정자로 구현
- **드롭 타겟**: 폴더에만 `.dropDestination()` 수정자로 구현
- **저장 확인**: 저장되지 않은 파일 이동 시 `SaveConfirmationResult` 열거형으로 처리

### 새 파일 생성 디렉토리 우선순위

`targetDirectoryForNewFile` 계산 프로퍼티로 새 파일 생성 시 대상 디렉토리 결정:

1. 선택된 파일의 부모 디렉토리
2. 선택된 폴더
3. 프로젝트 루트 디렉토리

```swift
var targetDirectoryForNewFile: FileSystemItem? {
    guard let selected = selectedItem else { return projectRoot }
    if selected.isDirectory { return selected }
    return findParent(of: selected) ?? projectRoot
}
```

- `selectedItem`: 사이드바에서 현재 선택된 항목 (파일 또는 폴더)
- 탭바 + 버튼, 새 파일 메뉴 등에서 사용
