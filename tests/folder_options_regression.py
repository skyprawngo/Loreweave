#!/usr/bin/env python3
"""Exercise real folder appearance storage and FileSystemManager using temporary projects."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SUPPORT = r'''
import Foundation
import AppKit
import SwiftUI

enum L10n {
    static var strings: [String: String] = [:]
    static func get(_ key: String) -> String { strings[key] ?? key }
    enum editor { static let untitled = "Untitled" }
    enum common {
        static let confirm = "OK", cancel = "Cancel", save = "Save", delete = "Delete"
    }
}
struct UserSettings {
    static let shared = UserSettings()
    let editorFontName = "system"
    let editorFontSize: CGFloat = 14, editorLineSpacing: CGFloat = 1
}
enum ProjectManager { static let dataFolderExtension = "weavedata" }
extension NSAlert {
    func beginSheetModalWithArrowNavigation(for window: NSWindow, completionHandler: @escaping (NSApplication.ModalResponse) -> Void) {
        beginSheetModal(for: window, completionHandler: completionHandler)
    }
}
'''
FILES = [
    'TextlinkEditor/Models/FileSystemItem.swift',
    'TextlinkEditor/Services/FileSystem/DocumentFileStore.swift',
    'TextlinkEditor/Services/FileSystem/FolderAppearanceStore.swift',
    'TextlinkEditor/Services/FileSystem/FileSystemManager.swift',
    'TextlinkEditor/Services/FileSystem/FileSystemDialogs.swift',
]
FILES += ['TextlinkEditor/Services/Editor/EditorTabManager.swift', 'TextlinkEditor/Services/Versions/VersionHistoryStore.swift', 'TextlinkEditor/Services/Writing/WritingWorkspaceStore.swift']
FILES += [str(p.relative_to(ROOT)) for p in (ROOT / 'TextlinkEditor/Services/Editor/Session').glob('*.swift')]
FILES += [str(p.relative_to(ROOT)) for p in (ROOT / 'TextlinkEditor/Services/FileSystem/Workspace').glob('*.swift')]
SOURCE = SUPPORT + '\n'.join((ROOT / path).read_text() for path in FILES)
HARNESS = r'''
func expect(_ value: @autoclosure () -> Bool, _ message: String) {
    precondition(value(), message)
    print("PASS " + message)
}
let fm = FileManager.default
let base = URL(fileURLWithPath: CommandLine.arguments[1])
let project = base.appendingPathComponent("Novel.weaveproj")
try fm.createDirectory(at: project, withIntermediateDirectories: true)
let store = FolderAppearanceStore(projectURL: project)
expect(try! store.load().isEmpty, "old projects need no migration")
let manager = FileSystemManager.shared
manager.initializeProject(at: project)
let root = manager.projectRoot!
let folder = manager.createFolder(named: "세계관", in: root)!
let nested = manager.createFolder(named: "Nested", in: folder)!
try manager.setFolderIcon(.star, for: folder)
try manager.setFolderIcon(.book, for: nested)
expect(folder.iconName == "star", "custom icon overrides section icon immediately")
folder.isExpanded = true
expect(folder.iconName == "star", "expansion retains custom icon")
manager.refreshProject()
expect(manager.findItem(by: folder.url)?.iconName == "star", "refresh retains override")
manager.closeProject()
manager.initializeProject(at: project)
let reopened = manager.projectRoot!.children!.first!
expect(reopened.iconName == "star", "reopening loads saved icon")
expect(manager.rename(reopened, to: "Renamed"), "folder rename succeeds")
let renamed = manager.projectRoot!.children!.first!
expect(renamed.iconName == "star", "rename retains icon")
manager.loadChildren(of: renamed)
expect(renamed.children!.first!.iconName == "book", "rename carries descendant metadata")
let destination = manager.createFolder(named: "Destination", in: manager.projectRoot!)!
expect(manager.move(renamed, to: destination), "folder move succeeds")
let moved = destination.children!.first!
expect(moved.iconName == "star", "move retains icon")
expect(manager.copy(moved, to: manager.projectRoot!), "folder copy succeeds")
let copy = manager.projectRoot!.children!.first { $0.name == "Renamed" }!
expect(copy.iconName == "star", "copy carries appearance")
try manager.setFolderIcon(nil, for: copy)
expect(copy.iconName == "folder", "default clears custom icon")
expect(moved.iconName == "star", "reset does not alter source folder")
let section = manager.createFolder(named: "세계관", in: manager.projectRoot!)!
try manager.setFolderIcon(.heart, for: section)
try manager.setFolderIcon(nil, for: section)
expect(section.iconName == "globe.asia.australia", "reset restores built-in section icon")
let other = base.appendingPathComponent("Other.weaveproj")
try fm.createDirectory(at: other, withIntermediateDirectories: true)
manager.initializeProject(at: other)
do { try manager.setFolderIcon(.flag, for: moved); fatalError("accepted stale project folder") } catch {}
expect(try! FolderAppearanceStore(projectURL: other).load().isEmpty, "project switch isolates metadata")
manager.initializeProject(at: project)
let current = manager.projectRoot!.children!.first { $0.name == "Renamed" }!
let metadata = project.appendingPathComponent(".Novel.weavedata/folder-icons.json")
let saved = try Data(contentsOf: metadata)
try Data("invalid".utf8).write(to: metadata)
do { try manager.setFolderIcon(.film, for: current); fatalError("overwrote corrupt metadata") } catch {}
expect(try! String(contentsOf: metadata, encoding: .utf8) == "invalid", "invalid metadata is preserved on save failure")
expect(current.customFolderIcon == nil, "failed save does not change visible icon")
try saved.write(to: metadata)
try store.remove(for: moved.url)
expect(try! store.load().keys.allSatisfy { !$0.hasPrefix("Destination/Renamed") }, "removal clears descendant overrides")
expect(try! store.load().keys.contains("Renamed/Nested"), "removal preserves copied subtree")
for icon in FolderIcon.allCases {
    expect(NSImage(systemSymbolName: icon.rawValue, accessibilityDescription: nil) != nil, "symbol exists: " + icon.rawValue)
}
let editor = EditorTabManager(recoveryDirectory: base.appendingPathComponent("Recovery"))
editor.restoreSession(from: project)
let manuscript = manager.createFile(named: "draft.md", in: manager.projectRoot!, content: "baseline")!
editor.openFile(manuscript)
editor.setEditState(TabEditState(content: "unsaved", originalContent: "baseline"), for: manuscript.url)
let tabID = editor.tabs[0].id
expect(manager.rename(manuscript, to: "renamed-draft.md"), "sidebar rename command succeeds")
let renamedDocument = project.appendingPathComponent("renamed-draft.md")
expect(editor.tabs[0].id == tabID && editor.tabs[0].url == renamedDocument, "sidebar and tab use same committed path")
expect(editor.getCachedContent(for: renamedDocument) == "unsaved", "sidebar rename retains live editor draft")
let projectedFile = manager.findItem(by: renamedDocument)!
editor.openFile(projectedFile)
expect(editor.tabs.count == 1 && editor.selectedTab?.id == tabID, "sidebar path alias selects existing tab instead of duplicating it")
expect(editor.getCachedContent(for: projectedFile.url) == "unsaved", "path alias reads the same editor buffer")
expect(manager.findItem(by: renamedDocument) != nil && manager.findItem(by: manuscript.url) == nil, "sidebar replaces old path with renamed path")
editor.setCachedContent("baseline", for: renamedDocument)
try DocumentFileStore.save("external-style write", at: renamedDocument, expected: "baseline")
let deadline = Date().addingTimeInterval(5)
while editor.getCachedContent(for: renamedDocument) != "external-style write", Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
expect(editor.getCachedContent(for: renamedDocument) == "external-style write", "shared repository event updates renamed document")
_ = editor.closeAllTabs(force: true)
manager.closeProject()
print("ALL FOLDER OPTIONS REGRESSIONS PASSED")
'''

if __name__ == '__main__':
    with tempfile.TemporaryDirectory(prefix='folder-options-') as temp:
        directory = Path(temp)
        fixture = directory / 'main.swift'
        fixture.write_text(SOURCE + HARNESS)
        executable = directory / 'regression'
        subprocess.run(['swiftc', str(fixture), '-o', str(executable)], check=True)
        subprocess.run([str(executable), str(directory)], check=True)
