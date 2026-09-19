import Foundation
import CryptoKit

/// Session snapshots are separate from manuscript I/O. Only the local recovery copy may carry external URLs.
struct EditorSessionStore {
    struct Loaded {
        let session: EditorSessionState?
        let trustedLocal: Bool
        let error: String?
    }
    let recoveryDirectory: URL
    func localURL(for project: URL) -> URL {
        let digest = SHA256.hash(data: Data(project.standardizedFileURL.path.utf8)).map { String(format: "%02x", $0) }.joined()
        return recoveryDirectory.appendingPathComponent(digest + ".json")
    }
    func write(local: EditorSessionState, portable: EditorSessionState, project: URL, portableURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        try FileManager.default.createDirectory(at: recoveryDirectory, withIntermediateDirectories: true)
        try encoder.encode(local).write(to: localURL(for: project), options: .atomic)
        try encoder.encode(portable).write(to: portableURL, options: .atomic)
    }
    func load(project: URL, portableURL: URL) -> Loaded {
        let local = localURL(for: project)
        var failure: String?
        for file in [local, portableURL] where FileManager.default.fileExists(atPath: file.path) {
            do {
                let session = try JSONDecoder().decode(EditorSessionState.self, from: Data(contentsOf: file))
                return Loaded(session: session, trustedLocal: file == local, error: failure)
            } catch {
                failure = error.localizedDescription
                let archive = file.deletingPathExtension().appendingPathExtension("unreadable-" + UUID().uuidString + ".json")
                try? FileManager.default.copyItem(at: file, to: archive)
            }
        }
        return Loaded(session: nil, trustedLocal: false, error: failure)
    }
}
