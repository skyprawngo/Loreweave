# Loreweave 코딩 규칙

## 코드 설계 원칙

### 객체 재사용
- 리스트/컬렉션 업데이트 시 **기존 객체를 재사용**하고 새 항목만 생성
- 매번 전체 객체를 새로 생성하면 SwiftUI 상태 불안정 및 성능 저하 발생
- 예: `Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })`로 기존 항목 조회 후 재사용

### 동기/비동기 처리 기준
- **동기 실행 (메인 스레드)**: 사용자가 명시적으로 트리거하는 단일 작업 (예: 폴더 클릭 시 하위 항목 로드)
- **비동기 실행 (백그라운드 스레드)**: 자동 실행되는 작업, 대량 데이터 처리, 네트워크 요청
- UI 업데이트는 반드시 **메인 스레드**에서 수행

### SwiftUI 최적화
- 뷰를 작은 컴포넌트로 분리하여 불필요한 재렌더링 방지
- 조건부 렌더링(`if isExpanded`)으로 lazy 로딩 구현
- `@State`, `@Bindable` 등 적절한 프로퍼티 래퍼 선택

## 다국어 지원

**모든 UI 텍스트는 `L10n`을 통해 표시** (상세: `Loreweave/Localization/claude.md`)

## 파일 시스템

**프로젝트 탐색기**: `FileSystemManager`가 파일/폴더 CRUD 및 변경 감시 담당 (상세: `Loreweave/Services/FileSystem/claude.md`)

## 파일 구조

**Views**: 윈도우 뷰는 루트에, 하위 뷰는 `{ViewName에서 View 제외}/` 폴더에 배치 (상세: `Loreweave/Views/claude.md`)

```
Loreweave/
├── Localization/          # 다국어 (claude.md 참조)
├── Models/
│   ├── Project.swift
│   └── FileSystemItem.swift
├── Theme/                 # 테마/색상 시스템 (claude.md 참조)
│   └── AppColors.swift
├── Views/
└── Services/              # 도메인별 분류 (claude.md 참조)
    ├── Core/              # 앱 전역 (권한, 설정)
    ├── Editor/            # 에디터 탭 관리
    ├── FileSystem/        # 파일 시스템
    └── Project/           # 프로젝트 관리
```

## 테마 시스템

**앱 전역 색상은 `AppColors`를 통해 중앙 관리** (상세: `Loreweave/Theme/claude.md`)

- 하드코딩 색상 대신 `AppColors.tabText`, `AppColors.toolbarIcon` 등 사용
- 테마 변경 시 한 곳에서 수정 가능

### 색상 하드코딩 금지

**RGB 값 직접 사용 금지** - 반드시 `NSColor` 시스템 색상 또는 `AppColors` 사용

```swift
// 금지
Color(red: 0.5, green: 0.5, blue: 0.5)
.foregroundStyle(.secondary)

// 권장
AppColors.toolbarIcon
Color(nsColor: .secondaryLabelColor)
```

**이유**: 하드코딩 RGB는 윈도우 활성/비활성, 다크/라이트 모드 변경에 반응하지 않음

## 권한 시스템

**앱에서 필요한 권한은 `PermissionManager`를 통해 중앙 관리** (상세: `Loreweave/Services/Core/claude.md`)

## 에디터 탭 시스템

**에디터 탭 관리는 `EditorTabManager`를 통해 중앙 관리** (상세: `Loreweave/Services/Editor/claude.md`)

### 탭 열기 흐름
1. 사이드바(`ProjectExplorerView`)에서 파일 클릭
2. `EditorTabManager.openFile()` 호출
3. `TabBarView`에 탭 표시 (이미 열린 파일이면 해당 탭 선택)
4. `EditorView`에서 선택된 탭의 파일 내용 로드 및 표시

### 주요 컴포넌트
- `EditorTabManager`: 탭 상태 관리 (싱글톤)
- `EditorTab`: 열린 파일 탭 모델 (`FileSystemItem` 참조)
- `TabBarView`: 탭바 UI
- `EditorView`: 파일 내용 편집기

## 앱 시작 동작

**설정에서 앱 시작 시 동작 선택 가능** (상세: `Loreweave/Services/Core/claude.md`)

- `showWelcome`: 시작 화면 표시 (기본값)
- `openLastProject`: 마지막 프로젝트 자동 열기
- 마지막 프로젝트는 `ProjectManager.openProject()` 호출 시 `UserSettings`에 자동 저장

## 복잡한 작업 지시 시 루프백 체계

복잡하거나 모호한 작업을 지시할 때, Claude가 먼저 상황을 정리하고 질문하여 사용자와 확인하는 루프백 방식을 사용합니다.

### 루프백 프로세스

1. **상황 정리**: Claude가 지시 내용을 분석하고 이해한 바를 요약
2. **질문 제시**: 불명확한 부분이나 확인이 필요한 사항을 질문
3. **사용자 답변**: 질문에 답변하여 보완
4. **작업 진행**: 충분히 명확해지면 구현 시작

### 루프백 응답 형식

```markdown
## 문제 상황 이해

[현재 상황과 문제점 설명]

## 해결해야 할 것

[구현해야 할 내용 정리]

## 확인하고 싶은 점

1. [질문 1]
2. [질문 2]
...

이렇게 이해한 것이 맞나요?
```

### 루프백이 필요한 경우

- 여러 해석이 가능한 지시
- 기존 코드 구조에 영향을 주는 변경
- 사용자 경험(UX)에 대한 결정이 필요한 경우
- 성능 vs 기능 트레이드오프가 있는 경우
- **버그/문제 수정 요청 시 증상이 명확하지 않은 경우**
  - 구체적인 증상 (예: "깜빡임", "느림", "안됨" 등)
  - 재현 조건 (어떤 동작을 할 때 발생하는지)
  - 예상 동작 vs 실제 동작

### 중요: 모호한 요청은 반드시 질문할 것

**추측하여 구현하지 말고, 불명확한 점이 있으면 먼저 질문**

```markdown
// 나쁜 예: 추측하여 바로 구현
"애니메이션이 이상하다" → 임의로 코드 수정

// 좋은 예: 먼저 질문
"애니메이션이 이상하다" →
  - 어떤 증상인가요? (깜빡임/끊김/방향 이상 등)
  - 어떤 동작을 할 때 발생하나요?
```

