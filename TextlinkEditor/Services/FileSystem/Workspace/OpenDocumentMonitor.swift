import AppKit

/// Events invalidate our snapshot; only a fresh read can determine document state.
/// Parent + file watches survive atomic replacement, and the presenter cooperates with macOS apps.
final class OpenDocumentMonitor: NSObject, NSFilePresenter {
    let presentedItemURL: URL?
    let presentedItemOperationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    private var sources: [DispatchSourceFileSystemObject] = []
    private var pending: DispatchWorkItem?
    private let onChange: () -> Void
    private var stopped = false

    init(url: URL, onChange: @escaping () -> Void) {
        presentedItemURL = url
        self.onChange = onChange
        super.init()
        NSFileCoordinator.addFilePresenter(self)
        reconnect()
    }

    func reconnect() {
        guard !stopped, let url = presentedItemURL else { return }
        for source in sources { source.cancel() }
        sources.removeAll()
        for target in [url, url.deletingLastPathComponent()] {
            let fd = open(target.path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd,
                eventMask: [.write, .extend, .attrib, .delete, .rename, .revoke], queue: .main)
            source.setEventHandler { [weak self] in self?.changed() }
            source.setCancelHandler { close(fd) }
            source.resume()
            sources.append(source)
        }
    }

    private func changed() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.stopped else { return }
            self.reconnect()
            self.onChange()
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    func presentedItemDidChange() { DispatchQueue.main.async { [weak self] in self?.changed() } }
    func presentedItemDidMove(to newURL: URL) { presentedItemDidChange() }
    func accommodatePresentedItemDeletion(completionHandler: @escaping (Error?) -> Void) {
        presentedItemDidChange()
        completionHandler(nil)
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        pending?.cancel()
        for source in sources { source.cancel() }
        sources.removeAll()
        NSFileCoordinator.removeFilePresenter(self)
    }

    deinit { stop() }
}
