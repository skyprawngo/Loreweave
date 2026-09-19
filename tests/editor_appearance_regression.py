#!/usr/bin/env python3
"""Compile real appearance persistence and exercise inheritance without touching user settings."""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[1]
code = r'''
import Foundation
func expect(_ condition: @autoclosure () -> Bool, _ label: String) {
    precondition(condition(), label)
    print("PASS " + label)
}
let base = URL(fileURLWithPath: CommandLine.arguments[1])
let file = base.appendingPathComponent("A.md"), other = base.appendingPathComponent("B.md")
let repository = JSONEditorAppearanceRepository(url: base.appendingPathComponent("appearance.json"))
let events = WorkspaceFileEvents()
let store = EditorAppearanceStore(repository: repository, events: events)
var defaults = EditorAppearance(fontName: "Global", fontSize: 14, lineSpacing: 1, letterSpacing: 0)
expect(try! store.effective(for: file, defaults: defaults) == defaults, "untouched file inherits every global property")
expect(!FileManager.default.fileExists(atPath: repository.url.path), "reading a file does not create an override")
try store.update(.fontName("FileFont"), for: file)
defaults.fontName = "NewGlobal"; defaults.fontSize = 20; defaults.lineSpacing = 1.5; defaults.letterSpacing = 2
let styled = try store.effective(for: file, defaults: defaults)
expect(styled.fontName == "FileFont" && styled.fontSize == 20 && styled.lineSpacing == 1.5 && styled.letterSpacing == 2, "one override does not freeze unrelated defaults")
expect(try! store.effective(for: other, defaults: defaults) == defaults, "another file keeps inheriting defaults")
try store.update(.letterSpacing(-1), for: file)
try store.update(.fontSize(18), for: file)
try store.update(.lineSpacing(0.9), for: file)
let persisted = EditorAppearanceStore(repository: repository, events: WorkspaceFileEvents())
expect(try! persisted.effective(for: file, defaults: defaults) == EditorAppearance(fontName: "FileFont", fontSize: 18, lineSpacing: 0.9, letterSpacing: -1), "all appearance fields survive reopening the store")
let moved = base.appendingPathComponent("Renamed.md")
events.publish(.init(url: moved, change: .moved(from: file)))
expect(try! store.effective(for: file, defaults: defaults) == defaults, "rename releases old path override")
expect(try! store.effective(for: moved, defaults: defaults).fontName == "FileFont", "rename event carries file override")
let copy = base.appendingPathComponent("Copy.md")
events.publish(.init(url: copy, change: .documentCopied(from: moved)))
expect(try! store.effective(for: copy, defaults: defaults) == store.effective(for: moved, defaults: defaults), "save-as copies overrides while preserving source")
try store.reset(for: copy)
expect(try! store.effective(for: copy, defaults: defaults) == defaults, "reset restores live global inheritance")
expect(try! store.effective(for: moved, defaults: defaults).fontName == "FileFont", "reset affects only the chosen file")
let folder = base.appendingPathComponent("Folder"), renamedFolder = base.appendingPathComponent("RenamedFolder")
let child = folder.appendingPathComponent("Child.md")
try store.update(.fontSize(30), for: child)
events.publish(.init(url: renamedFolder, change: .moved(from: folder)))
expect(try! store.effective(for: renamedFolder.appendingPathComponent("Child.md"), defaults: defaults).fontSize == 30, "folder relocation carries descendant preferences")
events.publish(.init(url: renamedFolder, change: .trashed))
expect(try! store.effective(for: renamedFolder.appendingPathComponent("Child.md"), defaults: defaults) == defaults, "trash clears overrides so a new file at the same path inherits defaults")
let corruptURL = base.appendingPathComponent("corrupt.json")
try Data("corrupt".utf8).write(to: corruptURL)
let corrupt = EditorAppearanceStore(repository: JSONEditorAppearanceRepository(url: corruptURL))
do { try corrupt.update(.fontSize(10), for: file); preconditionFailure("overwrote corrupt data") } catch {}
expect(try! String(contentsOf: corruptURL, encoding: .utf8) == "corrupt", "corrupt preference store is not overwritten")
final class FailingRepository: EditorAppearanceRepository {
    func load() throws -> [String: EditorAppearanceOverride] { [:] }
    func save(_ records: [String: EditorAppearanceOverride]) throws { throw CocoaError(.fileWriteOutOfSpace) }
}
let failing = EditorAppearanceStore(repository: FailingRepository())
do { try failing.update(.fontSize(50), for: file); preconditionFailure("ignored write failure") } catch {}
expect(try! failing.effective(for: file, defaults: defaults) == defaults, "failed write does not publish an in-memory override")
print("ALL EDITOR APPEARANCE REGRESSIONS PASSED")
'''
with tempfile.TemporaryDirectory(prefix='editor-appearance-') as work:
    work = Path(work)
    (work/'main.swift').write_text(code)
    sources = [root/'TextlinkEditor/Services/Editor/Appearance/EditorAppearanceStore.swift',
               root/'TextlinkEditor/Services/FileSystem/Workspace/WorkspaceFileEvents.swift',
               root/'TextlinkEditor/Services/FileSystem/Workspace/WorkspaceFileIdentity.swift']
    subprocess.run(['swiftc', *map(str, sources), str(work/'main.swift'), '-o', str(work/'regression')], check=True)
    subprocess.run([str(work/'regression'), str(work)], check=True)
