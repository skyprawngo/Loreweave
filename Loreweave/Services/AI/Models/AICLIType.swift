//
//  AICLIType.swift
//  Loreweave
//
//  AI CLI 타입 정의
//

import Foundation

/// 지원하는 AI CLI 타입
enum AICLIType: String, CaseIterable, Identifiable {
    case claude = "claude"
    case chatgpt = "chatgpt"

    var id: String { rawValue }

    /// 표시 이름
    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .chatgpt: return "ChatGPT"
        }
    }

    /// CLI 명령어 이름
    var commandName: String {
        switch self {
        case .claude: return "claude"
        case .chatgpt: return "chatgpt"
        }
    }

    /// 아이콘 (SF Symbols)
    var iconName: String {
        switch self {
        case .claude: return "brain.head.profile"
        case .chatgpt: return "bubble.left.and.bubble.right"
        }
    }

    /// 공식 설치 페이지 URL
    var installPageURL: URL? {
        switch self {
        case .claude:
            return URL(string: "https://docs.anthropic.com/en/docs/claude-code/getting-started")
        case .chatgpt:
            return URL(string: "https://platform.openai.com/docs/guides/chat")
        }
    }

    /// 공식 설치 스크립트 (있는 경우)
    var installScript: String? {
        switch self {
        case .claude:
            // Claude CLI 공식 설치 명령어 (npm)
            return "npm install -g @anthropic-ai/claude-code"
        case .chatgpt:
            // ChatGPT CLI는 별도 설치 스크립트가 없음
            return nil
        }
    }

    /// Homebrew 설치 명령어 (있는 경우)
    var homebrewFormula: String? {
        switch self {
        case .claude:
            return nil // npm으로 설치
        case .chatgpt:
            return nil
        }
    }

    /// CLI가 설치될 일반적인 경로들
    var possiblePaths: [String] {
        switch self {
        case .claude:
            return [
                "/usr/local/bin/claude",
                "/opt/homebrew/bin/claude",
                "~/.npm-global/bin/claude",
                "/usr/bin/claude"
            ]
        case .chatgpt:
            return [
                "/usr/local/bin/chatgpt",
                "/opt/homebrew/bin/chatgpt",
                "~/.local/bin/chatgpt",
                "/usr/bin/chatgpt"
            ]
        }
    }
}
