#!/usr/bin/env python3
"""Exercise metadata preservation, scoped references, draft export, archive bytes and DOCX XML."""
import pathlib, subprocess, tempfile, zipfile, xml.etree.ElementTree as ET
root = pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='lore-writing-test-') as temp:
    temp = pathlib.Path(temp)
    harness = temp / 'main.swift'
    harness.write_text(r'''
import Foundation
enum L10n { static func get(_ key: String) -> String { key } }
func check(_ condition: @autoclosure () -> Bool, _ message: String) { if !condition() { fatalError(message) } }
let base = URL(fileURLWithPath: CommandLine.arguments[1])
let project = base.appendingPathComponent("Story.weaveproj")
try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
try Data("원고 & <안녕> 😀\n둘째 행".utf8).write(to: project.appendingPathComponent("first.md"))
let store = WritingWorkspaceStore(projectURL: project)
var doc = WritingWorkspaceDocument()
var first = WritingScene(); first.title = "첫 장면"; first.manuscriptPath = "first.md"
var second = WritingScene(); second.title = "둘째 장면"; second.manuscriptPath = "missing.md"; second.includedInExport = false
doc.scenes = [first, second]
var lore = WritingLoreEntry(); lore.body = "비밀"; lore.includeInAI = true; lore.revealedFromSceneID = second.id
doc.lore = [lore]
try store.save(doc)
var deleting = doc
do { try deleting.removeScene(id: second.id); fatalError("removed referenced reveal scene") } catch WritingWorkspaceError.referencedScene {}
check(deleting == doc, "blocked removal preserves all metadata")
deleting.removeLore(id: lore.id)
try deleting.removeScene(id: second.id)
check(deleting.scenes.count == 1 && deleting.lore.isEmpty, "explicit metadata removal")
let keptFile = FileManager.default.fileExists(atPath: project.appendingPathComponent("first.md").path)
check(keptFile, "removal preserves manuscript")
let loaded = try store.load(); check(loaded == doc, "metadata roundtrip")
check(store.references(doc, at: first.id).isEmpty, "spoiler excluded")
check(store.references(doc, at: second.id).count == 1, "revealed lore included")
check(store.references(doc, at: nil).isEmpty, "unknown scene excludes scoped lore")
let submission = try store.submission(doc, drafts: ["first.md": "미저장 초안 😀"], markdown: true)
check(submission == "# 첫 장면\n\n미저장 초안 😀", "draft export, order and exclusions")
let metrics = WritingMetrics("한글 😀\n e\u{301}")
check(metrics.characters == 7 && metrics.nonWhitespaceCharacters == 4 && metrics.words == 3, "grapheme metrics")
for path in ["../escape.md", "/tmp/escape.md"] {
    do { _ = try store.resolve(path); fatalError("accepted traversal") } catch WritingWorkspaceError.unsafePath {}
}
try store.exportDOCX("원고 & <안녕> 😀\n둘째 행", to: base.appendingPathComponent("result.docx"))
try store.archive(to: base.appendingPathComponent("project.zip"), drafts: ["first.md": "보관된 초안"])
let source = try String(contentsOf: project.appendingPathComponent("first.md"), encoding: .utf8)
check(source.hasPrefix("원고"), "archive leaves source untouched")
try FileManager.default.moveItem(at: project.appendingPathComponent("first.md"), to: project.appendingPathComponent("renamed.md"))
try store.relocatePaths(old: project.appendingPathComponent("first.md"), new: project.appendingPathComponent("renamed.md"))
doc.scenes[0].manuscriptPath = "renamed.md"
let rescanned = try store.load(); check(rescanned.scenes.count == 2 && rescanned.lore.count == 1, "scan never deletes missing links")
let renamedProject = base.appendingPathComponent("Renamed.weaveproj")
try FileManager.default.moveItem(at: project, to: renamedProject)
let afterRename = try WritingWorkspaceStore(projectURL: renamedProject).load()
check(afterRename == doc, "Finder project rename preserves metadata discovery")
try FileManager.default.createSymbolicLink(at: renamedProject.appendingPathComponent("outside.md"), withDestinationURL: base.appendingPathComponent("result.docx"))
do { _ = try WritingWorkspaceStore(projectURL: renamedProject).resolve("outside.md"); fatalError("symlink accepted") } catch WritingWorkspaceError.unsafePath {}
print("writing workspace assertions passed")
''')
    executable = temp / 'test'
    subprocess.run(['swiftc', str(root / 'TextlinkEditor/Services/Writing/WritingWorkspaceStore.swift'), str(harness), '-o', str(executable)], check=True)
    subprocess.run([str(executable), str(temp)], check=True)
    with zipfile.ZipFile(temp / 'result.docx') as z:
        tree = ET.fromstring(z.read('word/document.xml'))
        text = ''.join(tree.itertext())
        assert text == '원고 & <안녕> 😀둘째 행', text
        assert '_rels/.rels' in z.namelist()
    converted = subprocess.run(['/usr/bin/textutil', '-convert', 'txt', '-stdout', str(temp / 'result.docx')], check=True, capture_output=True).stdout.decode()
    assert '원고 & <안녕> 😀' in converted and '둘째 행' in converted, converted
    with zipfile.ZipFile(temp / 'project.zip') as z:
        assert z.read('Story.weaveproj/first.md').decode() == '보관된 초안'
        assert 'Story.weaveproj/.Story.weavedata/writing-workspace.json' in z.namelist()
print('DOCX package/XML and archived draft bytes passed')
