import AppKit

/// Owns observation and asynchronous read lifetime, not editor buffers or UI state.
/// Identity + request + base checks prevent stale reads crossing a save, rename or tab replacement.
final class DocumentObservationController {
    private let repository: any WorkspaceDocumentRepository
    private let events: WorkspaceFileEvents
    private var monitors: [URL: OpenDocumentMonitor] = [:]
    private var reads: [URL: Task<Void, Never>] = [:]
    private var requests: [URL: UUID] = [:]
    private var timer: Timer?
    private var activation: NSObjectProtocol?
    private var wake: NSObjectProtocol?
    var identity: (URL) -> (id: UUID, base: String?)? = { _ in nil }
    var receive: (URL, Result<String, Error>) -> Void = { _, _ in }

    init(repository: any WorkspaceDocumentRepository, events: WorkspaceFileEvents) {
        self.repository = repository
        self.events = events
    }
    func cancelRead(_ url: URL) { reads.removeValue(forKey: url)?.cancel(); requests[url] = nil }
    func remove(_ url: URL) { cancelRead(url); monitors.removeValue(forKey: url)?.stop() }
    func requestRead(_ url: URL) {
        guard let current = identity(url) else { return }
        cancelRead(url)
        let ticket = DocumentReadIdentity(requestID: UUID(), documentID: current.id, base: current.base)
        requests[url] = ticket.requestID
        let repository = repository
        reads[url] = Task { @MainActor [weak self] in
            let result: Result<String, Error>
            do { result = .success(try await repository.readSnapshot(url)) }
            catch { result = .failure(error) }
            guard let self, !Task.isCancelled, requests[url] == ticket.requestID,
                  let current = identity(url), current.id == ticket.documentID else { return }
            reads[url] = nil; requests[url] = nil
            guard ticket.matches(requestID: ticket.requestID, documentID: current.id, base: current.base) else {
                requestRead(url)
                return
            }
            receive(url, result)
        }
    }
    func synchronize(_ urls: Set<URL>) {
        for url in Array(monitors.keys) where !urls.contains(url) { remove(url) }
        for url in urls where monitors[url] == nil {
            monitors[url] = OpenDocumentMonitor(url: url) { [weak self] in
                self?.events.publish(.init(url: url, change: .invalidated))
            }
            requestRead(url)
        }
        if urls.isEmpty { stop(); return }
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self else { return }
            for monitor in monitors.values { monitor.reconnect() }
            refresh()
        }
        activation = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
            object: nil, queue: .main) { [weak self] _ in self?.refresh() }
        wake = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main) { [weak self] _ in self?.refresh() }
    }
    func refresh() { for url in Array(monitors.keys) { requestRead(url) } }
    func stop() {
        timer?.invalidate(); timer = nil
        if let activation { NotificationCenter.default.removeObserver(activation) }
        if let wake { NSWorkspace.shared.notificationCenter.removeObserver(wake) }
        activation = nil; wake = nil
        for url in Array(monitors.keys) { remove(url) }
        for task in reads.values { task.cancel() }
        reads.removeAll(); requests.removeAll()
    }
    deinit { stop() }
}
