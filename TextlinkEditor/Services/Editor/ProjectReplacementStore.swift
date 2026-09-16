import Foundation

enum ProjectReplacementStore {
    struct Change: Codable, Identifiable, Sendable {
        var id: String { relativePath }
        let relativePath: String
        let original: String
        let replacement: String
        let occurrences: Int
    }
    struct Preview: Sendable {
        let changes: [Change]
        let skipped: Int
        let limitReached: Bool
    }
    struct Batch: Codable, Identifiable, Sendable {
        let id: UUID
        let date: Date
        let changes: [Change]
        var state: String
        var completedPaths: [String]
    }
    enum Failure: LocalizedError {
        case invalidPath, changed(String), incomplete(String), empty
        var errorDescription: String? {
            switch self {
            case .invalidPath: return L10n.get("projectReplace.invalidPath")
            case .changed(let path): return String(format: L10n.get("projectReplace.changed"), path)
            case .incomplete(let path): return String(format: L10n.get("projectReplace.incomplete"), path)
            case .empty: return L10n.get("projectReplace.empty")
            }
        }
    }

    static func preview(projectURL: URL, query: String, replacement: String) throws -> Preview {
        guard !query.isEmpty else { return Preview(changes: [], skipped: 0, limitReached: false) }
        var changes: [Change] = [], skipped = 0, inspected = 0
        var enumerationError: Error?
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        guard let files = FileManager.default.enumerator(at: projectURL, includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles], errorHandler: { _, error in enumerationError = error; return false }) else {
            throw Failure.invalidPath
        }
        for case let file as URL in files {
            try Task.checkCancellation()
            let attributes = try file.resourceValues(forKeys: keys)
            if attributes.isSymbolicLink == true { files.skipDescendants(); skipped += 1; continue }
            guard attributes.isRegularFile == true, ["md", "markdown", "txt"].contains(file.pathExtension.lowercased()) else { continue }
            if inspected == 200 { return Preview(changes: changes, skipped: skipped, limitReached: true) }
            inspected += 1
            guard (attributes.fileSize ?? Int.max) <= 5_000_000,
                  let original = try? String(contentsOf: file, encoding: .utf8) else { skipped += 1; continue }
            let replaced = original.replacingOccurrences(of: query, with: replacement, options: .literal)
            guard original != replaced else { continue }
            var occurrences = 0, range = original.startIndex..<original.endIndex
            while let found = original.range(of: query, options: .literal, range: range) {
                occurrences += 1; range = found.upperBound..<original.endIndex
            }
            let root = projectURL.standardizedFileURL.resolvingSymlinksInPath()
            let path = file.standardizedFileURL.resolvingSymlinksInPath().path
            guard path.hasPrefix(root.path + "/") else { throw Failure.invalidPath }
            changes.append(Change(relativePath: String(path.dropFirst(root.path.count + 1)), original: original,
                                  replacement: replaced, occurrences: occurrences))
        }
        if let enumerationError { throw enumerationError }
        return Preview(changes: changes.sorted { $0.relativePath < $1.relativePath }, skipped: skipped, limitReached: false)
    }

    static func documentURL(projectURL: URL, relativePath: String) throws -> URL {
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/"), !relativePath.contains("\0"),
              relativePath.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({ !$0.isEmpty && $0 != ".." && $0 != "." && !$0.hasPrefix(".") }) else {
            throw Failure.invalidPath
        }
        let root = projectURL.standardizedFileURL.resolvingSymlinksInPath()
        let result = root.appendingPathComponent(relativePath).standardizedFileURL
        try rejectLinks(result, root: root)
        guard result.resolvingSymlinksInPath().path.hasPrefix(root.path + "/") else { throw Failure.invalidPath }
        return result
    }

    static func apply(projectURL: URL, changes: [Change],
                      writer: (String, URL, String) throws -> Void = { try DocumentFileStore.save($0, at: $1, expected: $2) }) throws -> Batch {
        guard !changes.isEmpty, Set(changes.map(\.relativePath)).count == changes.count else { throw Failure.empty }
        // Validate the complete preview before any snapshot or manuscript write.
        for change in changes {
            let url = try documentURL(projectURL: projectURL, relativePath: change.relativePath)
            guard try String(contentsOf: url, encoding: .utf8) == change.original else { throw Failure.changed(change.relativePath) }
        }
        for change in changes {
            _ = try VersionHistoryStore.snapshot(projectURL: projectURL,
                documentURL: documentURL(projectURL: projectURL, relativePath: change.relativePath),
                content: change.original, reason: "projectReplace.snapshot")
        }
        var batch = Batch(id: UUID(), date: Date(), changes: changes, state: "pending", completedPaths: [])
        let journal = try journalURL(projectURL: projectURL, id: batch.id)
        try persist(batch, to: journal)
        do {
            for change in changes {
                let url = try documentURL(projectURL: projectURL, relativePath: change.relativePath)
                try writer(change.replacement, url, change.original)
                batch.completedPaths.append(change.relativePath)
                try persistProgress(batch, to: journal)
            }
            batch.state = "applied"
            try persist(batch, to: journal)
            return batch
        } catch {
            let originalError = error
            var remaining: [String] = []
            for change in changes.reversed() where batch.completedPaths.contains(change.relativePath) {
                do {
                    let url = try documentURL(projectURL: projectURL, relativePath: change.relativePath)
                    try DocumentFileStore.save(change.original, at: url, expected: change.replacement)
                } catch { remaining.append(change.relativePath) }
            }
            batch.completedPaths = remaining
            batch.state = remaining.isEmpty ? "rolledBack" : "partial"
            try? persist(batch, to: journal)
            if !remaining.isEmpty { throw Failure.incomplete(journal.lastPathComponent) }
            throw originalError
        }
    }

    static func undo(projectURL: URL, batch: Batch) throws {
        let reverse = batch.changes.map { Change(relativePath: $0.relativePath, original: $0.replacement,
                                                replacement: $0.original, occurrences: $0.occurrences) }
        _ = try apply(projectURL: projectURL, changes: reverse)
    }

    private static func persist(_ batch: Batch, to url: URL) throws {
        try JSONEncoder().encode(batch).write(to: url, options: .atomic)
    }
    private static func persistProgress(_ batch: Batch, to url: URL) throws {
        struct Progress: Codable { let state: String; let completedPaths: [String] }
        try JSONEncoder().encode(Progress(state: batch.state, completedPaths: batch.completedPaths))
            .write(to: url.deletingPathExtension().appendingPathExtension("progress.json"), options: .atomic)
    }
    private static func rejectLinks(_ url: URL, root: URL) throws {
        var cursor = url
        while cursor.path.hasPrefix(root.path + "/") {
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: cursor.path)) != nil { throw Failure.invalidPath }
            cursor.deleteLastPathComponent()
        }
    }
    private static func journalURL(projectURL: URL, id: UUID) throws -> URL {
        let root = projectURL.standardizedFileURL.resolvingSymlinksInPath()
        let directory = root.appendingPathComponent(".\(root.deletingPathExtension().lastPathComponent).weavedata/replacements")
        try rejectLinks(directory, root: root)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(id.uuidString + ".json")
    }
}
