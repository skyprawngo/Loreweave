# 탭과 원고 저장

`EditorTabManager.swift`는 URL별 `TabEditState`에 편집 텍스트, 저장본(`originalContent`), 0-based 커서를 보관한다. 수정 여부는 두 텍스트의 비교로 계산하며 저장 성공 시 저장본을 갱신한다. 화면의 저장 상태도 이 결과를 사용한다.

## 저장·복구 경계

원고 쓰기는 `FileSystem/DocumentFileStore.swift`의 신규 생성/기준본 비교 저장을 거친다. 닫기·전환·삭제는 먼저 에디터를 flush하고 저장/버리기/취소를 결정한다. 버리기 승인만으로 캐시를 지우지 않으며, 후속 파일 작업 실패 시 초안을 유지한다.

앱의 Application Support/TextlinkEditor/Recovery에 프로젝트 경로별 복구 사본을 먼저 저장하고, `.{projectName}.weavedata/editor-session.json`에도 프로젝트 내부 탭을 저장한다. 탭·커서와 수정 중 `draftContent`·`baseContent`를 포함한다. 프로젝트 밖으로 다른 이름 저장한 탭의 `externalURL`은 앱 소유 복구 사본에서만 복원하며 프로젝트가 제공하는 절대 경로는 신뢰하지 않는다. 변경 후 0.5초 지연 저장이므로 갑작스러운 종료 직전 입력까지 보장하는 저널은 아니다. 복원 실패 시 원본 세션의 별도 사본 보존을 시도하고 오류를 알린다. 이것은 편집 초안 복구이며 전체 프로젝트의 장기 버전 백업은 아니다. 글꼴 등 프로젝트 설정은 같은 폴더의 `editor-settings.json`에 있다.

파일 이동·이름 변경은 탭 ID를 유지하면서 URL·편집 캐시·저장 상태를 함께 옮긴다. `EditorContainerView`와 `TextlinkEditorRepresentable`은 문서 ID·URL·내용 revision으로 지연된 binding 갱신의 귀속을 확인한다. IME 확정 결과를 이전 URL로 돌려주는 연결을 유지해야 한다.

## 텍스트 엔진과 Undo

구조는 [TextEngine](TextEngine/claude.md)에 있다. `TextlinkEditorRepresentable.Coordinator`가 문서 ID별 `NativeManuscriptTextView`를 보관한다. 각 NSTextView는 독립 UndoManager를 사용하며 탭 전환에서 이력을 유지하고, 닫힌 탭의 캐시는 해제한다. 디스크 새 버전이나 외부 본문 교체는 네이티브 본문을 다시 로드하고 이력을 초기화한다. Undo 스택 자체를 세션에 영속 저장하는 것은 아니다.

찾기·바꾸기와 서식 명령은 `EditorCommand`를 통해 텍스트·선택·Undo를 함께 바꾼다. 커서·선택 표시의 행 번호와 엔진의 0-based 위치를 혼동하지 않는다.

현재 원고 화면은 `NativeManuscriptView.swift`의 NSTextView와 NSScrollView를 사용한다. AppKit이 단어/행/문서 이동·선택, IME, 클립보드, Undo를 처리한다. NSLayoutManager의 비연속 레이아웃을 사용하고 줄 번호는 표시 영역만 그린다. 전체 원고의 행 시작 UTF-16 인덱스는 본문 변경 때 갱신하며, 저장 형식은 기존 문자열/원고 파일 계약을 유지한다. `tests/native_editor_regression.py`는 네이티브 명령과 합성 대용량 문서 비용을, `tests/editor_binding_regression.py`는 문서 귀속을 검증한다. 기존 Core Text 뷰는 비교·회귀용 소스로 남아 있으며 원고 화면에는 연결되지 않는다.

## 버전과 프로젝트 바꾸기

`../Versions/VersionHistoryStore.swift`는 저장 전 본문과 수동 스냅샷을 프로젝트 메타데이터에 보관한다(문서당 최근 30개). 버전 복원은 새 파일 생성으로 원본 덮어쓰기를 피한다. 탭 경로 이동은 버전 기록과 집필 자료 링크도 함께 이동시킨다.

`ProjectReplacementStore.swift`는 디스크 원고의 문자 그대로 바꾸기를 미리보고, 선택한 모든 파일의 기준본을 확인한 후 버전과 작업 저널을 남긴다. 중간 실패의 롤백은 후속 외부 편집을 덮어쓰지 않는다. UI는 미저장 열린 원고를 거부하며, 마지막 작업 되돌리기도 현재 본문 일치를 요구한다. 앱 재실행 후 자동 일괄 Undo를 제공하는 것은 아니다.

## 인라인 AI 공간

원고 우클릭 또는 ⌘⌥I는 `editorInlineAI` 알림으로 `InlineAIChatView`를 설치한다. `NativeManuscriptTextView`의 layout delegate가 해당 표시 행 아래에 공간을 예약한다. 원고 문자열·저장 형식에는 패널 마커를 넣지 않는다. 패널과 미전송 입력은 탭의 네이티브 뷰 수명에만 속하며 외부 본문 교체 시 제거한다. 전송 즉시 패널을 닫고, 지시와 실행 결과는 인라인 편집 기록에 남는다.
