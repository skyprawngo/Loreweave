import Foundation

/// Project-scoped storage contract. Callers never depend on paths or serialization.
protocol AIHistoryRepository {
    func load(from project: URL) throws -> AIHistorySnapshot?
    func save(messages: [AIMessage], taggedIds: Set<UUID>, sessionIds: [UUID: String],
              cliType: String, to project: URL) throws
}

struct AIHistorySnapshot: Codable {
    var schemaVersion = 1
    var metadata: ChatSessionMetadata
    var cards: [SavedConversationCard]

    var session: AIChatSession {
        AIChatSession(projectPath: metadata.projectPath, cliType: metadata.cliType,
            messages: cards.flatMap { [$0.userMessage] + ($0.assistantMessage.map { [$0] } ?? []) },
            createdAt: metadata.createdAt, updatedAt: metadata.updatedAt, cliSessionId: metadata.cliSessionId)
    }
    var sessionIds: [UUID: String] {
        Dictionary(uniqueKeysWithValues: metadata.cardSessionIds.compactMap { key, value in
            UUID(uuidString: key).map { ($0, value) }
        })
    }

    func validate() throws {
        guard schemaVersion == 1, metadata.schemaVersion <= 2 else { throw AIHistoryError.unsupportedVersion }
        guard metadata.cardIds == cards.map(\.id), Set(metadata.cardIds).count == cards.count else { throw AIHistoryError.invalidRecords }
        var ids = Set<UUID>()
        for card in cards {
            guard card.id == card.userMessage.id, card.userMessage.role == .user,
                  ids.insert(card.id).inserted else { throw AIHistoryError.invalidRecords }
            if let response = card.assistantMessage {
                guard response.role == .assistant, !response.isStreaming,
                      ids.insert(response.id).inserted,
                      response.conversationId == nil || response.conversationId == (card.userMessage.conversationId ?? card.id),
                      response.category == card.userMessage.category else { throw AIHistoryError.invalidRecords }
            }
        }
        let expected = AIConversationRecord.index(cards)
        guard metadata.conversations.map(\.id) == expected.map(\.id),
              zip(metadata.conversations, expected).allSatisfy({ $0.cardIds == $1.cardIds && $0.requestIds == $1.requestIds && $0.category == $1.category }) else {
            throw AIHistoryError.invalidRecords
        }
    }

    static func make(messages: [AIMessage], taggedIds: Set<UUID>, sessionIds: [UUID: String],
                     cliType: String, project: URL, createdAt: Date? = nil) throws -> Self {
        var cards: [SavedConversationCard] = []
        for message in messages {
            if message.role == .user {
                cards.append(SavedConversationCard(userMessage: message,
                    isTaggedForContext: taggedIds.contains(message.conversationId ?? message.id)))
            } else if message.role == .assistant, !message.isStreaming {
                guard !cards.isEmpty, cards[cards.count - 1].assistantMessage == nil else { throw AIHistoryError.invalidRecords }
                cards[cards.count - 1].assistantMessage = message
            }
        }
        var metadata = ChatSessionMetadata(projectPath: project.path, cliType: cliType, createdAt: createdAt ?? Date())
        metadata.cardIds = cards.map(\.id)
        metadata.conversations = AIConversationRecord.index(cards)
        metadata.taggedCardIds = taggedIds
        metadata.cardSessionIds = Dictionary(uniqueKeysWithValues: sessionIds.map { ($0.key.uuidString, $0.value) })
        let snapshot = Self(metadata: metadata, cards: cards)
        try snapshot.validate()
        return snapshot
    }
}

enum AIHistoryError: LocalizedError {
    case unsupportedVersion, invalidRecords, unreadableLegacy
    var errorDescription: String? { L10n.get("ai.error.historyLoadFailed") }
}

/// One atomic commit contains messages and indexes together. Legacy files remain untouched.
/// A corrupt/future database is never silently replaced with an empty or stale legacy snapshot.
final class JSONAIHistoryRepository: AIHistoryRepository {
    private let write: (Data, URL) throws -> Void
    init(write: @escaping (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }) {
        self.write = write
    }
    func databaseURL(for project: URL) -> URL {
        project.appendingPathComponent(".\(project.deletingPathExtension().lastPathComponent).weavedata/ai-sessions/history-store.json")
    }
    func load(from project: URL) throws -> AIHistorySnapshot? {
        let file = databaseURL(for: project)
        if FileManager.default.fileExists(atPath: file.path) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let result = try decoder.decode(AIHistorySnapshot.self, from: Data(contentsOf: file))
            try result.validate()
            return result
        }
        let legacy = LegacyAIHistoryReader.shared
        let session = legacy.loadSession(from: project)
        guard !legacy.lastLoadFailed else { throw AIHistoryError.unreadableLegacy }
        guard let session else { return nil }
        return try AIHistorySnapshot.make(messages: session.messages,
            taggedIds: legacy.loadTaggedCardIds(from: project), sessionIds: legacy.loadCardSessionIds(from: project),
            cliType: session.cliType, project: project, createdAt: session.createdAt)
    }
    func save(messages: [AIMessage], taggedIds: Set<UUID>, sessionIds: [UUID: String],
              cliType: String, to project: URL) throws {
        let previous = try load(from: project)
        let snapshot = try AIHistorySnapshot.make(messages: messages, taggedIds: taggedIds,
            sessionIds: sessionIds, cliType: cliType, project: project, createdAt: previous?.metadata.createdAt)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        let file = databaseURL(for: project)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try write(data, file)
    }
}
