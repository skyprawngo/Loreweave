#!/usr/bin/env python3
"""Run production project creation against temp folders with isolated session/bookmark doubles."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
manager = (ROOT / 'TextlinkEditor/Services/Project/ProjectManager.swift').read_text()
paths = manager[manager.index('    private func dataFolderURL'):manager.index('    /// 기본 저장 위치')]
creation = manager[manager.index('    func createProject('):manager.index('    /// .weaveproj 폴더에서 프로젝트 열기')]
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
}
'''
SUPPORT += (ROOT / 'TextlinkEditor/Services/FileSystem/Workspace/WorkspaceFileEvents.swift').read_text()
SOURCE = SUPPORT + model + '\nenum ProjectSection:' + sections + '\n' + (ROOT / 'TextlinkEditor/Services/FileSystem/DocumentFileStore.swift').read_text() + r'''
final class ProjectManager {
    static let projectExtension = "weaveproj", dataFolderExtension = "weavedata"
    private let projectMetadataFile = "project.json"
    var currentProject: Project?
    var lastError: Error?
    func saveBookmark(for: URL) {}
    func addToRecentProjects(_ project: Project) {}
    func stopAccessing(_ url: URL) {}
    func presentError(_ error: Error) { lastError = error }
    func showSaveDirectoryPanel() -> URL? { nil }
''' + paths + creation + '\n}\n'
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
expect(FileManager.default.fileExists(atPath: custom.path!.appendingPathComponent(".Custom.weavedata/project.json").path), "Custom extension metadata path preserved")
expect(manager.createProject(name: "Custom.draft", at: base, options: .init(includesDefaultFolders: false)) == nil, "Existing project cannot be overwritten")
expect(FileManager.default.fileExists(atPath: custom.path!.appendingPathComponent(ProjectSection.editor.localizedFolderName).path), "Collision preserves original folders")
EditorTabManager.shared.allowsClose = false
expect(manager.createProject(name: "Cancelled", at: base) == nil, "Close cancellation aborts creation")
expect(!FileManager.default.fileExists(atPath: base.appendingPathComponent("Cancelled.weaveproj").path), "Cancelled creation writes no folders")
print("PASS defaults, custom extension, collision preservation and cancellation")
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
