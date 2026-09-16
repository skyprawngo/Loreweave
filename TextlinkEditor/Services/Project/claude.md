# 프로젝트 형식과 접근 수명

`ProjectManager.swift`와 `Models/Project.swift`가 `.weaveproj` 폴더 및 메타데이터를 다룬다.

```text
MyProject.weaveproj/
├── .MyProject.weavedata/
│   ├── project.json
│   ├── editor-settings.json
│   └── ai-sessions/
└── 원고와 섹션 폴더
```

프로젝트 생성 때 섹션 폴더 이름은 `folder.*` 번역으로 정해진다. 이후 언어 변경이 기존 폴더명을 바꾼다고 가정하지 않는다.

숨김 데이터 폴더명은 프로젝트 파일명에서 계산되며 Editor와 AI 서비스에도 경로 계산이 있다. 이름 변경이나 저장 형식 수정은 이 참조들과 기존 데이터 호환성을 함께 살핀다.

열기·닫기는 bookmark 접근, 최근/마지막 프로젝트와 연결된다. `openProjectFromFile`, `openProject`, `closeProject`와 메인 화면의 탭/AI 전환 호출을 함께 추적한다. `deleteProject`처럼 UI 이름과 다른 의미를 가질 수 있는 작업은 구현에서 실제 파일 삭제 여부를 확인한다.
