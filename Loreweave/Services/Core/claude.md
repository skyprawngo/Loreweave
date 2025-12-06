# Core Services

앱 전역에서 사용되는 핵심 서비스들입니다.

## 파일 목록

| 파일 | 역할 |
|------|------|
| `PermissionManager.swift` | 앱 권한 중앙 관리 (Security-Scoped Bookmark) |
| `UserSettings.swift` | 사용자 설정 및 디렉토리 접근 권한 저장 |
| `KeyboardShortcutManager.swift` | 키보드 단축키 관리 (JSON 파일로 저장) |

---

## 권한 시스템 (PermissionManager)

앱에서 필요한 권한은 `PermissionManager`를 통해 중앙 관리됩니다.

### 새 권한 추가 방법

1. **PermissionType enum에 새 케이스 추가**:
   ```swift
   enum PermissionType: String, CaseIterable, Identifiable {
       case documentsAccess = "documentsAccess"
       case newPermission = "newPermission"  // 새 권한 추가

       var title: String { ... }        // L10n 키 추가
       var description: String { ... }  // L10n 키 추가
       var iconName: String { ... }     // SF Symbol 이름
       var bookmarkKey: String { ... }  // UserDefaults 저장 키
   }
   ```

2. **권한 요청 메서드 구현**:
   ```swift
   func requestPermission(_ permission: PermissionType) -> Bool {
       switch permission {
       case .documentsAccess:
           return requestDocumentsAccess()
       case .newPermission:
           return requestNewPermission()  // 새 메서드 구현
       }
   }
   ```

3. **로컬라이제이션 문자열 추가** (ko.json, en.json, ja.json):
   - `permission.{name}.title`
   - `permission.{name}.description`

### 권한 사용

```swift
// 권한 확인
if PermissionManager.shared.isGranted(.documentsAccess) { ... }

// 승인된 URL 가져오기
if let url = PermissionManager.shared.getBookmarkedURL(for: .documentsAccess) { ... }

// 접근 종료
PermissionManager.shared.stopAccessing(url)
```

---

## 사용자 설정 (UserSettings)

앱 설정과 디렉토리 접근 권한을 저장합니다.

### 주요 설정 항목

- **일반**: 테마(`appTheme`), 언어(`appLanguage`), 앱 시작 동작(`appLaunchBehavior`)
- **자동 저장**: 활성화(`autoSaveEnabled`), 간격(`autoSaveInterval`)
- **AI**: 제공자(`aiProvider`), API 키(`aiApiKey`)
- **에디터**: 폰트 크기/이름, 줄간격, 줄 번호 표시
- **프로젝트**: 기본 저장 위치, 최근 프로젝트 목록, 마지막 열린 프로젝트(`lastOpenedProject`)

### 사용 예시

```swift
// 설정 읽기/쓰기
UserSettings.shared.autoSaveEnabled = true
UserSettings.shared.editorFontSize = 16

// 기본 프로젝트 저장 위치
UserSettings.shared.setDefaultProjectLocation(url)
let location = UserSettings.shared.getDefaultProjectLocation()

// 최근 프로젝트 관리
UserSettings.shared.addRecentProject(projectURL)
let recents = UserSettings.shared.getRecentProjects()

// 마지막 열린 프로젝트 관리
UserSettings.shared.setLastOpenedProject(projectURL)
let lastProject = UserSettings.shared.getLastOpenedProject()
```

### 앱 시작 동작 (AppLaunchBehavior)

앱 시작 시 동작을 설정합니다:
- `.showWelcome`: 시작 화면 표시 (기본값)
- `.openLastProject`: 마지막으로 열린 프로젝트 자동 열기

마지막 프로젝트는 `ProjectManager.openProject()` 호출 시 자동으로 저장됩니다.

---

## 키보드 단축키 (KeyboardShortcutManager)

키보드 단축키를 관리하고 샌드박스 위치에 JSON 파일로 저장합니다.

### 저장 위치

`~/Library/Application Support/Loreweave/shortcuts.json`

### 주요 구성 요소

- **ShortcutAction**: 단축키로 실행할 수 있는 액션 enum
- **ShortcutCategory**: 액션 카테고리 (file, edit, view, tab, ai, project)
- **ModifierKeys**: 수정자 키 (command, shift, option, control)
- **ShortcutBinding**: 액션과 키 조합 바인딩

### 사용 예시

```swift
let manager = KeyboardShortcutManager.shared

// 단축키 바인딩 조회
if let binding = manager.binding(for: .save) {
    print("저장: \(binding.displayString)")  // "⌘S"
}

// 단축키 변경
manager.setKey("s", modifiers: [.command, .shift], for: .saveAs)

// 활성화/비활성화 토글
manager.toggleEnabled(for: .zoomIn)

// 충돌 확인
if let conflict = manager.findConflict(key: "s", modifiers: .command, excluding: .save) {
    print("충돌: \(conflict.action.displayName)")
}

// 기본값으로 초기화
manager.resetToDefaults()
manager.resetToDefault(for: .save)  // 특정 액션만
```

### 새 단축키 액션 추가 방법

1. **ShortcutAction enum에 새 케이스 추가**:
   ```swift
   enum ShortcutAction: String, CaseIterable, Identifiable, Codable {
       case newAction = "category.newAction"

       var category: ShortcutCategory {
           switch self {
           case .newAction: return .file
           }
       }
   }
   ```

2. **defaultBindings에 기본 단축키 추가**:
   ```swift
   private static var defaultBindings: [ShortcutBinding] {
       [
           // ...
           ShortcutBinding(action: .newAction, key: "n", modifiers: [.command, .option], isEnabled: true),
       ]
   }
   ```

3. **로컬라이제이션 키 추가** (ko.json):
   - `shortcut.category.newAction`: 액션 표시 이름

### 연동 뷰

- `ShortcutsSettingsView`: 단축키 설정 테이블 뷰
- `ShortcutEditSheet`: 단축키 편집 시트
