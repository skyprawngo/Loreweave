# 화면과 입력 연결

`MainEditorView.swift`가 프로젝트 탐색, 탭, 에디터, AI 패널을 연결한다. 종속 뷰는 `MainEditor/`에 있으며 시작·설정·약관은 `WelcomeView`, `SettingsView`, `TermsOfServiceView`에서 찾는다.

원고 화면은 `EditorContainerView` → `EditorPanel/LoreTextView/LoreEditorRepresentable` → `LoreEditorView`/`LoreTextView`로 이어진다. Core Text 행 렌더링은 flipped 좌표계를 사용한다. 스크롤·선택·커서·gutter 변경은 동일한 좌표 기준을 공유해야 한다.

AppKit 입력의 IME 조합 중 문자열 전체 교체는 조합을 깨뜨릴 수 있다. `hasMarkedText`, 조합 확정/취소, first responder와 SwiftUI binding의 갱신 순서를 함께 확인한다. 메뉴 키 동작은 [Core](../Services/Core/claude.md)의 단축키와 responder 경로를 따른다.

색상은 `AppColors`, 투명/불투명 배경은 `ThemeAwareBackground`의 기존 경로를 사용한다. Liquid Glass 사용 가능 여부는 앱 타깃 macOS 26.0 설정과 연결된다. 고정 UI 치수 목록보다 변경 주변 화면의 현재 컴포넌트를 기준으로 맞춘다.
