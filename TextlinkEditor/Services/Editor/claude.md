# 탭과 원고 저장

`EditorTabManager.swift`는 URL별 `TabEditState`에 편집 텍스트, 저장본(`originalContent`), 0-based 커서를 보관한다. 수정 여부는 두 텍스트의 비교로 계산하며 저장 성공 시 저장본을 갱신한다. 화면의 저장 상태도 이 결과를 사용한다.

## 저장·복구 경계

원고 쓰기는 `FileSystem/DocumentFileStore.swift`의 신규 생성/기준본 비교 저장을 거친다. 닫기·전환·삭제는 먼저 에디터를 flush하고 저장/버리기/취소를 결정한다. 버리기 승인만으로 캐시를 지우지 않으며, 후속 파일 작업 실패 시 초안을 유지한다.

앱의 Application Support/TextlinkEditor/Recovery에 프로젝트 경로별 복구 사본을 먼저 저장하고, `.{projectName}.weavedata/editor-session.json`에도 프로젝트 내부 탭을 저장한다. 탭·커서와 수정 중 `draftContent`·`baseContent`를 포함한다. 프로젝트 밖으로 다른 이름 저장한 탭의 `externalURL`은 앱 소유 복구 사본에서만 복원하며 프로젝트가 제공하는 절대 경로는 신뢰하지 않는다. 변경 후 0.5초 지연 저장이므로 갑작스러운 종료 직전 입력까지 보장하는 저널은 아니다. 복원 실패 시 원본 세션의 별도 사본 보존을 시도하고 오류를 알린다. 이것은 편집 초안 복구이며 전체 프로젝트의 장기 버전 백업은 아니다. 글꼴 등 프로젝트 설정은 같은 폴더의 `editor-settings.json`에 있다.

파일 이동·이름 변경은 탭 ID를 유지하면서 URL·편집 캐시·저장 상태를 함께 옮긴다. `EditorContainerView`와 `TextlinkEditorRepresentable`은 문서 ID·URL·내용 revision으로 지연된 binding 갱신의 귀속을 확인한다. IME 확정 결과를 이전 URL로 돌려주는 연결을 유지해야 한다.

## 외부 파일 동기화

`EditorTabManager`가 열린 문서 전체의 감시 수명을 소유한다. 파일과 부모 디렉터리의 vnode 감시, `NSFilePresenter`, 앱 활성화·잠자기 복귀 및 5초 보완 검사를 함께 사용한다. 이벤트 후 백그라운드에서 완전한 본문을 읽고 탭 ID·요청 ID·기준본을 재검증한다. 원자적 파일 교체 후 감시는 다시 연결한다. `EditorContainerView`는 확인된 본문 갱신 알림만 화면에 적용한다.

깨끗한 문서는 외부본을 반영한다. 양쪽이 수정되면 기준본과 앱 초안을 그대로 유지하고 조용히 충돌 상태로 둔다. 삭제되면 사이드바에서는 사라지지만 열린 본문은 유지하고 탭 제목에는 취소선을 표시한다. 자동 저장은 충돌·삭제 파일을 쓰지 않는다. 명시적 저장에서만 다른 이름 저장을 제안하며, 복사 저장은 기존 경로를 덮어쓰지 않는 배타적 생성이다. 충돌·삭제 탭을 닫으면 질문 없이 버리되 실제 닫기가 완료된 뒤 복구 세션을 동기 저장한다. 종료의 승인된 버리기 항목도 복원 목록에서 제외한다. 읽기 실패는 삭제로 간주하지 않는다.

`tests/storage_regression.py`는 실제 임시 파일의 원자적 교체·직접 쓰기·비활성 탭·삭제·충돌·복사 저장·닫기 후 복구를 검증한다. 외부 쓰기는 강제 잠그지 않으며 비협조 writer와 최종 비교/교체 사이의 경쟁을 완전히 제거하는 계약은 아니다.

## 텍스트 엔진과 Undo

구조는 [TextEngine](TextEngine/claude.md)에 있다. `TextlinkEditorRepresentable.Coordinator`가 문서 ID별 `NativeManuscriptTextView`를 보관한다. 각 NSTextView는 독립 UndoManager를 사용하며 탭 전환에서 이력을 유지하고, 닫힌 탭의 캐시는 해제한다. 디스크 새 버전이나 외부 본문 교체는 네이티브 본문을 다시 로드하고 이력을 초기화한다. Undo 스택 자체를 세션에 영속 저장하는 것은 아니다.

찾기·바꾸기와 서식 명령은 `EditorCommand`를 통해 텍스트·선택·Undo를 함께 바꾼다. 커서·선택 표시의 행 번호와 엔진의 0-based 위치를 혼동하지 않는다.

현재 원고 화면은 `NativeManuscriptView.swift`의 NSTextView와 NSScrollView를 사용한다. AppKit이 단어/행/문서 이동·선택, IME, 클립보드, Undo를 처리한다. `NSTextContentStorage` → `NSTextLayoutManager` → `NSTextContainer`의 TextKit 2 구성을 사용한다. 줄 번호·현재 행 강조는 표시 중인 문단/행 fragment에서 계산한다. 이 경로에서 `NSTextView.layoutManager`에 접근하면 TextKit 1 호환 모드가 켜지므로 사용하지 않는다. 전체 원고의 행 시작 UTF-16 인덱스는 본문 변경 때 갱신하며, 저장 형식은 기존 문자열/원고 파일 계약을 유지한다. `tests/native_editor_regression.py`는 네이티브 명령과 합성 대용량 문서 비용을, `tests/editor_binding_regression.py`는 문서 귀속을 검증한다. 기존 Core Text 뷰는 비교·회귀용 소스로 남아 있으며 원고 화면에는 연결되지 않는다.

부가 표시의 fragment 순회는 좌표뿐 아니라 `viewportRange`의 텍스트 끝 위치로 제한한다. 미배치 fragment는 좌표가 0일 수 있으므로 건너뛰며 계속 순회하면 문서 끝까지 객체를 생성한다. 화면 밖 커서의 강조 좌표도 조회하지 않는다. 네이티브 회귀 검사는 10만 줄의 연속 스크롤·역방향 점프에서 부가 조회가 만드는 fragment 수를 제한해 이 경계를 검증한다.

너비 변경은 즉시 줄바꿈하되 기존 viewport의 텍스트 위치와 화면 내 오프셋을 유지한다. 이전 픽셀 좌표로 문서 뒤쪽을 재탐색하지 않도록 공개 `relocateViewport` API를 사용한다. SwiftUI의 크기·툴바 갱신에서는 마지막으로 받은 본문과 revision이 같으면 네이티브 전체 문자열을 읽지 않는다. `tests/native_resize_regression.py`는 10만 줄의 앞·중간·뒤에서 연속 너비 변경, 표시 문단·선택 유지, IME와 Undo를 검증한다.

## 에디터와 앱 UI의 작업 분리

표시 중인 NSTextView와 TextKit 배치는 메인 스레드가 소유한다. 별도 큐는 레이아웃 관리자가 없는 초기 저장소·행 인덱스 준비와 불변 세션 스냅샷의 JSON 인코딩·복구 파일 쓰기를 담당한다. 자동 복구는 직렬 큐에 제출하고, 명시적 세션 저장과 복원은 앞선 쓰기를 기다려 오래된 스냅샷의 역전 저장을 막는다. 종료 경로의 명시적 저장은 완료를 보장하기 위해 기다린다.

본문/커서 캐시는 SwiftUI 관찰에서 제외하고 탭의 수정 표시가 바뀔 때만 탭 배열을 갱신한다. 캐시는 저장·AI 요청 시 명시적으로 읽으며, 원고 binding과 선택 표시의 지연 알림은 최신 세대만 반영한다. 저장용 캐시 갱신은 지연하지 않는다.

행 인덱스는 NSTextStorage 문자 편집 알림에서 변경 문단과 인접 문단만 다시 읽는다. Undo·IME도 같은 경로를 거친다. 이후 행의 숫자 오프셋 이동은 여전히 행 수에 비례하지만 본문 전체를 문자열로 재스캔하지 않는다. `tests/editor_isolation_regression.py`는 유니코드 편집·Undo의 전체 인덱스 대조와 10만 줄에서의 스캔 범위를, `tests/storage_regression.py`는 관찰 분리·백그라운드 저장 중 메인 루프 진행·저장 순서를 검증한다. 이 검사는 실제 앱의 모든 패널 애니메이션이 프레임 손실 없이 동작한다는 증거는 아니다.

## 툴 실행 경계

`EditorToolBridge.swift`는 도구를 본문 편집·표시 설정·탐색·AI 요청으로 분류하고 텍스트/레이아웃/선택에 대한 영향을 선언받는다. 툴바 서식과 찾기·바꾸기는 `execute(EditorCommand)`로, 글꼴·크기·줄간격·자간은 `applyDisplayStyle`로 들어와 같은 브릿지를 거친다. AI 툴바 요청도 명령으로 전달하지만 종료는 요청 전달 완료를 뜻하며 외부 모델의 응답 완료를 뜻하지 않는다. Bold 등의 기존 저장 계약은 마크다운 표기 삽입이다.

브릿지는 식별자별 시작·적용·뷰포트 배치 완료·종료 이벤트를 제공한다. 실제 배치 완료는 `layout()` 이후에만 알리고, 변경 없음은 배치를 생략하며 문서 교체/뷰 분리는 대기 중 종료를 취소한다. 본문 편집의 읽기 전용 검사와 편집/탐색 전 IME 확정도 공통 처리다. 표시 설정은 조합을 유지하고 변경된 속성만 한 저장소 트랜잭션으로 적용해 대체 글꼴을 불필요하게 지우지 않는다. 표시 설정 변경의 스크롤 기준은 커서 줄이다. 화면 안의 커서는 기존 화면 Y 위치를 유지하고, 화면 밖이면 속성 적용 전에 커서 줄을 맨 위로 이동한다. 속성 적용 직후와 첫 후속 레이아웃에서 기준점을 복원하며 문서 교체·뷰 분리 때 폐기한다. 창 너비 변경은 기존 viewport 기준을 유지한다.

새 사용자 도구는 `../Core/EditorToolRegistry.swift`의 `tool(...)`로 ID·이름·분류·영향·실행 처리를 함께 등록한다. 기본 키가 없어도 설정 단축키 목록에 자동 반영된다. 툴바/메뉴는 `.tool(id)`를 사용하며 네이티브 target이 `toolBridge.perform`으로 실행을 감싼다. 버튼에 별도 시작/종료 알림이나 강제 전체 레이아웃을 넣지 않는다. `onEvent`는 관찰용이며 재진입 도구 실행은 취소된다. `tests/editor_tool_regression.py`는 실제 TextKit 2와 10만 줄 fixture에서 이벤트 순서·속성 편집 횟수·Undo·IME·취소를 검증한다. 본문 수정 후 문자열 스냅샷 발행과 저장본 비교는 여전히 문서 크기에 영향을 받는다.

## 버전과 프로젝트 바꾸기

`../Versions/VersionHistoryStore.swift`는 저장 전 본문과 수동 스냅샷을 프로젝트 메타데이터에 보관한다(문서당 최근 30개). 버전 복원은 새 파일 생성으로 원본 덮어쓰기를 피한다. 탭 경로 이동은 버전 기록과 집필 자료 링크도 함께 이동시킨다.

`ProjectReplacementStore.swift`는 디스크 원고의 문자 그대로 바꾸기를 미리보고, 선택한 모든 파일의 기준본을 확인한 후 버전과 작업 저널을 남긴다. 중간 실패의 롤백은 후속 외부 편집을 덮어쓰지 않는다. UI는 미저장 열린 원고를 거부하며, 마지막 작업 되돌리기도 현재 본문 일치를 요구한다. 앱 재실행 후 자동 일괄 Undo를 제공하는 것은 아니다.

## 인라인 AI 공간

원고 우클릭 또는 ⌘⌥I는 `editorInlineAI` 알림으로 `InlineAIChatView`를 설치한다. `NativeManuscriptTextView`의 TextKit 2 delegate가 `ManuscriptLayoutFragment.bottomMargin`으로 선택 문단 아래에 공간을 예약한다. 패널을 열고 닫을 때 해당 fragment의 여백과 레이아웃을 함께 무효화한다. 빈 문서와 마지막 빈 줄의 extra line fragment도 처리한다. 원고 문자열·저장 형식에는 패널 마커를 넣지 않는다. 패널과 미전송 입력은 탭의 네이티브 뷰 수명에만 속하며 외부 본문 교체 시 제거한다. 전송 즉시 패널을 닫고, 지시와 실행 결과는 인라인 편집 기록에 남는다.

## 대용량 원고 로딩

`DocumentFileStore.readInChunks`는 작업 스레드에서 64KB씩 읽고 완전한 UTF-8 본문만 전달한다. `PreparedManuscript`는 문단 경계의 청크마다 대체 글꼴을 미리 계산하고, 레이아웃 관리자가 없는 저장소를 화면에 한 번만 이전한다. 로딩 요청 ID와 문서 ID로 취소된 탭의 결과를 버리며 로딩 중에는 저장과 편집 캐시 갱신을 막는다. 전체 논리 문서는 네이티브 선택·Undo·저장을 위해 유지하며 디스크 페이지 편집기는 아니다. 준비된 저장소는 `NSTextContentStorage.textStorage`에 연결한다. 화면의 배치·캐시는 TextKit 2의 viewport controller가 담당하며 전체 문서 `ensureLayout`은 호출하지 않는다. `tests/chunked_loading_regression.py`는 취소·UTF-8 경계·백그라운드 준비·저장을 검증한다.
