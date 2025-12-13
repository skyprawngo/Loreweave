# Loreweave 코딩 규칙

## 빌드 요구사항

- **최소 배포 타겟**: macOS 26.0 (Tahoe) - Liquid Glass UI 사용

## 코드 설계 원칙

### 객체 재사용
리스트/컬렉션 업데이트 시 기존 객체를 재사용하고 새 항목만 생성. 매번 전체 객체를 새로 생성하면 SwiftUI 상태 불안정 및 성능 저하 발생.

### 동기/비동기 처리 기준
- **동기 (메인 스레드)**: 사용자가 명시적으로 트리거하는 단일 작업
- **비동기 (백그라운드)**: 자동 실행 작업, 대량 데이터 처리, 네트워크 요청
- UI 업데이트는 반드시 메인 스레드에서 수행

### SwiftUI 최적화
- 뷰를 작은 컴포넌트로 분리하여 불필요한 재렌더링 방지
- 조건부 렌더링(`if isExpanded`)으로 lazy 로딩 구현

## 에디터 텍스트뷰

**커스텀 LoreEditor** - Core Text 기반 행별 렌더링 (VSCode Monaco 스타일)

- 뷰: `Views/MainEditor/EditorPanel/LoreTextView/`
- 엔진: `Services/Editor/TextEngine/` (상세: `TextEngine/claude.md`)

## 파일 구조

```
Loreweave/
├── Localization/          # 다국어 (claude.md 참조)
├── Models/
├── Theme/                 # 테마/색상 (claude.md 참조)
├── Views/                 # 뷰 (claude.md 참조)
└── Services/              # 서비스 (claude.md 참조)
    ├── Core/              # 앱 전역 (권한, 설정)
    ├── Editor/            # 에디터 탭/텍스트엔진
    ├── FileSystem/        # 파일 시스템
    └── Project/           # 프로젝트 관리
```

## 테마 시스템

**`AppColors`를 통해 중앙 관리** (상세: `Theme/claude.md`)

**금지**: RGB 하드코딩 → **권장**: `AppColors.*` 또는 `NSColor` 시스템 색상

## 단축키 시스템

**`KeyboardShortcutManager`를 통해 중앙 관리**

새 단축키 추가 시:
1. `ShortcutAction` enum에 케이스 추가
2. `category` 프로퍼티에 분류 추가
3. `defaultBindings`에 기본 키 설정
4. 다국어 키 추가 (`shortcut.category.newAction`)
5. `AppCommands`에서 액션 연결 (메뉴 커맨드인 경우)

**금지**: 뷰에서 `.keyboardShortcut()` 하드코딩

## 루프백 체계

복잡하거나 모호한 작업 지시 시 먼저 상황 정리 후 질문:

1. **상황 정리**: 지시 내용 분석 및 요약
2. **질문 제시**: 불명확한 부분 확인
3. **작업 진행**: 충분히 명확해지면 구현 시작

### 루프백이 필요한 경우
- 여러 해석이 가능한 지시
- 기존 코드 구조에 영향을 주는 변경
- UX 결정이 필요한 경우
- 버그 수정 시 증상이 명확하지 않은 경우

**중요**: 추측하여 구현하지 말고, 불명확한 점은 먼저 질문
