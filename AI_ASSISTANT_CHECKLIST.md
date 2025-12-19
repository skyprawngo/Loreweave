# AI 어시스턴트 기능 체크리스트

AI CLI 연결 및 채팅 기능 구현 완료 현황

## 구현 완료 항목

### 1. 설정 및 상태 관리
- [x] `UserSettings`에 AI 어시스턴트 활성화 설정 추가
  - `aiAssistantEnabled`: Bool - 활성화 여부
  - `aiAssistantCLIType`: String - 선택된 CLI 타입
- [x] `AIConnectionState` enum - 연결 상태 관리
  - `inactive` → `selectingAI` → `checkingCLI` → `cliNotInstalled`/`ready` → `connected`

### 2. 데이터 모델 (Services/AI/Models/)
- [x] `AICLIType.swift` - AI CLI 타입 정의
  - Claude, ChatGPT 지원
  - CLI 명령어, 설치 경로, 설치 스크립트 정보 포함
- [x] `AIMessage.swift` - 채팅 메시지 모델
  - 역할(user/assistant/system), 내용, 타임스탬프, 스트리밍 상태
- [x] `AIConnectionState.swift` - 연결 상태 enum
  - 연결 흐름별 상태 정의

### 3. CLI 서비스 (Services/AI/CLI/)
- [x] `CLIDetector.swift` - CLI 설치 감지
  - `which` 명령어로 PATH 검색
  - 일반적인 설치 경로 직접 확인
  - npm/Node.js 설치 여부 확인
- [x] `CLIInstaller.swift` - CLI 설치 지원
  - npm을 통한 자동 설치 (Claude)
  - 설치 페이지 열기 (수동 설치)
  - 설치 진행 상황 스트리밍
- [x] `CLIProcessManager.swift` - CLI 프로세스 관리
  - 프롬프트 전송 및 스트리밍 응답 수신
  - 세션 시작/종료

### 4. 채팅 서비스 (Services/AI/Chat/)
- [x] `ChatHistoryManager.swift` - 채팅 히스토리 관리
  - 프로젝트별 히스토리 저장 (`.{name}.weavedata/ai-chat-history.json`)
  - 세션 저장/로드/삭제
  - 메시지 추가/업데이트

### 5. UI 컴포넌트 (Views/MainEditor/AIAssistant/)

#### 비활성화 상태 (Inactive/)
- [x] `AIInactiveView.swift` - 초기 비활성화 상태
  - "AI 연결하기" 버튼

#### 설정 단계 (Setup/)
- [x] `AISetupView.swift` - AI 선택 드롭다운
  - Claude/ChatGPT 선택
  - 확인/취소 버튼
- [x] `CLIInstallGuideView.swift` - CLI 설치 안내
  - 설치 상태별 UI
  - 자동 설치 / 수동 설치 페이지 열기 / 재확인 버튼

#### 채팅 UI (Chat/)
- [x] `AIChatView.swift` - 채팅 메인 뷰
  - 헤더 (AI 이름, 메뉴)
  - 메시지 목록
  - 입력 영역
- [x] `ChatMessageView.swift` - 개별 메시지 뷰
  - 역할별 아이콘/색상
  - 스트리밍 상태 표시
- [x] `ChatInputView.swift` - 입력 영역
  - 텍스트 입력 필드
  - 전송/취소 버튼

#### 메인 컨테이너
- [x] `AIAssistantContainerView.swift` - 상태별 뷰 분기
  - `AIAssistantViewModel` - 상태 관리 및 비즈니스 로직

### 6. 다국어 지원
- [x] 한국어 (ko.json)
- [x] 영어 (en.json)
- [x] 일본어 (ja.json)

### 7. 문서화
- [x] `Services/AI/claude.md` - AI 서비스 문서

---

## 파일 구조

```
Services/AI/
├── claude.md
├── Models/
│   ├── AICLIType.swift
│   ├── AIMessage.swift
│   └── AIConnectionState.swift
├── CLI/
│   ├── CLIDetector.swift
│   ├── CLIInstaller.swift
│   └── CLIProcessManager.swift
└── Chat/
    └── ChatHistoryManager.swift

Views/MainEditor/AIAssistant/
├── AIAssistantContainerView.swift
├── Inactive/
│   └── AIInactiveView.swift
├── Setup/
│   ├── AISetupView.swift
│   └── CLIInstallGuideView.swift
└── Chat/
    ├── AIChatView.swift
    ├── ChatMessageView.swift
    └── ChatInputView.swift
```

---

## 디버깅 가이드

### 1. AI 연결 문제
- `CLIDetector.checkInstallation(for:)` 결과 확인
- CLI가 설치된 경로가 PATH에 포함되어 있는지 확인
- 터미널에서 `which claude` 또는 `which chatgpt` 실행하여 경로 확인

### 2. 메시지 전송 문제
- `CLIProcessManager.sendPrompt` 에러 로그 확인
- CLI가 올바르게 인증되어 있는지 확인 (Claude의 경우 `claude login`)

### 3. 히스토리 저장 문제
- 프로젝트 숨김 폴더 존재 여부 확인: `.{프로젝트명}.weavedata/`
- `ai-chat-history.json` 파일 권한 확인

### 4. UI 상태 문제
- `AIAssistantViewModel.connectionState` 값 확인
- `UserSettings.aiAssistantEnabled`, `aiAssistantCLIType` 값 확인

---

## 향후 확장 가능 기능

- [ ] 파일 참조 기능 (@file)
- [ ] 선택된 텍스트 컨텍스트 전달
- [ ] 코드 블록 렌더링 (마크다운)
- [ ] 대화 내보내기/가져오기
- [ ] 다중 세션 지원
- [ ] 커스텀 시스템 프롬프트
- [ ] 토큰 사용량 표시
