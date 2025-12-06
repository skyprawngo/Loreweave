# 로컬라이제이션 지침

## 사용법

```swift
Text(L10n.sidebar.worldbuilding)  // ✅ accessor 사용
Text(L10n.get("custom.key"))      // ✅ 동적 키
Text("세계관")                     // ❌ 하드코딩 금지
```

## 번역 동기화

`로컬라이제이션 수행` 또는 `번역 동기화` 지시가 있을 때 아래 작업을 수행합니다.

## 작업 절차

1. **ko.json을 기준으로** 다른 언어 파일(en.json, ja.json)과 비교
2. 누락된 키가 있으면 해당 언어 파일에 추가
3. 번역이 필요한 경우 적절한 번역 제공

## 파일 구조

```
Localization/
├── L10n.swift         # 로컬라이제이션 accessor
├── claude.md          # 이 파일 (로컬라이제이션 지침)
└── Strings/
    ├── ko.json        # 한국어 (기준 언어)
    ├── en.json        # 영어
    └── ja.json        # 일본어
```

## JSON 형식

단순 key-value 구조:
```json
{
  "category.key": "번역된 텍스트"
}
```

## 키 네이밍 규칙

- `app.*` - 앱 정보
- `sidebar.*` - 사이드바 메뉴
- `editor.*` - 에디터 관련
- `ai.*` - AI 어시스턴트 관련
- `tabs.*` - 탭 관련
- `common.*` - 공통 UI (취소, 확인, 삭제 등)
- `settings.*` - 설정 관련
- `welcome.*` - 시작 화면 관련
- `permission.*` - 권한 관련

### 권한 키 네이밍 규칙

새 권한 추가 시 다음 키들을 추가해야 합니다:

- `permission.{name}.title` - 권한 제목
- `permission.{name}.description` - 권한 설명
- `permission.{name}.panelTitle` - 패널 제목 (필요 시)
- `permission.{name}.panelMessage` - 패널 메시지 (필요 시)
- `permission.{name}.grant` - 허용 버튼 텍스트 (필요 시)

## 주의사항

- **개발 중에는 ko.json만 수정** (다른 언어 파일은 수정하지 않음)
- 다른 언어 파일(en.json, ja.json)은 `로컬라이제이션 수행` 또는 `번역 동기화` 지시 시에만 일괄 동기화
- L10n.swift의 accessor도 필요시 업데이트
