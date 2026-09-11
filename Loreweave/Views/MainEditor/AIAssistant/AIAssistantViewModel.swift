import SwiftUI

struct AIDocumentSnapshot {
    let name: String
    let content: String
}

@MainActor @Observable
final class AIAssistantViewModel {
    let chatGPTAccount = ChatGPTAccountService()
    var connectionState: AIConnectionState = .inactive
    var selectedCLIType: AICLIType?
    var installStatus: CLIInstallationStatus = .unknown
    var messages: [AIMessage] = []
    var inputText = ""
    var isProcessing = false
    var taggedCardIds: Set<UUID> = []
    var selectionState: CLISelectionState = .empty
    var selectedCardId: UUID?
    var includeCurrentDocument = false
    var errorMessage: String?
    private var historyLoadFailed = false
    private var projectFolderURL: URL?
    private var cardSessionIds: [UUID: String] = [:]
    private let processManager = CLIProcessManager()
    private var requestTask: Task<Void, Never>?
    private var setupTask: Task<Void, Never>?
    private var requestId: UUID?

    init() { loadSavedState() }

    func loadSavedState() {
        guard UserSettings.shared.aiAssistantEnabled else {
            cancelSend()
            connectionState = .inactive
            return
        }
        guard let type = AICLIType(rawValue: UserSettings.shared.aiAssistantCLIType) else {
            connectionState = .selectingAI
            return
        }
        selectedCLIType = type
        checkCLIInstallation(type)
    }

    func setProject(_ url: URL?) {
        guard url != projectFolderURL else { return }
        cancelSend()
        projectFolderURL = url
        messages = []
        taggedCardIds = []
        cardSessionIds = [:]
        selectedCardId = nil
        inputText = ""
        includeCurrentDocument = false
        errorMessage = nil
        if let url, case .connected(let type) = connectionState { loadHistory(type, url: url) }
    }

    private func loadHistory(_ type: AICLIType, url: URL) {
        let history = ChatHistoryManager.shared
        let session = history.loadSession(from: url)
        historyLoadFailed = history.lastLoadFailed
        if historyLoadFailed { errorMessage = L10n.get("ai.error.historyLoadFailed") }
        messages = session?.messages ?? []
        taggedCardIds = history.loadTaggedCardIds(from: url)
        // A provider may only resume its own sessions. Cross-provider continuations use app history.
        if session?.cliType == type.rawValue {
            cardSessionIds = history.loadCardSessionIds(from: url)
        } else { cardSessionIds = [:] }
    }

    func prepareDraftAction(_ instruction: String) {
        inputText = instruction
        includeCurrentDocument = true
        selectedCardId = nil
    }

    func startConnection() {
        UserSettings.shared.aiAssistantEnabled = true
        loadSavedState()
    }

    func confirmAISelection(_ type: AICLIType) {
        UserSettings.shared.aiAssistantCLIType = type.rawValue
        selectedCLIType = type
        checkCLIInstallation(type)
    }

    func checkCLIInstallation(_ type: AICLIType, skipAutoDetect: Bool = false) {
        setupTask?.cancel()
        connectionState = .checkingCLI(type)
        installStatus = .checking
        setupTask = Task { [weak self] in
            let status = await CLIDetector.shared.checkInstallation(for: type)
            guard !Task.isCancelled, let self else { return }
            installStatus = status
            if case .installed = status {
                if type == .chatgpt {
                    await chatGPTAccount.refresh()
                    guard !Task.isCancelled else { return }
                    if chatGPTAccount.account != nil { completeConnection(type) }
                    else { connectionState = .ready(type) }
                } else { completeConnection(type) }
            }
            else { connectionState = .cliNotInstalled(type) }
        }
    }

    func completeConnection(_ type: AICLIType) {
        cancelSend()
        UserSettings.shared.aiAssistantEnabled = true
        UserSettings.shared.aiAssistantCLIType = type.rawValue
        selectedCLIType = type
        connectionState = .connected(type)
        selectedCardId = nil
        if let url = projectFolderURL { loadHistory(type, url: url) }
    }

    func changeAI() { cancelSend(); chatGPTAccount.cancelLogin(); connectionState = .selectingAI }
    func disconnect() {
        cancelSend()
        setupTask?.cancel()
        chatGPTAccount.cancelLogin()
        UserSettings.shared.aiAssistantEnabled = false
        UserSettings.shared.aiAssistantCLIType = ""
        connectionState = .inactive
        selectedCLIType = nil
    }
    func cancelSetup() { disconnect(); installStatus = .unknown }
    func openInstallPage() {
        if let selectedCLIType { CLIInstaller.shared.openInstallPage(for: selectedCLIType) }
    }
    func selectCLIPath(_ url: URL) {
        guard let type = selectedCLIType else { return }
        guard CLIDetector.isValidExecutable(url, for: type) else {
            installStatus = .installationFailed(L10n.get("ai.error.invalidExecutable"))
            return
        }
        if UserSettings.shared.setAICLIPath(url) { checkCLIInstallation(type) }
    }

    /// Both preview and send use the flushed editor cache, including unsaved changes.
    func currentDocumentSnapshot() -> AIDocumentSnapshot? {
        EditorTabManager.shared.flushEditor()
        guard let tab = EditorTabManager.shared.selectedTab,
              let content = EditorTabManager.shared.getCachedContent(for: tab.url) else { return nil }
        return AIDocumentSnapshot(name: tab.title, content: content)
    }

    func sendMessage(continueFromCardId: UUID? = nil) {
        guard !isProcessing, !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              case .connected(let type) = connectionState else { return }
        if type == .chatgpt && chatGPTAccount.account == nil { connectionState = .ready(type); return }
        guard let projectURL = projectFolderURL else { errorMessage = L10n.get("ai.error.noProject"); return }
        guard !UserSettings.shared.aiTerminalMode else {
            errorMessage = CLIProcessManager.CLIError.terminalUnavailable.localizedDescription
            return
        }
        guard !historyLoadFailed else { errorMessage = L10n.get("ai.error.historyLoadFailed"); return }
        errorMessage = nil
        let id = UUID()
        let userId = UUID()
        let conversationId = continueFromCardId ?? userId
        let assistantId = UUID()
        let originalInput = inputText
        // Subscription accounts use the app-visible history, including after migration or account changes.
        let existingSession = type == .chatgpt ? nil : cardSessionIds[conversationId]
        var context: [(question: String, answer: String)] = []
        var question: AIMessage?
        for message in messages {
            if message.role == .user { question = message }
            else if message.role == .assistant, message.outcome == nil || message.outcome == "completed", let question {
                let root = question.conversationId ?? question.id
                if taggedCardIds.contains(root) || (existingSession == nil && root == continueFromCardId) {
                    context.append((question.content, message.content))
                }
            }
        }
        var prompt = AIPromptTemplateManager.shared.buildPromptWithContext(userInput: inputText, taggedCards: context, cliType: type)
        if includeCurrentDocument {
            guard let document = currentDocumentSnapshot() else {
                errorMessage = L10n.get("ai.error.contextUnavailable")
                return
            }
            prompt = AIPromptTemplateManager.render(L10n.get("ai.chat.documentPrompt"),
                values: ["name": document.name, "document": document.content, "question": prompt], doubleBraces: false)
        }
        guard prompt.utf8.count <= 1_000_000 else { errorMessage = L10n.get("ai.error.contextTooLarge"); return }
        messages.append(AIMessage(id: userId, role: .user, content: originalInput, conversationId: conversationId))
        messages.append(AIMessage(id: assistantId, role: .assistant, content: "", isStreaming: true, conversationId: conversationId))
        guard persist() else { messages.removeLast(2); return }
        inputText = ""
        selectedCardId = conversationId
        isProcessing = true
        requestId = id
        requestTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await processManager.sendPrompt(prompt, cliType: type, workingDirectory: projectURL,
                                                                 sessionId: existingSession) { [weak self] chunk in
                    guard let self, requestId == id, projectFolderURL == projectURL,
                          let index = messages.firstIndex(where: { $0.id == assistantId }) else { return }
                    let old = messages[index]
                    messages[index] = AIMessage(id: old.id, role: .assistant, content: old.content + chunk,
                                               timestamp: old.timestamp, isStreaming: true, conversationId: conversationId)
                }
                guard requestId == id, projectFolderURL == projectURL, !Task.isCancelled else { return }
                if let session = result.sessionId { cardSessionIds[conversationId] = session }
                finish(assistantId, content: result.response, outcome: "completed")
            } catch {
                guard requestId == id, projectFolderURL == projectURL else { return }
                errorMessage = error.localizedDescription
                // Keep the prompt available for editing/retry without dropping its persisted failed turn.
                inputText = originalInput
                finish(assistantId, content: error.localizedDescription, outcome: "failed")
            }
        }
    }

    private func finish(_ messageId: UUID, content: String, outcome: String) {
        guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return }
        let old = messages[index]
        messages[index] = AIMessage(id: old.id, role: .assistant, content: content, timestamp: old.timestamp,
                                   conversationId: old.conversationId, outcome: outcome)
        requestId = nil
        requestTask = nil
        isProcessing = false
        _ = persist()
    }

    func cancelSend() {
        requestId = nil // invalidate callbacks before touching process/UI state
        requestTask?.cancel()
        processManager.cancel()
        requestTask = nil
        if let index = messages.lastIndex(where: \.isStreaming) {
            let old = messages[index]
            if let root = old.conversationId { cardSessionIds.removeValue(forKey: root) }
            let content = old.content.isEmpty ? L10n.get("ai.chat.cancelled") : old.content + "\n\n" + L10n.get("ai.chat.cancelled")
            messages[index] = AIMessage(id: old.id, role: .assistant, content: content,
                                       timestamp: old.timestamp, conversationId: old.conversationId, outcome: "cancelled")
            _ = persist()
        }
        isProcessing = false
    }

    private func persist() -> Bool {
        guard !historyLoadFailed, let url = projectFolderURL, case .connected(let type) = connectionState else { return false }
        do {
            try ChatHistoryManager.shared.saveState(messages: messages, taggedIds: taggedCardIds,
                                                    sessionIds: cardSessionIds, cliType: type.rawValue, to: url)
            return true
        } catch { errorMessage = L10n.get("ai.error.historySaveFailed"); return false }
    }
    func clearHistory() {
        cancelSend()
        let previous = messages
        let tags = taggedCardIds
        let sessions = cardSessionIds
        messages = []; taggedCardIds = []; cardSessionIds = [:]
        if !persist() { messages = previous; taggedCardIds = tags; cardSessionIds = sessions }
        else { selectedCardId = nil }
    }
    func saveTaggedCards() { _ = persist() }
    func deleteCard(id: UUID) {
        cancelSend()
        let previous = messages
        let tags = taggedCardIds
        let sessions = cardSessionIds
        messages.removeAll { ($0.conversationId ?? $0.id) == id }
        // Legacy assistant messages have no conversation ID; remove by pairing too.
        if let userIndex = previous.firstIndex(where: { $0.id == id }), userIndex + 1 < previous.count,
           previous[userIndex + 1].role == .assistant {
            let assistantId = previous[userIndex + 1].id
            messages.removeAll { $0.id == assistantId }
        }
        taggedCardIds.remove(id); cardSessionIds.removeValue(forKey: id)
        if !persist() { messages = previous; taggedCardIds = tags; cardSessionIds = sessions }
        else if selectedCardId == id { selectedCardId = nil }
    }
    func sendSelectionResponse(_ optionId: Int) { /* interactive mode is no longer supported */ }
}
