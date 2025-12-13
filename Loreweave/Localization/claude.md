# 로컬라이제이션 지침

## 사용법
- `L10n.sidebar.worldbuilding` - accessor 사용
- `L10n.get("custom.key")` - 동적 키
- 하드코딩 금지

## 번역 동기화

`로컬라이제이션 수행` 또는 `번역 동기화` 지시가 있을 때:
1. ko.json을 기준으로 다른 언어 파일(en.json, ja.json)과 비교
2. 누락된 키가 있으면 해당 언어 파일에 추가
3. 적절한 번역 제공

## 파일 구조

```
Localization/
├── L10n.swift         # 로컬라이제이션 accessor
└── Strings/
    ├── ko.json        # 한국어 (기준 언어)
    ├── en.json        # 영어
    └── ja.json        # 일본어
```

## 키 네이밍 규칙

- `app.*` - 앱 정보
- `sidebar.*` - 사이드바 메뉴
- `editor.*` - 에디터 관련
- `ai.*` - AI 어시스턴트 관련
- `common.*` - 공통 UI
- `settings.*` - 설정 관련
- `permission.*` - 권한 관련

## 주의사항

- **개발 중에는 ko.json만 수정** (다른 언어 파일은 `번역 동기화` 지시 시에만 수정)
