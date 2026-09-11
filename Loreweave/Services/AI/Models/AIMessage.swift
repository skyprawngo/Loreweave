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
    var conversationId: UUID?
    var outcome: String?

    init(
        id: UUID = UUID(),
        role: AIMessageRole,
        content: String,
        timestamp: Date = Date(),
        isStreaming: Bool = false,
        conversationId: UUID? = nil,
        outcome: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.isStreaming = isStreaming
        self.conversationId = conversationId
        self.outcome = outcome
    }

    static func == (lhs: AIMessage, rhs: AIMessage) -> Bool {
        lhs.id == rhs.id && lhs.content == rhs.content && lhs.isStreaming == rhs.isStreaming && lhs.conversationId == rhs.conversationId && lhs.outcome == rhs.outcome
    }
}

/// CLI 대화형 선택 옵션
/// Claude CLI가 사용자에게 선택지를 제공할 때 파싱된 옵션
struct CLISelectionOption: Identifiable, Equatable {
    let id: Int
    let label: String
    let isSelected: Bool

    init(id: Int, label: String, isSelected: Bool = false) {
        self.id = id
        self.label = label
        self.isSelected = isSelected
    }
}

/// CLI 선택 상태
struct CLISelectionState: Equatable {
    var options: [CLISelectionOption]
    var isWaitingForSelection: Bool

    init(options: [CLISelectionOption] = [], isWaitingForSelection: Bool = false) {
        self.options = options
        self.isWaitingForSelection = isWaitingForSelection
    }

    static let empty = CLISelectionState()
}

/// 채팅 세션 (프로젝트별 저장용)
struct AIChatSession: Codable {
    let id: UUID
    let projectPath: String
    let cliType: String
    var messages: [AIMessage]
    let createdAt: Date
    var updatedAt: Date

    /// CLI 세션 ID (대화 연속성 유지용)
    /// Claude CLI: --resume 옵션에 사용
    var cliSessionId: String?

    init(
        id: UUID = UUID(),
        projectPath: String,
        cliType: String,
        messages: [AIMessage] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        cliSessionId: String? = nil
    ) {
        self.id = id
        self.projectPath = projectPath
        self.cliType = cliType
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.cliSessionId = cliSessionId
    }
}
