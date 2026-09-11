# OpenAI 구독 연결과 실제 앱 검증

2026-09-12. 이전 [구현 보고서](IMPLEMENTATION_2026-09-12.md)에 남긴 확인을 빌드한 macOS 앱과 합성 원고로 진행했다. 이번 작업 시작 기준 Git HEAD는 `17dccfa`였으며, 이 작업에서는 커밋·배포하지 않았다.

## OpenAI 구독 연결 결과

**브라우저 OAuth 로그인 → 앱 계정 표시 → 앱 종료·재실행 후 로그인 복원 → 실제 구독 AI 응답 → 사용량 조회까지 확인했다.**

LoreWeave의 ChatGPT 선택 화면에 ‘ChatGPT로 로그인’을 추가했다. 버튼은 공식 Codex App Server의 `account/login/start`를 호출하고 OpenAI 인증 URL을 기본 브라우저에 연다. 로그인 완료 이벤트의 ID를 현재 로그인 요청과 비교하고 계정 정보를 다시 조회한 후 채팅을 활성화한다. 계정 팝오버에서 사용량 조회와 앱 계정 로그아웃을 제공한다.

OAuth 발급·PKCE·callback 처리·토큰 갱신은 공식 Codex 실행 엔진이 담당한다. `cli_auth_credentials_store="keyring"`으로 macOS Keychain 저장을 요구하며, 키체인 실패 시 평문 저장으로 전환하지 않는다. LoreWeave 전용 `Application Support/Loreweave/OpenAI`를 사용하므로 다른 Codex 앱의 인증 파일을 가져오거나 덮어쓰지 않는다. 인증 정보를 프로젝트·UserDefaults·로그에 저장하지 않는다.

AI 호출도 같은 저장소와 키체인 설정을 사용한다. 상속된 OpenAI API 키·Codex 인증 환경변수를 제거하고 ChatGPT 로그인과 OpenAI 제공자를 지정한다. 따라서 API 키 과금으로 조용히 전환하지 않는다. 구독에 따른 모델 접근·한도는 OpenAI 응답을 따르며, 고정된 월 토큰 수나 무제한 사용을 약속하지 않는다.

후속 질문은 앱에 표시된 대화 기록으로 문맥을 구성한다. 과거 전역 Codex 저장소의 세션 ID를 앱 전용 저장소에서 재개하려다 실패하거나, 계정 변경 후 숨은 세션 문맥을 사용하는 문제를 피한다. 이전 대화 본문은 보존한다.

이번 Mac에서 사용한 엔진은 **codex-cli 0.145.0**이다. 현재 앱은 설치된 공식 실행 엔진을 감지해 사용한다. **엔진이 없는 Mac에 바이너리를 번들하거나 자동 설치하는 배포 작업은 포함하지 않았다.** 사용자는 앱에서 로그인하며 터미널에 토큰을 복사할 필요가 없다. OpenCode와 같은 브라우저 구독 로그인 경험을 제공하되, OpenCode의 OAuth client ID나 비공개 HTTP 호출을 복제하지 않고 공식 App Server 인증 계약을 사용했다.

근거: [공식 인증·키체인 저장](https://developers.openai.com/codex/auth), [App Server 로그인·계정·사용량 계약](https://developers.openai.com/codex/app-server), [OpenCode OpenAI 제공자 안내](https://opencode.ai/docs/providers/#openai).

## 실제 앱에서 확인한 것

검증 프로젝트: `/Users/skyprawngo/Documents/LoreWeave-QA-20260912.weaveproj`. 실제 사용자 원고 대신 별도 합성 원고를 사용했다.

| 시나리오 | 관찰 결과 |
|---|---|
| 시작·프로젝트 생성·파일 생성 | 빌드한 앱에서 생성하고 편집 화면 진입 |
| 한글·이모지·결합 문자 | ‘한글 원고 😀 é’ 등을 붙여넣고 저장. 디스크 문자열이 입력과 동일함을 별도 확인 |
| Undo | 붙여넣은 내용을 Cmd+Z로 되돌리고 상태바 변경 확인 |
| 미저장 탭 닫기 | 저장/저장 안 함/취소 대화상자 표시. 취소 후 원고 유지 |
| 외부 변경 충돌 | 합성 파일의 디스크 내용을 별도로 수정하자 충돌 안내. Cmd+S가 외부 수정본을 덮어쓰지 않음 |
| 종료 중 저장 실패 | 충돌 상태에서 종료 → 저장 선택 → 오류 표시. 앱이 종료되지 않고 초안 유지 |
| 다른 이름 저장 | 외부 파일은 `EXTERNAL-REVISION` 유지, 별도 파일에는 `LOCAL-DRAFT` 보존. 양쪽 디스크 내용을 확인 |
| 1천·1만·10만 행 | 한글·이모지 합성 파일을 실제 앱에서 각각 열고 글자/행 수 표시 확인 |
| 10만 행 하단 | 약 280만 글자 원고에서 Cmd+↓로 100001행 끝까지 이동, 하단 렌더링·입력·저장 확인 |
| OAuth 로그인 | 앱 버튼에서 웹 로그인 페이지 열림, 완료 후 계정/플랜 표시 |
| OAuth 재사용 | 앱을 정상 종료·재실행해 추가 로그인 없이 계정 복원 |
| 실제 AI 응답 | 앱 입력창에서 최소 테스트 요청 전송, ‘LoreWeave 연결 성공’ 답변 표시 |
| 대화 이어하기 | 최종 빌드 재실행 후 이전 카드를 열어 직전 답변 반복 요청. 앱 대화 문맥을 통해 같은 답변 수신 |
| 현재 파일 검색 | Cmd+F로 LOCAL-DRAFT 검색, 실제 3행 일치 문자열 선택 확인 |
| 구독 사용량 | 계정 팝오버에서 실제 남은 한도 응답 표시. 인증 정보와 이메일은 이 보고서에 기록하지 않음 |

대용량 파일을 열고 조작할 수 있다는 관찰이며, FPS·키 입력 p95·최대 메모리의 정밀 성능 측정은 아니다. 끝 이동은 macOS의 Cmd+↓로 검증했다.

## 실행 중 발견해 추가 수정한 결함

1. **네이티브 붙여넣기 메뉴가 커스텀 편집기에 연결되지 않음.** 키 이벤트 처리만 있었으므로 `paste:`, `copy:`, `cut:`, `selectAll:` responder 동작을 연결했다. 수정 빌드에서 붙여넣기·저장 성공을 확인했다.
2. **빈 AI 입력창의 클릭이 원고 포커스를 유지함.** NSTextView의 초기 프레임과 최소 높이·너비 추적을 설정하고 안내 레이블이 클릭을 가로채지 않게 했다. 수정 후 실제 AI 입력과 전송 성공을 확인했다.
3. **다른 이름 저장 성공 후 이전 충돌 오류 표시가 남음.** 성공한 대상 URL의 저장 오류를 해제하도록 수정했다.

## 자동 검증과 증거 한계

- 저장 회귀 21개, 텍스트 엔진 41개, 문서 binding 16개, AI 회귀 24개 통과.
- OAuth 회귀 17개 통과: 공식 도메인 검증, API 키 계정 거부, 저장소·환경 격리, 키체인 강제, RPC 성공/실패·대기 요청 종료.
- AI 입력 회귀 7개 통과: 빈 입력창 크기, 너비·줄바꿈, 안내 레이블 클릭, Unicode·선택 교체·first responder.
- 기존 단축키 회귀 28개 결과는 해당 코드 변경이 없어 재사용한다. 합계 154개 검사 항목이며 전부 실제 UI 테스트를 뜻하지 않는다.
- 설치된 실제 Codex 실행 엔진에서도 임시 저장소의 `initialize`·`initialized`·`account/read` 계약을 별도 확인했다.
- 한/영/일 번역 각각 396개 키 일치, 정적 번역 참조 누락 없음. `git diff --check` 통과.
- 앱 인증 저장소에 평문 `auth.json`이 생성되지 않았음을 파일 존재 여부만으로 확인했다. 토큰 값은 열람하지 않았다.
- Debug generic macOS unsigned 빌드 성공. AppIntents 미사용 메타데이터 경고는 유지된다.

남은 확인: 실제 한국어/일본어 IME로 **조합 중** 탭 전환·Undo, VoiceOver 접근성, 외부 볼륨 연결 해제, OAuth 토큰 실제 만료·강제 취소 후 갱신, 다른 Mac에서 키체인·엔진 설치와 배포 서명 검증. 한글 붙여넣기 성공을 IME 조합 검증으로 계산하지 않는다. 토큰 만료는 공식 런타임이 관리하지만 이번 세션에서 실제 만료 시점을 기다리거나 유효한 계정을 강제로 손상시키지는 않았다.

## 코드 진입점

- `Services/AI/Auth/ChatGPTAccountService.swift`: 계정 상태·로그인 수명·JSONL RPC·전용 실행 환경.
- `Setup/ChatGPTAccountView.swift`: 로그인·계정·사용량 UI.
- `AIAssistantViewModel.swift`, `AIAssistantContainerView.swift`: 인증 확인 후 채팅 활성화와 대화 문맥.
- `CLIProcessManager.swift`: 인증 저장소를 AI 실행에도 적용.
- `tests/oauth/run.py`, `tests/ai_input_regression.py`: 새 회귀 검증.
