import Foundation

/// Runtime boundary: implementations own process lifetime, streaming and cancellation.
@MainActor
protocol AIRequestExecuting {
    func sendPrompt(_ prompt: String, cliType: AICLIType, workingDirectory: URL?,
                    sessionId: String?, allowsWorkspaceEdits: Bool, options: AIRequestOptions,
                    streamHandler: @escaping @MainActor @Sendable (String) -> Void) async throws -> CLIPromptResult
    func cancel()
}
