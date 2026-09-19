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

/// Conversation index: a conversation owns ordered turn cards; each assistant ID identifies a request.
struct AIConversationRecord: Codable, Identifiable {
    let id: UUID
    let category: AIConversationCategory
    var cardIds: [UUID]
    var requestIds: [UUID]
    var provider: String?
    var model: String?
    var reasoningEffort: String?

    static func index(_ cards: [SavedConversationCard]) -> [Self] {
        var result: [Self] = []
        var positions: [UUID: Int] = [:]
        for card in cards {
            let root = card.userMessage.conversationId ?? card.userMessage.id
            if positions[root] == nil {
                positions[root] = result.count
                result.append(Self(id: root, category: card.userMessage.category, cardIds: [], requestIds: []))
            }
            let index = positions[root]!
            result[index].cardIds.append(card.id)
            if let response = card.assistantMessage { result[index].requestIds.append(response.id) }
            let request = card.userMessage
            result[index].provider = request.provider
            result[index].model = request.model
            result[index].reasoningEffort = request.reasoningEffort
        }
        return result
    }
}

/// 채팅 세션 메타데이터
struct ChatSessionMetadata: Codable {
    let projectPath: String
    let cliType: String
    var cardIds: [UUID]
    var conversations: [AIConversationRecord] = []
    var schemaVersion = 2
    var taggedCardIds: Set<UUID>
    let createdAt: Date
    var updatedAt: Date

    /// CLI 세션 ID (대화 연속성 유지용) - deprecated, 카드별 세션 ID 사용
    var cliSessionId: String?

    /// 카드별 CLI 세션 ID (세션 뷰: 각 카드 독립, 채팅 뷰: 카드 내 대화 계속)
    var cardSessionIds: [String: String]  // [카드 ID String: CLI 세션 ID]

    enum CodingKeys: String, CodingKey {
        case projectPath, cliType, cardIds, taggedCardIds, createdAt, updatedAt, cliSessionId, cardSessionIds, conversations, schemaVersion
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        projectPath = try c.decode(String.self, forKey: .projectPath)
        cliType = try c.decode(String.self, forKey: .cliType)
        cardIds = try c.decode([UUID].self, forKey: .cardIds)
        conversations = try c.decodeIfPresent([AIConversationRecord].self, forKey: .conversations) ?? []
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        taggedCardIds = try c.decodeIfPresent(Set<UUID>.self, forKey: .taggedCardIds) ?? []
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        cliSessionId = try c.decodeIfPresent(String.self, forKey: .cliSessionId)
        cardSessionIds = try c.decodeIfPresent([String: String].self, forKey: .cardSessionIds) ?? [:]
    }

    init(projectPath: String, cliType: String, createdAt: Date = Date()) {
        self.projectPath = projectPath
        self.cliType = cliType
        self.cardIds = []
        self.taggedCardIds = []
        self.createdAt = createdAt
        self.updatedAt = Date()
        self.cliSessionId = nil
        self.cardSessionIds = [:]
    }
}

