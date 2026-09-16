# NSTextView 에디터 전환

원고 화면의 `TextlinkEditorRepresentable`을 `NativeManuscriptHost` / `NativeManuscriptTextView`에 연결했다. 외부 패키지 없이 Apple AppKit의 NSTextView를 사용한다. 일반 키 입력·단어/행/문서 이동과 선택·IME·클립보드는 AppKit이 처리한다. 기본 편집 메뉴의 Undo/Redo selector를 문서별 UndoManager에 연결한다.

TextKit 1의 NSLayoutManager 비연속 레이아웃을 명시적으로 사용한다. 줄 번호는 NSRulerView에서 보이는 영역만 그리며, 행 시작 UTF-16 인덱스로 커서 위치를 기존 행/문자 단위 계약에 변환한다. 기존 Core Text 뷰 소스는 회귀 비교용으로 남아 있으나 원고 화면에서 생성하지 않는다. 사용자가 설정하는 행 이동/복제 명령은 기존 연산을 네이티브 편집에 연결한다.

문서 ID별 편집기와 Undo를 보관하고 닫힌 탭의 캐시는 해제한다. 같은 ID의 이름 변경은 이력을 유지하고 외부 본문 교체는 이전 Undo를 비운다. 문서 ID·URL·revision 검증, 파일 작업 전 조합 확정/flush, 기존 원고 저장·복구 경로는 유지한다. SwiftUI 문자열 binding 계약 때문에 본문 변경 때 문자열 전달과 행 인덱스 갱신은 남아 있다.

## 확인한 범위

- macOS Debug 빌드 성공: `/tmp/textlinkeditor-native-derived/Build/Products/Debug/TextlinkEditor.app`.
- `tests/editor_binding_regression.py`: 탭별 Undo, 이름 변경, 조합 중 텍스트 flush, 오래된 callback/명령 차단, 외부 revision, 읽기 실패 보호, 선택 상태 전달 통과.
- `tests/native_editor_regression.py`: 단어 이동/선택, 행/문서 끝 선택, 이모지 이동, 네이티브 Undo selector, 서식과 전체 치환 Undo, CRLF/마지막 빈 행, 읽기 전용 보호 통과.
- `tests/storage_regression.py`: 기존 저장/복구 회귀 통과.
- 실행 앱의 QA 프로젝트에서 Option+Shift+Right의 실제 단어 선택, Cmd+Z / Cmd+Shift+Z, 다른 탭으로 갔다 돌아온 뒤 Undo, 수정 후 Cmd+S와 실제 파일 바이트 일치를 확인했다. `native-editor-validation.md`는 검증 후 최초 텍스트로 복원하고 저장했다.
- 실행 앱에서 100,000줄 원고를 열고 Cmd+Down으로 마지막 행에 도달하는 것을 확인했다.

최적화된 독립 네이티브 테스트의 합성 100,000줄에서 로드/행 인덱스 약 21ms, 첫 viewport 레이아웃 약 11ms, 끝 이동 약 10ms였다. 이는 파일 I/O, 앱 전체 업데이트, 실제 화면 표시와 프레임 속도를 포함하는 수치가 아니다. 장시간 편집/트랙패드 스크롤, 실제 한글 입력기의 모든 조합 시나리오, 음성 입력·접근성 전체 기능은 전수 검증하지 않았다.
