# AI 연결과 대화 기록

## 호출 경로

`Views/MainEditor/AIAssistant/AIAssistantViewModel.swift`가 연결 상태, 프로젝트 문맥, 전송·취소를 조율한다. `AIAssistantContainerView`는 상태에 맞는 화면을 선택하고, `Chat/AIChatView.swift`는 카드와 입력 UI를 포함한다.

- `Models/AICLIType.swift`: Claude와 Codex 실행 파일 및 설치 정보. 기존 저장값 호환을 위해 Codex의 enum raw value는 `chatgpt`를 유지한다. 이 선언은 외부 CLI 호환성이 검증되었다는 뜻이 아니다.
- `CLI/CLIDetector.swift`, `CLIInstaller.swift`: 설치 감지·수동 경로·설치 안내.
- `CLI/CLIProcessManager.swift`: Claude stream-json / Codex exec JSONL의 명시적 완료 이벤트와 종료 코드를 처리한다. 각 ViewModel은 자체 실행기를 가지며, 요청별 POSIX 프로세스 그룹을 취소한다. 지속 터미널 모드는 지원하지 않는다.
- `Prompt/AIPromptTemplateManager.swift`와 `Resources/AIPromptTemplates.json`: 문맥 조립만 담당한다. CLI 인자와 출력 계약은 CLIProcessManager에 둔다.

## 저장 형식

`Chat/ChatHistoryManager.swift`가 `.{프로젝트명}.weavedata/ai-sessions/`에 `session-metadata.json`과 `cards/{UUID}.json`을 저장한다. 구형 `ai-chat-history.json`은 `loadLegacySession` 호환 경로다. 저장 형식 변경 시 카드 ID, 태그, CLI 세션 ID와 구형 로드를 함께 확인한다.

AI 프롬프트에 포함할 원고/선택/카드의 범위는 ViewModel에서 추적한다. UI 문구나 프롬프트 지시문만으로 외부 프로세스의 파일 접근 권한이 제한되는 것은 아니다. 연결 감지, 인증, 응답 성공, 기록 저장은 각각 다른 검증 단계다.

기존 구현 기록과 미검증 시나리오는 루트 [AI_ASSISTANT_CHECKLIST.md](../../../AI_ASSISTANT_CHECKLIST.md)를 참고한다.

## 실행과 검증 경계

전송 시 프로젝트 URL, request ID, conversation ID를 고정한다. 프로젝트 전환과 취소는 콜백을 먼저 무효화한다. 원고 첨부는 선택 사항이며 전송 직전 에디터를 flush한 캐시 내용으로 만든다. 외부 CLI의 인증은 CLI가 소유한다. Claude는 safe-mode와 빈 tools, Codex는 read-only sandbox와 사용자 config/rules 제외를 요청한다. 옵션을 지원하지 않는 버전은 명시적 호환성 오류로 처리한다.

`tests/ai/run.sh`는 실제 서비스 대신 임시 fixture 실행 파일로 UTF-8/JSONL, 종료·인증 오류, 프로세스 그룹 취소, 프로젝트 귀속 및 대화 저장을 검증한다. 실제 CLI 로그인·서비스 응답·권한 적용은 별도 검증이다. 외부 CLI 계약 기준은 [Claude headless](https://code.claude.com/docs/en/headless), [Claude flags](https://code.claude.com/docs/en/cli-reference), [Codex non-interactive](https://developers.openai.com/codex/noninteractive/), [Codex CLI reference](https://developers.openai.com/codex/cli/reference/)다.
