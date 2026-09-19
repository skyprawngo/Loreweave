import Foundation

/// Execution decorator: records actual workspace changes even on failure/cancellation.
/// It never changes the AI result or applies manuscript edits itself.
@MainActor
final class AIWorkspaceTrackingExecutor: AIRequestExecuting {
    private let base: any AIRequestExecuting
    private let requestID: UUID
    private let project: URL
    private let before: [String: String]?
    private let reportError: (Error) -> Void

    init(base: any AIRequestExecuting, requestID: UUID, project: URL,
         before: [String: String]?, reportError: @escaping (Error) -> Void) {
        self.base = base
        self.requestID = requestID
        self.project = project
        self.before = before
        self.reportError = reportError
    }
    func sendPrompt(_ prompt: String, cliType: AICLIType, workingDirectory: URL?,
                    sessionId: String?, allowsWorkspaceEdits: Bool, options: AIRequestOptions,
                    streamHandler: @escaping @MainActor @Sendable (String) -> Void) async throws -> CLIPromptResult {
        defer { reconcile() }
        return try await base.sendPrompt(prompt, cliType: cliType, workingDirectory: workingDirectory,
            sessionId: sessionId, allowsWorkspaceEdits: allowsWorkspaceEdits, options: options, streamHandler: streamHandler)
    }
    func cancel() { base.cancel() }

    private func reconcile() {
        guard let before else { return }
        do {
            // Deleted requests must not recreate their artifacts when a cancelled runner exits.
            guard try AIContextSelection.shared.savedRequestIDs(projectURL: project).contains(requestID) else { return }
            try AIWorkspaceEdits.finish(id: requestID, before: before, project: project)
        } catch { reportError(error) }
    }
}
