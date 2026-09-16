# 서비스 경계

| 영역 | 소유하는 상태·작업 |
|---|---|
| [Core](Core/claude.md) | 권한, 전역 설정, 테마, 단축키와 responder 연동 |
| [Project](Project/claude.md) | 프로젝트 메타데이터, 열기·닫기, 접근 수명 |
| [FileSystem](FileSystem/claude.md) | 디렉토리 트리, 파일 작업, 외부 변경 감시 |
| [Editor](Editor/claude.md) | 열린 탭, 편집 캐시, 저장과 텍스트 엔진 |
| [AI](AI/claude.md) | CLI 프로세스, 프롬프트, 프로젝트별 대화 기록 |

프로젝트 전환·파일 경로 변경은 여러 서비스의 상태를 건드린다. 서비스를 추가하기 전에 해당 상태의 기존 소유자를 확인한다.
