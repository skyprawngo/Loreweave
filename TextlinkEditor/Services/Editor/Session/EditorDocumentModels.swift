import Foundation

// MARK: - Tab State (저장용)

/// 탭 상태 저장을 위한 Codable 구조체
struct TabState: Codable {
    let relativePath: String  // 프로젝트 폴더 기준 상대 경로
    let isModified: Bool
    let cursorLine: Int       // 커서 행 위치
    let cursorColumn: Int     // 커서 열 위치
    var draftContent: String?
    var baseContent: String?
    var externalURL: URL?

    init(relativePath: String, isModified: Bool = false, cursorLine: Int = 0, cursorColumn: Int = 0) {
        self.relativePath = relativePath
        self.isModified = isModified
        self.cursorLine = cursorLine
        self.cursorColumn = cursorColumn
    }
}

/// 에디터 세션 상태 (탭 목록 + 선택된 탭)
struct EditorSessionState: Codable {
    let tabs: [TabState]
    let selectedTabIndex: Int

    init(tabs: [TabState], selectedTabIndex: Int) {
        self.tabs = tabs
        self.selectedTabIndex = selectedTabIndex
    }
}

/// 프로젝트별 에디터 설정 (폰트, 크기, 줄간격)
struct ProjectEditorSettings: Codable {
    var fontName: String
    var fontSize: CGFloat
    var lineSpacing: CGFloat  // 표시 비율: 100% = 1.0, 렌더링 시 기준 배율 적용

    init(fontName: String = "SF Pro", fontSize: CGFloat = 14.0, lineSpacing: CGFloat = 1.0) {
        self.fontName = fontName
        self.fontSize = fontSize
        self.lineSpacing = lineSpacing
    }

    /// UserSettings의 기본값에서 생성
    static func fromUserSettings() -> ProjectEditorSettings {
        ProjectEditorSettings(
            fontName: UserSettings.shared.editorFontName,
            fontSize: UserSettings.shared.editorFontSize,
            lineSpacing: UserSettings.shared.editorLineSpacing
        )
    }
}

/// 에디터에서 열린 파일 탭
struct EditorTab: Identifiable, Equatable {
    let id: UUID
    var fileItem: FileSystemItem
    var isModified: Bool
    /// 방금 저장됨 표시 (애니메이션용)
    var justSaved: Bool = false
    var diskState: DocumentDiskState = .current

    var title: String {
        fileItem.name
    }

    var url: URL {
        fileItem.url
    }

    /// 파일이 디스크에 존재하는지 확인
    var fileExists: Bool {
        diskState != .missing
    }

    init(fileItem: FileSystemItem, isModified: Bool = false) {
        self.id = UUID()
        self.fileItem = fileItem
        self.isModified = isModified
    }

    static func == (lhs: EditorTab, rhs: EditorTab) -> Bool {
        lhs.id == rhs.id
    }
}

/// 탭별 편집 상태를 통합 관리하는 구조체
struct TabEditState {
    /// 편집 중인 텍스트
    var content: String
    /// 디스크에 저장된 원본 내용 (수정 여부 판단 기준)
    var originalContent: String
    /// 커서 위치 (line, column)
    var cursorPosition: (line: Int, column: Int)

    /// 수정 여부 (content와 originalContent 비교)
    var isModified: Bool {
        content != originalContent
    }

    init(content: String = "", originalContent: String = "", cursorPosition: (line: Int, column: Int) = (0, 0)) {
        self.content = content
        self.originalContent = originalContent
        self.cursorPosition = cursorPosition
    }

    /// 저장 완료 후 호출 - originalContent를 현재 content로 업데이트
    mutating func markAsSaved() {
        originalContent = content
    }
}

enum DocumentDiskState: Equatable {
    case current, conflict, missing, unreadable
    var requiresCopy: Bool { self == .conflict || self == .missing }
}

