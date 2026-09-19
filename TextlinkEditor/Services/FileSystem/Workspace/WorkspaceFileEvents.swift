import Foundation

/// A committed mutation or an invalidation hint. Hints never contain authoritative text.
struct WorkspaceFileEvent {
    enum Change {
        case created, saved, copied(from: URL), moved(from: URL), trashed
        case documentCopied(from: URL)
        case invalidated
        case documentContentAccepted
        case documentStateChanged
    }
    let id = UUID()
    let url: URL
    let change: Change
}

/// Process-local, ordered on main. Subscribers must filter by their project/document ownership.
/// Legacy AppKit notifications are adapters, not additional state owners.
final class WorkspaceFileEvents {
    static let shared = WorkspaceFileEvents()
    static let notification = Notification.Name("workspaceFileEvent")
    private let center = NotificationCenter()

    @discardableResult
    func observe(_ receive: @escaping (WorkspaceFileEvent) -> Void) -> NSObjectProtocol {
        center.addObserver(forName: Self.notification, object: nil, queue: nil) { notification in
            if let event = notification.object as? WorkspaceFileEvent { receive(event) }
        }
    }
    func remove(_ token: NSObjectProtocol) { center.removeObserver(token) }
    func publish(_ event: WorkspaceFileEvent) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in self?.publish(event) }
            return
        }
        center.post(name: Self.notification, object: event)
        switch event.change {
        case .documentContentAccepted:
            NotificationCenter.default.post(name: .init("editorDiskContentDidChange"), object: event.url)
        case .documentStateChanged:
            NotificationCenter.default.post(name: .init("editorDiskStateDidChange"), object: event.url)
        default: break
        }
    }
}
