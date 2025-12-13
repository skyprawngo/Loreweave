# Core Services

앱 전역에서 사용되는 핵심 서비스들입니다.

## 파일 목록

| 파일 | 역할 |
|------|------|
| `PermissionManager.swift` | 앱 권한 중앙 관리 (Security-Scoped Bookmark) |
| `UserSettings.swift` | 사용자 설정 및 디렉토리 접근 권한 저장 |
| `KeyboardShortcutManager.swift` | 키보드 단축키 관리 (JSON 파일로 저장) |

## 권한 시스템 (PermissionManager)

새 권한 추가 시:
1. `PermissionType` enum에 케이스 추가 (title, description, iconName, bookmarkKey)
2. `requestPermission` 메서드에 분기 추가
3. 다국어 키 추가 (`permission.{name}.title`, `permission.{name}.description`)

## 사용자 설정 (UserSettings)

주요 설정 항목:
- **일반**: 테마, 언어, 앱 시작 동작
- **자동 저장**: 활성화, 간격
- **AI**: 제공자, API 키
- **에디터**: 폰트 크기/이름, 줄간격
- **프로젝트**: 기본 저장 위치, 최근/마지막 프로젝트

### 앱 시작 동작 (AppLaunchBehavior)
- `.showWelcome`: 시작 화면 표시 (기본값)
- `.openLastProject`: 마지막 프로젝트 자동 열기

## 키보드 단축키 (KeyboardShortcutManager)

저장 위치: `~/Library/Application Support/Loreweave/shortcuts.json`

새 단축키 추가 시:
1. `ShortcutAction` enum에 케이스 추가
2. `defaultBindings`에 기본 단축키 추가
3. 다국어 키 추가 (`shortcut.category.newAction`)
