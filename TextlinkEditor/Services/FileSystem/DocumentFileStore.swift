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
                if disk != content { try writeAtomically(content, to: target) }
            } catch { writeError = error }
        }
        if let error = coordinationError { throw error }
        if let error = writeError { throw error }
    }

    /// Stream UTF-8 into a same-volume replacement, then publish only the complete file.
    /// Never patch the live manuscript in place: a failed write must leave the base intact.
    private static func writeAtomically(_ content: String, to target: URL) throws {
        let manager = FileManager.default
        let directory = try manager.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                        appropriateFor: target, create: true)
        defer { try? manager.removeItem(at: directory) }
        let temporary = directory.appendingPathComponent(target.lastPathComponent)
        guard manager.createFile(atPath: temporary.path, contents: nil) else { throw Failure.unreadable }
        let handle = try FileHandle(forWritingTo: temporary)
        do {
            var buffer = Data()
            buffer.reserveCapacity(64 * 1024)
            for byte in content.utf8 {
                buffer.append(byte)
                if buffer.count == 64 * 1024 {
                    try handle.write(contentsOf: buffer)
                    buffer.removeAll(keepingCapacity: true)
                }
            }
            if !buffer.isEmpty { try handle.write(contentsOf: buffer) }
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }
        _ = try manager.replaceItemAt(target, withItemAt: temporary)
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
