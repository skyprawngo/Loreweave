# Services 디렉토리 규칙

서비스는 **도메인별**로 분류됩니다.

## 디렉토리 구조

```
Services/
├── claude.md           # 이 파일 (전체 구조 안내)
├── Core/               # 앱 전역 핵심 서비스
│   ├── claude.md
│   ├── PermissionManager.swift
│   └── UserSettings.swift
├── FileSystem/         # 파일 시스템 관련
│   ├── claude.md
│   └── FileSystemManager.swift
└── Project/            # 프로젝트 관리 관련
    ├── claude.md
    └── ProjectManager.swift
```

## 도메인 분류 기준

| 도메인 | 설명 | 예시 |
|--------|------|------|
| **Core** | 앱 전역에서 사용되는 핵심 서비스 | 권한, 설정 |
| **FileSystem** | 파일/폴더 작업 관련 | CRUD, 감시 |
| **Project** | .weaveproj 프로젝트 관리 | 생성, 열기, 저장 |

## 새 서비스 추가 시

1. **기존 도메인에 속하는 경우**: 해당 도메인 폴더에 추가
2. **새 도메인이 필요한 경우**: 폴더 생성 후 `claude.md` 작성
3. **여러 도메인에서 사용**: `Core/`에 배치

## 상세 문서

각 도메인의 상세 규칙은 해당 폴더의 `claude.md` 참조:

- [Core/claude.md](Core/claude.md) - 권한, 설정
- [FileSystem/claude.md](FileSystem/claude.md) - 파일 시스템
- [Project/claude.md](Project/claude.md) - 프로젝트 관리
