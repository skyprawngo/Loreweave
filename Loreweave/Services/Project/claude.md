# Project Services

## 파일 목록

| 파일 | 역할 |
|------|------|
| `ProjectManager.swift` | 프로젝트 생성/열기/저장 관리 |

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
- 프로젝트명 기반: `.{프로젝트명}.weavedata`
- `dataFolderURL(for:)` - 숨김 폴더 경로 생성

### 섹션 폴더
프로젝트 생성 시 현재 언어에 맞는 폴더명으로 자동 생성 (`folder.*` 로컬라이제이션 키)

### 주요 기능
- **생성**: `createProject(name:at:)`
- **열기**: `openProjectFromFile(at:)`
- **최근 프로젝트 열기**: `openProject(_:)`
- **닫기**: `closeProject()`
- **검증**: `validateRecentProjects()` - 존재하지 않는 프로젝트 자동 제거
