//
//  ChatHistoryManager.swift
//  Loreweave
//
//  채팅 히스토리 저장/로드 관리
//

import Foundation

/// 채팅 히스토리 매니저
final class ChatHistoryManager {
    static let shared = ChatHistoryManager()

    private let historyFileName = "ai-chat-history.json"

    private init() {}

    /// 채팅 히스토리 파일 경로 (프로젝트 숨김 폴더 내)
    private func historyFileURL(for projectFolderURL: URL) -> URL {
        let projectName = projectFolderURL.deletingPathExtension().lastPathComponent
        let dataFolderName = ".\(projectName).weavedata"
        let dataFolder = projectFolderURL.appendingPathComponent(dataFolderName)
        return dataFolder.appendingPathComponent(historyFileName)
    }

    /// 채팅 세션 저장
    func saveSession(_ session: AIChatSession, to projectFolderURL: URL) {
        let fileURL = historyFileURL(for: projectFolderURL)

        // 데이터 폴더 생성 확인
        let dataFolder = fileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dataFolder.path) {
            try? FileManager.default.createDirectory(at: dataFolder, withIntermediateDirectories: true)
        }

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(session)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("ChatHistoryManager: 세션 저장 실패 - \(error)")
        }
    }

    /// 채팅 세션 로드
    func loadSession(from projectFolderURL: URL) -> AIChatSession? {
        let fileURL = historyFileURL(for: projectFolderURL)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(AIChatSession.self, from: data)
        } catch {
            print("ChatHistoryManager: 세션 로드 실패 - \(error)")
            return nil
        }
    }

    /// 채팅 세션 삭제
    func deleteSession(from projectFolderURL: URL) {
        let fileURL = historyFileURL(for: projectFolderURL)

        if FileManager.default.fileExists(atPath: fileURL.path) {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    /// 메시지 추가 후 저장
    func appendMessage(_ message: AIMessage, to session: inout AIChatSession, projectFolderURL: URL) {
        session.messages.append(message)
        session.updatedAt = Date()
        saveSession(session, to: projectFolderURL)
    }

    /// 마지막 메시지 업데이트 (스트리밍 완료 시)
    func updateLastMessage(content: String, in session: inout AIChatSession, projectFolderURL: URL) {
        guard !session.messages.isEmpty else { return }

        let lastIndex = session.messages.count - 1
        session.messages[lastIndex] = AIMessage(
            id: session.messages[lastIndex].id,
            role: session.messages[lastIndex].role,
            content: content,
            timestamp: session.messages[lastIndex].timestamp,
            isStreaming: false
        )
        session.updatedAt = Date()
        saveSession(session, to: projectFolderURL)
    }

    /// 세션 히스토리 초기화
    func clearHistory(in session: inout AIChatSession, projectFolderURL: URL) {
        session.messages.removeAll()
        session.updatedAt = Date()
        saveSession(session, to: projectFolderURL)
    }
}
