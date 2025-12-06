# 단축키 기능 구현 체크리스트

## 1. 시스템 기본 기능 처리
- [x] 편집 카테고리(undo, redo, cut, copy, paste, selectAll) 토글 제거 및 "macOS 기본 기능" 표시

## 2. 에디터 UI 변경
- [x] 폰트 크기 +-버튼 → 슬라이더로 변경
- [x] 줄바꿈 폭 슬라이더 → 드롭다운 메뉴 (80%, 100%, 125%, 150%, 200%)
- [ ] .canvas 파일 확장자 인식 및 줌 레벨 지원 준비

## 3. 찾기/바꾸기 기능
- [x] FindReplaceView 생성 (에디터 상단 슬라이드 다운)
- [x] 찾기 범위 설정 (프로젝트 전체, 열린 탭, 현재 파일)
- [x] 찾기 기능 구현
- [x] 바꾸기 기능 구현
- [x] 단축키 연동 (⌘F, ⌘⌥F)

## 4. 파일 관련 단축키
- [x] newFile: 새 파일 생성
- [x] newFolder: 새 폴더 생성
- [ ] openFile: 파일 열기 다이얼로그
- [x] save: 현재 탭 저장
- [ ] saveAs: 다른 이름으로 저장
- [x] closeTab: 현재 탭 닫기
- [x] closeAllTabs: 모든 탭 닫기

## 5. 보기 관련 단축키
- [x] toggleSidebar: 사이드바 토글
- [x] toggleAIPanel: AI 패널 토글
- [x] zoomIn: 확대 (메뉴 연동)
- [x] zoomOut: 축소 (메뉴 연동)
- [x] resetZoom: 기본값으로 초기화 (메뉴 연동)

## 6. 탭 관련 단축키
- [x] nextTab: 다음 탭
- [x] previousTab: 이전 탭
- [x] goToTab1~9: 특정 탭으로 이동

## 7. 프로젝트 관련 단축키
- [x] openProject: 프로젝트 열기 (메뉴 연동)
- [ ] newProject: 새 프로젝트
- [x] refreshProject: 프로젝트 새로고침

## 8. AI 관련 단축키 (보류)
- [ ] aiContinueWriting
- [ ] aiRefine
- [ ] aiSummarize

---
*이 파일은 기능 구현 완료 후 삭제됩니다.*
