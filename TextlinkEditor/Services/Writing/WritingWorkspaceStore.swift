import Foundation

struct WritingScene: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var title = "새 장면"
    var manuscriptPath = ""
    var viewpoint = ""
    var characters: String? = nil
    var place = ""
    var summary = ""
    var status = "초고"
    var includedInExport = true
    var characterGoal = 0
}

struct WritingLoreEntry: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var name = "새 설정"
    var kind = "인물"
    var aliases = ""
    var body = ""
    var manuscriptPath = ""
    var includeInAI = false
    /// Empty means available from the beginning. IDs survive scene reordering.
    var revealedFromSceneID: UUID?
    var knownBy = ""
}

struct WritingWorkspaceDocument: Codable, Equatable, Sendable {
    var version = 1
    var scenes: [WritingScene] = []
    var lore: [WritingLoreEntry] = []

    mutating func removeScene(id: UUID) throws {
        guard !lore.contains(where: { $0.revealedFromSceneID == id }) else { throw WritingWorkspaceError.referencedScene }
        scenes.removeAll { $0.id == id }
    }

    mutating func removeLore(id: UUID) {
        lore.removeAll { $0.id == id }
    }
}

struct WritingMetrics: Equatable {
    let characters: Int
    let nonWhitespaceCharacters: Int
    let words: Int
    init(_ text: String) {
        characters = text.count
        nonWhitespaceCharacters = text.filter { !$0.isWhitespace }.count
        words = text.split(whereSeparator: { $0.isWhitespace }).count
    }
}

enum WritingWorkspaceError: LocalizedError {
    case unsafePath, invalidDocument, missingManuscript(String), archiveFailed, noScenes, referencedScene
    var errorDescription: String? {
        switch self {
        case .unsafePath: return L10n.get("writing.ui.60")
        case .invalidDocument: return L10n.get("writing.ui.61")
        case .missingManuscript(let path): return String(format: L10n.get("writing.error.missingManuscript"), path)
        case .archiveFailed: return L10n.get("writing.ui.62")
        case .referencedScene: return L10n.get("writing.error.referencedScene")
        case .noScenes: return L10n.get("writing.ui.63")
        }
    }
}

struct WritingWorkspaceStore: Sendable {
    let projectURL: URL

    func resolve(_ path: String) throws -> URL {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.split(separator: "/").contains(".."), !path.contains("\0") else { throw WritingWorkspaceError.unsafePath }
        let root = projectURL.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = projectURL.appendingPathComponent(path).standardizedFileURL
        let resolved = candidate.resolvingSymlinksInPath()
        guard resolved.path.hasPrefix(root.path + "/"), candidate.path == resolved.path || projectURL.standardizedFileURL.path != root.path else { throw WritingWorkspaceError.unsafePath }
        return candidate
    }

    func metadataURL() throws -> URL {
        let folder = ".\(projectURL.deletingPathExtension().lastPathComponent).weavedata"
        // A Finder project rename must not hide the existing metadata.
        let children = try FileManager.default.contentsOfDirectory(at: projectURL, includingPropertiesForKeys: nil)
        let expected = projectURL.appendingPathComponent(folder)
        let previous = children.filter { $0.lastPathComponent.hasPrefix(".") && $0.lastPathComponent.hasSuffix(".weavedata") && FileManager.default.fileExists(atPath: $0.appendingPathComponent("writing-workspace.json").path) }
        if previous.count > 1 && !FileManager.default.fileExists(atPath: expected.appendingPathComponent("writing-workspace.json").path) { throw WritingWorkspaceError.invalidDocument }
        let selected = FileManager.default.fileExists(atPath: expected.appendingPathComponent("writing-workspace.json").path) ? expected : (previous.count == 1 ? previous[0] : expected)
        return try resolve(selected.lastPathComponent + "/writing-workspace.json")
    }

    /// Relocate metadata links without changing IDs or removing unmatched records.
    func relocatePaths(old: URL, new: URL) throws {
        let prefix = projectURL.standardizedFileURL.path + "/"
        guard old.standardizedFileURL.path.hasPrefix(prefix), new.standardizedFileURL.path.hasPrefix(prefix) else { return }
        let from = String(old.standardizedFileURL.path.dropFirst(prefix.count))
        let to = String(new.standardizedFileURL.path.dropFirst(prefix.count))
        _ = try resolve(to)
        var document = try load()
        func relocated(_ path: String) -> String {
            if path == from { return to }
            if path.hasPrefix(from + "/") { return to + path.dropFirst(from.count) }
            return path
        }
        let original = document
        for index in document.scenes.indices { document.scenes[index].manuscriptPath = relocated(document.scenes[index].manuscriptPath) }
        for index in document.lore.indices { document.lore[index].manuscriptPath = relocated(document.lore[index].manuscriptPath) }
        if document != original { try save(document) }
    }

    func load() throws -> WritingWorkspaceDocument {
        let file = try metadataURL()
        guard FileManager.default.fileExists(atPath: file.path) else { return WritingWorkspaceDocument() }
        let document = try JSONDecoder().decode(WritingWorkspaceDocument.self, from: Data(contentsOf: file))
        guard document.version == 1, Set(document.scenes.map(\.id)).count == document.scenes.count, Set(document.lore.map(\.id)).count == document.lore.count else { throw WritingWorkspaceError.invalidDocument }
        return document
    }

    func save(_ document: WritingWorkspaceDocument) throws {
        let target = try metadataURL()
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(document).write(to: target, options: .atomic)
    }

    func manuscriptPaths() throws -> [String] {
        guard let enumerator = FileManager.default.enumerator(at: projectURL, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]) else { return [] }
        var paths: [String] = []
        for case let file as URL in enumerator {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true, ["md", "txt", "markdown"].contains(file.pathExtension.lowercased()) else { continue }
            let relative = String(file.path.dropFirst(projectURL.path.count + 1))
            _ = try resolve(relative); paths.append(relative)
        }
        return paths.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func text(for scene: WritingScene, drafts: [String: String] = [:]) throws -> String {
        let url = try resolve(scene.manuscriptPath)
        if let draft = drafts[scene.manuscriptPath] { return draft }
        guard FileManager.default.fileExists(atPath: url.path) else { throw WritingWorkspaceError.missingManuscript(scene.manuscriptPath) }
        return try String(contentsOf: url, encoding: .utf8)
    }

    func submission(_ document: WritingWorkspaceDocument, drafts: [String: String], markdown: Bool) throws -> String {
        let scenes = document.scenes.filter(\.includedInExport)
        guard !scenes.isEmpty else { throw WritingWorkspaceError.noScenes }
        return try scenes.map { scene in
            let body = try text(for: scene, drafts: drafts)
            return (markdown ? "# " : "") + scene.title + "\n\n" + body
        }.joined(separator: "\n\n")
    }

    func references(_ document: WritingWorkspaceDocument, at sceneID: UUID?) -> [WritingLoreEntry] {
        let position = sceneID.flatMap { id in document.scenes.firstIndex { $0.id == id } }
        return document.lore.filter { entry in
            guard entry.includeInAI else { return false }
            guard let revealed = entry.revealedFromSceneID else { return true }
            guard let index = document.scenes.firstIndex(where: { $0.id == revealed }), let position else { return false }
            return index <= position
        }
    }

    func exportDOCX(_ text: String, to destination: URL) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("word"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("_rels"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func xml(_ text: String) -> String {
            let valid = String(String.UnicodeScalarView(text.unicodeScalars.filter {
                $0.value == 9 || $0.value == 10 || $0.value == 13 || (0x20...0xD7FF).contains($0.value) || (0xE000...0xFFFD).contains($0.value) || (0x10000...0x10FFFF).contains($0.value)
            }))
            return valid.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;") }
        let paragraphs = text.components(separatedBy: .newlines).map { "<w:p><w:r><w:t xml:space=\"preserve\">\(xml($0))</w:t></w:r></w:p>" }.joined()
        let body = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:body>\(paragraphs)<w:sectPr/></w:body></w:document>"
        try Data(body.utf8).write(to: root.appendingPathComponent("word/document.xml"))
        try Data("<?xml version=\"1.0\"?><Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/></Types>".utf8).write(to: root.appendingPathComponent("[Content_Types].xml"))
        try Data("<?xml version=\"1.0\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/></Relationships>".utf8).write(to: root.appendingPathComponent("_rels/.rels"))
        let archive = root.appendingPathComponent("submission.docx")
        try zip(directory: root, items: ["[Content_Types].xml", "_rels", "word"], destination: archive)
        try Data(contentsOf: archive).write(to: destination, options: .atomic)
    }

    func archive(to destination: URL, drafts: [String: String]) throws {
        guard !destination.standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix(projectURL.standardizedFileURL.resolvingSymlinksInPath().path + "/") else { throw WritingWorkspaceError.unsafePath }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        if let walk = FileManager.default.enumerator(at: projectURL, includingPropertiesForKeys: [.isSymbolicLinkKey]) {
            for case let file as URL in walk where try file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true { throw WritingWorkspaceError.unsafePath }
        }
        let copy = root.appendingPathComponent(projectURL.lastPathComponent)
        try FileManager.default.copyItem(at: projectURL, to: copy)
        let copiedStore = WritingWorkspaceStore(projectURL: copy)
        for (path, content) in drafts {
            let target = try copiedStore.resolve(path)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(content.utf8).write(to: target, options: .atomic)
        }
        let archive = root.appendingPathComponent("project.zip")
        try zip(directory: root, items: [copy.lastPathComponent], destination: archive)
        try Data(contentsOf: archive).write(to: destination, options: .atomic)
    }

    private func zip(directory: URL, items: [String], destination: URL) throws {
        let task = Process(); task.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        task.currentDirectoryURL = directory
        task.arguments = ["-q", "-r", destination.path, "--"] + items
        task.standardOutput = FileHandle.nullDevice; task.standardError = FileHandle.nullDevice
        try task.run(); task.waitUntilExit()
        guard task.terminationStatus == 0 else { throw WritingWorkspaceError.archiveFailed }
    }
}
