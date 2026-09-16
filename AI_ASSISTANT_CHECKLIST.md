# AI 어시스턴트 검토 맥락

2026-09-11 현재 작업 트리를 기준으로 기존 구현 체크리스트를 정리했다. 아래는 소스에 있는 연결점과 검증할 시나리오이며, CLI 설치·인증이나 실제 채팅 성공을 인증하는 완료표가 아니다.

## 현재 구현 경로

- 연결 설정과 전송 상태: `Views/MainEditor/AIAssistant/AIAssistantViewModel.swift`.
- 카드·입력 화면: `Views/MainEditor/AIAssistant/Chat/AIChatView.swift`. 이전 별도 `ChatInputView.swift`, `ChatMessageView.swift` 목록은 현재 구조와 맞지 않는다.
- CLI 감지·설치·프로세스: `Services/AI/CLI/`.
- 문맥과 제공자 옵션: `Services/AI/Prompt/AIPromptTemplateManager.swift`, `Resources/AIPromptTemplates.json`.
- 대화 저장: `Services/AI/Chat/ChatHistoryManager.swift`의 `ai-sessions/session-metadata.json`, `cards/{UUID}.json`. 구형 단일 기록 파일 읽기도 남아 있다.

위 경로는 `TextlinkEditor/` 기준이다. 저장·호출 경계는 [AI 서비스 맥락](TextlinkEditor/Services/AI/claude.md)에 있다.

## 실제 동작 확인이 필요한 항목

- 제공자별 실행 파일 감지, 수동 경로 선택, 인증 실패와 설치 실패 안내.
- 단발/터미널 모드의 첫 응답, 후속 대화, 선택지, 중단과 프로세스 종료.
- 전송 중 프로젝트·제공자 변경 시 이전 출력과 세션이 새 대화에 섞이지 않는지.
- 저장된 카드·태그·세션 ID 복원, 구형 기록 읽기와 손상/쓰기 실패 처리.
- 포함된 원고·선택 줄·태그 카드가 사용자가 의도한 문맥과 일치하는지.
- 한국어·영어·일본어 UI 및 IME 입력·Undo·Redo.

검증 결과를 추가할 때 사용한 CLI/앱 버전, 실행 시나리오와 실제 결과를 남긴다. 새 기능 제안과 수정 우선순위는 앱 검토보고서에서 토의한다.
