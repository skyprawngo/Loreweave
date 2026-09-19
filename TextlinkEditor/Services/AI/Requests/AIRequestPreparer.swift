import Foundation

struct PreparedAIRequest {
    let prompt: String
    let allowsWorkspaceEdits: Bool
    let workspaceBefore: [String: String]?
}

enum AIRequestPreparationError: LocalizedError {
    case message(String)
    var errorDescription: String? { switch self { case .message(let message): return message } }
}

/// Creates the exact prompt and audit artifacts; never mutates conversation/UI state.
@MainActor
struct AIRequestPreparer {
    func prepare(requestInput: String, type: AICLIType, projectURL: URL, assistantId: UUID,
                 inlineRevision: ManuscriptRevision?, attachDocument: Bool, messages: [AIMessage],
                 taggedCardIds: Set<UUID>, existingSession: String?, continueFromCardId: UUID?) throws -> PreparedAIRequest {
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
        let allowsWorkspaceEdits = inlineRevision == nil && type == .chatgpt
        var workspaceBefore: [String: String]?
        if allowsWorkspaceEdits {
            workspaceBefore = try AIWorkspaceEdits.prepare(id: assistantId, project: projectURL)
        }
        var prompt = AIPromptTemplateManager.shared.buildPromptWithContext(userInput: requestInput, taggedCards: context, cliType: type)
        var revision = inlineRevision ?? (attachDocument ? ManuscriptRevisionBridge.capture(id: assistantId, project: projectURL) : nil)
        revision?.id = assistantId
        if let inlineRevision {
            guard let current = ManuscriptRevisionBridge.capture(id: assistantId, project: projectURL),
                  current.relativePath == inlineRevision.relativePath, current.original == inlineRevision.original,
                  (try? ManuscriptRevisionBridge.documentURL(inlineRevision, project: projectURL)) != nil else {
                throw AIRequestPreparationError.message(L10n.get("revision.unavailable"))
            }
            let payload = InlineEditRequest(instruction: requestInput, original: inlineRevision.target)
            prompt = try payload.prompt()
        }
        if attachDocument {
            guard let revision else {
                throw AIRequestPreparationError.message(L10n.get("ai.error.contextUnavailable"))
            }
            prompt = AIPromptTemplateManager.render(L10n.get("ai.chat.documentPrompt"),
                values: ["name": revision.relativePath, "document": revision.original, "question": prompt], doubleBraces: false)
        }
        if allowsWorkspaceEdits {
            let selectedPath = EditorTabManager.shared.selectedTab?.url.path ?? "(none)"
            prompt += "\n\nTextlinkEditor workspace editing: You may edit manuscript .md/.txt/.markdown files inside the current project when the user requests it. Read the actual file before editing and preserve unrelated content. Do not modify hidden app metadata, authentication, or project settings. Verify the saved result and describe the actual changes, not a proposed rewrite. Current editor file (data): " + selectedPath
        }
        EditorTabManager.shared.flushEditor()
        var manifest = try inlineRevision == nil ? AIContextSelection.shared.manifest(projectURL: projectURL) : AIContextManifest(entries: [], text: "")
        if inlineRevision != nil { manifest.entries = []; manifest.text = "" }
        if !manifest.text.isEmpty { prompt += "\n\n" + manifest.text }
        guard prompt.utf8.count <= 1_000_000 else { throw AIRequestPreparationError.message(L10n.get("ai.error.contextTooLarge")) }
        if let revision { manifest.entries.append(.init(source: revision.relativePath, reason: L10n.get("ai.chat.attachCurrentDocument"), characters: inlineRevision == nil ? revision.original.count : revision.target.count, kind: .manuscript)) }
        if inlineRevision == nil && !context.isEmpty {
            manifest.entries.append(.init(source: L10n.get("ai.workspace.references"), reason: "Conversation context",
                characters: context.reduce(0) { $0 + $1.question.count + $1.answer.count }, kind: .conversation))
        }
        manifest.entries.append(.init(source: L10n.get("ai.chat.user"), reason: "User request", characters: requestInput.count, kind: .request))
        manifest.text = prompt // Exact submitted prompt, including document, references and user request.
        try AIContextSelection.shared.persist(manifest, requestID: assistantId, projectURL: projectURL)
        if let revision {
            try ManuscriptRevisionBridge.save(revision, project: projectURL)
        }
        guard prompt.utf8.count <= 1_000_000 else { throw AIRequestPreparationError.message(L10n.get("ai.error.contextTooLarge")) }
        return PreparedAIRequest(prompt: prompt, allowsWorkspaceEdits: allowsWorkspaceEdits, workspaceBefore: workspaceBefore)
    }
}
