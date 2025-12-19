# AI 서비스

AI CLI 연결 및 채팅 기능을 담당하는 서비스 모듈.

## 디렉토리 구조

```
AI/
├── Models/                      # 데이터 모델
│   ├── AICLIType.swift          # AI CLI 타입 enum (Claude, ChatGPT)
│   ├── AIMessage.swift          # 채팅 메시지 및 세션 모델
│   └── AIConnectionState.swift  # 연결 상태 enum
├── CLI/                         # CLI 관련 서비스
│   ├── CLIDetector.swift        # CLI 설치 감지 (which, PATH 검색)
│   ├── CLIInstaller.swift       # CLI 설치 지원 (npm, 수동 안내)
│   └── CLIProcessManager.swift  # CLI 프로세스 실행 및 통신
└── Chat/                        # 채팅 서비스
    └── ChatHistoryManager.swift # 프로젝트별 히스토리 저장/로드
```

## 핵심 모델

### AICLIType
- `claude`: Claude CLI (`@anthropic-ai/claude-code`)
- `chatgpt`: ChatGPT CLI

### AIConnectionState
앱의 AI 연결 상태 흐름:
```
inactive → selectingAI → checkingCLI → cliNotInstalled/ready → connected
```

### AIMessage
- `role`: user, assistant, system
- `content`: 메시지 내용
- `isStreaming`: 스트리밍 응답 중 여부

## 서비스

### CLIDetector
- `checkInstallation(for:)`: CLI 설치 여부 확인
- `getVersion(for:)`: CLI 버전 확인
- `isNpmInstalled()`: npm 설치 여부 (Claude CLI 필수)

### CLIInstaller
- `install(_:progressHandler:)`: CLI 자동 설치
- `openInstallPage(for:)`: 수동 설치 페이지 열기

### CLIProcessManager
- `sendPrompt(_:cliType:workingDirectory:streamHandler:)`: 프롬프트 전송 및 스트리밍 응답

### ChatHistoryManager
- 프로젝트 숨김 폴더(`.{name}.weavedata/ai-chat-history.json`)에 히스토리 저장
- `saveSession(_:to:)` / `loadSession(from:)`

## 확장 시

### 새 AI CLI 추가
1. `AICLIType`에 케이스 추가
2. `commandName`, `installScript`, `possiblePaths` 정의
3. `CLIProcessManager.sendPrompt`에 CLI별 인자 처리 추가

### 새 채팅 기능 추가
1. `AIMessage`에 필요한 필드 추가
2. `ChatHistoryManager`에 관련 메서드 추가
