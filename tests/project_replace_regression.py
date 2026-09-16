#!/usr/bin/env python3
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
code = r'''
import Foundation
enum L10n { static func get(_ key: String) -> String { key } }
func check(_ condition: @autoclosure () throws -> Bool, _ message: String) rethrows {
    guard try condition() else { fatalError(message) }
    print("PASS \(message)")
}
let fm = FileManager.default, base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try fm.createDirectory(at: base, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: base) }
let project = base.appendingPathComponent("Novel.weaveproj")
try fm.createDirectory(at: project, withIntermediateDirectories: true)
let a = project.appendingPathComponent("a.md"), b = project.appendingPathComponent("b.md")
try Data("one One 한글 one 😀".utf8).write(to: a)
try Data("one".utf8).write(to: b)
try Data("one".utf8).write(to: project.appendingPathComponent(".hidden.md"))
let outside = base.appendingPathComponent("outside.md")
try Data("one".utf8).write(to: outside)
try fm.createSymbolicLink(at: project.appendingPathComponent("link.md"), withDestinationURL: outside)
let preview = try ProjectReplacementStore.preview(projectURL: project, query: "one", replacement: "two")
check(preview.changes.count == 2 && preview.skipped == 1, "scan excludes hidden and linked files")
check(preview.changes[0].replacement == "two One 한글 two 😀" && preview.changes[0].occurrences == 2, "literal replacement is case-sensitive and Unicode-safe")
try Data("external".utf8).write(to: b)
do { _ = try ProjectReplacementStore.apply(projectURL: project, changes: preview.changes); fatalError("stale preview accepted") } catch {}
try check(String(contentsOf: a, encoding: .utf8) == preview.changes[0].original, "preflight checks every file before first mutation")
try Data("one".utf8).write(to: b)
let batch = try ProjectReplacementStore.apply(projectURL: project, changes: preview.changes)
try check(String(contentsOf: b, encoding: .utf8) == "two", "batch applied")
try check(VersionHistoryStore.snapshots(projectURL: project, documentURL: a).first?.content == preview.changes[0].original, "snapshot precedes replacement")
try ProjectReplacementStore.undo(projectURL: project, batch: batch)
try check(String(contentsOf: a, encoding: .utf8) == preview.changes[0].original, "batch undo restores originals")
let second = try ProjectReplacementStore.apply(projectURL: project, changes: preview.changes)
try Data("newer user edit".utf8).write(to: b)
do { try ProjectReplacementStore.undo(projectURL: project, batch: second); fatalError("unsafe undo accepted") } catch {}
try check(String(contentsOf: a, encoding: .utf8) == preview.changes[0].replacement, "undo preflight rejects all if any file changed")
try Data(preview.changes[0].original.utf8).write(to: a)
try Data("one".utf8).write(to: b)
var writes = 0
do {
    _ = try ProjectReplacementStore.apply(projectURL: project, changes: preview.changes, writer: { content, url, expected in
        writes += 1
        if writes == 2 { throw CocoaError(.fileWriteUnknown) }
        try DocumentFileStore.save(content, at: url, expected: expected)
    }); fatalError("injected failure accepted")
} catch {}
try check(String(contentsOf: a, encoding: .utf8) == preview.changes[0].original, "mid-batch failure rolls back completed files")
writes = 0
do {
    _ = try ProjectReplacementStore.apply(projectURL: project, changes: preview.changes, writer: { content, url, expected in
        writes += 1
        if writes == 2 { try Data("concurrent edit".utf8).write(to: a); throw CocoaError(.fileWriteUnknown) }
        try DocumentFileStore.save(content, at: url, expected: expected)
    }); fatalError("injected failure accepted")
} catch ProjectReplacementStore.Failure.incomplete {} catch { fatalError("partial failure not reported") }
try check(String(contentsOf: a, encoding: .utf8) == "concurrent edit", "rollback preserves concurrent edits")
let journalDirectory = project.appendingPathComponent(".Novel.weavedata/replacements")
let journals = try fm.contentsOfDirectory(at: journalDirectory, includingPropertiesForKeys: nil).filter { !$0.lastPathComponent.contains("progress") }
let records = try journals.map { try JSONDecoder().decode(ProjectReplacementStore.Batch.self, from: Data(contentsOf: $0)) }
check(records.contains { $0.state == "partial" && !$0.completedPaths.isEmpty }, "partial state and originals remain in durable journal")
do { _ = try ProjectReplacementStore.documentURL(projectURL: project, relativePath: "../outside.md"); fatalError("traversal accepted") } catch {}
try check(String(contentsOf: outside, encoding: .utf8) == "one", "outside files preserved")
'''
with tempfile.TemporaryDirectory(prefix="lore-project-replace-") as scratch:
    scratch = Path(scratch)
    main = scratch / "main.swift"
    main.write_text(code)
    sources = ["TextlinkEditor/Services/FileSystem/DocumentFileStore.swift", "TextlinkEditor/Services/Versions/VersionHistoryStore.swift", "TextlinkEditor/Services/Editor/ProjectReplacementStore.swift"]
    executable = scratch / "check"
    subprocess.run(["swiftc", "-O", *[str(root / p) for p in sources], str(main), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
