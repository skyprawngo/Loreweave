import Foundation

@MainActor private final class ProposalFixture: AIRequestExecuting {
    var proposal: CollaborationProposal
    var beforeReturn: (() throws -> Void)?
    var capturedPrompt = ""
    var directory: URL?
    init(_ proposal: CollaborationProposal) { self.proposal = proposal }
    func sendPrompt(_ prompt: String, cliType: AICLIType, workingDirectory: URL?, sessionId: String?,
                    allowsWorkspaceEdits: Bool, options: AIRequestOptions,
                    streamHandler: @escaping @MainActor @Sendable (String) -> Void) async throws -> CLIPromptResult {
        precondition(!allowsWorkspaceEdits && options.readsProjectFiles)
        capturedPrompt = prompt
        directory = workingDirectory
        try beforeReturn?()
        return .init(response: String(decoding: try JSONEncoder().encode(proposal), as: UTF8.self), sessionId: "fixture")
    }
    func cancel() {}
}

@MainActor
func checkCollaboration(in folder: URL) async throws {
    var count = 0
    func check(_ value: Bool, _ message: String) {
        precondition(value, "Collaboration: " + message)
        count += 1
    }
    let root = folder.appendingPathComponent("협업 project")
    try FileManager.default.createDirectory(at: root.appendingPathComponent("설정"), withIntermediateDirectories: true)
    let store = CollaborationStore(project: root)
    let setting = try store.file("설정/인물.md")
    let manuscript = try store.file("원고.md")
    try "인물은 범인을 모른다.".write(to: setting, atomically: true, encoding: .utf8)
    try "나는 범인을 모른다.".write(to: manuscript, atomically: true, encoding: .utf8)
    try store.enable()
    check(try store.load().baseline == store.snapshot(), "initial activation establishes baseline")
    let task = try store.enqueue(origin: "comment", instruction: "처음부터 범인을 아는 인물로 바꿔")
    let evidence = [CollaborationEvidence(path: "설정/인물.md", quote: "인물은 범인을 모른다.")]
    let proposal = CollaborationProposal(summary: "설정과 대사 수정",
        edits: [
            .init(path: "설정/인물.md", content: "인물은 처음부터 범인을 안다.", reason: "사용자 결정", evidence: evidence, dependsOn: []),
            .init(path: "원고.md", content: "나는 처음부터 범인을 알았다.", reason: "인물 지식 반영", evidence: evidence, dependsOn: [])
        ], questions: [], facts: [
            .init(id: "knowledge", name: "범인 지식", path: "설정/인물.md", quote: "인물은 처음부터 범인을 안다.",
                  status: "confirmed", storyTime: "처음부터", knownBy: "주인공", decision: "사용자 요청")
        ])
    let fixture = ProposalFixture(proposal)
    _ = try await CollaborationEngine(store: store, executor: fixture).execute(taskID: task, provider: .claude, options: .init())
    check(try String(contentsOf: manuscript, encoding: .utf8) == "나는 처음부터 범인을 알았다.", "related manuscript updated")
    check(fixture.directory != root && !FileManager.default.fileExists(atPath: fixture.directory!.path), "isolated copy disposed")
    check(fixture.capturedPrompt.contains("Dialog, unreliable narration") && fixture.capturedPrompt.contains("reader revelation"), "canon distinctions included in model contract")
    let lore = try WritingWorkspaceStore(projectURL: root).load().lore
    check(lore.first?.body == "" && lore.first?.sourceQuote == "인물은 처음부터 범인을 안다." && lore.first?.canonStatus == "confirmed", "source-linked canon has no duplicate authoritative body")
    check(try store.load().tasks.first?.phase == .completed, "task completed after publication")
    check(try store.load().baseline == store.snapshot(), "AI edits advance baseline without feedback loop")
    try CollaborationApplier(store: store).undo(taskID: task)
    check(try String(contentsOf: manuscript, encoding: .utf8) == "나는 범인을 모른다.", "multi-file undo")
    check(try WritingWorkspaceStore(projectURL: root).load().lore.first?.canonStatus == "superseded", "undo invalidates changed canon evidence")

    let rollbackTask = try store.enqueue(origin: "comment", instruction: "rollback fixture")
    let rollbackBefore = try store.snapshot()
    var checks = 0
    do {
        _ = try CollaborationApplier(store: store, checkEditor: {
            checks += 1
            if checks == 3 { throw CollaborationFailure.conflict }
        }).apply(taskID: rollbackTask, before: rollbackBefore, changes: [
            .init(path: "설정/인물.md", before: rollbackBefore["설정/인물.md"], after: "first write"),
            .init(path: "원고.md", before: rollbackBefore["원고.md"], after: "second write")
        ])
        preconditionFailure("injected failure ignored")
    } catch {}
    check(try store.snapshot() == rollbackBefore, "partial publication failure rolls back all written files")
    check(try store.journals().last?.phase == "rolledBack", "rollback journal durable")

    let narrativeTask = try store.enqueue(origin: "comment", instruction: "대사 검토")
    let narrative = ProposalFixture(.init(summary: "가설 색인", edits: [], questions: [], facts: [
        .init(id: "belief", name: "인물의 주장", path: "원고.md", quote: "나는 범인을 모른다.",
              status: "confirmed", storyTime: "", knownBy: "화자", decision: "대사")
    ]))
    _ = try await CollaborationEngine(store: store, executor: narrative).execute(taskID: narrativeTask, provider: .claude, options: .init())
    check(try WritingWorkspaceStore(projectURL: root).load().lore.first(where: { $0.sourceKey == "belief" })?.canonStatus == "proposed", "manuscript statement cannot automatically become confirmed canon")
    let invalidFactTask = try store.enqueue(origin: "comment", instruction: "invalid evidence")
    narrative.proposal.facts[0].quote = "원문에 없는 추론"
    do {
        _ = try await CollaborationEngine(store: store, executor: narrative).execute(taskID: invalidFactTask, provider: .claude, options: .init())
        preconditionFailure("fabricated quote accepted")
    } catch {}
    check(try store.snapshot() == rollbackBefore, "fabricated evidence never modifies source")

    let blockedTask = try store.enqueue(origin: "comment", instruction: "blocked")
    try store.update { $0.protectedPaths.insert("원고.md") }
    do {
        _ = try await CollaborationEngine(store: store, executor: fixture).execute(taskID: blockedTask, provider: .claude, options: .init())
        preconditionFailure("protected edit accepted")
    } catch {}
    check(try String(contentsOf: setting, encoding: .utf8) == "인물은 범인을 모른다.", "protected edit rejects entire proposal")
    try store.update { $0.protectedPaths = [] }

    let conflictTask = try store.enqueue(origin: "comment", instruction: "concurrent edit")
    fixture.beforeReturn = { try "사용자가 새로 쓴 문장".write(to: manuscript, atomically: true, encoding: .utf8) }
    do {
        _ = try await CollaborationEngine(store: store, executor: fixture).execute(taskID: conflictTask, provider: .claude, options: .init())
        preconditionFailure("concurrent edit overwritten")
    } catch {}
    check(try String(contentsOf: manuscript, encoding: .utf8) == "사용자가 새로 쓴 문장", "concurrent edit preserved")
    fixture.beforeReturn = nil
    try "나는 범인을 모른다.".write(to: manuscript, atomically: true, encoding: .utf8)

    let qTask = try store.enqueue(origin: "comment", instruction: "반전도 유지하고 인물 지식도 바꿔")
    let question = CollaborationQuestion(id: "ending", question: "반전을 유지할까요?", evidence: evidence, options: ["유지", "변경"])
    var questionProposal = proposal
    questionProposal.questions = [question]
    questionProposal.edits[1].dependsOn = ["ending"]
    let questionFixture = ProposalFixture(questionProposal)
    _ = try await CollaborationEngine(store: store, executor: questionFixture).execute(taskID: qTask, provider: .claude, options: .init())
    check(try String(contentsOf: manuscript, encoding: .utf8) == "나는 범인을 모른다.", "dependent edit waits")
    check(try String(contentsOf: setting, encoding: .utf8) == "인물은 처음부터 범인을 안다.", "independent edit proceeds")
    check(try store.load().tasks.first(where: { $0.id == qTask })?.phase == .waiting, "question stored durably")
    try store.updateTask(qTask) { $0.questions[0].answer = "유지"; $0.phase = .queued }
    questionFixture.proposal = .init(summary: "답변 반영",
        edits: [.init(path: "원고.md", content: "나는 범인을 알지만 모른다고 말했다.", reason: "반전 유지",
                      evidence: [.init(path: "설정/인물.md", quote: "인물은 처음부터 범인을 안다.")], dependsOn: ["ending"])],
        questions: [], facts: [])
    _ = try await CollaborationEngine(store: store, executor: questionFixture).execute(taskID: qTask, provider: .claude, options: .init())
    check(try String(contentsOf: manuscript, encoding: .utf8) == "나는 범인을 알지만 모른다고 말했다.", "answer resumes dependent work")
    try "후속 사용자 편집".write(to: manuscript, atomically: true, encoding: .utf8)
    do { try CollaborationApplier(store: store).undo(taskID: qTask); preconditionFailure("undo overwrote user") } catch {}
    check(try String(contentsOf: manuscript, encoding: .utf8) == "후속 사용자 편집", "undo detects later user changes")

    let beforeRecovery = try store.snapshot()
    let recoveryTask = try store.enqueue(origin: "comment", instruction: "recover")
    let recoveryChange = CollaborationChange(path: "원고.md", before: beforeRecovery["원고.md"], after: "중단된 쓰기")
    let journal = CollaborationTransaction(taskID: recoveryTask, changes: [recoveryChange])
    try store.saveJournal(journal)
    try store.updateTask(recoveryTask) { $0.phase = .applying; $0.transactionIDs = [journal.id] }
    try "중단된 쓰기".write(to: manuscript, atomically: true, encoding: .utf8)
    try CollaborationApplier(store: store).recover()
    check(try store.snapshot() == beforeRecovery, "restart rolls back incomplete transaction")
    check(try store.load().tasks.first(where: { $0.id == recoveryTask })?.phase == .review, "interrupted task requires review")

    let changes = [CollaborationChange(path: "원고.md", before: "old", after: "new")]
    let first = try store.enqueue(origin: "documents", instruction: "batch", changes: changes)
    let second = try store.enqueue(origin: "git", instruction: "git", changes: changes)
    check(first == second, "app and Git batches deduplicate")
    let delayedGit = try store.enqueue(origin: "git", instruction: "late Git observation",
        changes: [.init(path: "원고.md", before: "AI has advanced baseline", after: "new")])
    check(first == delayedGit, "late Git observation deduplicates after baseline advances")
    let directed = try store.enqueue(origin: "gitInstruction", instruction: "keep the twist", changes: changes)
    let repeated = try store.enqueue(origin: "gitInstruction", instruction: "keep the twist", changes: changes)
    let different = try store.enqueue(origin: "gitInstruction", instruction: "reveal the twist", changes: changes)
    check(directed == repeated, "identical change instructions deduplicate")
    check(directed != different && directed != first, "distinct author decisions retain separate tasks")
    check(!CollaborationStore.validPath("../outside.md") && !CollaborationStore.validPath(".git/config.md")
          && !CollaborationStore.validPath("image.png"), "unsafe and nontext targets rejected")
    let outside = folder.appendingPathComponent("outside.md")
    try "outside".write(to: outside, atomically: true, encoding: .utf8)
    try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link.md"), withDestinationURL: outside)
    do { _ = try store.file("link.md"); preconditionFailure("symlink accepted") } catch {}
    check(try String(contentsOf: outside, encoding: .utf8) == "outside", "symlink target untouched")

    let gitRoot = folder.appendingPathComponent("git fixture")
    try FileManager.default.createDirectory(at: gitRoot, withIntermediateDirectories: true)
    func git(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-c", "core.hooksPath=/dev/null"] + arguments
        process.currentDirectoryURL = gitRoot
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        precondition(process.terminationStatus == 0)
    }
    try git(["init"])
    let gitFile = gitRoot.appendingPathComponent("draft.md")
    try "staged".write(to: gitFile, atomically: true, encoding: .utf8)
    try git(["add", "--", "draft.md"])
    try "working".write(to: gitFile, atomically: true, encoding: .utf8)
    let stage = try CollaborationGit.staged(project: gitRoot)
    check(stage["draft.md"]! == "staged", "partial staging reads index rather than working tree")
    let gitStore = CollaborationStore(project: gitRoot)
    try gitStore.enable()
    let stagedTask = try gitStore.enqueue(origin: "git", instruction: "staged",
        changes: [.init(path: "draft.md", before: nil, after: "staged")])
    do {
        _ = try await CollaborationEngine(store: gitStore, executor: fixture).execute(taskID: stagedTask, provider: .claude, options: .init())
        preconditionFailure("unstaged edit overwritten")
    } catch {}
    check(try String(contentsOf: gitFile, encoding: .utf8) == "working", "working tree divergence blocks application")
    let subfolder = gitRoot.appendingPathComponent("nested")
    try FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: true)
    do { _ = try CollaborationGit.staged(project: subfolder); preconditionFailure("parent repo accepted") } catch {}
    check(true, "Git root mismatch rejected")
    let renamed = folder.appendingPathComponent("renamed project")
    try FileManager.default.moveItem(at: root, to: renamed)
    check(try CollaborationStore(project: renamed).load().tasks.count == storeCountAtRename(renamed), "project rename retains original collaboration metadata")
    print("Collaboration regression passed: \(count) assertions")
}

@MainActor private func storeCountAtRename(_ root: URL) throws -> Int {
    let data = try Data(contentsOf: root.appendingPathComponent(".협업 project.weavedata/collaboration/state.json"))
    return try JSONDecoder().decode(CollaborationDocument.self, from: data).tasks.count
}
