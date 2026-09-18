# TextKit 2 원고 에디터 전환

2026-09-17. 기존 미커밋 변경을 보존하고 원고 에디터와 AI 수정안 비교 뷰를 전환했다. 실행 중인 사용자 앱 교체, 커밋·푸시는 하지 않았다.

## 구조와 이식한 기능

`NativeManuscriptView.swift`는 `NSTextContentStorage → NSTextLayoutManager → NSTextContainer → NSTextView`를 직접 구성한다. 원고 화면에서 TextKit 1 `layoutManager`/glyph API 접근을 제거했다. 실제 편집·스크롤·인라인 패널 검사의 시작과 끝에 같은 `NSTextLayoutManager`가 유지되는지 확인한다.

- 네이티브 단어·행·문서 이동과 선택, 한글 조합 범위, 이모지, 서식·찾기·바꾸기, 문서별 Undo를 유지했다.
- 줄 번호·수정 표시·현재 행 강조는 viewport의 문단/행 fragment 좌표를 사용한다. 자동 줄바꿈은 원고 행 번호를 늘리지 않으며, 마지막 빈 줄과 빈 문서도 처리한다.
- 인라인 AI는 사용자 원고에 attachment 문자나 마커를 넣지 않는다. 커스텀 `NSTextLayoutFragment.bottomMargin`으로 문단 아래에 공간을 예약하고, 열기·닫기·편집 시 해당 fragment를 다시 배치한다. 패널 폭은 편집 영역을 따라간다. 단발 편집, 전송 후 닫기, 별도 기록과 실제 AI 편집 서비스 계약은 유지한다.
- 백그라운드 청크 읽기·글꼴 준비는 유지하고 준비된 저장소를 `NSTextContentStorage.textStorage`로 이전한다. 직접 편집은 content storage의 editing transaction 안에서 수행한다.
- 탭별 네이티브 뷰와 Undo, 비동기 로딩 취소·커서 복원, 외부 수정 반영 및 AI 수정 연결을 유지한다.
- AI 수정안 비교의 읽기 전용 원고 뷰도 TextKit 2로 생성한다. AI 메시지 입력창 등 다른 용도의 텍스트 UI는 이번 원고 엔진 전환 범위 밖이다.

전체 논리 문서는 계속 메모리에 보관한다. 이 전환은 디스크 페이지를 필요할 때만 읽는 편집기를 구현한 것은 아니다. 저장 포맷과 원자적 저장·충돌 보호 정책은 바꾸지 않았다. 화면 layout은 TextKit 2 viewport controller가 담당하고, 줄 번호를 위해 전체 문서 layout을 강제하지 않는다.

API 근거: 로컬 macOS SDK의 NSTextLayoutManager/NSTextContentManager/NSTextLayoutFragment 헤더와 [Apple의 bottomMargin 문서](https://developer.apple.com/documentation/appkit/nstextlayoutfragment/bottommargin). 이 속성은 마지막 행 아래와 fragment 하단 사이의 공간을 정의한다.

## 검증

- `tests/native_editor_regression.py`: 네이티브 명령·Undo, IME marked text의 프로그래밍 방식 조합/확정, CRLF·결합 문자·이모지, 인라인 공간/닫기/편집/폭 변경, 자동 줄바꿈·마지막 빈 줄 번호, 글꼴·자간 변경, 1천/1만/10만 줄 스크롤·끝 이동, 청크 경계 Undo, 실제 viewport에 행이 남는지, TextKit 2 유지 검사 통과.
- `tests/editor_binding_regression.py`: 탭별 Undo, 오래된 callback 차단, 외부 수정, AI 선택 capture/실제 편집/Undo, 비동기 커서 복원, TextKit 2 유지 검사 통과.
- `tests/chunked_loading_regression.py`: UTF-8·CRLF 청크 경계, 취소, 잘못된 UTF-8, 주 스레드를 막지 않는 준비, 저장소 단일 이전, 원자적 저장 왕복 검사 통과.
- macOS Debug, `CODE_SIGNING_ALLOWED=NO` 앱 빌드 성공. `git diff --check` 통과.
- 별도 AppKit 테스트 창의 실제 렌더링을 PNG로 확인했다. 인라인 패널 전후 본문과 줄 번호가 겹치지 않는다. 이 테스트는 전체 SwiftUI 앱을 수동 조작한 증거가 아니다.

## 같은 조건에서의 성능 비교

같은 Mac에서 한글·이모지가 포함된 합성 10만 줄, 900×700 창, 글꼴 14pt를 사용했다. 전환 직전 저장해 둔 TextKit 1 소스와 TextKit 2 소스를 동일한 독립 AppKit harness로 순차 실행했다. 준비와 화면 연결은 별도로 측정했다. 수치는 한 번의 비교 실행 결과이며 반복 통계나 전체 앱 프레임률은 아니다.

| 작업 | 기존 TextKit 1 | TextKit 2 |
|---|---:|---:|
| 청크 글꼴 준비 (제품에서는 백그라운드) | 864ms | 870ms |
| 준비된 원고 화면 연결 | 43ms | 48ms |
| 첫 display 호출 | 8ms | 23ms |
| 큰 스크롤 이동 5회 | 329ms | 96ms |
| 문서 끝으로 이동 | 26ms | 3.2ms |
| 편집·Undo 후 연속 스크롤 100회 평균 | 0.19ms | 2.93ms |
| 위 연속 스크롤의 최대 구간 | 8.5ms | 58ms |
| 테스트 프로세스 peak RSS | 172MiB | 171MiB |

큰 이동과 문서 끝 이동은 개선됐지만 모든 비용이 감소한 것은 아니다. Undo 후 첫 viewport 재구성에서는 약 58~60ms의 지연이 남는다. 후속 기능 검사에서도 유사한 결과였다. 메모리가 유의미하게 줄었다고 볼 수는 없다. 전체 앱에서 사용자의 실제 원고·입력기로 장시간 편집하고 트랙패드 관성 스크롤하는 검증은 남아 있다.

네이티브 회귀 검사의 `display` 시간에는 의도적인 100ms RunLoop 대기가 포함되므로 이 표의 첫 display 시간과 직접 비교하지 않는다.
