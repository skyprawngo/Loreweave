import Foundation
import Darwin

/// UTF-8 documents have a loaded base version. Never silently replace a newer disk version.
enum DocumentFileStore {
    enum Failure: Error { case invalidName, conflict, unreadable }

    static func validateName(_ name: String) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name != ".", name != "..", !name.contains("/"), !name.contains(":"),
              !name.contains("\0") else { throw Failure.invalidName }
    }

    static func create(_ content: String, at url: URL, events: WorkspaceFileEvents? = .shared) throws {
        try validateName(url.lastPathComponent)
        try Data(content.utf8).write(to: url, options: .withoutOverwriting)
        events?.publish(.init(url: url, change: .created))
    }

    /// Read on a worker in bounded I/O chunks. Decode only a complete UTF-8 snapshot:
    /// neither a split scalar nor cancellation can publish a partial manuscript to the editor.
    static func readInChunks(at url: URL, chunkSize: Int = 64 * 1024) async throws -> String {
        let worker = Task.detached(priority: .userInitiated) { () throws -> String in
            try Task.checkCancellation()
            let coordinator = NSFileCoordinator()
            var coordinationError: NSError?
            var result: Result<String, Error>?
            coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { target in
                result = Result {
                    let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
                    let before = try target.resourceValues(forKeys: keys)
                    let handle = try FileHandle(forReadingFrom: target)
                    defer { try? handle.close() }
                    var opened = stat()
                    guard fstat(handle.fileDescriptor, &opened) == 0 else { throw Failure.unreadable }
                    var bytes = Data()
                    while true {
                        try Task.checkCancellation()
                        guard let part = try handle.read(upToCount: max(1, chunkSize)), !part.isEmpty else { break }
                        bytes.append(part)
                    }
                    try Task.checkCancellation()
                    var refreshedTarget = target
                    refreshedTarget.removeAllCachedResourceValues()
                    let after = try refreshedTarget.resourceValues(forKeys: keys)
                    var completed = stat(), pathState = stat()
                    guard fstat(handle.fileDescriptor, &completed) == 0,
                          stat(target.path, &pathState) == 0,
                          opened.st_dev == pathState.st_dev, opened.st_ino == pathState.st_ino,
                          opened.st_size == completed.st_size,
                          opened.st_mtimespec.tv_sec == completed.st_mtimespec.tv_sec,
                          opened.st_mtimespec.tv_nsec == completed.st_mtimespec.tv_nsec,
                          opened.st_ctimespec.tv_sec == completed.st_ctimespec.tv_sec,
                          opened.st_ctimespec.tv_nsec == completed.st_ctimespec.tv_nsec else { throw Failure.conflict }
                    guard before.contentModificationDate == after.contentModificationDate,
                          before.fileSize == after.fileSize else { throw Failure.conflict }
                    guard let text = String(data: bytes, encoding: .utf8) else { throw Failure.unreadable }
                    return text
                }
            }
            if let coordinationError { throw coordinationError }
            guard let result else { throw Failure.unreadable }
            return try result.get()
        }
        return try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    }

    static func save(_ content: String, at url: URL, expected: String, events: WorkspaceFileEvents? = .shared) throws {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var writeError: Error?
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { target in
            do {
                let data = try Data(contentsOf: target)
                guard let disk = String(data: data, encoding: .utf8) else { throw Failure.unreadable }
                guard disk == expected || disk == content else { throw Failure.conflict }
                if disk != content { try writeAtomically(content, to: target, expected: data) }
            } catch { writeError = error }
        }
        if let error = coordinationError { throw error }
        if let error = writeError { throw error }
        events?.publish(.init(url: url, change: .saved))
    }

    /// Stream UTF-8 into a same-volume replacement, then publish only the complete file.
    /// Never patch the live manuscript in place: a failed write must leave the base intact.
    private static func writeAtomically(_ content: String, to target: URL, expected: Data) throws {
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
        // Preparing a large replacement can take time. Revalidate immediately before publishing.
        guard try Data(contentsOf: target) == expected else { throw Failure.conflict }
        _ = try manager.replaceItemAt(target, withItemAt: temporary)
    }

    static func contains(_ url: URL, in directory: URL) -> Bool {
        let base = directory.standardizedFileURL.path.precomposedStringWithCanonicalMapping
        let path = url.standardizedFileURL.path.precomposedStringWithCanonicalMapping
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
