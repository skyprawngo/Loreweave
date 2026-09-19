import Foundation

/// One-based manuscript line plus its source text; offset preserves partial/wrapped lines.
struct EditorViewportPosition: Codable, Equatable {
    var firstVisibleLine: Int
    var firstLineText: String
    var offsetWithinLine: Double
    var cursorLine: Int?
    var cursorLineText: String?
    var cursorOffsetWithinLine: Int?
    var cursorTextBefore: String?
    var cursorTextAfter: String?

    init(firstVisibleLine: Int, firstLineText: String, offsetWithinLine: Double,
         cursorLine: Int? = nil, cursorLineText: String? = nil, cursorOffsetWithinLine: Int? = nil) {
        self.firstVisibleLine = firstVisibleLine
        self.firstLineText = firstLineText
        self.offsetWithinLine = offsetWithinLine
        self.cursorLine = cursorLine
        self.cursorLineText = cursorLineText
        self.cursorOffsetWithinLine = cursorOffsetWithinLine
    }

    private enum CodingKeys: String, CodingKey { case firstVisibleLine, firstLineText, offsetWithinLine, cursorLine, cursorLineText, cursorOffsetWithinLine, cursorTextBefore, cursorTextAfter }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        firstVisibleLine = try c.decode(Int.self, forKey: .firstVisibleLine)
        firstLineText = try c.decode(String.self, forKey: .firstLineText)
        offsetWithinLine = try c.decode(Double.self, forKey: .offsetWithinLine)
        cursorLine = try c.decodeIfPresent(Int.self, forKey: .cursorLine)
        cursorLineText = try c.decodeIfPresent(String.self, forKey: .cursorLineText)
        cursorOffsetWithinLine = try c.decodeIfPresent(Int.self, forKey: .cursorOffsetWithinLine)
        cursorTextBefore = try c.decodeIfPresent(String.self, forKey: .cursorTextBefore)
        cursorTextAfter = try c.decodeIfPresent(String.self, forKey: .cursorTextAfter)
    }
}

/// App-local reading position survives closing a tab and is separate from draft recovery.
final class EditorViewportStore {
    static let shared = EditorViewportStore()
    private let defaults: UserDefaults
    private let key = "editor.viewportPositions.v1"
    private var records: [String: EditorViewportPosition]
    private let events: WorkspaceFileEvents
    private var observer: NSObjectProtocol?
    private(set) var loadError: Error?

    init(defaults: UserDefaults = .standard, events: WorkspaceFileEvents = .shared) {
        self.defaults = defaults
        self.events = events
        records = [:]
        if let data = defaults.data(forKey: key) {
            do { records = try JSONDecoder().decode([String: EditorViewportPosition].self, from: data) }
            catch { loadError = error }
        }
        observer = events.observe { [weak self] event in
            guard let self else { return }
            if case .moved(let old) = event.change { self.move(from: old, to: event.url) }
        }
    }
    deinit { if let observer { events.remove(observer) } }
    private func path(_ url: URL) -> String { url.standardizedFileURL.path.precomposedStringWithCanonicalMapping }
    func position(for url: URL) -> EditorViewportPosition? { records[path(url)] }
    func save(_ position: EditorViewportPosition, for url: URL) {
        guard loadError == nil, position.firstVisibleLine > 0, position.offsetWithinLine.isFinite,
              records[path(url)] != position else { return }
        records[path(url)] = position
        persist()
    }
    private func move(from old: URL, to new: URL) {
        guard loadError == nil else { return }
        let source = path(old), destination = path(new)
        let moving = records.filter { $0.key == source || $0.key.hasPrefix(source + "/") }
        guard !moving.isEmpty else { return }
        for (key, value) in moving {
            records.removeValue(forKey: key)
            records[destination + key.dropFirst(source.count)] = value
        }
        persist()
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(records) { defaults.set(data, forKey: key) }
    }
}
