import Foundation

/// Normalize URL spelling without lowercasing: case-sensitive volumes remain distinct.
/// Keep stable tab UUIDs separate from this relocatable path identity.
enum WorkspaceFileIdentity {
    static func key(_ url: URL) -> String {
        url.standardizedFileURL.path.precomposedStringWithCanonicalMapping
    }
    static func same(_ lhs: URL, _ rhs: URL) -> Bool { lhs == rhs || key(lhs) == key(rhs) }
    static func relocated(_ url: URL, from old: URL, to new: URL) -> URL? {
        let source = key(url), base = key(old)
        guard source == base || source.hasPrefix(base + "/") else { return nil }
        return URL(fileURLWithPath: new.path + String(source.dropFirst(base.count)))
    }
}
