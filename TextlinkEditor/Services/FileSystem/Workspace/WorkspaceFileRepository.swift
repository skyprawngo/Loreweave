import Foundation

/// Disk boundary. Implementations cannot silently overwrite an existing destination or stale base.
protocol WorkspaceDocumentRepository {
    func read(_ url: URL) throws -> String
    func readSnapshot(_ url: URL) async throws -> String
    func save(_ content: String, at url: URL, expected: String) throws
    func create(_ content: String, at url: URL) throws
}

protocol WorkspaceFileRepository: WorkspaceDocumentRepository {
    func children(at url: URL) throws -> [URL]
    func createDirectory(at url: URL) throws
    func move(from: URL, to: URL) throws
    func copy(from: URL, to: URL) throws
    func trash(_ url: URL) throws
}

struct LocalWorkspaceFileRepository: WorkspaceFileRepository {
    func read(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }
    func readSnapshot(_ url: URL) async throws -> String { try await DocumentFileStore.readInChunks(at: url) }
    func save(_ content: String, at url: URL, expected: String) throws { try DocumentFileStore.save(content, at: url, expected: expected, events: nil) }
    func create(_ content: String, at url: URL) throws { try DocumentFileStore.create(content, at: url, events: nil) }
    func children(at url: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: url.standardizedFileURL,
            includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
    }
    func createDirectory(at url: URL) throws {
        try DocumentFileStore.validateName(url.lastPathComponent)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    }
    func move(from: URL, to: URL) throws {
        try DocumentFileStore.validateName(to.lastPathComponent)
        guard !DocumentFileStore.contains(to, in: from) else { throw DocumentFileStore.Failure.invalidName }
        try FileManager.default.moveItem(at: from, to: to)
    }
    func copy(from: URL, to: URL) throws {
        try DocumentFileStore.validateName(to.lastPathComponent)
        guard !DocumentFileStore.contains(to, in: from) else { throw DocumentFileStore.Failure.invalidName }
        try FileManager.default.copyItem(at: from, to: to)
    }
    func trash(_ url: URL) throws { try FileManager.default.trashItem(at: url, resultingItemURL: nil) }
}

/// Document lifecycle participates before destructive commands; committed events follow successful I/O only.
protocol WorkspaceDocumentParticipant: AnyObject {
    func prepareForFileMove()
    func prepareForFileDeletion(at url: URL) -> Bool
}

final class WorkspaceFileCoordinator {
    static let shared = WorkspaceFileCoordinator()
    private let repository: any WorkspaceFileRepository
    let documents: any WorkspaceDocumentRepository
    let events: WorkspaceFileEvents
    private struct Participant { weak var value: (any WorkspaceDocumentParticipant)? }
    private var participants: [Participant] = []
    init(repository: any WorkspaceFileRepository = LocalWorkspaceFileRepository(), events: WorkspaceFileEvents = .shared) {
        self.repository = repository
        self.documents = EventPublishingDocumentRepository(base: repository, events: events)
        self.events = events
    }
    func children(at url: URL) throws -> [URL] { try repository.children(at: url) }
    func register(_ participant: any WorkspaceDocumentParticipant) {
        participants.removeAll { $0.value == nil }
        participants.append(Participant(value: participant))
    }
    func move(from: URL, to: URL) throws {
        for participant in participants { participant.value?.prepareForFileMove() }
        try repository.move(from: from, to: to)
        events.publish(.init(url: to, change: .moved(from: from)))
    }
    @discardableResult func trash(_ url: URL) throws -> Bool {
        for participant in participants {
            if participant.value?.prepareForFileDeletion(at: url) == false { return false }
        }
        try repository.trash(url)
        events.publish(.init(url: url, change: .trashed))
        return true
    }
    func copy(from: URL, to: URL) throws {
        try repository.copy(from: from, to: to)
        events.publish(.init(url: to, change: .copied(from: from)))
    }
    func createDirectory(at url: URL) throws {
        try repository.createDirectory(at: url)
        events.publish(.init(url: url, change: .created))
    }
}

/// Decorator publishes only successful writes. Custom backends and isolated event buses use the same contract.
struct EventPublishingDocumentRepository: WorkspaceDocumentRepository {
    let base: any WorkspaceDocumentRepository
    let events: WorkspaceFileEvents
    func read(_ url: URL) throws -> String { try base.read(url) }
    func readSnapshot(_ url: URL) async throws -> String { try await base.readSnapshot(url) }
    func save(_ content: String, at url: URL, expected: String) throws {
        try base.save(content, at: url, expected: expected)
        events.publish(.init(url: url, change: .saved))
    }
    func create(_ content: String, at url: URL) throws {
        try base.create(content, at: url)
        events.publish(.init(url: url, change: .created))
    }
}
