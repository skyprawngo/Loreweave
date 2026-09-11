#!/usr/bin/env python3
"""Run production storage/tab code with isolated dialog/settings doubles, no app preferences."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
swift = r'''
import Foundation
import AppKit
import Observation

final class NSAlert {
    enum Style { case warning }
    static var responses: [NSApplication.ModalResponse] = []
    var messageText = "", informativeText = ""
    var alertStyle: Style = .warning
    func addButton(withTitle: String) {}
    @discardableResult func runModal() -> NSApplication.ModalResponse {
        Self.responses.isEmpty ? .alertFirstButtonReturn : Self.responses.removeFirst()
    }
}
enum L10n {
    static func get(_ s: String) -> String { s }
    enum common { static let cancel = "Cancel", confirm = "OK" }
    enum editor { static let untitled = "Untitled" }
}
struct UserSettings {
    static let shared = UserSettings()
    let editorFontName = "system"
    let editorFontSize: CGFloat = 14, editorLineSpacing: CGFloat = 1
}
enum ProjectManager { static let dataFolderExtension = "weavedata" }
final class FileSystemItem {
    let url: URL
    var name: String
    let isDirectory: Bool
    init(url: URL, isDirectory: Bool) { self.url = url; name = url.lastPathComponent; self.isDirectory = isDirectory }
}
func expect(_ condition: @autoclosure () -> Bool, _ label: String) {
    guard condition() else { fatalError(label) }
    print("PASS " + label)
}
let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: base) }
let project = base.appendingPathComponent("Novel.weaveproj")
let data = project.appendingPathComponent(".Novel.weavedata")
try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
let file = project.appendingPathComponent("chapter.md")
try DocumentFileStore.create("original", at: file)
do { try DocumentFileStore.create("", at: file); fatalError("overwrote original") } catch {}
expect(try! String(contentsOf: file, encoding: .utf8) == "original", "exclusive creation preserves existing document")
try DocumentFileStore.save("saved", at: file, expected: "original")
do { try DocumentFileStore.save("lost", at: file, expected: "original"); fatalError("ignored conflict") } catch {}
expect(try! String(contentsOf: file, encoding: .utf8) == "saved", "conflicting disk revision is preserved")
expect(!DocumentFileStore.contains(base.appendingPathComponent("Novel.weaveproj-other/chapter.md"), in: project), "path boundary is directory-aware")
expect(DocumentFileStore.changedLines(from: "a\nb\nc", to: "a\nnew\nc") == [2], "linear diff reports modified region")
expect(DocumentFileStore.changedLines(from: String(repeating: "a\n", count: 10000), to: "x").count == 1, "long document diff is bounded")
let localRecovery = base.appendingPathComponent("Recovery")
let manager = EditorTabManager(recoveryDirectory: localRecovery)
manager.restoreSession(from: project)
manager.openFile(FileSystemItem(url: file, isDirectory: false))
manager.setEditState(TabEditState(content: "draft", originalContent: "saved"), for: file)
manager.saveSession(to: project)
manager.closeAllTabs(force: true)
// force close writes a new session, so restore the captured crash snapshot explicitly.
manager.openFile(FileSystemItem(url: file, isDirectory: false))
manager.setEditState(TabEditState(content: "draft", originalContent: "saved"), for: file)
manager.saveSession(to: project)
manager.restoreSession(from: project)
expect(manager.getCachedContent(for: file) == "draft", "unsaved crash snapshot restores")
expect(manager.isModified(url: file), "recovered draft remains unsaved")
NSAlert.responses = [.alertThirdButtonReturn]
expect(!manager.prepareToClose(manager.tabs), "cancel rejects close")
expect(manager.getCachedContent(for: file) == "draft", "cancel preserves draft")
NSAlert.responses = [.alertSecondButtonReturn]
expect(manager.prepareToClose(manager.tabs), "discard decision accepted")
expect(manager.getCachedContent(for: file) == "draft", "prepare does not destroy draft before I/O succeeds")
try Data("external".utf8).write(to: file, options: .atomic)
expect(!manager.saveTab(at: 0, content: "draft"), "manager refuses external conflict")
expect(manager.getCachedContent(for: file) == "draft", "failed save retains draft")
expect(manager.saveErrors[file] != nil, "failed save exposes error")
let target = project.appendingPathComponent("renamed.md")
let id = manager.tabs[0].id
try FileManager.default.moveItem(at: file, to: target)
manager.relocateTabs(from: file, to: target)
expect(manager.tabs[0].id == id && manager.tabs[0].url == target, "rename retains document identity")
expect(manager.getCachedContent(for: target) == "draft" && manager.getCachedContent(for: file) == nil, "rename moves cache ownership")
let external = base.appendingPathComponent("outside.md")
try DocumentFileStore.create("outside", at: external)
manager.openFile(FileSystemItem(url: external, isDirectory: false))
manager.setEditState(TabEditState(content: "outside draft", originalContent: "outside"), for: external)
manager.saveSession(to: project)
manager.restoreSession(from: project)
expect(manager.getCachedContent(for: external) == "outside draft", "external document draft restores")
let emptyProject = base.appendingPathComponent("Empty.weaveproj")
try FileManager.default.createDirectory(at: emptyProject, withIntermediateDirectories: true)
manager.restoreSession(from: emptyProject)
expect(manager.tabs.isEmpty, "project without session clears old workspace")
let sessionFile = data.appendingPathComponent("editor-session.json")
try Data("broken json".utf8).write(to: sessionFile)
for url in try FileManager.default.contentsOfDirectory(at: localRecovery, includingPropertiesForKeys: nil) { try FileManager.default.removeItem(at: url) }
manager.restoreSession(from: project)
expect(manager.recoveryError != nil, "corrupt recovery is reported")
expect(try! FileManager.default.contentsOfDirectory(atPath: data.path).contains(where: { $0.contains("unreadable-") }), "corrupt original is archived")
var forged = TabState(relativePath: "ignored", isModified: true)
forged.externalURL = external
forged.draftContent = "forged"
forged.baseContent = "outside"
try JSONEncoder().encode(EditorSessionState(tabs: [forged], selectedTabIndex: 0)).write(to: sessionFile)
manager.restoreSession(from: project)
expect(manager.tabs.isEmpty, "project metadata cannot inject external write targets")

let largeURL = base.appendingPathComponent("large-utf8.md")
let largeOriginal = String(repeating: "한😀e\u{301}\n", count: 30000)
try DocumentFileStore.create(largeOriginal, at: largeURL)
let largeChanged = largeOriginal + "final\n"
try DocumentFileStore.save(largeChanged, at: largeURL, expected: largeOriginal)
expect(try! String(contentsOf: largeURL, encoding: .utf8) == largeChanged, "streamed atomic save preserves UTF8 chunk boundaries")
print("ALL STORAGE REGRESSIONS PASSED")
'''
with tempfile.TemporaryDirectory(prefix="loreweave-storage-tests-") as work:
    work = Path(work)
    (work / "main.swift").write_text(swift)
    subprocess.run(["xcrun", "swiftc", str(root / "Loreweave/Services/FileSystem/DocumentFileStore.swift"),
                    str(root / "Loreweave/Services/Editor/EditorTabManager.swift"), str(work / "main.swift"),
                    "-o", str(work / "regression")], check=True)
    subprocess.run([str(work / "regression")], check=True)
