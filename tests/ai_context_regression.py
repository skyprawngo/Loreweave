#!/usr/bin/env python3
"""Compile the actual context builder; all data is an isolated temporary project."""
from pathlib import Path
import subprocess, tempfile, platform
root = Path(__file__).resolve().parents[1]
harness = r'''
import Foundation
enum L10n { static func get(_ key: String) -> String { key } }
@MainActor final class EditorTabManager {
    static let shared = EditorTabManager()
    var cache: [URL: String] = [:]
    var modified: Set<URL> = []
    func getCachedContent(for url: URL) -> String? { cache[url] }
    func isModified(url: URL) -> Bool { modified.contains(url) }
}
@main struct Test {
    @MainActor static func main() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let project = base.appendingPathComponent("Fixture.weaveproj")
        try fm.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }
        let file = project.appendingPathComponent("draft.md")
        try "disk text".write(to: file, atomically: true, encoding: .utf8)
        let context = AIContextSelection()
        try context.addFile(file, projectURL: project)
        try context.addFile(file, projectURL: project)
        precondition(context.items(projectURL: project).count == 1)
        EditorTabManager.shared.cache[file] = ""
        let restoredPlaceholder = try context.manifest(projectURL: project)
        precondition(restoredPlaceholder.text.contains("disk text"))
        EditorTabManager.shared.cache[file] = "stale clean cache"
        let cleanCache = try context.manifest(projectURL: project)
        precondition(cleanCache.text.contains("disk text") && !cleanCache.text.contains("stale clean cache"))
        EditorTabManager.shared.modified.insert(file)
        EditorTabManager.shared.cache[file] = "unsaved 한글 😀"
        try context.captureSelection("captured text", sourceURL: file, projectURL: project)
        var manifest = try context.manifest(projectURL: project)
        precondition(manifest.text.contains("unsaved 한글 😀") && manifest.text.contains("captured text") && !manifest.text.contains("disk text"))
        EditorTabManager.shared.cache[file] = "later draft"
        precondition(try context.manifest(projectURL: project).text.contains("later draft"))
        precondition(context.items(projectURL: base).isEmpty)
        let store = WritingWorkspaceStore(projectURL: project)
        var workspace = WritingWorkspaceDocument()
        workspace.scenes = [WritingScene(), WritingScene()]
        var lore = WritingLoreEntry(); lore.name = "Secret"; lore.body = "hidden twist"; lore.includeInAI = true; lore.revealedFromSceneID = workspace.scenes[1].id
        workspace.lore = [lore]; try store.save(workspace)
        context.setScene(1, projectURL: project)
        precondition(try !context.manifest(projectURL: project).text.contains("hidden twist"))
        context.setScene(2, projectURL: project)
        manifest = try context.manifest(projectURL: project)
        precondition(manifest.text.contains("hidden twist"))
        let id = UUID(); try context.persist(manifest, requestID: id, projectURL: project)
        let saved = project.appendingPathComponent(".Fixture.weavedata/ai-context/\(id.uuidString).json")
        precondition(try JSONDecoder().decode(AIContextManifest.self, from: Data(contentsOf: saved)).text == manifest.text)
        let outside = base.appendingPathComponent("outside.md")
        try "external".write(to: outside, atomically: true, encoding: .utf8)
        let link = project.appendingPathComponent("link.md")
        try fm.createSymbolicLink(at: link, withDestinationURL: outside)
        do { try context.addFile(link, projectURL: project); fatalError("accepted symlink") } catch AIContextError.unsafePath {}
        do { try context.addFile(outside, projectURL: project); fatalError("accepted external") } catch AIContextError.unsafePath {}
        EditorTabManager.shared.cache[file] = String(repeating: "x", count: AIContextSelection.byteLimit + 1)
        do { _ = try context.manifest(projectURL: project); fatalError("accepted oversize") } catch AIContextError.tooLarge {}
        print("PASS context: fresh drafts, captured text, deduplication, project isolation, reveal filter, exact persisted manifest, safe paths, size limit")
    }
}
'''
# Swift precondition autoclosures cannot throw.
harness = harness.replace('precondition(try context.manifest(projectURL: project).text.contains("later draft"))', 'let later = try context.manifest(projectURL: project); precondition(later.text.contains("later draft"))')
harness = harness.replace('precondition(try !context.manifest(projectURL: project).text.contains("hidden twist"))', 'let early = try context.manifest(projectURL: project); precondition(!early.text.contains("hidden twist"))')
harness = harness.replace('precondition(try JSONDecoder().decode(AIContextManifest.self, from: Data(contentsOf: saved)).text == manifest.text)', 'let decoded = try JSONDecoder().decode(AIContextManifest.self, from: Data(contentsOf: saved)); precondition(decoded.text == manifest.text)')
with tempfile.TemporaryDirectory(prefix='lore-ai-context-') as temp:
    work = Path(temp)
    (work/'Harness.swift').write_text(harness)
    subprocess.run(['swiftc', '-swift-version', '5', '-target', f'{platform.machine()}-apple-macos26.0', str(root/'TextlinkEditor/Services/AI/Context/AIContextSelection.swift'), str(root/'TextlinkEditor/Views/MainEditor/AIAssistant/Context/AIContextPickerView.swift'), str(root/'TextlinkEditor/Services/Writing/WritingWorkspaceStore.swift'), str(work/'Harness.swift'), '-o', str(work/'test')], check=True)
    subprocess.run([str(work/'test')], check=True)
