//
//  AIMessage.swift
//  Loreweave
//
//  채팅 메시지 모델
//

import Foundation

/// 채팅 메시지 역할
enum AIMessageRole: String, Codable {
    case user = "user"
    case assistant = "assistant"
    case system = "system"
}

/// 채팅 메시지
struct AIMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let role: AIMessageRole
    let content: String
    let timestamp: Date
    var isStreaming: Bool

    init(
        id: UUID = UUID(),
        role: AIMessageRole,
        content: String,
        timestamp: Date = Date(),
        isStreaming: Bool = false
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.isStreaming = isStreaming
    }

    static func == (lhs: AIMessage, rhs: AIMessage) -> Bool {
        lhs.id == rhs.id
    }
}

/// 채팅 세션 (프로젝트별 저장용)
struct AIChatSession: Codable {
    let id: UUID
    let projectPath: String
    let cliType: String
    var messages: [AIMessage]
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        projectPath: String,
        cliType: String,
        messages: [AIMessage] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.projectPath = projectPath
        self.cliType = cliType
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
