import Foundation

func checkHistoryRepository(in folder: URL) throws {
    func check(_ value: @autoclosure () -> Bool, _ label: String) {
        precondition(value(), label)
        print("PASS \(label)")
    }
    func rejects(_ label: String, _ body: () throws -> Void) {
        do { try body(); preconditionFailure(label) }
        catch { print("PASS \(label)") }
    }
    let repository = JSONAIHistoryRepository()
    let project = folder.appendingPathComponent("Migration.weaveproj")
    let directory = repository.databaseURL(for: project).deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory.appendingPathComponent("cards"), withIntermediateDirectories: true)
    let user = AIMessage(role: .user, content: "legacy")
    let answer = AIMessage(role: .assistant, content: "answer")
    var metadata = ChatSessionMetadata(projectPath: project.path, cliType: "claude", createdAt: Date(timeIntervalSince1970: 100))
    metadata.cardIds = [user.id]
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
    let legacyMetadata = try encoder.encode(metadata)
    let metadataURL = directory.appendingPathComponent("session-metadata.json")
    try legacyMetadata.write(to: metadataURL)
    let cardURL = directory.appendingPathComponent("cards/\(user.id.uuidString).json")
    let legacyCard = try encoder.encode(SavedConversationCard(userMessage: user, assistantMessage: answer))
    try legacyCard.write(to: cardURL)
    let loaded = try repository.load(from: project)!
    check(loaded.session.messages.count == 2, "legacy cards migrate in memory")
    try repository.save(messages: loaded.session.messages, taggedIds: [user.id], sessionIds: [user.id: "session"], cliType: "claude", to: project)
    let database = repository.databaseURL(for: project)
    let committed = try Data(contentsOf: database)
    let migrated = try repository.load(from: project)!
    check(migrated.metadata.createdAt == metadata.createdAt && migrated.sessionIds[user.id] == "session", "migration preserves creation date and session IDs")
    let originalMetadata = try Data(contentsOf: metadataURL)
    let originalCard = try Data(contentsOf: cardURL)
    check(originalMetadata == legacyMetadata && originalCard == legacyCard, "legacy originals remain intact")
    let failing = JSONAIHistoryRepository(write: { _, _ in throw CocoaError(.fileWriteOutOfSpace) })
    rejects("write failure is reported") { try failing.save(messages: [], taggedIds: [], sessionIds: [:], cliType: "claude", to: project) }
    let afterFailure = try Data(contentsOf: database)
    check(afterFailure == committed, "failed commit leaves previous snapshot byte-identical")
    let wrong = AIMessage(role: .assistant, content: "wrong owner", conversationId: UUID())
    rejects("cross-conversation response rejected") { try repository.save(messages: [user, wrong], taggedIds: [], sessionIds: [:], cliType: "claude", to: project) }
    rejects("duplicate message IDs rejected") { try repository.save(messages: [user, user], taggedIds: [], sessionIds: [:], cliType: "claude", to: project) }
    var future = migrated; future.schemaVersion = 999
    try encoder.encode(future).write(to: database)
    rejects("future schema cannot be loaded") { _ = try repository.load(from: project) }
    rejects("future schema cannot be overwritten") { try repository.save(messages: [], taggedIds: [], sessionIds: [:], cliType: "claude", to: project) }
    try Data("broken".utf8).write(to: database)
    rejects("corrupt snapshot does not fall back to stale legacy data") { _ = try repository.load(from: project) }
    rejects("corrupt snapshot cannot be overwritten") { try repository.save(messages: [], taggedIds: [], sessionIds: [:], cliType: "claude", to: project) }
    try committed.write(to: database)
    try repository.save(messages: [], taggedIds: [], sessionIds: [:], cliType: "claude", to: project)
    let cleared = try repository.load(from: project)!
    check(cleared.cards.isEmpty && cleared.metadata.conversations.isEmpty && cleared.sessionIds.isEmpty, "clear commits messages and indexes together")

    let brokenProject = folder.appendingPathComponent("Broken.weaveproj")
    let brokenDirectory = repository.databaseURL(for: brokenProject).deletingLastPathComponent()
    try FileManager.default.createDirectory(at: brokenDirectory, withIntermediateDirectories: true)
    try legacyMetadata.write(to: brokenDirectory.appendingPathComponent("session-metadata.json"))
    rejects("missing legacy card blocks migration") { _ = try repository.load(from: brokenProject) }
}
