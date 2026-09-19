#!/usr/bin/env python3
"""Run production project creation against temp folders with isolated session/bookmark doubles."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
manager = (ROOT / 'TextlinkEditor/Services/Project/ProjectManager.swift').read_text()
paths = manager[manager.index('    private func dataFolderURL'):manager.index('    /// 기본 저장 위치')]
creation = manager[manager.index('    func createProject('):manager.index('    /// 일반 폴더에서 프로젝트 열기')]
recognition = manager[manager.index('    func isProjectFolder('):manager.index('\n}\n\n// MARK: - Open Panel Delegate')]
opening = manager[manager.index('    func openProjectFromFile('):manager.index('    @discardableResult', manager.index('    func openProjectFromFile('))]
sections = (ROOT / 'TextlinkEditor/Models/FileSystemItem.swift').read_text().split('enum ProjectSection:', 1)[1]
model = (ROOT / 'TextlinkEditor/Models/Project.swift').read_text()
SUPPORT = r'''
import Foundation
import SwiftUI
import AppKit

enum L10n {
    static var strings: [String: String] = [:]
    static func get(_ key: String) -> String { strings[key] ?? key }
    enum common { static var cancel: String { L10n.get("common.cancel") } }
}
final class EditorTabManager {
    static let shared = EditorTabManager()
    var tabs: [Int] = []
    var allowsClose = true
    func prepareToClose(_ tabs: [Int]) -> Bool { allowsClose }
    func saveSession(to: URL, omittingApprovedDiscards: Bool) {}
    func restoreSession(from: URL) {}
}
final class UserSettings {
    static let shared = UserSettings()
    func setLastOpenedProject(_ url: URL) {}
    var forgottenURL: URL?
    func clearLastOpenedProject(ifMatching url: URL) { forgottenURL = url }
}
'''
SUPPORT += (ROOT / 'TextlinkEditor/Services/FileSystem/Workspace/WorkspaceFileEvents.swift').read_text()
SOURCE = SUPPORT + model + '\nenum ProjectSection:' + sections + '\n' + (ROOT / 'TextlinkEditor/Services/FileSystem/DocumentFileStore.swift').read_text() + r'''
final class ProjectManager {
    static let projectExtension = "weaveproj", dataFolderExtension = "weavedata"
    private let projectMetadataFile = "project.json"
    var currentProject: Project?
    var lastError: Error?
    var recentProjects: [Project] = []
    var removedBookmarks: [String] = []
    var recentSaveCount = 0
    func restoreAccess(to: URL) -> Bool { false }
    func saveRecentProjects() { recentSaveCount += 1 }
    func removeBookmarks(for paths: [String]) { removedBookmarks += paths }
    func saveBookmark(for: URL) {}
    func addToRecentProjects(_ project: Project) {}
    func stopAccessing(_ url: URL) {}
    func presentError(_ error: Error) { lastError = error }
    func showSaveDirectoryPanel() -> URL? { nil }
''' + paths + creation + recognition + '\n' + opening + '\n}\n'
HARNESS = r'''
func expect(_ value: @autoclosure () -> Bool, _ message: String) {
    precondition(value(), message)
}
let base = URL(fileURLWithPath: CommandLine.arguments[1])
let locales = URL(fileURLWithPath: CommandLine.arguments[2])
let manager = ProjectManager()
let all = ProjectSection.allCases
for language in ["ko", "en", "ja"] {
    L10n.strings = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: locales.appendingPathComponent(language + ".json")))
    for includeFolders in [false, true] {
        let included = includeFolders ? all : []
        let options = ProjectCreationOptions(includesDefaultFolders: includeFolders)
        let name = "Project-\(language)-\(includeFolders)"
        let project = manager.createProject(name: name, at: base, options: options)!
        let directory = project.path!
        expect(directory.lastPathComponent == name && project.name == name, "Project uses the exact folder name without a suffix")
        expect(manager.isProjectFolder(directory), "Ordinary project folder is recognized by metadata")
        let children = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        let expected = Set(included.map(\.localizedFolderName))
        expect(Set(children.filter { !$0.hasPrefix(".") }) == expected, "Only selected folders are created")
        let metadata = directory.appendingPathComponent(".\(name).weavedata/project.json")
        let loaded = try JSONDecoder().decode(Project.self, from: Data(contentsOf: metadata))
        expect(loaded.id == project.id && loaded.path == directory, "Metadata remains readable for every template")
        expect(options.orderedSections == all.filter { included.contains($0) }, "Template order is deterministic")
    }
    print("PASS \(language): empty/full templates, localized disk names and metadata")
}
let standard = manager.createProject(name: "Default", at: base)!
expect(try! FileManager.default.contentsOfDirectory(atPath: standard.path!.path).filter { !$0.hasPrefix(".") }.count == 6, "Default still creates all folders")
let custom = manager.createProject(name: "Custom.draft", at: base, options: .init(includesDefaultFolders: true))!
expect(custom.path!.lastPathComponent == "Custom.draft", "Custom extension preserved")
expect(custom.name == "Custom.draft" && manager.isProjectFolder(custom.path!), "Dots remain part of a regular folder name")
expect(FileManager.default.fileExists(atPath: custom.path!.appendingPathComponent(".Custom.weavedata/project.json").path), "Custom extension metadata path preserved")
expect(manager.createProject(name: "Custom.draft", at: base, options: .init(includesDefaultFolders: false)) == nil, "Existing project cannot be overwritten")
expect(FileManager.default.fileExists(atPath: custom.path!.appendingPathComponent(ProjectSection.manuscripts.localizedFolderName).path), "Collision preserves original folders")
EditorTabManager.shared.allowsClose = false
expect(manager.createProject(name: "Cancelled", at: base) == nil, "Close cancellation aborts creation")
expect(!FileManager.default.fileExists(atPath: base.appendingPathComponent("Cancelled").path), "Cancelled creation writes no folders")
expect(!manager.isProjectFolder(base), "Uninitialized folders are not mistaken for projects")
print("PASS defaults, custom extension, collision preservation and cancellation")
expect(ProjectSection.from(folderName: "원고") == .manuscripts, "Current Korean template folders are recognized")
expect(ProjectSection.from(folderName: "Editor") == nil, "Retired template folders are not treated as standard sections")
let missing = base.appendingPathComponent("deleted-project")
let existing = base.appendingPathComponent("existing-no-metadata")
try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: false)
manager.currentProject = nil
manager.recentProjects = [Project(name: "Gone", path: missing), Project(name: "Duplicate", path: missing), Project(name: "Exists", path: existing)]
expect(manager.openProjectFromFile(at: missing) == nil, "Missing project reports an open failure")
expect(manager.recentProjects.count == 1 && manager.recentProjects[0].path == existing, "Failed missing path removes all recent entries for that path")
expect(manager.recentSaveCount == 1 && manager.removedBookmarks.contains(missing.path), "Recent list and bookmark cleanup are persisted")
expect(UserSettings.shared.forgottenURL == missing, "Missing last-opened path is cleared")
expect(manager.openProjectFromFile(at: existing) == nil, "Missing metadata still reports an error")
expect(manager.recentProjects.count == 1 && manager.recentSaveCount == 1, "Existing folder is retained when metadata cannot be read")
print("PASS failed open removes missing paths and preserves existing folders")
'''

if __name__ == '__main__':
    with tempfile.TemporaryDirectory(prefix='project-creation-') as temp:
        directory = Path(temp)
        fixture = directory / 'main.swift'
        fixture.write_text(SOURCE + HARNESS)
        executable = directory / 'regression'
        subprocess.run(['swiftc', str(fixture), '-o', str(executable)], check=True)
        output = directory / 'projects'
        output.mkdir()
        subprocess.run([str(executable), str(output), str(ROOT / 'TextlinkEditor/Localization/Strings')], check=True)
