import Foundation

/// 채팅 히스토리 매니저
final class LegacyAIHistoryReader {
    static let shared = LegacyAIHistoryReader()

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

    // MARK: - Public API (Legacy Support)

    /// 채팅 세션 로드 (기존 AIChatSession 형식으로 변환)
    func loadSession(from projectFolderURL: URL) -> AIChatSession? {
        lastLoadFailed = false
        // 새 형식 먼저 시도
        if let metadata = loadMetadata(from: projectFolderURL) {
            guard metadata.schemaVersion <= 2 else { lastLoadFailed = true; return nil }
            var messages: [AIMessage] = []
            var seenIds = Set<UUID>()

            for cardId in metadata.cardIds {
                if let card = loadCard(id: cardId, from: projectFolderURL) {
                    // 데이터 유효성 검사: userMessage는 반드시 user role이어야 함
                    guard card.id == cardId, card.userMessage.id == cardId, card.userMessage.role == .user else {
                        print("⚠️ ChatHistoryManager: 카드 \(cardId) - userMessage의 role이 user가 아님, 스킵")
                        lastLoadFailed = true
                        continue
                    }

                    // 중복 ID 검사
                    if seenIds.contains(card.userMessage.id) {
                        print("⚠️ ChatHistoryManager: 중복 ID 발견 - \(card.userMessage.id), 스킵")
                        lastLoadFailed = true
                        continue
                    }
                    seenIds.insert(card.userMessage.id)

                    messages.append(card.userMessage)

                    if let assistant = card.assistantMessage {
                        // assistantMessage 유효성 검사
                        guard assistant.role == .assistant else {
                            print("⚠️ ChatHistoryManager: 카드 \(cardId) - assistantMessage의 role이 assistant가 아님, 스킵")
                            lastLoadFailed = true
                            continue
                        }

                        // assistant ID도 중복 검사
                        if seenIds.contains(assistant.id) {
                            print("⚠️ ChatHistoryManager: assistant 중복 ID 발견 - \(assistant.id), 스킵")
                            lastLoadFailed = true
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

        guard !lastLoadFailed else { return nil }
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
