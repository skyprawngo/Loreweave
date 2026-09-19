import Foundation
import Observation

@MainActor @Observable
final class CollaborationCoordinator {
    var document = CollaborationDocument()
    var pending: [CollaborationChange] = []
    var error: String?
    var notification: String?
    var isWorking = false
    var showingPanel = false
    var commentAnchor: CollaborationAnchor?
    var project: URL?
    var runtime: (() -> (AICLIType, AIRequestOptions, any AIRequestExecuting)?)?
    private var polling: Task<Void, Never>?
    private var active: Task<Void, Never>?
    private var activeExecutor: (any AIRequestExecuting)?
    private var activeID: UUID?
    private var gitCandidate: String?
    private var gitObservedAt = Date()
    private var epoch = UUID()
    private var eventToken: NSObjectProtocol?
    private var needsRefresh = true
    private var gitProbeAt = Date.distantPast

    init() {
        eventToken = WorkspaceFileEvents.shared.observe { [weak self] event in
            guard let self, let project = self.project, DocumentFileStore.contains(event.url, in: project) else { return }
            self.needsRefresh = true
        }
    }

    func setProject(_ url: URL?) {
        guard project != url else { return }
        cancel()
        polling?.cancel()
        epoch = UUID()
        project = url
        commentAnchor = nil
        document = .init()
        pending = []
        error = nil
        notification = nil
        gitCandidate = nil
        needsRefresh = true
        guard let url else { return }
        do {
            let store = CollaborationStore(project: url)
            try CollaborationApplier(store: store, checkEditor: { try EditorTabManager.shared.validateAIApplication(project: url) }).recover()
            try refresh()
        } catch { self.error = error.localizedDescription; return }
        let owner = epoch
        polling = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self, self.epoch == owner else { return }
                await self.tick()
            }
        }
    }

    func refresh() throws {
        guard let project else { return }
        let store = CollaborationStore(project: project)
        document = try store.load()
        if document.enabled {
            let disk = try store.snapshot()
            try store.refreshCanon(contents: disk)
            document = try store.load()
            var visible = disk
            for (path, text) in EditorTabManager.shared.collaborationDrafts(project: project) { visible[path] = text }
            pending = CollaborationStore.changes(from: document.baseline, to: visible)
        } else { pending = [] }
        needsRefresh = false
    }

    func enable() {
        perform { store in
            try EditorTabManager.shared.prepareForAIWorkspaceEdit(project: store.project)
            try store.enable()
        }
    }

    func configure(paused: Bool? = nil, git: Bool? = nil, roots: [String]? = nil, protected: Set<String>? = nil) {
        let pausedTask = paused == true ? activeID : nil
        if paused == true { cancel() }
        perform { store in
            if git == true { _ = try CollaborationGit.staged(project: store.project) }
            try store.update {
                if let paused { $0.paused = paused }
                if let git { $0.gitEnabled = git }
                if let roots {
                    guard roots.allSatisfy({ !$0.isEmpty && !$0.hasPrefix("/") && !$0.split(separator: "/").contains(where: { $0.hasPrefix(".") }) }) else { throw CollaborationFailure.unsafePath }
                    $0.canonRoots = roots
                }
                if let protected { $0.protectedPaths = protected }
                if let pausedTask, let index = $0.tasks.firstIndex(where: { $0.id == pausedTask }) {
                    $0.tasks[index].phase = .queued
                }
            }
        }
    }

    func submitChanges(_ paths: Set<String>) {
        perform { store in
            try EditorTabManager.shared.prepareForAIWorkspaceEdit(project: store.project)
            let state = try store.load()
            let changes = CollaborationStore.changes(from: state.baseline, to: try store.snapshot()).filter { paths.contains($0.path) }
            guard !changes.isEmpty else { return }
            try store.enqueue(origin: "documents", instruction: L10n.get("collaboration.batchInstruction"), changes: changes)
        }
    }

    func submitComment(_ text: String, anchor: CollaborationAnchor? = nil) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        perform { store in
            try EditorTabManager.shared.prepareForAIWorkspaceEdit(project: store.project)
            if !(try store.load().enabled) { try store.enable() }
            if let anchor {
                guard try store.snapshot()[anchor.path].map(CollaborationHash.text) == anchor.version else { throw CollaborationFailure.conflict }
            }
            try store.enqueue(origin: anchor == nil ? "chat" : "comment", instruction: text, anchor: anchor)
            commentAnchor = nil
            showingPanel = true
        }
    }

    func submitVersionChange(path: String, before: String?, after: String?, instruction: String) {
        perform { store in
            guard CollaborationStore.validPath(path), !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CollaborationFailure.unsafePath }
            guard try store.snapshot()[path] == after else { throw CollaborationFailure.conflict }
            if !(try store.load().enabled) { try store.enable() }
            try store.enqueue(origin: "gitInstruction", instruction: instruction,
                changes: [.init(path: path, before: before, after: after)])
            showingPanel = true
        }
    }

    func captureComment() {
        guard let project, let tab = EditorTabManager.shared.selectedTab else { return }
        do {
            let store = CollaborationStore(project: project)
            let prefix = project.resolvingSymlinksInPath().path + "/"
            let path = tab.url.resolvingSymlinksInPath().path
            guard path.hasPrefix(prefix) else { throw CollaborationFailure.unsafePath }
            let relative = String(path.dropFirst(prefix.count))
            _ = try store.file(relative)
            var anchor: CollaborationAnchor?
            let capture: (String, NSRange) -> Void = { text, selection in
                let source = text as NSString
                guard selection.length > 0, selection.location >= 0, NSMaxRange(selection) <= source.length else { return }
                let start = max(0, selection.location - 120)
                let end = min(source.length, NSMaxRange(selection) + 120)
                anchor = .init(path: relative, quote: source.substring(with: selection),
                    surroundingText: source.substring(with: NSRange(location: start, length: end - start)),
                    version: CollaborationHash.text(text), location: selection.location, length: selection.length)
            }
            NotificationCenter.default.post(name: .init("editorWillPerformFileOperation"), object: nil, userInfo: ["captureSelection": capture])
            guard let anchor else { throw ManuscriptRevision.Failure.unavailable }
            commentAnchor = anchor
            showingPanel = true
        } catch { self.error = error.localizedDescription }
    }

    func answer(taskID: UUID, questionID: String, text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        perform { store in
            try store.updateTask(taskID) {
                guard let index = $0.questions.firstIndex(where: { $0.id == questionID }) else { throw CollaborationFailure.damagedStore }
                $0.questions[index].answer = text
                if $0.questions.allSatisfy({ $0.answer != nil }) { $0.phase = .queued }
            }
        }
    }

    func retry(_ id: UUID) {
        perform { store in
            try store.updateTask(id) { $0.phase = .queued; $0.error = nil }
        }
    }

    func cancel(_ id: UUID? = nil) {
        let target = id ?? activeID
        if id == nil || id == activeID { active?.cancel(); activeExecutor?.cancel() }
        if let project, let target {
            do { try CollaborationStore(project: project).updateTask(target) { $0.phase = .cancelled } }
            catch { self.error = error.localizedDescription }
        }
        if id == nil { activeID = nil }
    }

    func undo(_ id: UUID) {
        guard !isWorking else { return }
        perform { store in
            try CollaborationApplier(store: store, checkEditor: {
                try EditorTabManager.shared.validateAIApplication(project: store.project)
            }).undo(taskID: id)
        }
    }

    private func perform(_ operation: (CollaborationStore) throws -> Void) {
        guard let project else { return }
        do { try operation(CollaborationStore(project: project)); try refresh(); error = nil }
        catch { self.error = error.localizedDescription }
    }

    private func tick() async {
        guard let project else { return }
        do {
            // Reload durable work created by ordinary chat, not just this panel.
            document = try CollaborationStore(project: project).load()
            if isWorking { return }
            if needsRefresh { try refresh() }
            guard document.enabled, !document.paused else { return }
            if document.gitEnabled, Date().timeIntervalSince(gitProbeAt) >= 1 {
                let owner = epoch
                gitProbeAt = Date()
                try await pollGit(project)
                guard epoch == owner else { return }
            }
            guard let task = document.tasks.first(where: { $0.phase == .queued }), let (provider, options, executor) = runtime?() else { return }
            isWorking = true
            activeID = task.id
            activeExecutor = executor
            let owner = epoch
            active = Task { [weak self] in
                guard let self else { return }
                let store = CollaborationStore(project: project)
                defer {
                    self.isWorking = false
                    self.active = nil
                    self.activeExecutor = nil
                    self.activeID = nil
                }
                do {
                    _ = try await CollaborationEngine(store: store, executor: executor, checkEditor: {
                        try EditorTabManager.shared.validateAIApplication(project: project)
                    }).execute(taskID: task.id, provider: provider, options: options)
                    guard self.epoch == owner else { return }
                    try self.refresh()
                    self.notification = self.document.tasks.first(where: { $0.id == task.id })?.phase == .waiting
                        ? L10n.get("collaboration.needsDecision") : L10n.get("collaboration.finished")
                } catch {
                    do {
                        try store.updateTask(task.id) {
                            if !(Task.isCancelled && $0.phase == .queued) {
                                $0.phase = Task.isCancelled ? .cancelled : ((error is CollaborationFailure || error is ManuscriptRevision.Failure) ? .review : .failed)
                            }
                            $0.error = error.localizedDescription
                        }
                    } catch { if self.epoch == owner { self.error = error.localizedDescription } }
                    if self.epoch == owner {
                        try? self.refresh()
                        self.notification = error.localizedDescription
                    }
                }
            }
        } catch { self.error = error.localizedDescription }
    }

    private func pollGit(_ project: URL) async throws {
        let owner = epoch
        let staged = try await Task.detached { try CollaborationGit.staged(project: project) }.value
        guard owner == epoch, !Task.isCancelled else { return }
        let store = CollaborationStore(project: project)
        let state = try store.load()
        let rawChanges = staged.map { CollaborationChange(path: $0.key, before: nil, after: $0.value) }
        let fingerprint = try CollaborationHash.changes(rawChanges)
        if gitCandidate != fingerprint { gitCandidate = fingerprint; gitObservedAt = Date(); return }
        guard Date().timeIntervalSince(gitObservedAt) >= 3, state.lastGitFingerprint != fingerprint else { return }
        let changes = staged.compactMap { path, text -> CollaborationChange? in
            state.baseline[path] == text ? nil : .init(path: path, before: state.baseline[path], after: text)
        }
        if !changes.isEmpty {
            try store.enqueue(origin: "git", instruction: L10n.get("collaboration.batchInstruction"), changes: changes)
        }
        try store.update { $0.lastGitFingerprint = fingerprint }
        document = try store.load()
    }
}
