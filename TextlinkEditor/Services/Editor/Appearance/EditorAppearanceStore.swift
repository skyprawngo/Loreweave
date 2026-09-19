import Foundation

struct EditorAppearance: Equatable {
    var fontName: String
    var fontSize: CGFloat
    var lineSpacing: CGFloat
    var letterSpacing: CGFloat
}

/// Nil means inherit. Only the property explicitly edited by the user becomes an override.
struct EditorAppearanceOverride: Codable, Equatable {
    var fontName: String?
    var fontSize: CGFloat?
    var lineSpacing: CGFloat?
    var letterSpacing: CGFloat?
    func resolve(over defaults: EditorAppearance) -> EditorAppearance {
        EditorAppearance(fontName: fontName ?? defaults.fontName, fontSize: fontSize ?? defaults.fontSize,
            lineSpacing: lineSpacing ?? defaults.lineSpacing, letterSpacing: letterSpacing ?? defaults.letterSpacing)
    }
}

enum EditorAppearanceChange {
    case fontName(String), fontSize(CGFloat), lineSpacing(CGFloat), letterSpacing(CGFloat)
    func apply(to value: inout EditorAppearanceOverride) {
        switch self {
        case .fontName(let name): value.fontName = name
        case .fontSize(let size): value.fontSize = size
        case .lineSpacing(let ratio): value.lineSpacing = ratio
        case .letterSpacing(let spacing): value.letterSpacing = spacing
        }
    }
}

protocol EditorAppearanceRepository {
    func load() throws -> [String: EditorAppearanceOverride]
    func save(_ records: [String: EditorAppearanceOverride]) throws
}

struct JSONEditorAppearanceRepository: EditorAppearanceRepository {
    struct Snapshot: Codable {
        var schemaVersion = 1
        var documents: [String: EditorAppearanceOverride]
    }
    let url: URL
    func load() throws -> [String: EditorAppearanceOverride] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: url))
        guard snapshot.schemaVersion == 1 else { throw CocoaError(.coderReadCorrupt) }
        return snapshot.documents
    }
    func save(_ records: [String: EditorAppearanceOverride]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(Snapshot(documents: records)).write(to: url, options: .atomic)
    }
}

/// App-local per-file preferences, including documents outside the project.
/// No manuscript bytes, dirty flags, or editor layout objects are owned here.
final class EditorAppearanceStore {
    static let changed = Notification.Name("editorAppearanceChanged")
    static let defaultsChanged = Notification.Name("editorAppearanceDefaultsChanged")
    static let shared = EditorAppearanceStore(repository: JSONEditorAppearanceRepository(url:
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TextlinkEditor/editor-appearance-overrides.json")))
    private let repository: any EditorAppearanceRepository
    private var records: [String: EditorAppearanceOverride]?
    private let events: WorkspaceFileEvents
    private var token: NSObjectProtocol?
    private(set) var error: Error?

    init(repository: any EditorAppearanceRepository, events: WorkspaceFileEvents = .shared) {
        self.repository = repository
        self.events = events
        token = events.observe { [weak self] event in
            guard let self else { return }
            do {
                switch event.change {
                case .moved(let old): try self.relocate(from: old, to: event.url)
                case .copied(let old): try self.relocate(from: old, to: event.url, copying: true)
                case .documentCopied(let old): try self.relocate(from: old, to: event.url, copying: true)
                case .trashed: try self.remove(under: event.url)
                default: break
                }
            } catch {
                self.error = error
                NotificationCenter.default.post(name: Self.changed, object: nil)
            }
        }
    }
    deinit { if let token { events.remove(token) } }
    private func load() throws -> [String: EditorAppearanceOverride] {
        if let records { return records }
        do {
            let loaded = try repository.load()
            records = loaded
            error = nil
            return loaded
        } catch { self.error = error; throw error }
    }
    func effective(for url: URL?, defaults: EditorAppearance) throws -> EditorAppearance {
        guard let url else { return defaults }
        return (try load()[WorkspaceFileIdentity.key(url)] ?? .init()).resolve(over: defaults)
    }
    func update(_ change: EditorAppearanceChange, for url: URL) throws {
        var next = try load()
        let key = WorkspaceFileIdentity.key(url)
        var value = next[key] ?? .init()
        change.apply(to: &value)
        guard next[key] != value else { return }
        next[key] = value
        try commit(next)
    }
    func reset(for url: URL) throws {
        var next = try load()
        guard next.removeValue(forKey: WorkspaceFileIdentity.key(url)) != nil else { return }
        try commit(next)
    }
    func remove(under url: URL) throws {
        let previous = try load()
        let next = previous.filter { WorkspaceFileIdentity.relocated(URL(fileURLWithPath: $0.key), from: url, to: url) == nil }
        if previous != next { try commit(next) }
    }
    func relocate(from old: URL, to new: URL, copying: Bool = false) throws {
        var next = try load()
        let previous = next
        for (key, value) in previous {
            guard let target = WorkspaceFileIdentity.relocated(URL(fileURLWithPath: key), from: old, to: new) else { continue }
            if !copying { next.removeValue(forKey: key) }
            next[WorkspaceFileIdentity.key(target)] = value
        }
        if previous != next { try commit(next) }
    }
    private func commit(_ next: [String: EditorAppearanceOverride]) throws {
        do { try repository.save(next) }
        catch { self.error = error; throw error }
        records = next
        error = nil
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }
}
