#!/usr/bin/env python3
"""Compile production version/backup store; exercise isolated filesystem transactions."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
checks = r'''
import Foundation
enum L10n { static func get(_ key: String) -> String { key } }
func check(_ condition: @autoclosure () throws -> Bool, _ message: String) rethrows {
    guard try condition() else { fatalError(message) }
    print("PASS \(message)")
}
let fm = FileManager.default
let base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try fm.createDirectory(at: base, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: base) }
let project = base.appendingPathComponent("Novel.weaveproj")
try fm.createDirectory(at: project, withIntermediateDirectories: true)
let document = project.appendingPathComponent("chapter.md")
try Data("disk".utf8).write(to: document)
let first = try VersionHistoryStore.snapshot(projectURL: project, documentURL: document, content: "한글 😀 draft")
let again = try VersionHistoryStore.snapshot(projectURL: project, documentURL: document, content: "한글 😀 draft")
check(first.id == again.id, "unchanged snapshot is deduplicated")
try check(String(contentsOf: document, encoding: .utf8) == "disk", "snapshot leaves disk manuscript intact")
for n in 0..<35 { _ = try VersionHistoryStore.snapshot(projectURL: project, documentURL: document, content: "revision \(n)") }
let versions = try VersionHistoryStore.snapshots(projectURL: project, documentURL: document)
check(versions.count == 30 && versions.first?.content == "revision 34", "newest 30 versions retained")
let restored = project.appendingPathComponent("restored.md")
try VersionHistoryStore.restoreCopy(first, to: restored)
try check(String(contentsOf: restored, encoding: .utf8) == first.content, "restore preserves Unicode bytes")
do { try VersionHistoryStore.restoreCopy(first, to: document); fatalError("overwrite accepted") } catch {}
try check(String(contentsOf: document, encoding: .utf8) == "disk", "restore refuses existing manuscript")
do { _ = try VersionHistoryStore.snapshot(projectURL: project, documentURL: base.appendingPathComponent("outside"), content: "x"); fatalError("outside accepted") } catch {}
let link = project.appendingPathComponent("link.md")
try fm.createSymbolicLink(at: link, withDestinationURL: base.appendingPathComponent("outside"))
do { _ = try VersionHistoryStore.snapshot(projectURL: project, documentURL: link, content: "x"); fatalError("symlink accepted") } catch {}
let rejected = base.appendingPathComponent("Rejected.weaveproj")
do { try ProjectBackupStore.create(projectURL: project, destinationURL: rejected); fatalError("symlink backed up") } catch {}
check(!fm.fileExists(atPath: rejected.path), "failed backup publishes no partial folder")
try fm.removeItem(at: link)
let backup = base.appendingPathComponent("Backup")
try ProjectBackupStore.create(projectURL: project, destinationURL: backup)
try check(String(contentsOf: backup.appendingPathComponent("chapter.md"), encoding: .utf8) == "disk", "backup retains saved manuscript")
let backupVersions = try VersionHistoryStore.snapshots(projectURL: backup, documentURL: backup.appendingPathComponent("chapter.md"))
check(backupVersions.count == 30, "renamed backup preserves version metadata")
do { try ProjectBackupStore.create(projectURL: project, destinationURL: backup); fatalError("backup overwrite accepted") } catch {}
do { try ProjectBackupStore.create(projectURL: project, destinationURL: project.appendingPathComponent("Nested.weaveproj")); fatalError("nested accepted") } catch {}
check(!fm.fileExists(atPath: project.appendingPathComponent("Nested.weaveproj").path), "recursive backup rejected")
let renamed = project.appendingPathComponent("renamed.md")
try fm.moveItem(at: document, to: renamed)
try VersionHistoryStore.relocate(projectURL: project, from: document, to: renamed)
try check(VersionHistoryStore.snapshots(projectURL: project, documentURL: renamed).count == 30, "rename keeps manuscript history")
try check(VersionHistoryStore.snapshots(projectURL: project, documentURL: document).isEmpty, "rename releases old history location")
let folder = project.appendingPathComponent("drafts")
try fm.createDirectory(at: folder, withIntermediateDirectories: true)
let nested = folder.appendingPathComponent("nested.md")
_ = try VersionHistoryStore.snapshot(projectURL: project, documentURL: nested, content: "nested")
let movedFolder = project.appendingPathComponent("chapters")
try fm.moveItem(at: folder, to: movedFolder)
try VersionHistoryStore.relocate(projectURL: project, from: folder, to: movedFolder)
try check(VersionHistoryStore.snapshots(projectURL: project, documentURL: movedFolder.appendingPathComponent("nested.md")).first?.content == "nested", "folder rename updates descendant history paths")
let metadata = project.appendingPathComponent(".Novel.weavedata/versions")
try fm.moveItem(at: metadata, to: base.appendingPathComponent("moved"))
try fm.createSymbolicLink(at: metadata, withDestinationURL: base.appendingPathComponent("moved"))
do { _ = try VersionHistoryStore.snapshot(projectURL: project, documentURL: document, content: "x"); fatalError("storage symlink accepted") } catch {}
print("PASS symlinked metadata rejected")
'''
with tempfile.TemporaryDirectory(prefix="lore-versions-") as scratch:
    scratch = Path(scratch)
    main = scratch / "main.swift"
    main.write_text(checks)
    executable = scratch / "check"
    subprocess.run(["swiftc", "-O", str(root / "TextlinkEditor/Services/Versions/VersionHistoryStore.swift"), str(main), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
