//
//  ChatHistoryManager.swift
//  TextlinkEditor
//
//  채팅 히스토리 저장/로드 관리 - 대화 카드별 저장
//

import Foundation

/// 저장용 대화 카드 모델
struct SavedConversationCard: Codable {
    let id: UUID
    let userMessage: AIMessage
    var assistantMessage: AIMessage?
    var isTaggedForContext: Bool
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userMessage
        case assistantMessage
        case isTaggedForContext
        case createdAt
    }

    init(userMessage: AIMessage, assistantMessage: AIMessage? = nil, isTaggedForContext: Bool = false) {
        self.id = userMessage.id
        self.userMessage = userMessage
        self.assistantMessage = assistantMessage
        self.isTaggedForContext = isTaggedForContext
        self.createdAt = userMessage.timestamp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        userMessage = try container.decode(AIMessage.self, forKey: .userMessage)
        assistantMessage = try container.decodeIfPresent(AIMessage.self, forKey: .assistantMessage)
        isTaggedForContext = try container.decodeIfPresent(Bool.self, forKey: .isTaggedForContext) ?? false
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userMessage, forKey: .userMessage)
        try container.encodeIfPresent(assistantMessage, forKey: .assistantMessage)
        try container.encode(isTaggedForContext, forKey: .isTaggedForContext)
        try container.encode(createdAt, forKey: .createdAt)
    }
}

/// 채팅 세션 메타데이터
struct ChatSessionMetadata: Codable {
    let projectPath: String
    let cliType: String
    var cardIds: [UUID]
    var taggedCardIds: Set<UUID>
    let createdAt: Date
    var updatedAt: Date

    /// CLI 세션 ID (대화 연속성 유지용) - deprecated, 카드별 세션 ID 사용
    var cliSessionId: String?

    /// 카드별 CLI 세션 ID (세션 뷰: 각 카드 독립, 채팅 뷰: 카드 내 대화 계속)
    var cardSessionIds: [String: String]  // [카드 ID String: CLI 세션 ID]

    enum CodingKeys: String, CodingKey {
        case projectPath, cliType, cardIds, taggedCardIds, createdAt, updatedAt, cliSessionId, cardSessionIds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        projectPath = try c.decode(String.self, forKey: .projectPath)
        cliType = try c.decode(String.self, forKey: .cliType)
        cardIds = try c.decode([UUID].self, forKey: .cardIds)
        taggedCardIds = try c.decodeIfPresent(Set<UUID>.self, forKey: .taggedCardIds) ?? []
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        cliSessionId = try c.decodeIfPresent(String.self, forKey: .cliSessionId)
        cardSessionIds = try c.decodeIfPresent([String: String].self, forKey: .cardSessionIds) ?? [:]
    }

    init(projectPath: String, cliType: String) {
        self.projectPath = projectPath
        self.cliType = cliType
        self.cardIds = []
        self.taggedCardIds = []
        self.createdAt = Date()
        self.updatedAt = Date()
        self.cliSessionId = nil
        self.cardSessionIds = [:]
    }
}

/// 채팅 히스토리 매니저
final class ChatHistoryManager {
    static let shared = ChatHistoryManager()

    private(set) var lastLoadFailed = false

    private let metadataFileName = "session-metadata.json"
    private let cardsFolder = "cards"

    private init() {}

    // MARK: - Path Helpers

    /// AI 대화 세션 폴더 경로 (프로젝트 숨김 폴더 내)
    private func sessionFolderURL(for projectFolderURL: URL) -> URL {
        let projectName = projectFolderURL.deletingPathExtension().lastPathComponent
        let dataFolderName = ".\(projectName).weavedata"
        let dataFolder = projectFolderURL.appendingPathComponent(dataFolderName)
        return dataFolder.appendingPathComponent("ai-sessions")
    }

    /// 메타데이터 파일 경로
    private func metadataFileURL(for projectFolderURL: URL) -> URL {
        sessionFolderURL(for: projectFolderURL).appendingPathComponent(metadataFileName)
    }

    /// 카드 폴더 경로
    private func cardsFolderURL(for projectFolderURL: URL) -> URL {
        sessionFolderURL(for: projectFolderURL).appendingPathComponent(cardsFolder)
    }

    /// 개별 카드 파일 경로
    private func cardFileURL(for cardId: UUID, projectFolderURL: URL) -> URL {
        cardsFolderURL(for: projectFolderURL).appendingPathComponent("\(cardId.uuidString).json")
    }

    // MARK: - Reading

    private func loadMetadata(from projectFolderURL: URL) -> ChatSessionMetadata? {
        let fileURL = metadataFileURL(for: projectFolderURL)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(ChatSessionMetadata.self, from: data)
        } catch {
            lastLoadFailed = true
            print("ChatHistoryManager: 메타데이터 로드 실패 - \(error)")
            return nil
        }
    }

    private func loadCard(id: UUID, from projectFolderURL: URL) -> SavedConversationCard? {
        let fileURL = cardFileURL(for: id, projectFolderURL: projectFolderURL)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(SavedConversationCard.self, from: data)
        } catch {
            lastLoadFailed = true
            print("ChatHistoryManager: 카드 로드 실패 (\(id)) - \(error)")
            return nil
        }
    }

    /// Save one project snapshot. Answers are paired by turn ID, never by the last disk card.
    /// Metadata is published last, before removing no-longer-referenced card files.
    func saveState(messages: [AIMessage], taggedIds: Set<UUID>, sessionIds: [UUID: String],
                   cliType: String, to projectURL: URL) throws {
        let previousIds = Set(loadMetadata(from: projectURL)?.cardIds ?? [])
        try FileManager.default.createDirectory(at: cardsFolderURL(for: projectURL), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        var metadata = ChatSessionMetadata(projectPath: projectURL.path, cliType: cliType)
        var current: SavedConversationCard?
        var cards: [SavedConversationCard] = []
        for message in messages {
            if message.role == .user {
                if let current { cards.append(current) }
                current = SavedConversationCard(userMessage: message, isTaggedForContext: taggedIds.contains(message.conversationId ?? message.id))
            } else if message.role == .assistant, !message.isStreaming {
                current?.assistantMessage = message
            }
        }
        if let current { cards.append(current) }
        for card in cards {
            try encoder.encode(card).write(to: cardFileURL(for: card.id, projectFolderURL: projectURL), options: .atomic)
        }
        metadata.cardIds = cards.map(\.id)
        metadata.taggedCardIds = taggedIds
        metadata.cardSessionIds = Dictionary(uniqueKeysWithValues: sessionIds.map { ($0.key.uuidString, $0.value) })
        try encoder.encode(metadata).write(to: metadataFileURL(for: projectURL), options: .atomic)
        for removed in previousIds.subtracting(Set(metadata.cardIds)) {
            try? FileManager.default.removeItem(at: cardFileURL(for: removed, projectFolderURL: projectURL))
        }
    }

    // MARK: - Public API (Legacy Support)

    /// 채팅 세션 로드 (기존 AIChatSession 형식으로 변환)
    func loadSession(from projectFolderURL: URL) -> AIChatSession? {
        lastLoadFailed = false
        // 새 형식 먼저 시도
        if let metadata = loadMetadata(from: projectFolderURL) {
            var messages: [AIMessage] = []
            var seenIds = Set<UUID>()

            for cardId in metadata.cardIds {
                if let card = loadCard(id: cardId, from: projectFolderURL) {
                    // 데이터 유효성 검사: userMessage는 반드시 user role이어야 함
                    guard card.userMessage.role == .user else {
                        print("⚠️ ChatHistoryManager: 카드 \(cardId) - userMessage의 role이 user가 아님, 스킵")
                        continue
                    }

                    // 중복 ID 검사
                    if seenIds.contains(card.userMessage.id) {
                        print("⚠️ ChatHistoryManager: 중복 ID 발견 - \(card.userMessage.id), 스킵")
                        continue
                    }
                    seenIds.insert(card.userMessage.id)

                    messages.append(card.userMessage)

                    if let assistant = card.assistantMessage {
                        // assistantMessage 유효성 검사
                        guard assistant.role == .assistant else {
                            print("⚠️ ChatHistoryManager: 카드 \(cardId) - assistantMessage의 role이 assistant가 아님, 스킵")
                            continue
                        }

                        // assistant ID도 중복 검사
                        if seenIds.contains(assistant.id) {
                            print("⚠️ ChatHistoryManager: assistant 중복 ID 발견 - \(assistant.id), 스킵")
                            continue
                        }
                        seenIds.insert(assistant.id)

                        messages.append(assistant)
                    } else {
                        print("ChatHistoryManager: 카드 \(cardId)에 assistantMessage가 없음")
                    }
                } else {
                    lastLoadFailed = true
                    print("ChatHistoryManager: 카드 \(cardId) 로드 실패")
                }
            }

            return AIChatSession(
                projectPath: metadata.projectPath,
                cliType: metadata.cliType,
                messages: messages,
                createdAt: metadata.createdAt,
                updatedAt: metadata.updatedAt,
                cliSessionId: metadata.cliSessionId
            )
        }

        // 기존 형식 호환 시도
        return loadLegacySession(from: projectFolderURL)
    }

    /// 기존 형식 로드 (하위 호환)
    private func loadLegacySession(from projectFolderURL: URL) -> AIChatSession? {
        let projectName = projectFolderURL.deletingPathExtension().lastPathComponent
        let dataFolderName = ".\(projectName).weavedata"
        let legacyFileURL = projectFolderURL
            .appendingPathComponent(dataFolderName)
            .appendingPathComponent("ai-chat-history.json")

        guard FileManager.default.fileExists(atPath: legacyFileURL.path) else { return nil }

        do {
            let data = try Data(contentsOf: legacyFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(AIChatSession.self, from: data)
        } catch {
            lastLoadFailed = true
            return nil
        }
    }

    /// 태그된 카드 ID 로드
    func loadTaggedCardIds(from projectFolderURL: URL) -> Set<UUID> {
        loadMetadata(from: projectFolderURL)?.taggedCardIds ?? []
    }

    /// Session maps belong to the provider recorded in the same metadata file.
    func loadCardSessionIds(from projectFolderURL: URL) -> [UUID: String] {
        guard let metadata = loadMetadata(from: projectFolderURL) else { return [:] }
        return Dictionary(uniqueKeysWithValues: metadata.cardSessionIds.compactMap { key, value in
            UUID(uuidString: key).map { ($0, value) }
        })
    }
}
