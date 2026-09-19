//
//  FileSystemItem.swift
//  TextlinkEditor
//
//  파일 시스템 항목 모델 (파일/폴더)
//

import Foundation

/// 파일 시스템 항목 (파일 또는 폴더)
@Observable
final class FileSystemItem: Identifiable, Hashable {
    let id: UUID
    let url: URL
    var name: String
    let isDirectory: Bool
    var children: [FileSystemItem]?
    /// 디렉터리를 펼치지 않아도 표시할 직접 하위 폴더/파일 수
    var childFolderCount: Int = 0
    var childFileCount: Int = 0
    var isExpanded: Bool
    var customFolderIcon: String?

    /// 부모 항목 (약한 참조로 순환 참조 방지)
    weak var parent: FileSystemItem?

    /// 섹션 타입 캐시 (초기화 시 한 번만 계산)
    let sectionType: ProjectSection?

    init(url: URL, isDirectory: Bool, parent: FileSystemItem? = nil) {
        self.id = UUID()
        self.url = url
        self.name = url.lastPathComponent
        self.isDirectory = isDirectory
        self.parent = parent
        self.isExpanded = false
        self.children = isDirectory ? [] : nil
        // 섹션 타입은 초기화 시 한 번만 계산
        self.sectionType = isDirectory ? ProjectSection.from(folderName: url.lastPathComponent) : nil
    }

    // MARK: - Hashable

    static func == (lhs: FileSystemItem, rhs: FileSystemItem) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // MARK: - Computed Properties

    /// 파일 확장자
    var fileExtension: String {
        url.pathExtension.lowercased()
    }

    /// 아이콘 이름 (SF Symbols)
    var iconName: String {
        if isDirectory {
            if let customFolderIcon { return customFolderIcon }
            // 섹션 폴더인 경우 전용 아이콘 사용 (캐시된 값 사용)
            if let section = sectionType {
                return section.iconName
            }
            return isExpanded ? "folder.fill" : "folder"
        }

        switch fileExtension {
        case "md", "markdown":
            return "doc.text"
        case "txt":
            return "doc.plaintext"
        case "json":
            return "curlybraces"
        case "png", "jpg", "jpeg", "gif", "webp":
            return "photo"
        case "pdf":
            return "doc.richtext"
        default:
            return "doc"
        }
    }

    /// 섹션 폴더 여부 (캐시된 값 사용)
    var isSection: Bool {
        sectionType != nil
    }

    /// 하위 항목 개수 (폴더인 경우만)
    var childCount: Int {
        childFolderCount + childFileCount
    }

    /// 상대 경로 (프로젝트 루트 기준)
    func relativePath(from rootURL: URL) -> String {
        let rootPath = rootURL.path
        let itemPath = url.path

        if itemPath.hasPrefix(rootPath) {
            let relativePath = String(itemPath.dropFirst(rootPath.count))
            return relativePath.hasPrefix("/") ? String(relativePath.dropFirst()) : relativePath
        }
        return name
    }

    /// 자식 항목 정렬 (폴더 우선, 이름 순)
    func sortChildren() {
        children?.sort { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    /// 자식 항목 중 특정 URL 찾기
    func findChild(with url: URL) -> FileSystemItem? {
        if self.url == url { return self }

        guard let children = children else { return nil }

        for child in children {
            if child.url == url { return child }
            if let found = child.findChild(with: url) {
                return found
            }
        }
        return nil
    }

    /// 모든 자손 항목 평탄화
    func flattenedDescendants() -> [FileSystemItem] {
        var result = [FileSystemItem]()
        if let children = children {
            for child in children {
                result.append(child)
                result.append(contentsOf: child.flattenedDescendants())
            }
        }
        return result
    }
}

// MARK: - 프로젝트 섹션 폴더 타입

/// .weaveproj 프로젝트의 표준 섹션 폴더
enum ProjectSection: String, CaseIterable {
    case manuscripts
    case settings
    case characters
    case plot
    case scenes
    case research

    /// 로컬라이즈된 폴더 이름
    var localizedFolderName: String {
        switch self {
        case .manuscripts: return L10n.get("folder.manuscripts")
        case .settings: return L10n.get("folder.settings")
        case .characters: return L10n.get("folder.characters")
        case .plot: return L10n.get("folder.plot")
        case .scenes: return L10n.get("folder.scenes")
        case .research: return L10n.get("folder.research")
        }
    }

    /// 아이콘 이름 (SF Symbols)
    var iconName: String {
        switch self {
        case .manuscripts: return "doc.text"
        case .settings: return "globe.asia.australia"
        case .characters: return "person.2"
        case .plot: return "arrow.triangle.branch"
        case .scenes: return "rectangle.split.3x3"
        case .research: return "book"
        }
    }

    /// 모든 언어의 표준 폴더 이름 목록
    static var allLocalizedNames: [String] {
        return [
            // Korean template
            "원고", "설정", "인물", "플롯", "장면", "자료",
            // English template
            "Manuscripts", "Settings", "Characters", "Plot", "Scenes", "Research",
            // Japanese template
            "原稿", "設定", "登場人物", "プロット", "シーン", "資料"
        ]
    }

    /// 폴더 이름 → 섹션 타입 매핑 (O(1) 룩업)
    private static let folderNameMapping: [String: ProjectSection] = [
        // Korean template
        "원고": .manuscripts, "설정": .settings, "인물": .characters, "플롯": .plot,
        "장면": .scenes, "자료": .research,
        // English template (case-insensitive lookup)
        "manuscripts": .manuscripts, "settings": .settings, "characters": .characters,
        "plot": .plot, "scenes": .scenes, "research": .research,
        // Japanese template
        "原稿": .manuscripts, "設定": .settings, "登場人物": .characters, "プロット": .plot,
        "シーン": .scenes, "資料": .research
    ]

    /// 폴더 이름으로부터 섹션 타입 추론 (모든 언어 지원)
    static func from(folderName: String) -> ProjectSection? {
        // 먼저 원본으로 시도 (한국어, 일본어)
        if let section = folderNameMapping[folderName] {
            return section
        }
        // 영어는 소문자로 변환 후 시도
        return folderNameMapping[folderName.lowercased()]
    }
}
