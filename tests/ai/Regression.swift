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
    func prepareForAIWorkspaceEdit(project: URL) throws {}
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
        if CommandLine.arguments.contains("--live-workspace") {
            let project = FileManager.default.temporaryDirectory.appendingPathComponent("TextlinkEditor-Live-" + UUID().uuidString + ".weaveproj")
            try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: project) }
            let file = project.appendingPathComponent("draft.md")
            try "첫 번째 행\n2".write(to: file, atomically: true, encoding: .utf8)
            let id = UUID(), before = try AIWorkspaceEdits.prepare(id: UUID(), project: project)
            let result = try await CLIProcessManager().sendPrompt("Edit only draft.md in this temporary QA project. Read it, replace its last line 2 with 새로운문장, save preserving the first line and no trailing newline, then read the saved file to verify. Do not change any other file. Reply briefly.", cliType: .chatgpt, workingDirectory: project, allowsWorkspaceEdits: true) { _ in }
            try AIWorkspaceEdits.finish(id: id, before: before, project: project)
            let actual = try String(contentsOf: file, encoding: .utf8)
            guard actual == "첫 번째 행\n새로운문장",
                  AIWorkspaceEdits.load(id: id, project: project)?.changes.first?.after == actual else {
                fatalError("Live workspace edit failed: " + result.response)
            }
            print("PASS live Codex workspace edit, exact saved bytes, persisted before/after comparison")
            return
        }
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
        vm.errorMessage = "existing sidebar error"
        vm.sendMessage(continueFromCardId: sidebarConversation, inlineInput: "검정으로 수정", inlineRevision: edit)
        while vm.isProcessing { try await Task.sleep(nanoseconds: 20_000_000) }
        expect(fullText == (editBase as NSString).replacingCharacters(in: NSRange(location: 0, length: 5), with: "검정"), "inline edit executes replacement on captured range")
        expect(vm.messages.last?.kind == "inlineEdit" && vm.messages.last?.outcome == "completed", "inline edit records applied outcome separately")
        expect(ChatHistoryManager.shared.loadSession(from: b)?.messages.last?.kind == "inlineEdit", "inline category survives history persistence")
        let firstEditConversation = vm.messages.last!.conversationId
        expect(firstEditConversation != sidebarConversation, "inline edit always creates a new history conversation")
        expect(vm.selectedCardId == sidebarConversation && vm.inputText == "keep sidebar draft", "automatic edit does not display a new sidebar answer or replace its draft")
        expect(vm.errorMessage == "existing sidebar error", "inline success leaves sidebar errors unchanged")
        let beforeStale = vm.messages.count
        vm.sendMessage(inlineInput: "stale edit", inlineRevision: edit)
        expect(vm.messages.count == beforeStale && !vm.isProcessing, "stale inline target prevents dispatch")
        expect(vm.inlineErrorMessage != nil && vm.errorMessage == "existing sidebar error", "preflight error stays in inline input")
        fullText = editBase
        try fixture("cat >/dev/null\nprintf '%s\\n' '{\"type\":\"result\",\"subtype\":\"success\",\"result\":\"ordinary chat is not an edit\"}'\n")
        vm.sendMessage(inlineInput: "invalid result", inlineRevision: edit)
        while vm.isProcessing { try await Task.sleep(nanoseconds: 20_000_000) }
        expect(fullText == editBase && vm.messages.last?.outcome == "failed", "conversational response cannot overwrite manuscript")
        expect(vm.messages.last?.conversationId != firstEditConversation, "each inline edit has an independent history entry")
        expect(vm.selectedCardId == sidebarConversation && vm.inputText == "keep sidebar draft", "failed inline edit preserves sidebar conversation and draft")
        expect(vm.errorMessage == "existing sidebar error" && vm.inlineErrorMessage == nil, "accepted inline failure appears only in history")
        expect(vm.messages.last?.content.contains("ordinary chat is not an edit") == true, "failed edit retains original AI response in history")
        expect(ChatHistoryManager.shared.loadSession(from: b)?.messages.last?.content == vm.messages.last?.content, "failed AI response survives persistence")
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
        let workspace = folder.appendingPathComponent("Workspace.weaveproj")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let workspaceManuscript = workspace.appendingPathComponent("draft.md")
        let removed = workspace.appendingPathComponent("removed.txt")
        try "first\n2".write(to: workspaceManuscript, atomically: true, encoding: .utf8)
        try "remove me".write(to: removed, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: workspace.appendingPathComponent("outside.md"), withDestinationURL: executable)
        let editID = UUID(), before = try AIWorkspaceEdits.prepare(id: UUID(), project: workspace)
        expect(before.count == 2, "snapshot excludes symlinks and metadata")
        let codexExecutable = folder.appendingPathComponent("codex")
        UserSettings.shared.path = codexExecutable
        func codexFixture(_ body: String) throws {
            try ("#!/bin/sh\nprintf '%s\n' \"$@\" > arguments.log\ncat >/dev/null\n" + body).write(to: codexExecutable, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: codexExecutable.path)
        }
        try codexFixture("printf 'first\\n새로운문장' > draft.md\nprintf 'created' > new.md\nrm removed.txt\nprintf '%s\\n' '{\"type\":\"item.completed\",\"item\":{\"type\":\"agent_message\",\"text\":\"Explanation, not workspaceManuscript text\"}}' '{\"type\":\"turn.completed\"}'\n")
        _ = try await manager.sendPrompt("edit", cliType: .chatgpt, workingDirectory: workspace, allowsWorkspaceEdits: true) { _ in }
        let arguments = try String(contentsOf: workspace.appendingPathComponent("arguments.log"), encoding: .utf8)
        expect(arguments.contains("workspace-write") && arguments.contains(workspace.path) && !arguments.contains("danger-full-access"), "normal Codex explicitly bounds workspace writing")
        try AIWorkspaceEdits.finish(id: editID, before: before, project: workspace)
        let edits = AIWorkspaceEdits.load(id: editID, project: workspace)!
        expect(edits.changes.count == 3, "created, deleted and edited files recorded")
        let changed = edits.changes.first { $0.relativePath == "draft.md" }!
        expect(changed.before == "first\n2" && changed.after == "first\n새로운문장", "comparison uses disk revisions, not response prose")
        expect(edits.changes.first { $0.relativePath == "removed.txt" }?.after == nil, "deleted file retains original")
        expect(edits.changes.first { $0.relativePath == "new.md" }?.before == nil, "created file retains absent baseline")
        try codexFixture("printf '%s\\n' '{\"type\":\"turn.completed\"}'\n")
        _ = try await manager.sendPrompt("inline", cliType: .chatgpt, workingDirectory: workspace) { _ in }
        expect(try! String(contentsOf: workspace.appendingPathComponent("arguments.log"), encoding: .utf8).contains("read-only"), "inline/default CLI remains read-only")
        let failedID = UUID(), failedBefore = try AIWorkspaceEdits.snapshot(project: workspace)
        try codexFixture("printf 'partial' > draft.md\nexit 7\n")
        do { _ = try await manager.sendPrompt("fail after write", cliType: .chatgpt, workingDirectory: workspace, allowsWorkspaceEdits: true) { _ in }; preconditionFailure("expected failure") } catch {}
        try AIWorkspaceEdits.finish(id: failedID, before: failedBefore, project: workspace)
        expect(AIWorkspaceEdits.load(id: failedID, project: workspace)?.changes.first?.after == "partial", "partial writes remain comparable after process failure")
        let cancelledID = UUID(), cancelledBefore = try AIWorkspaceEdits.snapshot(project: workspace)
        try codexFixture("printf 'cancelled write' > draft.md\nexec /bin/sleep 30\n")
        let pendingEdit = Task { try await manager.sendPrompt("cancel after write", cliType: .chatgpt, workingDirectory: workspace, allowsWorkspaceEdits: true) { _ in } }
        for _ in 0..<100 {
            if (try? String(contentsOf: workspaceManuscript, encoding: .utf8)) == "cancelled write" { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        pendingEdit.cancel()
        do { _ = try await pendingEdit.value; preconditionFailure("expected cancellation") } catch {}
        try AIWorkspaceEdits.finish(id: cancelledID, before: cancelledBefore, project: workspace)
        expect(AIWorkspaceEdits.load(id: cancelledID, project: workspace)?.changes.first?.after == "cancelled write", "partial writes remain comparable after cancellation")
        try ManuscriptRevisionBridge.remove(id: editID, project: workspace)
        expect(!AIWorkspaceEdits.exists(id: editID, project: workspace), "history cleanup removes actual revision records")
        print("AI regression passed: \(assertions) assertions (fixtures only)")
    }
}
