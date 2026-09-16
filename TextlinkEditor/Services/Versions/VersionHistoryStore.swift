import Foundation

/// Complete immutable snapshots are published atomically; drafts and their live files are never mutated.
enum VersionHistoryStore {
    struct Snapshot: Codable, Identifiable, Equatable, Sendable {
        let id: UUID
        let date: Date
        let relativePath: String
        let reason: String
        let content: String
    }

    enum Failure: LocalizedError {
        case outsideProject, unsafeStorage, invalidSnapshot
        var errorDescription: String? {
            switch self {
            case .outsideProject: return L10n.get("versions.outsideProject")
            case .unsafeStorage: return L10n.get("versions.unsafeStorage")
            case .invalidSnapshot: return L10n.get("versions.invalidSnapshot")
            }
        }
    }
    private static let lock = NSRecursiveLock()
    static let retainedVersions = 30

    static func snapshot(projectURL: URL, documentURL: URL, content: String,
                         reason: String = "versions.beforeSave") throws -> Snapshot {
        lock.lock(); defer { lock.unlock() }
        let path = try relativePath(documentURL, in: projectURL)
        let directory = try storage(projectURL, relativePath: path, create: true)
        // The save path reads one preceding manuscript, not all 30 retained manuscripts.
        let existing = try orderedFiles(directory)
        if let latest = existing.first {
            let newest = try read(latest)
            guard newest.relativePath == path else { throw Failure.invalidSnapshot }
            if newest.content == content { return newest }
        }
        let snapshot = Snapshot(id: UUID(), date: Date(), relativePath: path, reason: reason, content: content)
        let destination = directory.appendingPathComponent(snapshot.id.uuidString + ".json")
        try publish(JSONEncoder().encode(snapshot), to: destination)
        // Publish first. Cleanup failure never discards the newly captured manuscript.
        for old in existing.dropFirst(retainedVersions - 1) {
            try? FileManager.default.removeItem(at: old)
        }
        return snapshot
    }

    static func snapshots(projectURL: URL, documentURL: URL) throws -> [Snapshot] {
        lock.lock(); defer { lock.unlock() }
        let path = try relativePath(documentURL, in: projectURL)
        let directory = try storage(projectURL, relativePath: path, create: false)
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try orderedFiles(directory).map(read)
            .filter { $0.relativePath == path }
            .sorted { $0.date > $1.date }
    }

    private static func orderedFiles(_ directory: URL) throws -> [URL] {
        let keys: Set<URLResourceKey> = [.isSymbolicLinkKey, .creationDateKey]
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys))
            .filter { $0.pathExtension == "json" }
        let dated = try files.map { url -> (URL, Date) in
            let values = try url.resourceValues(forKeys: keys)
            guard values.isSymbolicLink != true else { throw Failure.unsafeStorage }
            guard UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil else { throw Failure.invalidSnapshot }
            return (url, values.creationDate ?? .distantPast)
        }
        return dated.sorted { $0.1 > $1.1 }.map(\.0)
    }

    private static func read(_ url: URL) throws -> Snapshot {
        let value = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: url))
        guard url.deletingPathExtension().lastPathComponent == value.id.uuidString,
              validRelativePath(value.relativePath) else { throw Failure.invalidSnapshot }
        return value
    }

    static func restoreCopy(_ snapshot: Snapshot, to destination: URL) throws {
        guard validRelativePath(snapshot.relativePath) else { throw Failure.invalidSnapshot }
        try publish(Data(snapshot.content.utf8), to: destination)
    }

    /// Move history after a successful file/folder rename. Failure preserves the old history.
    static func relocate(projectURL: URL, from source: URL, to destination: URL) throws {
        lock.lock(); defer { lock.unlock() }
        let oldPath = try relativePath(source, in: projectURL)
        let newPath = try relativePath(destination, in: projectURL)
        guard oldPath != newPath else { return }
        let oldDirectory = try storage(projectURL, relativePath: oldPath, create: false)
        let manager = FileManager.default
        guard manager.fileExists(atPath: oldDirectory.path) else { return }
        let newDirectory = try storage(projectURL, relativePath: newPath, create: false)
        guard !manager.fileExists(atPath: newDirectory.path),
              !newDirectory.path.hasPrefix(oldDirectory.path + "/") else { throw Failure.unsafeStorage }
        try manager.createDirectory(at: newDirectory.deletingLastPathComponent(), withIntermediateDirectories: true)
        let staging = newDirectory.deletingLastPathComponent().appendingPathComponent(".relocate-" + UUID().uuidString)
        defer { try? manager.removeItem(at: staging) }
        try manager.copyItem(at: oldDirectory, to: staging)
        guard let files = manager.enumerator(at: staging, includingPropertiesForKeys: [.isSymbolicLinkKey], errorHandler: nil) else {
            throw Failure.invalidSnapshot
        }
        for case let file as URL in files {
            guard try file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw Failure.unsafeStorage }
            guard file.pathExtension == "json" else { continue }
            let old = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: file))
            guard old.relativePath == oldPath || old.relativePath.hasPrefix(oldPath + "/"),
                  validRelativePath(old.relativePath) else { throw Failure.invalidSnapshot }
            let updated = Snapshot(id: old.id, date: old.date,
                                   relativePath: newPath + old.relativePath.dropFirst(oldPath.count),
                                   reason: old.reason, content: old.content)
            try JSONEncoder().encode(updated).write(to: file, options: .atomic)
            try manager.setAttributes([.creationDate: old.date], ofItemAtPath: file.path)
        }
        try manager.moveItem(at: staging, to: newDirectory)
        try? manager.removeItem(at: oldDirectory)
    }

    private static func publish(_ data: Data, to destination: URL) throws {
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".version-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try data.write(to: temporary, options: .withoutOverwriting)
        try FileManager.default.moveItem(at: temporary, to: destination)
    }

    private static func validRelativePath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.contains("\0") &&
        path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    private static func relativePath(_ document: URL, in project: URL) throws -> String {
        let root = project.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        try rejectLinks(document.standardizedFileURL, root: project.standardizedFileURL.resolvingSymlinksInPath())
        let target = document.standardizedFileURL.resolvingSymlinksInPath().path
        guard target.hasPrefix(root) else { throw Failure.outsideProject }
        let relative = String(target.dropFirst(root.count))
        guard validRelativePath(relative), !relative.split(separator: "/").contains(where: { $0.hasPrefix(".") }) else {
            throw Failure.outsideProject
        }
        return relative
    }

    private static func rejectLinks(_ url: URL, root: URL) throws {
        var cursor = url
        while cursor.path.hasPrefix(root.path + "/") {
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: cursor.path)) != nil {
                throw Failure.unsafeStorage
            }
            cursor.deleteLastPathComponent()
        }
    }

    private static func storage(_ project: URL, relativePath: String, create: Bool) throws -> URL {
        let root = project.standardizedFileURL.resolvingSymlinksInPath()
        let directory = root.appendingPathComponent(".\(project.deletingPathExtension().lastPathComponent).weavedata")
            .appendingPathComponent("versions", isDirectory: true)
            .appendingPathComponent(relativePath, isDirectory: true)
        try rejectLinks(directory, root: root)
        guard directory.resolvingSymlinksInPath().path == directory.path else { throw Failure.unsafeStorage }
        if create { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        return directory
    }
}

enum ProjectBackupStore {
    /// Destination is a new .weaveproj folder outside the source; publish only a complete copy.
    static func create(projectURL: URL, destinationURL: URL) throws {
        let manager = FileManager.default
        let source = projectURL.standardizedFileURL.resolvingSymlinksInPath()
        let target = destinationURL.standardizedFileURL.resolvingSymlinksInPath()
        guard target != source, !target.path.hasPrefix(source.path + "/"),
              target.pathExtension == "weaveproj" else { throw VersionHistoryStore.Failure.outsideProject }
        guard !manager.fileExists(atPath: target.path) else { throw CocoaError(.fileWriteFileExists) }
        let staging = target.deletingLastPathComponent().appendingPathComponent(".backup-" + UUID().uuidString)
        defer { try? manager.removeItem(at: staging) }
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: source, options: .withoutChanges, error: &coordinationError) { coordinated in
            do {
                let enumeration = manager.enumerator(at: coordinated, includingPropertiesForKeys: [.isSymbolicLinkKey], errorHandler: { _, error in
                    copyError = error; return false
                })
                guard let enumeration else { throw CocoaError(.fileReadUnknown) }
                for case let item as URL in enumeration {
                    guard try item.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
                        throw VersionHistoryStore.Failure.unsafeStorage
                    }
                }
                if let copyError { throw copyError }
                try manager.copyItem(at: coordinated, to: staging)
                // Metadata folder names follow the project name, including a user-renamed backup.
                let oldMetadata = staging.appendingPathComponent(".\(source.deletingPathExtension().lastPathComponent).weavedata")
                let newMetadata = staging.appendingPathComponent(".\(target.deletingPathExtension().lastPathComponent).weavedata")
                if oldMetadata != newMetadata, manager.fileExists(atPath: oldMetadata.path) {
                    try manager.moveItem(at: oldMetadata, to: newMetadata)
                }
                try manager.moveItem(at: staging, to: target)
            } catch { copyError = error }
        }
        if let coordinationError { throw coordinationError }
        if let copyError { throw copyError }
    }
}
