import Foundation

/// Compatibility facade for existing callers; persistence belongs to the repository.
final class ChatHistoryManager {
    static let shared = ChatHistoryManager()
    private let repository = JSONAIHistoryRepository()
    private(set) var lastLoadFailed = false

    func loadSession(from project: URL) -> AIChatSession? {
        lastLoadFailed = false
        do { return try repository.load(from: project)?.session }
        catch { lastLoadFailed = true; return nil }
    }
    func loadTaggedCardIds(from project: URL) -> Set<UUID> {
        (try? repository.load(from: project))?.metadata.taggedCardIds ?? []
    }
    func loadCardSessionIds(from project: URL) -> [UUID: String] {
        (try? repository.load(from: project))?.sessionIds ?? [:]
    }
    func saveState(messages: [AIMessage], taggedIds: Set<UUID>, sessionIds: [UUID: String],
                   cliType: String, to project: URL) throws {
        try repository.save(messages: messages, taggedIds: taggedIds, sessionIds: sessionIds, cliType: cliType, to: project)
    }
}
