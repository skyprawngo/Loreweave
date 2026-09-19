import SwiftUI

struct AIDocumentSnapshot {
    let name: String
    let content: String
}

@MainActor @Observable
final class AIAssistantViewModel {
    static let shared = AIAssistantViewModel()
    let chatGPTAccount = ChatGPTAccountService()
    let collaboration = CollaborationCoordinator()
    var connectionState: AIConnectionState = .inactive
    var selectedCLIType: AICLIType?
    var installStatus: CLIInstallationStatus = .unknown
    var messages: [AIMessage] = []
    var inputText = ""
    var isProcessing = false
    var taggedCardIds: Set<UUID> = []
    var selectionState: CLISelectionState = .empty
    var showingHistory = false
    var selectedCardId: UUID?
    var includeCurrentDocument = false
    var errorMessage: String?
    var inlineErrorMessage: String?
    private var historyLoadFailed = false
    private var projectFolderURL: URL?
    private var cardSessionIds: [UUID: String] = [:]
    private let processManager: any AIRequestExecuting
    private let history: any AIHistoryRepository
    private var requestTask: Task<Void, Never>?
    private var setupTask: Task<Void, Never>?
    private var requestId: UUID?

    var availableModels: [AIModelOption] {
        get { modelPreferences.availableModels }
        set { modelPreferences.availableModels = newValue }
    }
    var modelsLoading = false
    var modelsError = false
    private var modelCatalogOwner = UUID()
    let modelPreferences: AIModelPreferences
    var modelSelections: [String: String] {
        get { modelPreferences.modelSelections }
        set { modelPreferences.modelSelections = newValue }
    }
    func models(for type: AICLIType) -> [AIModelOption] { modelPreferences.models(for: type) }
    func selectedModel(for type: AICLIType, category: AIConversationCategory = .chat) -> AIModelOption? {
        modelPreferences.selectedModel(for: type, category: category)
    }
    func selectModel(_ id: String, for type: AICLIType, category: AIConversationCategory = .chat) {
        modelPreferences.selectModel(id, for: type, category: category)
    }
    func selectEffort(_ effort: String, for type: AICLIType, category: AIConversationCategory = .chat) {
        modelPreferences.selectEffort(effort, for: type, category: category)
    }
    func requestOptions(for type: AICLIType, category: AIConversationCategory = .chat) -> AIRequestOptions {
        modelPreferences.requestOptions(for: type, category: category)
    }
    func refreshModels() async {
        let owner = UUID()
        modelCatalogOwner = owner
        modelsLoading = true
        modelsError = false
        defer { if modelCatalogOwner == owner { modelsLoading = false } }
        do {
            let models = try await chatGPTAccount.availableModels()
            guard modelCatalogOwner == owner else { return }
            availableModels = models
            for category in AIConversationCategory.allCases {
                if let model = selectedModel(for: .chatgpt, category: category) {
                    selectModel(model.id, for: .chatgpt, category: category)
                }
            }
            modelsError = models.isEmpty
        } catch {
            guard modelCatalogOwner == owner else { return }
            modelsError = true
        }
    }

    init(modelDefaults: UserDefaults = .standard, history: any AIHistoryRepository = JSONAIHistoryRepository(),
         executor: (any AIRequestExecuting)? = nil) {
        modelPreferences = AIModelPreferences(modelDefaults: modelDefaults)
        self.history = history
        self.processManager = executor ?? CLIProcessManager()
        loadSavedState()
        collaboration.runtime = { [weak self] in
            guard let self, !self.isProcessing, case .connected(let provider) = self.connectionState,
                  provider != .chatgpt || self.chatGPTAccount.account != nil else { return nil }
            return (provider, self.requestOptions(for: provider), self.processManager)
        }
    }

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
        inlineErrorMessage = nil
        if let url, case .connected(let type) = connectionState { loadHistory(type, url: url) }
        collaboration.setProject(url)
    }

    private func loadHistory(_ type: AICLIType, url: URL) {
        do {
            let snapshot = try history.load(from: url)
            historyLoadFailed = false
            messages = snapshot?.session.messages ?? []
            taggedCardIds = snapshot?.metadata.taggedCardIds ?? []
            // A session belongs to the provider of its last response, not the last
            // provider selected for the project as a whole.
            cardSessionIds = snapshot?.sessionIds ?? [:]
            selectedCardId = messages.last(where: {
                $0.role == .user && $0.category == .chat && ($0.provider ?? snapshot?.metadata.cliType) == type.rawValue
            }).map { $0.conversationId ?? $0.id }
        } catch {
            historyLoadFailed = true
            errorMessage = L10n.get("ai.error.historyLoadFailed")
        }
    }

    func resumableSession(for conversationId: UUID, provider: AICLIType) -> String? {
        guard let last = messages.last(where: {
            ($0.conversationId ?? $0.id) == conversationId && $0.role == .assistant
        }), last.category == .chat, last.outcome == nil || last.outcome == "completed",
           last.provider == provider.rawValue else { return nil }
        return cardSessionIds[conversationId]
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

    func sendMessage(continueFromCardId: UUID? = nil, inlineInput: String? = nil, inlineRevision: ManuscriptRevision? = nil) {
        func reportPreparationError(_ message: String) {
            if inlineRevision != nil { inlineErrorMessage = message }
            else { errorMessage = message }
        }
        let requestInput = inlineInput ?? inputText
        let attachDocument = inlineInput == nil && includeCurrentDocument
        guard !isProcessing, !collaboration.isWorking, !requestInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              case .connected(let type) = connectionState else { return }
        if type == .chatgpt && chatGPTAccount.account == nil { connectionState = .ready(type); return }
        guard let projectURL = projectFolderURL else { reportPreparationError(L10n.get("ai.error.noProject")); return }
        guard !UserSettings.shared.aiTerminalMode else {
            reportPreparationError(CLIProcessManager.CLIError.terminalUnavailable.localizedDescription)
            return
        }
        guard !historyLoadFailed else { reportPreparationError(L10n.get("ai.error.historyLoadFailed")); return }
        if inlineRevision != nil { inlineErrorMessage = nil }
        else { errorMessage = nil }
        let id = UUID()
        let userId = UUID()
        let continuedConversation = continueFromCardId ?? (inlineInput == nil ? selectedCardId : nil)
        let conversationId = inlineRevision == nil ? (continuedConversation ?? userId) : userId
        let assistantId = UUID()
        var requestPersisted = false
        defer { if !requestPersisted { removeRequestArtifacts(ids: [assistantId]) } }
        let category: AIConversationCategory = inlineRevision == nil ? .chat : .inlineEdit
        if let savedModel = modelSelections[modelPreferences.preferenceKey(type, category)], !savedModel.isEmpty,
           selectedModel(for: type, category: category) == nil {
            reportPreparationError(L10n.get("ai.model.retry"))
            return
        }
        var options = requestOptions(for: type, category: category)
        options.readsProjectFiles = inlineRevision == nil
        let originalInput = requestInput
        let existingSession = inlineRevision == nil ? resumableSession(for: conversationId, provider: type) : nil
        let prepared: PreparedAIRequest
        do {
            prepared = try AIRequestPreparer().prepare(requestInput: requestInput, type: type,
                projectURL: projectURL, assistantId: assistantId, inlineRevision: inlineRevision,
                attachDocument: attachDocument, messages: messages, taggedCardIds: taggedCardIds,
                existingSession: existingSession, continueFromCardId: continuedConversation)
        } catch { reportPreparationError(error.localizedDescription); return }
        messages.append(AIMessage(id: userId, role: .user, content: originalInput, conversationId: conversationId, kind: category.rawValue, provider: type.rawValue, model: options.model, reasoningEffort: options.effort))
        messages.append(AIMessage(id: assistantId, role: .assistant, content: "", isStreaming: true, conversationId: conversationId, kind: category.rawValue, provider: type.rawValue, model: options.model, reasoningEffort: options.effort))
        guard persist() else { messages.removeLast(2); return }
        requestPersisted = true
        if inlineInput == nil {
            inputText = ""
            selectedCardId = conversationId
        }
        isProcessing = true
        requestId = id
        requestTask = Task { [weak self] in
            guard let self else { return }
            let executor = AIWorkspaceProposalExecutor(base: processManager, requestID: assistantId, project: projectURL)
            var receivedResponse: String?
            do {
                let result = try await executor.sendPrompt(prepared.prompt, cliType: type, workingDirectory: projectURL,
                                                                 sessionId: existingSession, allowsWorkspaceEdits: prepared.allowsWorkspaceEdits, options: options) { [weak self] chunk in
                    guard let self, requestId == id, projectFolderURL == projectURL,
                          let index = messages.firstIndex(where: { $0.id == assistantId }) else { return }
                    let old = messages[index]
                    messages[index] = AIMessage(id: old.id, role: .assistant, content: old.content + chunk,
                                               timestamp: old.timestamp, isStreaming: true, conversationId: conversationId, kind: old.kind, provider: old.provider, model: old.model, reasoningEffort: old.reasoningEffort)
                }
                guard requestId == id, projectFolderURL == projectURL, !Task.isCancelled else { return }
                if let session = result.sessionId ?? existingSession {
                    cardSessionIds[conversationId] = session
                } else {
                    cardSessionIds.removeValue(forKey: conversationId)
                }
                receivedResponse = result.response
                if let inlineRevision {
                    let replacement = try InlineEditRequest.replacement(from: result.response)
                    try ManuscriptRevisionBridge.apply(inlineRevision, proposal: replacement,
                        selected: Set(inlineRevision.changes(proposal: replacement).map(\.id)), project: projectURL)
                    finish(assistantId, content: L10n.get("ai.inline.applied") + "\n\n" + replacement, outcome: "completed", usage: result.usage)
                } else {
                    finish(assistantId, content: result.response, outcome: "completed", usage: result.usage)
                }
            } catch {
                guard requestId == id, projectFolderURL == projectURL else { return }
                // A failed session may be missing or contain an incomplete turn.
                // A user retry rebuilds context from saved completed messages.
                cardSessionIds.removeValue(forKey: conversationId)
                // Accepted inline requests report only in their own history entry.
                // Never replace the unrelated sidebar conversation's error or draft.
                if inlineRevision == nil { errorMessage = error.localizedDescription }
                // Keep the prompt available for editing/retry without dropping its persisted failed turn.
                if inlineInput == nil { inputText = originalInput }
                let response = receivedResponse ?? messages.first(where: { $0.id == assistantId })?.content ?? ""
                let failureRecord = inlineRevision != nil && !response.isEmpty
                    ? error.localizedDescription + "\n\n" + response : error.localizedDescription
                finish(assistantId, content: failureRecord, outcome: "failed")
            }
        }
    }

    private func finish(_ messageId: UUID, content: String, outcome: String, usage: AIContextUsage? = nil) {
        guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return }
        let old = messages[index]
        messages[index] = AIMessage(id: old.id, role: .assistant, content: content, timestamp: old.timestamp,
                                   conversationId: old.conversationId, outcome: outcome, kind: old.kind, usage: usage, provider: old.provider, model: old.model, reasoningEffort: old.reasoningEffort)
        requestId = nil
        requestTask = nil
        isProcessing = false
        _ = persist()
    }

    func cancelSend() {
        collaboration.cancel()
        requestId = nil // invalidate callbacks before touching process/UI state
        requestTask?.cancel()
        processManager.cancel()
        requestTask = nil
        if let index = messages.lastIndex(where: \.isStreaming) {
            let old = messages[index]
            if let root = old.conversationId { cardSessionIds.removeValue(forKey: root) }
            let content = old.content.isEmpty ? L10n.get("ai.chat.cancelled") : old.content + "\n\n" + L10n.get("ai.chat.cancelled")
            messages[index] = AIMessage(id: old.id, role: .assistant, content: content,
                                       timestamp: old.timestamp, conversationId: old.conversationId, outcome: "cancelled", kind: old.kind, provider: old.provider, model: old.model, reasoningEffort: old.reasoningEffort)
            _ = persist()
        }
        isProcessing = false
    }

    private func persist() -> Bool {
        guard !historyLoadFailed, let url = projectFolderURL, case .connected(let type) = connectionState else { return false }
        do {
            try history.save(messages: messages, taggedIds: taggedCardIds,
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
        else {
            selectedCardId = nil
            do {
                let ids = try projectFolderURL.map { try AIContextSelection.shared.savedRequestIDs(projectURL: $0) } ?? []
                removeRequestArtifacts(ids: ids.union(previous.map(\.id)))
            } catch { errorMessage = error.localizedDescription }
        }
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
        else {
            if selectedCardId == id { selectedCardId = nil }
            let retained = Set(messages.map(\.id))
            removeRequestArtifacts(previous.filter { !retained.contains($0.id) })
        }
    }
    private func removeRequestArtifacts(_ removed: [AIMessage]) {
        removeRequestArtifacts(ids: Set(removed.filter { $0.role == .assistant }.map(\.id)))
    }
    private func removeRequestArtifacts(ids: Set<UUID>) {
        guard let project = projectFolderURL else { return }
        var failures: [String] = []
        for id in ids {
            do { try ManuscriptRevisionBridge.remove(id: id, project: project) }
            catch { failures.append(error.localizedDescription) }
            do { try AIContextSelection.shared.removeManifest(requestID: id, projectURL: project) }
            catch { failures.append(error.localizedDescription) }
        }
        if !failures.isEmpty { errorMessage = failures.joined(separator: "\n") }
    }
    func sendSelectionResponse(_ optionId: Int) { /* interactive mode is no longer supported */ }
}
