# 탭과 원고 저장

`EditorTabManager.swift`는 URL별 `TabEditState`에 편집 텍스트, 저장본(`originalContent`), 0-based 커서를 보관한다. 수정 여부는 두 텍스트의 비교로 계산하며 저장 성공 시 저장본을 갱신한다. 화면의 저장 상태도 이 결과를 사용한다.

## 저장·복구 경계

원고 쓰기는 `FileSystem/DocumentFileStore.swift`의 신규 생성/기준본 비교 저장을 거친다. 닫기·전환·삭제는 먼저 에디터를 flush하고 저장/버리기/취소를 결정한다. 버리기 승인만으로 캐시를 지우지 않으며, 후속 파일 작업 실패 시 초안을 유지한다.

앱의 Application Support/Loreweave/Recovery에 프로젝트 경로별 복구 사본을 먼저 저장하고, `.{projectName}.weavedata/editor-session.json`에도 프로젝트 내부 탭을 저장한다. 탭·커서와 수정 중 `draftContent`·`baseContent`를 포함한다. 프로젝트 밖으로 다른 이름 저장한 탭의 `externalURL`은 앱 소유 복구 사본에서만 복원하며 프로젝트가 제공하는 절대 경로는 신뢰하지 않는다. 변경 후 0.5초 지연 저장이므로 갑작스러운 종료 직전 입력까지 보장하는 저널은 아니다. 복원 실패 시 원본 세션의 별도 사본 보존을 시도하고 오류를 알린다. 이것은 편집 초안 복구이며 전체 프로젝트의 장기 버전 백업은 아니다. 글꼴 등 프로젝트 설정은 같은 폴더의 `editor-settings.json`에 있다.

파일 이동·이름 변경은 탭 ID를 유지하면서 URL·편집 캐시·저장 상태를 함께 옮긴다. `EditorContainerView`와 `LoreEditorRepresentable`은 문서 ID·URL·내용 revision으로 지연된 binding 갱신의 귀속을 확인한다. IME 확정 결과를 이전 URL로 돌려주는 연결을 유지해야 한다.

## 텍스트 엔진과 Undo

구조는 [TextEngine](TextEngine/claude.md)에 있다. `LoreEditorRepresentable.Coordinator`가 문서 ID별 `EditorState`를 보관해 같은 편집 화면 안의 탭 전환에서 Undo를 유지한다. 디스크 새 버전이나 외부 본문 교체는 `loadText`로 이력을 초기화한다. Undo 스택 자체를 세션에 영속 저장하는 것은 아니다.

찾기·바꾸기와 서식 명령은 `EditorCommand`를 통해 텍스트·선택·Undo를 함께 바꾼다. 커서·선택 표시의 행 번호와 엔진의 0-based 위치를 혼동하지 않는다.
