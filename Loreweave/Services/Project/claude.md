# Project Services

프로젝트 관리 관련 서비스들입니다.

## 파일 목록

| 파일 | 역할 |
|------|------|
| `ProjectManager.swift` | 프로젝트 생성/열기/저장 관리 |

---

## ProjectManager

`.weaveproj` 프로젝트의 생성, 열기, 저장을 담당합니다.

### 프로젝트 구조

```
MyProject.weaveproj/
├── .MyProject.weavedata/   # 숨김 데이터 폴더 (설정 저장용)
│   └── project.json        # 프로젝트 메타데이터
├── 세계관/                 # 섹션 폴더 (언어별 현지화)
├── 캐릭터/
├── 플롯/
├── 콘티/
├── 에디터/
└── 아이디어/
```

### 숨김 데이터 폴더

- 프로젝트명 기반 숨김 폴더: `.{프로젝트명}.weavedata`
- `dataFolderURL(for:)` - 숨김 폴더 경로 생성
- `metadataURL(for:)` - 메타데이터 파일 경로 생성

### 섹션 폴더

| 섹션 | 한국어 | English | 日本語 |
|------|--------|---------|--------|
| Worldbuilding | 세계관 | Worldbuilding | 世界観 |
| Characters | 캐릭터 | Characters | キャラクター |
| Plot | 플롯 | Plot | プロット |
| Storyboard | 콘티 | Storyboard | コンテ |
| Editor | 에디터 | Editor | エディター |
| Ideas | 아이디어 | Ideas | アイデア |

- 프로젝트 생성 시 현재 언어에 맞는 폴더명으로 자동 생성
- 폴더명은 `folder.*` 로컬라이제이션 키로 관리
- `ProjectSection.from(folderName:)`으로 모든 언어의 폴더명 인식

### 주요 기능

- **생성**: `createProject(name:at:)` - 새 프로젝트 및 숨김 데이터 폴더 생성
- **열기**: `openProjectFromFile(at:)` - 기존 프로젝트 열기
- **최근 프로젝트 열기**: `openProject(_:)` - 최근 프로젝트 목록에서 열기
- **닫기**: `closeProject()` - 프로젝트 닫기 및 리소스 정리
- **검증**: `validateRecentProjects()` - 존재하지 않는 프로젝트 자동 제거

### 사용 예시

```swift
// 프로젝트 생성
let project = ProjectManager.shared.createProject(name: "소설", at: documentsURL)

// 프로젝트 열기 (파일에서)
ProjectManager.shared.openProjectFromFile(at: projectURL)

// 최근 프로젝트 열기
ProjectManager.shared.openProject(project)

// 현재 프로젝트 접근
if let project = ProjectManager.shared.currentProject {
    print(project.name)
}
```

### Security-Scoped Bookmark

- 프로젝트 폴더 접근 권한은 Security-Scoped Bookmark으로 유지
- 앱 재시작 후에도 접근 권한 유지
- `PermissionManager`와 연동하여 권한 관리
- 삭제된 프로젝트의 북마크는 `removeBookmarks(for:)`로 자동 정리
