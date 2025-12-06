//
//  FileSystemItem.swift
//  Loreweave
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
    var isExpanded: Bool

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
        children?.count ?? 0
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
    case worldbuilding
    case characters
    case plot
    case storyboard
    case editor
    case ideas

    /// 로컬라이즈된 폴더 이름
    var localizedFolderName: String {
        switch self {
        case .worldbuilding: return L10n.get("folder.worldbuilding")
        case .characters: return L10n.get("folder.characters")
        case .plot: return L10n.get("folder.plot")
        case .storyboard: return L10n.get("folder.storyboard")
        case .editor: return L10n.get("folder.editor")
        case .ideas: return L10n.get("folder.ideas")
        }
    }

    /// 아이콘 이름 (SF Symbols)
    var iconName: String {
        switch self {
        case .worldbuilding: return "globe.asia.australia"
        case .characters: return "person.2"
        case .plot: return "arrow.triangle.branch"
        case .storyboard: return "rectangle.split.3x3"
        case .editor: return "doc.text"
        case .ideas: return "lightbulb"
        }
    }

    /// 모든 언어의 폴더 이름 목록 (기존 프로젝트 인식용)
    static var allLocalizedNames: [String] {
        // 모든 언어에서 사용되는 폴더 이름들
        return [
            // Korean
            "세계관", "캐릭터", "플롯", "콘티", "에디터", "아이디어",
            // English
            "Worldbuilding", "Characters", "Plot", "Storyboard", "Editor", "Ideas",
            // Japanese
            "世界観", "キャラクター", "プロット", "コンテ", "エディター", "アイデア"
        ]
    }

    /// 폴더 이름 → 섹션 타입 매핑 (O(1) 룩업)
    private static let folderNameMapping: [String: ProjectSection] = [
        // Korean
        "세계관": .worldbuilding, "캐릭터": .characters, "플롯": .plot,
        "콘티": .storyboard, "에디터": .editor, "아이디어": .ideas,
        // English (lowercase)
        "worldbuilding": .worldbuilding, "characters": .characters, "plot": .plot,
        "storyboard": .storyboard, "editor": .editor, "ideas": .ideas,
        // Japanese
        "世界観": .worldbuilding, "キャラクター": .characters, "プロット": .plot,
        "コンテ": .storyboard, "エディター": .editor, "アイデア": .ideas
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
