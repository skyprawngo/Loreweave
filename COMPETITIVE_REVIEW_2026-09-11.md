# LoreWeave 경쟁 제품 비교와 제품 방향 검토

확인일: **2026-09-11**. 비교 대상: Scrivener, Ulysses, iA Writer, Obsidian, Novelcrafter, Sudowrite.

공식 제품 페이지·도움말·가격표를 직접 조회했다. “지원”은 공식 문서에 명시된 기능을 뜻하며, 이 조사에서 경쟁 앱을 설치하거나 한국어 원고를 입력해 검증하지는 않았다. 한국어 UI, 한글 입력 안정성, 한국어 교정·생성 품질은 서로 구분했다. 가격은 확인 당시 USD 표시이며 한국 결제 가격·세금·환율을 뜻하지 않는다. 웹페이지의 기능 설명과 실제 제품 전체의 동작이 일치하는지까지 실측한 보고서는 아니다.

LoreWeave의 기준은 현재 작업 트리와 [앱 검토보고서](/Users/skyprawngo/Documents/Coding/Loreweave/APP_REVIEW_2026-09-11.md)다. 아래 개선·추가·숨김·삭제는 **경쟁 조사에 따른 토의 제안**이다. 병렬로 진행한 기존 결함 수정은 [구현 결과](/Users/skyprawngo/Documents/Coding/Loreweave/IMPLEMENTATION_2026-09-12.md)에 별도로 기록했다. 아래 현재 상태 비교는 수정 전 검토보고서를 기준으로 하며, 복구 초안·기본 검색·요청 소유권 등은 이번 수정에 포함됐다. 경쟁 조사만을 근거로 추가 기능을 구현하거나 삭제하지는 않았다.

## 권장 방향

LoreWeave는 **한국어 장편 원고를 로컬에 보관하면서, 필요한 자료만 AI와 함께 검토하고 수정 결과를 선택해 반영하는 macOS 집필 도구**에 집중하는 편을 권한다.

경쟁 제품에는 이미 정리·집필·내보내기 또는 소설 문맥 관리의 강한 사례가 있다. 따라서 기능 수를 따라잡기보다 다음 사용자 경험을 하나의 완성된 흐름으로 만드는 것이 중요하다.

> 원고를 안심하고 열고 → 인물·사건 자료를 곁에 놓고 쓰고 → 필요한 부분만 AI에 보여주고 → 제안을 비교해 선택하고 → 언제든 이전 원고로 돌아가고 → 제출 가능한 파일로 내보낸다.

가장 먼저 할 일은 **원고 보존과 실제로 작동하는 기본 명령**이다. 차별화는 그 위에 **장면 시점에 맞는 설정 참조, AI 수정안 비교, 한국어 집필 지표**를 얹는 쪽이 적합하다. AI 모델 선택 개수, 터미널 출력, 빈 카테고리 화면을 늘리는 것만으로는 이 흐름이 완성되지 않는다.

## 1. 제품별 비교

### 집필 환경·원고 소유·복구

| 제품 | macOS와 집필 구조 | 로컬 원고·오프라인 | 복구·버전에서 확인한 점 |
|---|---|---|---|
| **Scrivener** | macOS 앱. 장편을 여러 문서로 나누어 구성하고 자료와 함께 집필하는 구조 | 프로젝트 중심 작업. 평문 파일만 직접 편집하는 도구와는 저장 구조가 다름 | 문서 Snapshot을 만들고 이전 버전으로 되돌리며 비교 가능. 장편 수정 전 보존의 좋은 기준. [제품 개요](https://www.literatureandlatte.com/scrivener/overview), [Snapshots](https://www.literatureandlatte.com/blog/use-snapshots-in-scrivener-to-save-versions-of-your-projects) |
| **Ulysses** | Mac·iPad·iPhone. 시트·그룹·프로젝트 중심 | 로컬 섹션과 iCloud, 외부 폴더 지원. 일반 외부 파일과 앱 내부 라이브러리의 기능 범위가 같지는 않음 | Mac 자동백업은 시간별·일별·주별 보존. **External Folders는 자동백업 대상에서 제외**. 백업 대상의 명확한 안내가 중요. [외부 폴더](https://help.ulysses.app/the-library/external-folders), [백업](https://help.ulysses.app/en_US/the-library/backups) |
| **iA Writer** | macOS 앱. 평문·Markdown과 집중 집필 중심 | 파일 기반이며 파일 저장 서비스를 선택하는 구조 | 이전 저장본으로 복귀, iCloud 사용 시 보관 버전 탐색, 휴지통·Time Machine 복구 안내. 무조건 자체 장기 백업을 제공한다고 해석하면 안 됨. [제품](https://ia.net/writer), [Mac 복구](https://ia.net/writer/support/help/versions-and-backups?platform=mac) |
| **Obsidian** | macOS 포함 데스크톱·모바일. 링크와 그래프·Canvas로 자료 연결 | 로컬 Markdown 파일, 오프라인 사용. 선택형 Sync 별도 | File recovery는 기본 5분 간격·7일 보존의 로컬 스냅숏이며 조정 가능. 완전한 백업이 아니며 기기별이고 파일 형식 제한이 있음. [제품](https://obsidian.md/), [다운로드](https://obsidian.md/download), [복구](https://obsidian.md/help/plugins/file-recovery) |
| **Novelcrafter** | 브라우저 기반. 장면·Codex·시리즈·채팅을 연결 | 공식 FAQ는 현재 인터넷 연결 필요, 오프라인은 미완료라고 명시. 이는 로컬 모델 연결 여부와 별개 | 장면·요약·Codex·프롬프트 등의 Revision History 복원 지원. [오프라인 FAQ](https://www.novelcrafter.com/help/faq/general/can-i-use-nc-in-ofline-mode), [버전 기록](https://docs.novelcrafter.com/en/articles/8677729-revision-history/) |
| **Sudowrite** | 웹 중심 AI 집필 UI, 문서와 Story Bible·생성 카드 결합 | 이 조사에서는 로컬 파일을 원본으로 직접 열어 편집하는 오프라인 동작을 확인하지 못함 | AI 결과 History 카드와 Synopsis의 이전 버전 접근 확인. **이를 전체 원고의 장기 복구 정책과 동일시하지 않음**. [인터페이스](https://docs.sudowrite.com/getting-started/dQph1snuwbfMWG9wRjsNug/interface/ubBg2ZEoAwasV98E3ZBwjn), [Synopsis](https://docs.sudowrite.com/using-sudowrite/1ow1qkGqof9rtcyGnrWUBS/synopsis/r4GGUdR23VKcK2WrQVdheb) |

LoreWeave는 로컬 원고를 직접 다루는 장점을 이미 갖지만, 현재 탭 닫기·종료 실패·동명 생성·파일 이동·외부 충돌 문제가 이 장점을 약화시킨다. 경쟁 제품의 복구 기능을 보기 전에 앱 검토보고서 R01–R05부터 해결해야 한다. 자동저장이 있다고 복구가 되는 것은 아니다. 특히 잘못 덮어쓴 내용까지 자동저장하면 되돌릴 별도 버전이 필요하다.

### AI 참조와 출력

| 제품 | AI·자료 참조에서 배울 점 | 내보내기·제출 |
|---|---|---|
| **Scrivener** | 연구 자료와 원고를 정리하고 여러 문서를 참조하는 집필 공간. 이번 공식 자료에서 통합 생성 AI는 확인하지 못했으므로 AI 기능 수를 경쟁 기준으로 삼지 않음 | Compile로 Word·PDF·평문 등의 원고 출력. 장별 편집과 최종 결과물 조립을 분리. [개요](https://www.literatureandlatte.com/scrivener/overview), [기능 소개](https://www.literatureandlatte.com/introducing-scrivener-3) |
| **Ulysses** | 문서 관리·집중 화면·교정의 결합. 확인한 Grammar/Style Check를 소설 설정집 기반 생성 AI로 분류하지 않음 | 여러 시트/그룹을 DOCX·PDF·ePub·HTML·텍스트로 출력, 미리보기·스타일과 자료 시트 제외 지원. [출력](https://help.ulysses.app/export?kb_language=en_US), [교정](https://help.ulysses.app/grammar-and-style-check) |
| **iA Writer** | Authorship으로 본인·AI·외부 참고문을 구별. **작성자가 지정하는 출처 표시이며 AI 탐지기가 아님**. 외부 수정문을 붙일 때 변경 부분을 구별하는 방향이 LoreWeave에 유용 | Markdown·HTML·PDF·Word 출력 시 저자 메타데이터 제거. 원본 파일 공유와 제출본 출력을 구분. [Mac Authorship](https://ia.net/writer/support/editor/authorship?tab=authorship-mac), [수정문 붙이기](https://ia.net/writer/how-to/track-authors-and-ai) |
| **Obsidian** | 링크·백링크·그래프·Canvas가 강점. 특정 AI 플러그인의 기능을 기본 앱 기능으로 계산하지 않음 | 기본 원고가 Markdown이므로 파일 자체의 이동성이 높음. 이번 조사에서 출판용 다중 장 조립·DOCX 출력은 기본 기능으로 확인하지 못함. [제품](https://obsidian.md/), [Markdown](https://obsidian.md/help/import/markdown) |
| **Novelcrafter** | Codex에서 인물·장소·설정과 시리즈 공유, Progressions로 시점별 상태를 관리. BYOK 제공자 또는 로컬 모델 연결. 일부 가격표 기능은 planned이므로 완료 기능에 포함하지 않음 | 원고 외 Codex·채팅 등을 함께 내보내는 기능이 공식 변경 기록에 있음. 출판용 최종 조판은 외부 프로그램 사용 안내. [Codex](https://www.novelcrafter.com/features/codex), [전체 프로젝트 출력](https://feedback.novelcrafter.com/changelog/september-19-2024), [조판 범위](https://www.novelcrafter.com/help/faq/export/format-for-export) |
| **Sudowrite** | Story Bible이 개요·인물·세계관·장면 생성의 참조 자료. Rewrite 결과의 변경 표시와 실제 참조 문맥 표시가 중요 | 개별 DOCX, 프로젝트 ZIP, **전체 원고를 한 DOCX로 병합** 지원. 프로젝트 출력에는 **Story Bible이 포함되지 않음**. [Story Bible](https://docs.sudowrite.com/using-sudowrite/1ow1qkGqof9rtcyGnrWUBS/what-is-story-bible/jmWepHcQdJetNrE991fjJC), [Rewrite](https://docs.sudowrite.com/using-sudowrite/1ow1qkGqof9rtcyGnrWUBS/rewrite/9hkeezeUsCiUCG4dRdEqjS), [출력](https://docs.sudowrite.com/using-sudowrite/1ow1qkGqof9rtcyGnrWUBS/exporting-files/3NtVWXcnwYaRCmPW2iwcCB) |

**비교 해석:** LoreWeave의 AI 카드는 출발점이다. 경쟁력을 만드는 것은 카드 자체보다 “어떤 원고와 설정을 읽었는지”, “무슨 문장을 바꿨는지”, “원래 문장으로 돌아갈 수 있는지”의 연결이다. 출력도 원고 제출본과 전체 프로젝트 보관본을 따로 제공해야 한다. 세계관과 AI 기록이 빠진 원고 DOCX를 “전체 백업”이라 부르면 안 된다.

### 한국어 지원에서 구분해야 할 것

| 제품 | 공식 자료로 확인한 범위 | 아직 입증되지 않은 범위 |
|---|---|---|
| Scrivener | macOS 집필·출력 기능 | 이번 조사에서 현행 한국어 UI 범위·IME·한국어 출력 품질을 별도 검증하지 않음 |
| Ulysses | 공식 교정 문서가 한국어를 현지화 언어로 다루면서 **한국어 문법·문체 검사 미지원**을 명시 | 한글 입력·문단 처리의 실제 안정성은 실측하지 않음. [교정 언어](https://help.ulysses.app/grammar-and-style-check) |
| iA Writer | Syntax Highlight 지원 언어 목록에 한국어가 없음 | 한국어 문체 검사 전반이나 모든 한글 지원이 없다는 뜻은 아님. 한글 IME는 미실측. [FAQ](https://ia.net/writer/support/basics/faq) |
| Obsidian | 로컬 Markdown 및 여러 플랫폼 사용 | 한글 편집·검색 품질, 개별 AI 플러그인의 한국어 결과는 미실측 |
| Novelcrafter | 사용 모델이 지원하는 LTR 언어의 생성 가능이라는 안내 | 한국어 소설 품질은 모델·프롬프트에 좌우되며 공식 안내가 문학 품질을 보장하지 않음. [언어 안내](https://www.novelcrafter.com/help/faq/general/language-compatibility) |
| Sudowrite | 거의 모든 언어로 쓰면 언어를 맞춰 제안하나 다른 기능에서 영어로 돌아갈 수 있다는 안내 | 한국어 고유 문체·높임말·시점·인물 말투 유지 품질 미실측. [언어 FAQ 포함 가격 페이지](https://sudowrite.com/pricing) |

따라서 “해외 앱은 한국어가 안 된다”는 포지셔닝은 근거가 부족하다. LoreWeave는 **한글 IME와 Unicode 경계를 실제로 검증하고, 공백 포함/제외 글자 수·한국어 대사 검토·회차 제출 흐름을 명확히 제공**하는 것으로 차이를 만들어야 한다. 현재 LoreWeave의 한/영/일 번역 파일 존재도 이 검증을 대체하지 못한다.

### 비용 구조

| 제품 | 확인한 비용 구조 | 비교 시 주의점 |
|---|---|---|
| Scrivener | 플랫폼별 구매 라이선스, 주요 버전 업그레이드는 유료일 수 있음. 30일 실제 사용 기준 체험 | 현행 상점에서 Mac 숫자 가격이 본문에 명확히 노출되지 않아 특정 금액을 채택하지 않음. [상점](https://www.literatureandlatte.com/store/scrivener), [라이선스 FAQ](https://www.literatureandlatte.com/scrivener/faqs) |
| Ulysses | 미국 기준 **연 $39.99 또는 월 $5.99**, Mac/iPad/iPhone 포함 | 현지 App Store 가격은 다름. [가격](https://ulysses.app/pricing/) |
| iA Writer | Mac **$49.99 일회 구매**, 플랫폼별 별도 구매 | 일회 구매를 평생 모든 업그레이드 보장으로 해석하지 않음. [가격](https://ia.net/writer/pricing) |
| Obsidian | 기본 앱 무료. Sync Standard 연간 결제 월 환산 **$4**, 월 결제 **$5** | 동기화·웹 Publish 등은 선택 서비스. 기본 앱 무료와 Sync의 유료 버전 기록을 구분. [가격](https://obsidian.md/pricing), [Sync](https://obsidian.md/sync) |
| Novelcrafter | 월 결제 Scribe **$4**, Hobbyist **$8**, Artisan **$14**, Specialist **$20**. AI는 BYOK 구조 | 앱 구독과 연결한 모델 제공자의 비용을 구분. 로컬 모델은 장비·자원 부담이 있음. 오래된 도움말의 모델별 예시 단가는 재사용하지 않음. [가격](https://www.novelcrafter.com/pricing), [AI 비용 구조](https://www.novelcrafter.com/help/faq/ai-and-prompting/ai-cost) |
| Sudowrite | 월/연 구독과 AI 크레딧 포함형 등급 | 동적 페이지에서 월/연 표시와 프로모션 크레딧이 함께 추출되어 확정 결제 총액은 채택하지 않음. 크레딧을 글자 수·토큰 수와 동일시하지 않음. [가격](https://sudowrite.com/pricing) |

LoreWeave 요금제는 아직 정할 단계가 아니다. 다만 설정 UI에서 **앱 가격, 외부 AI 인증 방식, 실제 청구 주체**를 혼동시키지 않아야 한다. 현재 CLI 방식을 유지할지 API 연결을 추가할지는 제품 결정이며, 다른 앱의 BYOK 정책을 그대로 LoreWeave의 CLI에 적용해서 “API 결제가 반드시 추가된다”거나 “보유 구독으로 모든 호출이 된다”고 단정할 수 없다. 구체 제공자·실행 방식이 정해지면 해당 제공자의 당시 공식 계약을 별도로 확인해야 한다.

## 2. 현재 LoreWeave에 연결한 개선안

우선순위는 매출·사용빈도 측정 결과가 아니라 원고 보존 위험, 완성된 집필 흐름, 구현 의존성을 근거로 한 판단이다. P1은 먼저 해결할 신뢰성, P2는 첫 제품의 핵심 가치, P3는 검증 후 확장이다.

| 우선순위·제안 | 현재 연결점 | 최소한의 완성 형태 | 이유와 대가 |
|---|---|---|---|
| **P1 보완: 저장·닫기·충돌 처리** | 앱 보고서 R01–R05, EditorTabManager·FileSystemManager·앱 종료 | 저장 실패 시 닫기 중단, 동명 생성 거부, 이동 후 URL 일치, 외부 수정 시 두 버전 보존 | 모든 비교 제품의 집필 기능을 사용하기 위한 전제. 신규 기능보다 먼저 해야 하며 실패 시나리오 검증 비용이 듦 |
| **P1 추가: 복구 초안과 버전 탐색** | URL별 편집 캐시는 있으나 세션 파일에 미저장 본문이 없음 | 비정상 종료 후 복구, 변경 전 스냅숏, 날짜별 미리보기·다른 파일로 복구 | Scrivener/Ulysses/Obsidian에서 배울 공통 기준. 저장 공간·보존 기간·파일 이동에 따른 ID 유지 설계 필요 |
| **P1 보완: 문서별 Undo·한글 입력** | R06/R09, EditorState·LoreEditorRepresentable | A→B→A에도 Undo 유지, 한글 조합·이모지·결합 문자 위치 정확 | 한국어 중심 앱의 실질 차별화 전제. 커스텀 엔진 유지에는 지속적 AppKit/IME 검증 부담이 따름 |
| **P1 보완: AI 요청 소유권·취소·실패** | R07/R08/R12, CLIProcessManager·AIAssistantViewModel | 프로젝트/카드별 요청 고정, 취소 후 늦은 출력 차단, UTF-8 청크 보존, 오류 별도 표시 | 더 많은 모델을 추가하기 전에 대화 기록과 원고의 귀속을 보장. 가짜 CLI로 실패를 재현할 기반 필요 |
| **P2 보완: 검색·기본 명령** | R10/R11, MainEditorView·SpotlightView·AppCommands | 현재 파일 찾기/바꾸기, 다음으로 프로젝트 본문 검색, 실제 사용자 단축키 반영 | 장편에서 이름·사건을 찾는 기본기. 검색 결과 인덱스와 미저장 원고 반영이 필요 |
| **P2 추가: 제출본 출력** | 현재 명령과 파일 저장 흐름; 별도 출력 기능 필요 | 장면 순서 선택 → 자료 제외 → 한 파일 TXT/Markdown/DOCX → 미리보기 | Scrivener/Ulysses/Sudowrite 공통의 실용 가치. DOCX 서식·한글 폰트·줄바꿈 QA 부담. PDF/ePub은 다음 단계로 분리 가능 |
| **P2 추가: 전송 문맥 확인** | R13, 카드 태그·PromptTemplateManager | 현재 미저장 원고/선택 문단/설정 항목을 명시 첨부, 포함 이유·분량·제외 표시 | 실제로 읽은 범위를 사용자가 이해해야 제안도 평가 가능. 자동 첨부가 과해지면 비용·노출·불필요 문맥 증가 |
| **P2 추가: AI 수정안 비교·선택 적용** | AI 카드와 편집기 사이 연결 | 원문/제안/차이 표시, 부분 적용·거절, 적용 전 버전·Undo 기록 | iA Writer Authorship와 Sudowrite Rewrite에서 배울 부분. 생성 후 원문이 바뀌었다면 충돌 확인 필요 |
| **P2 추가: 장면 목록·요약·상태** | 기존 폴더·파일·프로젝트 분류 | 파일과 연결된 장면 순서, 시점 인물, 장소, 한 줄 요약, 초고/수정/완료 | Scrivener 구조화와 Novelcrafter 장면 흐름을 작게 도입. 파일명과 순서·상태를 강결합하면 이름 변경 부담이 생김 |
| **P2 추가: 작은 설정집과 수동 참조** | 세계관·캐릭터 폴더, AI 문맥 조립 | 인물/장소/규칙의 이름·별칭·본문·원고 연결, 사용자가 참조 여부 선택 | 처음부터 모든 원고를 자동 분석하는 것보다 결과를 통제하기 쉬움. 메타데이터의 저장·내보내기 계약 필요 |
| **P3 추가: 시점별 설정·불일치 검토** | 장면/설정집 도입 이후 | “3화 시점 주인공이 아는 사실”과 작품 전체의 사실 분리, 충돌 후보에 근거 문장 표시 | Novelcrafter Progressions와 닿는 가치. 거짓 양성·스포일러·추론 오류가 있어 경고를 자동 수정하면 안 됨 |
| **P3 추가: 한국어 집필 지표** | 현재 상태바 글자 수·에디터 설정 | 공백 포함/제외 글자 수, 회차 목표·진행, 대사/호칭 검토 옵션 | 번역 UI보다 집필 맥락에 가까움. 정확한 집계 규칙 공개, 목표 강요 없이 끌 수 있어야 함 |

### 첫 출시 흐름으로 묶는다면

1. **보존 가능한 편집기**: P1 전체와 현재 파일 찾기/바꾸기. 저장 성공 상태가 거짓으로 표시되지 않고, 미저장 원고가 닫기·종료·이동에서 남아야 한다.
2. **끝까지 쓸 수 있는 집필기**: 장면 순서·집중 모드·제출본 출력. 설정집은 작은 수동 구조로 시작한다.
3. **검토 가능한 AI 보조**: 문맥 선택·수정안 비교·부분 적용·되돌리기. 모델 목록 확장보다 먼저 현재 지원 경로 하나를 신뢰할 수 있게 한다.
4. **작품 맥락의 축적**: 별칭·시리즈·시점별 지식·불일치 검토. 실제 원고 사용에서 필요가 확인된 범위부터 확장한다.

단계는 고정 개발 일정이 아니다. 특히 검색과 출력은 “나중에”로 밀려 장기 미완성 상태가 되지 않도록 첫 집필 흐름에 포함하는 편이 좋다.

## 3. 삭제·숨김·통합을 토의할 후보

다음은 실제 삭제 지시가 아니라 제품 범위를 줄이는 선택지다. 기존 사용자 데이터가 있는 항목은 UI 숨김과 저장 데이터 폐기를 구분해야 한다.

| 후보 | 권고 | 근거·유지 가치·재노출 조건 |
|---|---|---|
| **동작하지 않는 버튼·메뉴** | 구현 전 숨기거나 비활성 이유 표시 | R10의 검색·서식·AI 도구 등. 눌러도 변화 없는 버튼은 기능의 존재를 약속한다. 실제 연결과 검증 후 노출 |
| **연결되지 않은 API Key 설정** | 현재 CLI 제품 흐름에서는 숨김 후보 | R11. 별도 API 기능이 없는데 값을 받으면 저장·청구·인증 오해가 생김. API 어댑터를 제품 범위에 넣을 때 복원 |
| **미검증 ChatGPT CLI 제공자 항목** | 삭제보다 지원 보류 표시/선택 숨김 검토 | 현재 `AICLIType`의 이름만으로 외부 제품 호환성이 성립하지 않음. 제공자 계약·설치·인증·응답·취소가 확인되면 노출 |
| **일반 사용자의 터미널 모드 토글** | 고급/실험 설정으로 이동 | R08의 수명주기 문제와 지원 부담. CLI 디버깅 가치가 있으므로 즉시 코드 삭제할 이유는 부족. 안정된 출력 계약이 확인되면 판단 |
| **툴바 검색과 별도 Spotlight의 겹치는 UI** | 하나의 검색 흐름으로 통합 | 파일 열기·원고 찾기 목적을 구분하되 같은 검색 구현 재사용. 둘 다 미완성으로 유지하는 비용을 줄임 |
| **원고용 서식 툴바 전체 상시 표시** | 집중 모드에서는 접고 선택 시 필요한 동작만 | iA Writer/Ulysses의 집중 원칙을 참고한 제안. 작가가 자주 쓰는 기능은 단축키·문맥 메뉴에 남겨 발견성을 보완 |
| **세계관·캐릭터·플롯·콘티 등 모든 분류를 처음부터 강제** | 프로젝트 템플릿에서 선택·이름 변경 허용 | 현재는 주로 폴더 분류. 구조화 기능처럼 보이는 과장을 줄이고 단편/에세이도 수용. 저장 폴더 자동 삭제는 하지 않음 |
| **즉시 모바일·협업·연재 플랫폼 확장** | 초기 제품 범위에서 보류 | 경쟁 제품에도 있지만 현재 원고 보존·출력보다 선행할 이유가 약함. 기기 간 충돌·서버 운영·공유 권한 비용이 커짐 |
| **전면 그래프·무한 Canvas를 먼저 추가** | 실제 탐색 필요 확인 전 보류 | Obsidian이 강한 영역. LoreWeave는 인물 문서 연결·참조 검색부터 제공해도 가치가 있음. 사용자 작업이 공간 배치에 의존할 때 확장 |
| **기존 커스텀 에디터 즉시 폐기** | 지금은 권하지 않음 | 변경 폭과 회귀 위험이 큼. 먼저 Unicode/IME/성능 기준을 세우고 기존 엔진 개선과 AppKit 표준 텍스트 시스템 실험을 비교한 뒤 판단 |

## 4. 차별화 기능을 구체화하는 예시

### “지금 이 장면에서 알고 있는 것”

설정집에 “정체: 왕자”라는 작품 전체 사실만 저장하면 AI가 초반 장면에서 그 사실을 누설할 수 있다. 장면별로 **사건의 실제 사실 / 해당 인물이 알고 있는 사실 / 독자에게 공개된 사실**을 구별해서 참조하도록 한다.

최소 구현은 복잡한 자동 추론이 아니라 설정 항목의 공개 시점과 수동 범위 지정이다. 검토 결과는 “2화에 등장한 이 문장이 7화 공개 설정을 전제로 하는 것 같습니다”와 원문 근거를 보여준다. 작가가 의도한 복선일 수 있으므로 자동 수정하지 않는다. 이는 경쟁 기능의 단순 복제가 아니라 LoreWeave가 선택할 수 있는 소설 편집 관점의 제안이다.

### “이 수정은 무엇을 바꿨나”

AI에게 문단을 다듬게 한 후 결과를 통째로 덮어쓰는 대신 문장별 변경, 의미 변화 후보, 선택한 적용 범위를 보여준다. 요청 당시 원문과 현재 원문이 다르면 다시 비교하도록 한다. 인물 말투가 바뀐 부분을 거절하고 중복 표현만 받아들일 수 있어야 한다.

색으로 출처를 표시하는 기능보다 먼저 **원문과 제안의 보존·부분 적용·되돌리기**가 필요하다. 출처 표시는 이 기록이 갖춰진 뒤 자연스럽게 붙일 수 있다.

### “원고 제출”과 “작품 보관”

제출은 독자에게 보여줄 장면만 순서대로 묶는 작업이고, 보관은 설정집·초안·태그·AI 대화·첨부까지 보존하는 작업이다. 내보내기 화면에서 두 목적을 분리하고 포함 목록을 확인하게 한다.

첫 단계는 TXT/Markdown 통합 출력과 전체 프로젝트 복사/보관 기능을 완성하고, DOCX를 이어서 제공하는 식으로 나눌 수 있다. HWP/HWPX 직접 출력은 국내 제출 수요를 먼저 확인한다. “한국어 작가용”이라는 이유만으로 복잡한 포맷 구현을 선행할 필요는 없다.

## 5. 토의할 결정과 확인 방법

| 결정 | 현재 권고 | 결정에 필요한 실제 확인 |
|---|---|---|
| 첫 핵심 사용자 | macOS에서 한국어 장편·연재 원고를 쓰고 AI 검토를 선택적으로 사용하는 개인 작가 | 단편/장편/연재 원고의 일주일 작업 흐름과 자주 오가는 외부 앱 |
| AI의 역할 | 초고 자동 생산보다 참조·검토·부분 수정 적용에 우선순위 | 같은 원고에서 “생성”과 “검토” 중 실제 시간을 줄이는 작업 |
| 원고 저장 원칙 | 일반 파일 유지, 구조 정보는 별도 메타데이터 | Finder 이동·다른 편집기 수정·프로젝트 이름 변경 후 복구 가능성 |
| 첫 출력 형식 | TXT/Markdown와 DOCX 우선, PDF/ePub 순차 | 실제 투고/편집자 전달 형식과 한글 문단·장 제목 요구 |
| AI 연결 범위 | 검증된 경로를 먼저 완성하고 연결 방식별 상태·비용 주체 표시 | 설치하지 않은 Mac에서 연결→실패→재시도→첫 응답까지 진행 가능 여부 |
| macOS 26 최소 요구 | 당장 낮추기보다 유지 비용과 대상 사용자 OS를 비교 | Liquid Glass 외 하위 OS 차단 요소 및 실제 대상 기기 분포 |

경쟁 앱 한국어 비교가 추가로 필요하면 동일한 시험 원고를 사용해야 한다. 완성형 한글, 조합 중 탭 전환, 이모지·결합 문자, 10만 자 이상의 원고, 장면 이동, 원고/설정 내보내기, AI의 높임말·시점 유지와 제안 거절을 같은 기준으로 확인한다. 이번 문서에는 그런 실측이 없으므로 어느 앱의 한국어 품질이 최고라는 순위를 매기지 않았다.

## 조사상 주의한 사항

- Sudowrite의 예전 기능 요청 게시판에는 전체 문서 병합 출력 요청이 남아 있지만, 2026년 공식 출력 문서는 병합 DOCX를 설명한다. 최신 공식 문서를 기준으로 했고 Story Bible 제외는 따로 명시했다.
- Novelcrafter 가격표에 `planned`가 붙은 항목은 현재 기능으로 계산하지 않았다. AI 비용 도움말의 오래된 모델 단가도 현행 단가로 옮기지 않았다.
- Ulysses의 외부 폴더 지원을 자동백업 보장과 혼동하지 않았다. Obsidian의 로컬 File recovery와 유료 Sync 이력도 별개로 보았다.
- 미확인 기능은 “없음”으로 단정하지 않았다. 공식 문서의 설명과 이 조사에서 수행한 검증 범위를 구분했다.
