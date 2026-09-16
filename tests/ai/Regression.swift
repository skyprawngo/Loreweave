import Foundation

// Compiled with the production parser, process manager, models and history manager.
// Fixture executables emit JSON only; no installed AI CLI or network is used.
final class UserSettings {
    static let shared = UserSettings()
    var path: URL?
    var aiAssistantEnabled = false
    var aiAssistantCLIType = ""
    var aiTerminalMode = false
    func setAICLIPath(_ url: URL) -> Bool { path = url; return true }
    func getAICLIPath() -> URL? { path }
}
struct TestEditorTab { var url: URL; var title: String }
@MainActor final class EditorTabManager {
    static let shared = EditorTabManager()
    var selectedTab: TestEditorTab?
    func flushEditor() {}
    func isModified(url: URL) -> Bool { false }
    func getCachedContent(for url: URL) -> String? { nil }
}
final class CLIInstaller {
    static let shared = CLIInstaller()
    func openInstallPage(for type: AICLIType) {}
}
enum L10n { static func get(_ key: String) -> String { key == "ai.chat.documentPrompt" ? "Document: {name}\n{document}\nQuestion: {question}" : key } }

@main struct AIRegression {
    @MainActor static func main() async throws {
        var assertions = 0
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
            assertions += 1
        }
        let text = "한글🙂é\n日本語"
        let event: [String: Any] = ["type": "stream_event", "event": ["delta": ["type": "text_delta", "text": text]]]
        let result: [String: Any] = ["type": "result", "subtype": "success", "result": text, "session_id": "session-1"]
        let bytes = try JSONSerialization.data(withJSONObject: event) + Data([10]) + JSONSerialization.data(withJSONObject: result) + Data([10])
        var parser = CLIJSONStream()
        var streamed = ""
        for byte in bytes { streamed += parser.append(Data([byte])).joined() }
        parser.finish()
        expect(streamed == text, "UTF-8 split at every byte must survive")
        expect(parser.response == text && parser.completed && !parser.failed, "Explicit final result")
        expect(parser.sessionId == "session-1", "Session ID is structured")
        var partial = CLIJSONStream()
        _ = partial.append(try JSONSerialization.data(withJSONObject: event))
        partial.finish()
        expect(!partial.completed, "Silence/partial data must not complete a response")
        var codex = CLIJSONStream()
        _ = codex.append(Data("{\"type\":\"thread.started\",\"thread_id\":\"thread-1\"}\n{\"type\":\"item.completed\",\"item\":{\"type\":\"agent_message\",\"text\":\"hello\"}}\n{\"type\":\"turn.completed\"}\n".utf8))
        expect(codex.completed && codex.response == "hello" && codex.sessionId == "thread-1", "Codex events")
        var failed = CLIJSONStream()
        _ = failed.append(Data("{\"type\":\"turn.failed\"}\n".utf8))
        expect(failed.failed, "Failed event is not assistant success")
        expect(AIPromptTemplateManager.render("{{question}} {{answer}}", values: ["question": "{{answer}}", "answer": "real"]) == "{{answer}} real", "Inserted text cannot replace another placeholder")

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TextlinkEditorAIRegression-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let a = folder.appendingPathComponent("A.weaveproj")
        let b = folder.appendingPathComponent("B.weaveproj")
        let root = UUID()
        let user = AIMessage(id: root, role: .user, content: "first", conversationId: root)
        let answer = AIMessage(role: .assistant, content: "answer", conversationId: root)
        let second = AIMessage(role: .user, content: "followup", conversationId: root)
        let response = AIMessage(role: .assistant, content: "followup answer", conversationId: root)
        try ChatHistoryManager.shared.saveState(messages: [user, answer, second, response], taggedIds: [root], sessionIds: [root: "session"], cliType: "claude", to: a)
        let bUser = AIMessage(role: .user, content: "B question")
        try ChatHistoryManager.shared.saveState(messages: [bUser], taggedIds: [], sessionIds: [:], cliType: "claude", to: b)
        let loaded = ChatHistoryManager.shared.loadSession(from: a)!
        expect(loaded.messages.count == 4 && loaded.messages.last?.content == response.content, "All turns roundtrip")
        expect(loaded.messages.allSatisfy { $0.conversationId == root }, "Conversation identity persists")
        expect(ChatHistoryManager.shared.loadSession(from: b)?.messages.count == 1, "Other project untouched")
        let old = "{\"projectPath\":\"old\",\"cliType\":\"claude\",\"cardIds\":[],\"createdAt\":\"2026-01-01T00:00:00Z\",\"updatedAt\":\"2026-01-01T00:00:00Z\"}"
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let oldMetadata = try decoder.decode(ChatSessionMetadata.self, from: Data(old.utf8))
        expect(oldMetadata.cardSessionIds.isEmpty, "Missing historical session map migrates")

        let executable = folder.appendingPathComponent("claude")
        UserSettings.shared.path = executable
        func fixture(_ body: String) throws {
            try ("#!/bin/sh\n" + body).write(to: executable, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        }
        try fixture("cat >/dev/null\nprintf '%s\\n' '{\"type\":\"result\",\"subtype\":\"success\",\"result\":\"fixture response\",\"session_id\":\"fixture\"}'\n")
        let manager = CLIProcessManager()
        let prompt = "apostrophe ' $(never execute) 한글"
        let first = try await manager.sendPrompt(prompt, cliType: .claude, workingDirectory: folder) { _ in }
        expect(first.response == "fixture response", "Direct process with stdin works")
        try fixture("cat >/dev/null\nexit 7\n")
        do {
            _ = try await manager.sendPrompt(prompt, cliType: .claude, workingDirectory: folder) { _ in }
            preconditionFailure("Nonzero exit must throw")
        } catch { assertions += 1 }
        try fixture("exit 9\n")
        do {
            _ = try await manager.sendPrompt(String(repeating: "x", count: 500_000), cliType: .claude, workingDirectory: folder) { _ in }
            preconditionFailure("Early exit must throw without killing the host via SIGPIPE")
        } catch CLIProcessManager.CLIError.failed(9) { assertions += 1 }
        try fixture("cat >/dev/null\nprintf '%s\\n' 'unknown option --safe-mode' >&2\nexit 2\n")
        do {
            _ = try await manager.sendPrompt(prompt, cliType: .claude, workingDirectory: folder) { _ in }
            preconditionFailure("Old CLI must report incompatible")
        } catch CLIProcessManager.CLIError.incompatibleCLI { assertions += 1 }
        try fixture("cat >/dev/null\nprintf '%s\\n' '{\"type\":\"result\",\"is_error\":true,\"result\":\"Not logged in\"}'\nexit 1\n")
        do {
            _ = try await manager.sendPrompt(prompt, cliType: .claude, workingDirectory: folder) { _ in }
            preconditionFailure("Authentication must report login required")
        } catch CLIProcessManager.CLIError.authentication { assertions += 1 }
        try fixture("cat >/dev/null\nexec /bin/sleep 30\n")
        let task = Task { try await manager.sendPrompt(prompt, cliType: .claude, workingDirectory: folder) { _ in } }
        try await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        do { _ = try await task.value; preconditionFailure("Cancellation must throw") }
        catch is CancellationError { assertions += 1 }
        try fixture("cat >/dev/null\n/bin/sleep 30 &\necho $! > child.pid\nwait\n")
        let childTask = Task { try await manager.sendPrompt(prompt, cliType: .claude, workingDirectory: folder) { _ in } }
        let childFile = folder.appendingPathComponent("child.pid")
        for _ in 0..<100 where !FileManager.default.fileExists(atPath: childFile.path) {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let childPID = Int32(try String(contentsOf: childFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))!
        childTask.cancel()
        do { _ = try await childTask.value; preconditionFailure("Child-group cancellation must throw") }
        catch is CancellationError { assertions += 1 }
        for _ in 0..<100 where kill(childPID, 0) == 0 { try await Task.sleep(nanoseconds: 10_000_000) }
        expect(kill(childPID, 0) == -1 && errno == ESRCH, "Cancellation terminates inherited CLI child processes")
        try fixture("cat >/dev/null\nexec /bin/sleep 30\n")
        // View-model regression: an old request cannot attach its result to the new project.
        let vm = AIAssistantViewModel()
        vm.completeConnection(.claude)
        vm.setProject(a)
        vm.inputText = "slow A request"
        vm.sendMessage()
        try await Task.sleep(nanoseconds: 100_000_000)
        vm.setProject(b)
        try await Task.sleep(nanoseconds: 200_000_000)
        expect(vm.messages.count == 1 && vm.messages[0].id == bUser.id, "Project switch drops old callbacks")
        expect(ChatHistoryManager.shared.loadSession(from: a)?.messages.last?.outcome == "cancelled", "Cancelled turn belongs to originating project")
        expect(ChatHistoryManager.shared.loadSession(from: b)?.messages.count == 1, "Old answer cannot overwrite B last card")
        try fixture("cat >/dev/null\nprintf '%s\\n' '{\"type\":\"result\",\"subtype\":\"success\",\"result\":\"new response\",\"session_id\":\"new\"}'\n")
        vm.inputText = "B followup"
        vm.sendMessage(continueFromCardId: bUser.id)
        while vm.isProcessing { try await Task.sleep(nanoseconds: 20_000_000) }
        if vm.messages.last?.content != "new response" { FileHandle.standardError.write(Data(("Fixture failure: " + (vm.errorMessage ?? "none") + " content=" + (vm.messages.last?.content ?? "nil") + "\n").utf8)) }
        expect(vm.messages.last?.content == "new response" && vm.selectedCardId == bUser.id, "Followup stays in selected conversation")
        expect(vm.messages.last?.conversationId == bUser.id, "Followup identity remains persisted")
        let manuscript = b.appendingPathComponent("manuscript.md")
        var fullText = "alpha\n한글 😀 원고 전체"
        try fullText.write(to: manuscript, atomically: true, encoding: .utf8)
        EditorTabManager.shared.selectedTab = TestEditorTab(url: manuscript, title: "manuscript.md")
        let observer = NotificationCenter.default.addObserver(forName: Notification.Name("editorWillPerformFileOperation"), object: nil, queue: .main) { note in
            (note.userInfo?["captureSelection"] as? (String, NSRange) -> Void)?(fullText, NSRange(location: 0, length: 5))
            if let apply = note.userInfo?["applyRevision"] as? (String, NSRange) -> String?, let updated = apply(fullText, NSRange(location: 0, length: 5)) { fullText = updated }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        vm.includeCurrentDocument = true
        vm.inputText = "whole manuscript review"
        vm.sendMessage()
        while vm.isProcessing { try await Task.sleep(nanoseconds: 20_000_000) }
        let responseID = vm.messages.last!.id
        let revision = ManuscriptRevisionBridge.load(id: responseID, project: b)!
        expect(revision.target == fullText && revision.selectionLength == fullText.utf16.count, "whole prompt and apply scope match despite selected text")
        let metadata = b.appendingPathComponent(".\(b.deletingPathExtension().lastPathComponent).weavedata")
        let manifest = try JSONDecoder().decode(AIContextManifest.self, from: Data(contentsOf: metadata.appendingPathComponent("ai-context/\(responseID.uuidString).json")))
        expect(manifest.text.contains(fullText) && manifest.entries.contains { $0.kind == .manuscript }, "manifest includes actual submitted manuscript")
        let sidebarConversation = vm.selectedCardId
        vm.inputText = "keep sidebar draft"
        let inlineConversation = UUID()
        vm.sendMessage(continueFromCardId: inlineConversation, inlineInput: "captured passage question")
        while vm.isProcessing { try await Task.sleep(nanoseconds: 20_000_000) }
        expect(vm.inputText == "keep sidebar draft" && vm.selectedCardId == sidebarConversation, "inline request preserves sidebar draft and selected conversation")
        expect(vm.messages.last?.conversationId == inlineConversation && vm.messages.last?.content == "new response", "inline response uses its own persisted conversation")
        let inlineID = vm.messages.last!.id
        let inlineManifest = try JSONDecoder().decode(AIContextManifest.self, from: Data(contentsOf: metadata.appendingPathComponent("ai-context/\(inlineID.uuidString).json")))
        expect(!inlineManifest.entries.contains { $0.kind == .manuscript }, "inline request does not silently attach entire manuscript")
        vm.sendMessage(continueFromCardId: inlineConversation, inlineInput: "follow up inline")
        while vm.isProcessing { try await Task.sleep(nanoseconds: 20_000_000) }
        expect(vm.messages.last?.conversationId == inlineConversation, "inline followup stays in same conversation")
        let editBase = fullText
        let edit = ManuscriptRevision(id: UUID(), relativePath: "manuscript.md", original: editBase, selectionLocation: 0, selectionLength: 5)
        let replacementJSON = String(decoding: try JSONSerialization.data(withJSONObject: ["replacement":"검정"]), as: UTF8.self)
        let editJSON = String(decoding: try JSONSerialization.data(withJSONObject: ["type":"result", "subtype":"success", "result":replacementJSON]), as: UTF8.self)
        try fixture("cat >/dev/null\nprintf '%s\\n' '" + editJSON + "'\n")
        vm.sendMessage(inlineInput: "검정으로 수정", inlineRevision: edit)
        while vm.isProcessing { try await Task.sleep(nanoseconds: 20_000_000) }
        expect(fullText == (editBase as NSString).replacingCharacters(in: NSRange(location: 0, length: 5), with: "검정"), "inline edit executes replacement on captured range")
        expect(vm.messages.last?.kind == "inlineEdit" && vm.messages.last?.outcome == "completed", "inline edit records applied outcome separately")
        expect(ChatHistoryManager.shared.loadSession(from: b)?.messages.last?.kind == "inlineEdit", "inline category survives history persistence")
        let beforeStale = vm.messages.count
        vm.sendMessage(inlineInput: "stale edit", inlineRevision: edit)
        expect(vm.messages.count == beforeStale && !vm.isProcessing, "stale inline target prevents dispatch")
        fullText = editBase
        try fixture("cat >/dev/null\nprintf '%s\\n' '{\"type\":\"result\",\"subtype\":\"success\",\"result\":\"ordinary chat is not an edit\"}'\n")
        vm.sendMessage(inlineInput: "invalid result", inlineRevision: edit)
        while vm.isProcessing { try await Task.sleep(nanoseconds: 20_000_000) }
        expect(fullText == editBase && vm.messages.last?.outcome == "failed", "conversational response cannot overwrite manuscript")
        let orphan = UUID()
        try AIContextSelection.shared.persist(manifest, requestID: orphan, projectURL: b)
        vm.clearHistory()
        let artifactIDs = try AIContextSelection.shared.savedRequestIDs(projectURL: b)
        expect(artifactIDs.isEmpty, "clear history removes orphan and linked artifacts")
        let c = folder.appendingPathComponent("C")
        try FileManager.default.createDirectory(at: c.appendingPathComponent(".C.weavedata"), withIntermediateDirectories: true)
        try Data("invalid directory".utf8).write(to: c.appendingPathComponent(".C.weavedata/ai-revisions"))
        EditorTabManager.shared.selectedTab = TestEditorTab(url: c.appendingPathComponent("draft.md"), title: "draft.md")
        vm.setProject(c); vm.includeCurrentDocument = true; vm.inputText = "failed artifact preparation"
        vm.sendMessage()
        expect(!vm.isProcessing && vm.messages.isEmpty, "artifact preparation failure prevents dispatch")
        let residual = try FileManager.default.contentsOfDirectory(at: c.appendingPathComponent(".C.weavedata/ai-context"), includingPropertiesForKeys: nil)
        expect(residual.isEmpty, "failed revision preparation cleans already persisted manifest")
        print("AI regression passed: \(assertions) assertions (fixtures only)")
    }
}
