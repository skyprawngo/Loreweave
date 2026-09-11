# LoreWeave 앱 검토보고서

검토 기준: 2026-09-11 작업 폴더의 현재 소스. 기존 미커밋 변경과 신규 파일을 포함했다.

## 먼저 읽을 결론

LoreWeave는 **로컬 원고 파일을 직접 관리하는 macOS 집필 편집기**라는 기반이 좋다. 프로젝트 폴더, 탭, 커스텀 에디터, AI 대화 카드가 이미 갖춰져 있다. 다만 실제 집필에 맡기기 전에는 **원고 보존과 편집의 신뢰성**을 먼저 보완해야 한다. 새 기능보다 저장·닫기·이동·프로젝트 전환에서 원고가 남는지부터 해결하는 편을 권한다.

현재는 UI가 약속하는 기능과 실제 동작 사이에 차이가 있다. 검색, 서식 버튼, 사용자 단축키, AI API 키 설정 등의 연결이 완성되지 않았다. AI 역시 요청과 프로젝트·카드의 소유권이 분리되어 있지 않아, 응답 도중 프로젝트를 바꾸면 다른 대화에 결과가 저장될 수 있다.

권장 순서는 다음과 같다.

1. **원고 보존**: 닫기/종료/이동/동명 생성/외부 변경 충돌, 복구 초안.
2. **집필 기본기**: 탭별 Undo, 한글·이모지 입력, 실제 저장 상태, 검색·서식·단축키.
3. **AI 신뢰성**: 요청별 소유권, 취소/완료/오류 처리, 대화 흐름과 전송 맥락.
4. **소설 특화 기능**: 수정안 비교·선택 적용, 인물·세계관 참조, 장면 관리.

앱 구현은 이번에 수정하지 않았다. 아래 내용은 토의 후 구현 범위를 고르기 위한 보고서다. AI용 문서는 별도로 실제 정비했다.

## 검토 범위와 증거 수준

프로젝트의 Swift 파일 **67개**를 대상으로 영역을 나누어 정적 검토했다. 앱 진입/종료, 프로젝트·파일 모델, 저장·탭·텍스트 엔진, AppKit 렌더링과 입력, AI 서비스·UI, 설정·명령·권한, 테마·다국어·리소스, Xcode 설정과 AI용 문서를 포함한다. 단순 파일 목록 확인에 그치지 않고 주요 사용자 동작의 호출·저장 경로를 추적했다.

| 검증 | 결과 | 증명하는 범위 |
|---|---|---|
| macOS Debug 빌드, 코드 서명 비활성화 | **성공** | 현재 소스의 컴파일·링크·번들 생성 |
| 빌드 경고 | 서로 다른 위치 **4곳** | CLIProcessManager의 non-Sendable 캡처 2곳, 미사용 변수 2곳 |
| JSON 파싱 | 전체 성공 | 번역·프롬프트·에셋 JSON 문법 |
| 번역 키 비교 | ko 336개, en/ja 각각 331개 | en/ja에 각각 5개 누락 |
| 정적 번역 참조 검사 | 공통 누락 1개 추가 | `shortcut.view.sidebar`가 세 언어 모두 없음 |
| 생성된 앱 번들 검사 | 번역 3개·약관 3개·프롬프트 JSON 포함 | 리소스 패키징; 실제 화면 표시 여부는 별개 |
| Foundation/CoreText 축소 재현 | 덮어쓰기·문자 인덱스 불일치 확인 | 해당 API와 알고리즘 동작, 앱 UI 전체 재현은 아님 |

**실행하지 않은 검증:** 실제 앱에서의 클릭·키 입력, 한국어/일본어 IME, VoiceOver, 장편 원고 성능 측정, CLI 설치·로그인·유료 AI 요청, 실제 사용자 원고에 대한 저장 실험, Release/배포·서명 검증. Xcode 프로젝트에는 현재 테스트 타깃이 없다. 따라서 이 보고서의 “확인”은 별도 명시가 없으면 **소스 경로로 확인한 결함**이며, 사용자 환경에서 재현을 완료했다는 뜻은 아니다.

빌드 명령:

```sh
xcodebuild -project Loreweave.xcodeproj -scheme Loreweave \
  -configuration Debug -destination 'generic/platform=macOS' \
  -derivedDataPath /tmp/loreweave-review-derived \
  CODE_SIGNING_ALLOWED=NO build
```

## 현재 앱의 기능 지도

| 영역 | 현재 상태 | 검토 판단 |
|---|---|---|
| 시작 화면·프로젝트 생성/열기 | 최근 프로젝트, 기본 위치, 마지막 프로젝트 복원 | 기반 있음. 전환과 실패 복구 보완 필요 |
| 프로젝트 구조 | `.weaveproj` 폴더, 숨김 `.weavedata` 메타데이터, 일반 원고 파일 | 파일을 다른 도구에서도 사용할 수 있는 장점 |
| 파일 탐색기 | 생성·이름 변경·삭제·드래그 이동·선택 | 디스크 작업과 열린 편집 상태를 함께 관리해야 함 |
| 편집기 | CoreText 렌더링, 줄바꿈, 글꼴/간격, 커서, 선택, Undo | 구현은 상당하나 문자 단위와 문서별 상태 경계에 결함 |
| 저장 | 수동/주기/탭 변경 저장, 외부 변경 감지, 세션 복원 | 실패·충돌·닫기 정책이 불완전 |
| 검색·탐색·서식 | 화면/메뉴/상태 일부 존재 | 여러 실행 경로 미연결 |
| AI | CLI 탐지·실행, 스트리밍, 카드/태그/기록, 터미널 모드 | 요청 생명주기·프로젝트 귀속·계속 대화 보완 필요 |
| 설정·단축키 | 설정 화면과 JSON 저장 | 저장된 설정과 실제 실행이 일부 분리 |
| 다국어·테마 | 한/영/일, 4종 테마, AppKit/SwiftUI 혼합 | 키 누락, 테마 적용 기준 불일치 |
| 배포·제품 범위 | macOS 26 타깃, 버전 0.1.0, sandbox 비활성화 | 현재 코드에는 iOS 앱·연재 플랫폼·CloudKit 구현이 없음 |

초기 아이디어의 모바일·플랫폼·동기화 구상과 현재 구현을 구분해야 한다. 폴더로 존재하는 인물/세계관/플롯 분류도 구조화된 인물 DB나 일관성 분석 기능이 완성되었다는 의미는 아니다.

## 우선 수정할 결함

P1은 원고/대화 손실 또는 잘못된 문서 변경 가능성이 있어 먼저 해결할 항목이다. P2는 핵심 동작·사용자 신뢰·성능을 저해하는 항목이다. 순위는 발생 빈도를 계측한 결과가 아니라 현재 코드에 근거한 검토 판단이다.

### R01 · P1 · 새 파일 생성이 기존 원고를 덮어쓴다

**조건과 영향:** 같은 폴더에서 기존 파일과 동일한 이름으로 새 파일을 생성하면 기본값인 빈 문자열을 기존 파일에 쓴다. “새 파일” 동작으로 원고가 사라질 수 있다. [FileSystemManager.swift:165](/Users/skyprawngo/Documents/Coding/Loreweave/Loreweave/Services/FileSystem/FileSystemManager.swift:165)의 `createFile`에는 충돌 방지 없이 `write`가 있다. 같은 Foundation 쓰기 방식의 임시 파일 재현에서 원고가 0 bytes로 바뀌었다.

**수정:** 기존 파일을 대체하지 않는 배타적 생성과 이름 충돌 안내를 구현한다. 파일 존재 검사만 하고 다시 일반 쓰기를 하는 방식은 검사와 쓰기 사이 경쟁을 남긴다. **확인:** 동명 파일 생성 시 기존 파일 해시가 유지되고 새 이름 선택/취소가 가능해야 한다.

### R02 · P1 · 탭 닫기와 프로젝트 전환에서 미저장 원고가 사라진다

[EditorTabManager.swift:191](/Users/skyprawngo/Documents/Coding/Loreweave/Loreweave/Services/Editor/EditorTabManager.swift:191)는 저장 확인 TODO를 남긴 채 캐시와 탭을 제거한다. 모두 닫기도 편집 상태를 지운다. 세션 저장은 [같은 파일:487](/Users/skyprawngo/Documents/Coding/Loreweave/Loreweave/Services/Editor/EditorTabManager.swift:487)에서 경로·수정 플래그·커서만 기록하며 원고 초안을 보관하지 않는다.

프로젝트 복원은 [같은 파일:521](/Users/skyprawngo/Documents/Coding/Loreweave/Loreweave/Services/Editor/EditorTabManager.swift:521)에서 세션 파일이 있으면 기존 탭을 모두 닫고, 없으면 이전 탭을 그대로 남긴다. 따라서 “세션 있음”과 “없음” 모두 프로젝트 전환의 일관성이 깨진다.

**수정:** 닫기·모두 닫기·프로젝트 변경을 저장/버리기/취소 공통 흐름으로 연결한다. 전환이 확정된 뒤 새 프로젝트 상태를 적용하고, 실패하면 기존 프로젝트를 유지한다. 복구 초안은 탭 배치와 분리해 저장한다. **확인:** 자동 저장을 끄고 A를 편집한 뒤 닫기, B로 전환, 세션 없는 B 열기, 잘못된 프로젝트 열기를 각각 검사한다.

### R03 · P1 · 종료 시 저장 실패를 무시한다

[LoreweaveApp.swift:276](/Users/skyprawngo/Documents/Coding/Loreweave/Loreweave/LoreweaveApp.swift:276)의 `saveTabAndContinue`는 저장 결과를 버리고 다음 탭으로 진행한다. 저장 대상 디렉터리가 사라지거나 쓰기에 실패해도 종료가 허용된다. 저장 확인 창을 붙일 에디터 창이 없을 때도 종료를 허용한다.

**수정:** 저장 실패 시 종료를 취소하고 미저장 상태를 유지한다. 재시도·다른 위치 저장을 제공하고, 열린 창 유무가 데이터 보존 여부를 결정하지 않게 한다. **확인:** 임시 원고의 상위 폴더를 이동해 저장 실패를 유도했을 때 종료되지 않아야 한다.

### R04 · P1 · 파일 이름 변경/이동과 열린 탭이 분리된다

[FileSystemManager.swift:278](/Users/skyprawngo/Documents/Coding/Loreweave/Loreweave/Services/FileSystem/FileSystemManager.swift:278)의 이름 변경과 [같은 파일:545](/Users/skyprawngo/Documents/Coding/Loreweave/Loreweave/Services/FileSystem/FileSystemManager.swift:545)의 이동은 디스크·트리를 갱신하지만 열린 탭과 URL 기반 편집 캐시를 함께 바꾸지 않는다. 이후 저장은 옛 경로에 파일을 다시 만들거나 실패할 수 있다.

또한 [ProjectExplorerView.swift:444](/Users/skyprawngo/Documents/Coding/Loreweave/Loreweave/Views/MainEditor/Sidebar/ProjectExplorerView.swift:444)의 “저장 후 이동”은 연결되지 않은 `getCurrentEditorContent` 콜백에 의존하며, 저장 결과와 관계없이 이동한다.

**수정:** 해당 URL의 캐시를 저장하고 성공한 경우에만 이동한다. 파일/폴더 하위 탭, 캐시, 세션 경로를 함께 갱신한다. **확인:** 수정된 파일과 그 상위 폴더를 각각 이동/이름 변경한 뒤 저장·다시 열기에서 중복 파일이나 원고 누락이 없어야 한다.

### R05 · P1 · 외부 변경과 로컬 수정이 충돌하면 덮어쓴다

[EditorContainerView.swift:431](/Users/skyprawngo/Documents/Coding/Loreweave/Loreweave/Views/MainEditor/EditorContainerView.swift:431)는 수정 중인 탭의 외부 변경 검사를 건너뛴다. [EditorTabManager.swift:269](/Users/skyprawngo/Documents/Coding/Loreweave/Loreweave/Services/Editor/EditorTabManager.swift:269)의 저장도 디스크 기준값을 비교하지 않는다. AI CLI나 다른 편집기가 파일을 수정한 뒤 수동/자동 저장하면 그 변경을 조용히 덮어쓸 수 있다.

**수정:** 로드/마지막 저장 시점의 버전을 저장 직전에 비교한다. 충돌 시 자동 저장을 멈추고 두 버전 보존, 비교·선택·병합을 제공한다. **확인:** 같은 파일을 앱과 외부에서 동시에 수정했을 때 어느 한쪽도 자동으로 소실되지 않아야 한다.

### R06 · P1 · 문자 인덱스 단위가 섞여 있다

엔진의 열 위치는 Swift `Character` 기준인데 CoreText와 `NSRange`는 UTF-16 기준이다. [LineRenderer.swift:450](/Users/skyprawngo/Documents/Coding/Loreweave/Loreweave/Views/MainEditor/EditorPanel/LoreTextView/LineRenderer.swift:450) 및 [LoreTextView.swift:1293](/Users/skyprawngo/Documents/Coding/Loreweave/Loreweave/Views/MainEditor/EditorPanel/LoreTextView/LoreTextView.swift:1293) 부근에서 단위 경계가 섞인다. `😀AB`에서 이모지 직후 UTF-16 위치 2는 사용자 문자 위치 1인데 열 2로 해석된다. 클릭·선택·입력 위치가 달라질 수 있다.

**수정:** 문서 내부 위치 체계를 명시하고 AppKit/CoreText 경계에서 변환한다. 한글 완성형뿐 아니라 이모지, 가족 이모지, 결합 악센트, 일본어 조합, 여러 줄 선택을 검사한다. 문서 전체를 단순히 UTF-16로 바꾸는 것만으로 사용자 문자 단위 삭제까지 해결되지는 않는다.

### R07 · P1 · AI 응답이 다른 프로젝트 또는 카드에 저장된다

[AIAssistantViewModel.swift:69](/Users/skyprawngo/Documents/Coding/Loreweave/Loreweave/Views/MainEditor/AIAssistant/AIAssistantViewModel.swift:69)는 진행 중 요청을 정리하지 않고 프로젝트를 교체한다. [같은 파일:422](/Users/skyprawngo/Documents/Coding/Loreweave/Loreweave/Views/MainEditor/AIAssistant/AIAssistantViewModel.swift:422)는 완료 시점의 현재 프로젝트에 저장하고, [ChatHistoryManager.swift:383](/Users/skyprawngo/Documents/Coding/Loreweave/Loreweave/Services/AI/Chat/ChatHistoryManager.swift:383)는 지정된 카드가 아닌 마지막 카드의 답변을 갱신한다.

**수정:** 요청 생성 때 프로젝트·대화·카드·메시지 ID를 고정한다. 전환/삭제/취소 뒤 도착한 응답은 현재 화면의 다른 항목을 건드리지 못하게 한다. **확인:** A 응답 중 B 열기, 응답 중 카드 삭제, 취소 직후 재전송을 가짜 CLI로 재현해 저장 귀속을 검사한다.

### R08 · P1 · AI 터미널의 취소·완료·타임아웃이 요청과 묶여 있지 않다

[AIAssistantViewModel.swift:451](/Users/skyprawngo/Documents/Coding/Loreweave/Loreweave/Views/MainEditor/AIAssistant/AIAssistantViewModel.swift:451)의 취소는 일반 실행 프로세스를 정리하는 `stopSession()`만 호출하고 별도 터미널 프로세스는 남긴다. [CLIProcessManager.swift:465](/Users/skyprawngo/Documents/Coding/Loreweave/Loreweave/Services/AI/CLI/CLIProcessManager.swift:465)는 출력이 1.5초 멎으면 완료로 간주한다. [같은 파일:419](/Users/skyprawngo/Documents/Coding/Loreweave/Loreweave/Services/AI/CLI/CLIProcessManager.swift:419)의 5분 타이머도 특정 요청 ID를 확인하지 않는다.

**수정:** 지원 CLI의 명시적 완료 이벤트를 기준으로 처리하고, 요청별 task·타이머·프로세스 소유권을 둔다. 취소는 성공과 구분한다. **확인:** 중간에 2초 멈추는 출력, 첫 요청 종료 후 다음 요청, 취소 후 늦은 출력, 실제 자식 프로세스 종료를 검사한다.

### R09 · P2 · Undo가 문서/입력 상태와 분리된다

[LoreEditorRepresentable.swift:114](/Users/skyprawngo/Documents/Coding/Loreweave/Loreweave/Views/MainEditor/EditorPanel/LoreTextView/LoreEditorRepresentable.swift:114)는 문서 ID 대신 텍스트 차이로 문서를 교체한다. `EditorState.loadText`는 Undo를 초기화한다. 다른 본문의 탭으로 이동하면 Undo가 사라지고, 본문이 같은 다른 문서는 기존 Undo 상태를 공유할 수 있다.

AI 입력의 [AIChatView.swift:375](/Users/skyprawngo/Documents/Coding/Loreweave/Loreweave/Views/MainEditor/AIAssistant/Chat/AIChatView.swift:375)는 Undo 시 textStorage만 바꾸고 Binding을 갱신하는 편집 알림을 보내지 않는다. 화면과 전송 문자열이 어긋날 수 있으며, 삭제 기록에도 UTF-16/Character 혼용이 있다.

**수정:** 탭마다 문서 ID와 편집 상태를 유지한다. AI 입력은 기본 NSTextView Undo를 활용하거나 실제 변경 범위·모델 알림까지 함께 처리한다. **확인:** A→B→A, 같은 본문의 A/B, 한글·이모지 삭제 후 Undo·전송을 검사한다.

### R10 · P2 · 제공되는 메뉴/버튼 일부가 실제로 동작하지 않는다

| 항목 | 근거 | 수정 방향 |
|---|---|---|
| 찾기·바꾸기, 다른 이름 저장, 확대 초기화 | [AppCommands.swift:132](/Users/skyprawngo/Documents/Coding/Loreweave/Loreweave/Services/Core/AppCommands.swift:132) 등에서 요청 플래그만 설정; 해당 소비자 없음 | 명령을 실제 편집/저장 흐름에 연결 |
| 툴바 검색·뒤로/앞으로 | [MainEditorView.swift:170](/Users/skyprawngo/Documents/Coding/Loreweave/Loreweave/Views/MainEditorView.swift:170), 검색어 상태만 존재 | 파일 검색과 방문 기록 구현 |
| Spotlight 검색 | [SpotlightView.swift:297](/Users/skyprawngo/Documents/Coding/Loreweave/Loreweave/Views/MainEditor/SpotlightView.swift:297)는 TODO, 선택도 창 닫기만 수행 | 진입점부터 결과 열기까지 연결하거나 중복 UI 정리 |
| 굵게·기울임·밑줄·취소선 | [EditorContainerView.swift:63](/Users/skyprawngo/Documents/Coding/Loreweave/Loreweave/Views/MainEditor/EditorContainerView.swift:63)의 `pendingFormatAction` 대입만 존재 | 선택 영역 변경과 Undo를 연결 |
| 에디터 AI 도구 메뉴 | [EditorToolbarView.swift:91](/Users/skyprawngo/Documents/Coding/Loreweave/Loreweave/Views/MainEditor/EditorPanel/EditorToolbarView.swift:91)의 action이 비어 있음 | 선택 문단을 AI 요청과 연결 |

우선 현재 파일 찾기/바꾸기를 완성하고 프로젝트 검색을 확장하는 편이 좋다. 미구현 동작은 완성 전까지 비활성 상태와 이유를 표시해야 한다. 기능 체크리스트의 완료 표시는 현재 동작의 증거로 사용할 수 없다.

### R11 · P2 · 설정과 실제 실행, 저장 상태 표시가 일치하지 않는다

- 단축키 설정은 [KeyboardShortcutManager.swift:331](/Users/skyprawngo/Documents/Coding/Loreweave/Loreweave/Services/Core/KeyboardShortcutManager.swift:331)에 저장되지만 실제 메뉴는 [AppCommands.swift:103](/Users/skyprawngo/Documents/Coding/Loreweave/Loreweave/Services/Core/AppCommands.swift:103)부터 고정 키를 사용한다. 설정을 바꾸거나 비활성화해도 실행 키가 따르지 않는다.
- [EditorContainerView.swift:39](/Users/skyprawngo/Documents/Coding/Loreweave/Loreweave/Views/MainEditor/EditorContainerView.swift:39)의 자동 저장 옵션은 초기 `@State` 복사이며 설정 화면의 변경을 구독하지 않는다. 열린 에디터에 변경이 즉시 반영되지 않는다.
- 상태바는 [같은 파일:577](/Users/skyprawngo/Documents/Coding/Loreweave/Loreweave/Views/MainEditor/EditorContainerView.swift:497) 부근에서 저장 결과와 무관하게 `autoSaved` 문구를 표시한다. 자동 저장 OFF/실패 상태도 구분하지 못한다.
- [SettingsView.swift:328](/Users/skyprawngo/Documents/Coding/Loreweave/Loreweave/Views/SettingsView.swift:328)의 API Key는 화면의 로컬 상태뿐이며 인증이나 저장에 연결되지 않는다.

**수정:** 실행 명령의 단축키 소스를 하나로 만들고 설정 변경을 소비자가 관찰하게 한다. 저장 상태는 미저장/저장 중/저장 완료/실패와 마지막 성공 시각으로 표현한다. CLI 인증을 유지한다면 동작하지 않는 API Key 입력 대신 실제 인증 상태와 연결 안내를 제공한다.

### R12 · P2 · AI 실패·한글 스트림·로그 처리가 불완전하다

[CLIProcessManager.swift:146](/Users/skyprawngo/Documents/Coding/Loreweave/Loreweave/Services/AI/CLI/CLIProcessManager.swift:146)는 실행 종료 코드를 검사하지 않고 stdout/stderr를 합쳐 정상 답변으로 반환한다. [같은 파일:130](/Users/skyprawngo/Documents/Coding/Loreweave/Loreweave/Services/AI/CLI/CLIProcessManager.swift:130)은 임의 파이프 청크를 각각 UTF-8로 변환해 실패한 청크를 버린다. 한글 바이트가 청크 경계에 걸리면 내용이 유실될 수 있다. [같은 파일:117](/Users/skyprawngo/Documents/Coding/Loreweave/Loreweave/Services/AI/CLI/CLIProcessManager.swift:117)은 프롬프트가 포함된 명령 전문을 일반 로그에 출력한다.

**수정:** 실패/로그인 필요/취소/부분 응답을 분리하고, 미완성 바이트를 보관하는 디코더를 사용한다. 본문 로그를 제거하고 요청 ID·오류·소요시간으로 진단한다. **확인:** 비정상 종료, 바이트 단위 한국어 출력, 빈 응답, 취소, 로그 본문 미포함을 가짜 CLI로 검사한다.

### R13 · P2 · AI 대화 계속하기와 맥락 표시가 실제 전달과 다르다

[AIAssistantViewModel.swift:218](/Users/skyprawngo/Documents/Coding/Loreweave/Loreweave/Views/MainEditor/AIAssistant/AIAssistantViewModel.swift:218)는 후속 질문도 새 카드로 만들지만 상세 화면은 이전 카드의 질문·답변만 표시한다. 또한 UI는 현재 파일·열린 탭을 맥락으로 보여 주지만, [같은 파일:260](/Users/skyprawngo/Documents/Coding/Loreweave/Loreweave/Views/MainEditor/AIAssistant/AIAssistantViewModel.swift:260)의 프롬프트는 태그한 이전 대화만 포함한다. CLI의 프로젝트 작업 디렉터리와 미저장 문서 내용을 직접 전달하는 것은 서로 다르다.

**수정:** 대화와 개별 질문/답변을 분리하고 상세 화면은 해당 대화 전체를 표시한다. 실제 전송하는 원고·선택 문단·참조 파일을 명시적으로 첨부하며 미리보기로 확인할 수 있게 한다. 세션 ID를 일반 출력에서 추출하는 현재 방식은 지원 CLI 버전별 검증이 필요하다.

### R14 · P2 · 장편 원고에서 비용이 커지는 경로가 있다

[GutterView.swift:175](/Users/skyprawngo/Documents/Coding/Loreweave/Loreweave/Views/MainEditor/EditorPanel/LoreTextView/GutterView.swift:175)의 행 위치 계산과 LoreTextView의 누적 합산을 결합하면 긴 문서 하단 그리기 비용이 커진다. [EditorTabManager.swift:682](/Users/skyprawngo/Documents/Coding/Loreweave/Loreweave/Services/Editor/EditorTabManager.swift:682)의 LCS는 이전/새 행 수의 곱만큼 메모리와 계산이 필요하다. 상태바 글자/단어 수도 본문을 다시 순회한다.

**수정:** 행 높이 누적 인덱스와 변경 구간 갱신, 문서 크기에 따른 diff 제한과 백그라운드 계산을 적용한다. **확인:** 1천/1만/10만 행 및 한 문단이 매우 긴 한국어 파일로 열기·입력·아래쪽 스크롤·외부 변경 시간을 측정한다. 현재 지연 시간이나 최대 처리 용량을 실측한 것은 아니다.

### R15 · P2 · 테마·다국어·레이아웃 정책을 일치시켜야 한다

[AppColors.swift:20](/Users/skyprawngo/Documents/Coding/Loreweave/Loreweave/Theme/AppColors.swift:20)는 저장된 설정을 읽고, ThemeManager/ThemeAwareBackground는 시작 시 적용된 테마를 유지한다. 재시작 전 색상과 배경이 서로 다른 테마 기준을 사용할 수 있다. 설정 변경의 “취소”도 값을 저장하므로 실제 의미는 “나중에 적용”에 가깝다.

영어/일본어에는 `common.save`, `editor.letterSpacing`, `permission.addDirectory.grant`, `permission.addDirectory.panelMessage`, `permission.addDirectory.panelTitle`이 없다. 모든 언어에 `shortcut.view.sidebar`가 없으며, L10n은 누락 시 키를 그대로 표시한다.

**수정:** 현재 적용 테마를 단일 기준으로 삼고, 즉시 적용 또는 재시작 적용 중 하나를 일관되게 구현한다. 번역 키를 채우고 fallback을 마련한다. AI 패널 고정 350pt와 별도로 존재하는 저장 너비 설정도 실제 크기 조절에 연결할 필요가 있다. 실제 색 대비·작은 창·확대 글꼴·VoiceOver 검증은 추가로 필요하다.

## 추가 재현이 필요한 위험과 정비 후보

아래 항목은 중요한 코드상 위험이지만 실제 UI/환경 재현을 추가한 뒤 수정 범위와 심각도를 확정하는 편이 좋다.

| 항목 | 근거/발생 조건 | 권장 확인 또는 정비 |
|---|---|---|
| 조합 중 포커스 이탈 | LoreTextView `resignFirstResponder`→`commitMarkedTextSilently`가 내용 알림을 생략 | 한글 조합 중 AI 패널/설정 클릭 후 저장·재열기. 탭 전환과 일반 포커스 이동을 구분 |
| 저장된 커서 범위 초과 | Representable의 커서 복원은 문서 길이에 맞추지 않으며 Backspace는 직접 인덱싱 | 외부에서 문서를 짧게 만든 후 복원·삭제. 모든 복원 위치 정규화 |
| 읽기 실패를 빈 문서로 표현 | EditorContainer `loadFileContent`의 catch가 빈 문자열 사용 | 잘못된 UTF-8/접근 실패에서 오류 상태와 읽기 전용 처리, 원본 보존 |
| 긴 문단 선택/스크롤 | LineRenderer 선택 영역, LoreEditorView의 논리행 단위 스크롤 | 화면보다 긴 문단 중간 입력·부분 선택. 실제 caret와 wrapped line 기준으로 변경 |
| 하위 폴더 외부 변경 | FileSystemManager는 루트 디렉터리 FD 감시, 초기 로드는 재귀 | 하위 폴더 파일 추가/삭제가 탐색기에 반영되는지 확인 |
| 여러 창의 전역 상태 공유 | WindowGroup과 singleton 프로젝트·탭·명령·프로세스 관리자 | 단일 프로젝트/창 정책 명시 또는 창별 workspace 소유권. 한 창 닫기 영향 검사 |
| CLI 탐지/실행 경로 차이 | CLIDetector의 PATH 탐지와 CLIProcessManager의 경로 탐색이 다름 | 탐지한 실행파일·버전·제공자를 실행까지 전달. 실제 지원 CLI 목록 확정 |
| 메타데이터 호환·저장 실패 | 카드/metadata 별도 쓰기, decode 필수 필드, print 중심 오류 처리 | schemaVersion·구버전 fixture·부분 손상 복구·저장 재시도 |
| 프로젝트 이름/경로 변경 | 숨김 데이터 폴더명이 프로젝트 폴더명에서 파생 | Finder 이름 변경·외장 볼륨 재연결 후 복구. 파일명 충돌·경로 입력 검증 |
| 설정 잔여 코드 | API key UserDefaults 속성, 중복 언어 설정 경로, 미사용 크기 설정 | 실제 소비자가 있는 설정만 유지; API 방식 도입 시 Keychain 등 저장 계약 설계 |
| 접근성 | 커스텀 NSView 렌더러, hover에서만 드러나는 조작, 텍스트 접근성 구현 확인 필요 | VoiceOver 읽기·선택·편집과 키보드만으로 탐색하는 실사용 검사 |
| 제품 설명·약관 리소스 | 초기 기획과 현재 기능 차이, 약관의 날짜/데이터 설명 혼재 | 실제 기능·로컬 저장·외부 AI 전달을 제품 설명과 맞춤. 법률 적합성 평가는 이번 범위가 아님 |

## 기능을 추가한다면

아래는 현재 코드와 집필 흐름에 근거한 제품 제안이다. 확정 요구사항이나 경쟁 제품 조사 결과는 아니다. 구현량은 상대적인 규모이며 일정 약속이 아니다.

| 제안 | 사용자가 얻는 것 | 최소 범위와 구현 위치 | 규모/선행조건 |
|---|---|---|---|
| **복구 초안·수정 이력** | 잘못 닫거나 AI가 덮어써도 이전 원고 복원 | 문서 ID별 초안과 체크포인트, 복구 목록; EditorTabManager/저장 계층 | 중. R01~05와 함께 우선 |
| **프로젝트 검색·안전한 일괄 치환** | 인명·설정·복선 표현을 찾아 고침 | 현재 파일→프로젝트 확장, 결과 위치 이동, 치환 전 미리보기·되돌리기 | 중. 문서 위치 체계 선행 |
| **AI 수정안 비교·선택 적용** | 원문을 잃지 않고 교정 제안 수용 | 원문/제안/변경 이유, 문단별 수락, 한 번에 Undo, 버전 충돌 검사 | 중~대. 저장/Undo/AI 소유권 선행 |
| **명시적 AI 참조 문서** | 어떤 설정을 근거로 답했는지 알 수 있음 | 선택 문단·현재 원고·인물/세계관 파일 첨부, 전송 내용·출처 표시 | 중. 미저장 내용과 디스크 내용 구분 |
| **장면/챕터 목록** | 파일 관리보다 서사 구조에 집중 | 기존 폴더와 원고를 재사용한 순서·시점·등장인물·상태·짧은 개요 | 중. 기존 파일 형식 보존 |
| **일관성 검토** | 설정 모순과 시점 오류를 찾음 | 선정한 원고와 설정을 비교해 의심 지점·근거 문단 제시, 자동 수정은 별도 | 대. 출처 연결 선행 |
| **집필 집중 모드** | 패널을 감추고 글쓰기 지속 | 실제 글 폭, 현재 문단 강조, 세션 글자 수·선택적 목표 | 소~중. 성능/입력 안정화 뒤 |
| **원고 묶음 내보내기** | 챕터 순서로 검토·공유 | 우선 Markdown/TXT 통합과 미리보기, 이후 DOCX/EPUB | 중. 파일 순서/메타데이터 설계 필요 |

추천하는 첫 제품 확장은 **검색**과 **AI 수정안 비교·선택 적용**이다. 검색은 반복되는 집필 작업을 바로 줄이고, 선택 적용은 LoreWeave를 단순 채팅 옆에 둔 편집기에서 원고 편집과 AI가 연결된 도구로 발전시킨다. 다만 둘 다 원고 보존과 Undo 수정 이후에 진행해야 한다.

모바일, CloudKit 동기화, 연재 플랫폼은 현재 파일·세션 모델에 더 큰 변경을 요구한다. 먼저 macOS에서 장편 한 편을 안전하게 편집·복구·내보낼 수 있는 상태를 완료하는 것을 권한다.

## AI용 문서 정비

프로젝트 내부의 루트/하위 `claude.md` 11개, AI 기능 체크리스트, 일반 기능 체크리스트와 숨김 AI 설정의 역할을 조사했다. **프로젝트 내부에 SKILL.md는 없었다.** 전역 사용자 스킬과 플러그인 원본은 LoreWeave 전용 파일이 아니므로 수정하지 않았다.

정비 방향은 “모델에게 보편적인 코딩 절차를 반복해서 지시”하는 문서에서 **제품 맥락·실제 진입점·데이터 소유권·주의해야 할 구현 경계**를 알려 주는 문서로 바꾸는 것이다.

- 루트 [AGENTS.md](/Users/skyprawngo/Documents/Coding/Loreweave/AGENTS.md)를 공통 진입점으로 추가하고 기존 `claude.md`는 호환 진입점으로 정리했다.
- 상황마다 먼저 질문하라는 광범위한 루프백, 사용자 작업은 메인 스레드에서 처리하라는 분류, 파일 목록의 반복 등 불필요하거나 부정확한 지시를 제거했다.
- “DarkTheme만 수정”, “개발 중 ko만 수정”처럼 다른 구현/리소스를 의도적으로 뒤처지게 하는 규칙을 실제 공유 계약 중심으로 바꿨다.
- 탭/Undo·IME·저장·외부 변경·AI 요청 귀속 등 놓치기 쉬운 맥락은 보존했다. 현재 결함을 정상 동작이나 유지해야 할 규칙처럼 문서화하지 않는다.
- 삭제된 채팅 UI 파일, 오래된 AI 저장 구조, 자동 설치 등의 설명을 현재 코드에 맞췄다. 완료 체크리스트는 검증 완료 증거로 해석하지 않도록 정리했다.
- `.claude/settings.local.json`의 실행 허용 설정은 동작 권한에 해당하므로 이번 Markdown 정비에서 보존했다.

## 토의할 결정

우선 **R01~09의 원고·대화 보존과 입력 안정성**을 한 차례 정리하는 것을 제안한다. 이 단계의 완료 기준은 “빌드 성공”이 아니라 닫기·이동·충돌·취소 후에도 원문과 대화가 올바른 위치에 남는 것이다.

그다음 아래 결정에 따라 제품 방향을 좁힐 수 있다.

1. **편집 방식:** Markdown 원문 편집을 유지할지, 서식을 숨기는 집필 화면을 목표로 할지. 서식·선택·내보내기에 영향을 준다.
2. **AI 역할:** 제안과 비교 적용을 기본으로 할지, CLI의 직접 파일 수정을 주요 기능으로 둘지. 권장 기본은 원문/제안을 비교한 뒤 선택 적용이다.
3. **프로젝트 단위:** 일반 폴더·파일 구조를 그대로 중심에 둘지, 장면/인물 메타데이터를 추가할지. 권장 시작점은 기존 파일을 보존하는 선택적 메타데이터다.
4. **다음 기능:** 검색과 안전한 치환, AI 수정안 비교, 장면 목록 중 어떤 작업이 실제 집필 시간을 가장 많이 줄이는지.

검토보고서는 현재 작업 폴더의 스냅샷이다. 이후 소스가 변경되면 근거 줄 번호와 판정도 재확인해야 한다.
