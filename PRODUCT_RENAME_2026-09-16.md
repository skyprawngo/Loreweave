# TextlinkEditor 이름 변경

앱 표시명, 앱 진입점, Commands 및 에디터 타입, 소스 디렉토리, Xcode 프로젝트·타깃·스킴·제품, entitlement 파일명, 번역·문서·테스트 참조를 TextlinkEditor로 변경했다. 새 Bundle ID는 `com.textlinkeditor.app`이다. 개발자 계정에 App ID를 등록하거나 서명 인증서를 변경한 것은 아니다.

루트 작업 폴더 `/Users/skyprawngo/Documents/Coding/Loreweave`는 요청대로 유지했다. 추후 이 폴더를 옮긴 뒤 `TextlinkEditor.xcodeproj`를 열면 된다. 테스트와 빌드는 저장소 기준 상대 경로를 사용한다. 과거 보고서의 실제 루트 절대 경로는 현재 위치를 유지한다.

기존 원고 포맷인 `.weaveproj`와 `.weavedata`는 변경하지 않았다. 이름 변경 때문에 기존 프로젝트의 형식을 바꾸지 않는다.

기존 사용자 데이터 연결용 식별자는 의도적으로 유지한다:
- `com.loreweave.settings`: 앱 설정
- Application Support의 `Loreweave/Recovery`: 복구 초안
- Application Support의 `Loreweave` 내 단축키 파일
- `Loreweave/OpenAI`: 기존 AI 인증 저장소. 인증 저장 경로는 키체인 계정 식별과 연결될 수 있으므로 임의로 옮기지 않는다.
- 첫 실행 시 `com.loreweave.app`의 기존 기본 설정을 새 앱 도메인의 없는 키로 복사한다. 기존 도메인은 삭제하지 않는다.

이 항목들은 화면에 표시되는 앱 이름이 아니라 호환성을 위한 저장 식별자다. iCloud 컨테이너 연결, TextLinkViewer 병합, 루트 폴더 이동은 이번 변경에 포함하지 않았다.
