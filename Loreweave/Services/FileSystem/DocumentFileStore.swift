import Foundation

/// UTF-8 documents have a loaded base version. Never silently replace a newer disk version.
enum DocumentFileStore {
    enum Failure: Error { case invalidName, conflict, unreadable }

    static func validateName(_ name: String) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name != ".", name != "..", !name.contains("/"), !name.contains(":"),
              !name.contains("\0") else { throw Failure.invalidName }
    }

    static func create(_ content: String, at url: URL) throws {
        try validateName(url.lastPathComponent)
        try Data(content.utf8).write(to: url, options: .withoutOverwriting)
    }

    static func save(_ content: String, at url: URL, expected: String) throws {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var writeError: Error?
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { target in
            do {
                let data = try Data(contentsOf: target)
                guard let disk = String(data: data, encoding: .utf8) else { throw Failure.unreadable }
                guard disk == expected || disk == content else { throw Failure.conflict }
                try Data(content.utf8).write(to: target, options: .atomic)
            } catch { writeError = error }
        }
        if let error = coordinationError { throw error }
        if let error = writeError { throw error }
    }

    static func contains(_ url: URL, in directory: URL) -> Bool {
        let base = directory.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path == base || path.hasPrefix(base + "/")
    }

    /// Bounded linear comparison; no quadratic LCS allocation for long manuscripts.
    static func changedLines(from old: String, to new: String) -> Set<Int> {
        let a = old.components(separatedBy: "\n"), b = new.components(separatedBy: "\n")
        var start = 0
        while start < min(a.count, b.count), a[start] == b[start] { start += 1 }
        var endA = a.count, endB = b.count
        while endA > start, endB > start, a[endA - 1] == b[endB - 1] { endA -= 1; endB -= 1 }
        return start < endB ? Set((start + 1)...endB) : []
    }
}
