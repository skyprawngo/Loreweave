import Foundation

/// Sidebar-only appearance. Keys are project-relative folder paths, never manuscript contents.
struct FolderAppearanceStore {
    let projectURL: URL

    private var fileURL: URL {
        let name = projectURL.deletingPathExtension().lastPathComponent
        return projectURL.appendingPathComponent(".\(name).weavedata/folder-icons.json")
    }

    func pathKey(for url: URL) throws -> String {
        let root = projectURL.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        // The folder itself may already have moved. Resolve its surviving parent,
        // so aliases such as /var and /private/var yield the same key after rename.
        let standardized = url.standardizedFileURL
        let components = standardized.deletingLastPathComponent().resolvingSymlinksInPath()
            .appendingPathComponent(standardized.lastPathComponent).pathComponents
        guard components.count > root.count, components.starts(with: root) else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        return components.dropFirst(root.count).joined(separator: "/")
            .precomposedStringWithCanonicalMapping
    }

    func load() throws -> [String: String] {
        do {
            return try JSONDecoder().decode([String: String].self, from: Data(contentsOf: fileURL))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return [:]
        }
    }

    func setIcon(_ icon: FolderIcon?, for url: URL) throws {
        let key = try pathKey(for: url)
        guard try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        var icons = try load()
        icons[key] = icon?.rawValue
        try save(icons)
    }

    /// Called only after a successful disk move/copy; carries descendant overrides too.
    func relocate(from source: URL, to destination: URL, copying: Bool = false) throws {
        let oldKey = try pathKey(for: source)
        let newKey = try pathKey(for: destination)
        var icons = try load()
        let affected = icons.filter { $0.key == oldKey || $0.key.hasPrefix(oldKey + "/") }
        guard !affected.isEmpty else { return }
        for (key, icon) in affected {
            if !copying { icons.removeValue(forKey: key) }
            icons[newKey + key.dropFirst(oldKey.count)] = icon
        }
        try save(icons)
    }

    func remove(for url: URL) throws {
        let key = try pathKey(for: url)
        let original = try load()
        let icons = original.filter { $0.key != key && !$0.key.hasPrefix(key + "/") }
        if icons.count != original.count { try save(icons) }
    }

    private func save(_ icons: [String: String]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(icons).write(to: fileURL, options: .atomic)
    }
}

/// Curated SF Symbols shared by the picker and persisted appearance validation.
enum FolderIcon: String, CaseIterable, Identifiable {
    case folder, book, doc = "doc.text", people = "person.2", globe = "globe.asia.australia"
    case idea = "lightbulb", plot = "arrow.triangle.branch", storyboard = "rectangle.split.3x3"
    case star, heart, flag, tag, archive = "archivebox", photo, music = "music.note", film

    var id: String { rawValue }
    var title: String { L10n.get("folderOptions.icon.\(rawValue)") }
}
