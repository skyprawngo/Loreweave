# FileSystem Services

## 파일 목록

| 파일 | 역할 |
|------|------|
| `FileSystemManager.swift` | 파일/폴더 CRUD 및 변경 감시 |

## FileSystemManager

프로젝트 탐색기의 파일/폴더 작업을 담당합니다.

### 주요 기능
- **디렉토리 로드**: `loadChildren(of:)` - 동기적으로 하위 항목 로드
- **펼침/접기**: `toggleExpand(_:)` - 폴더 확장 상태 토글
- **CRUD**: createFolder, createFile, rename, delete, move, copy
- **파일 감시**: `startWatching(at:)` - DispatchSource로 변경 감지
- **드래그 앤 드롭**: `move(_:to:)` - 항목 이동

### 설계 원칙
- **동기적 실행**: 파일 I/O는 메인 스레드에서 동기적으로 실행
- **객체 재사용**: 기존 `FileSystemItem` 객체를 재사용하여 SwiftUI 상태 안정성 유지
- **Lazy Loading**: 폴더 클릭 시 해당 폴더의 직접 자식만 로드

### 새 파일 생성 디렉토리 우선순위
1. 선택된 파일의 부모 디렉토리
2. 선택된 폴더
3. 프로젝트 루트 디렉토리
