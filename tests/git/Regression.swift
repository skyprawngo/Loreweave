import Foundation

enum L10n { static func get(_ key: String) -> String { key } }

@main struct GitRegression {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TextlinkGit-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var assertions = 0
        func check(_ value: Bool, _ label: String) { precondition(value, label); assertions += 1; print("PASS " + label) }
        func git(_ args: [String]) throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["-C", root.path] + args
            process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
            try process.run(); process.waitUntilExit(); precondition(process.terminationStatus == 0)
        }
        func write(_ path: String, _ text: String) throws { try text.write(to: root.appendingPathComponent(path), atomically: true, encoding: .utf8) }
        let repo = ProjectGitRepository(project: root)
        check(try !repo.snapshot().exists, "inspection never initializes Git")
        try repo.initialize()
        try git(["config", "user.name", "Fixture"])
        try git(["config", "user.email", "fixture@example.test"])
        try git(["config", "commit.gpgsign", "false"])
        try write("한글 문서.md", "original\n")
        try write("[draft].md", "literal\n")
        try write("d.md", "unrelated\n")
        try write(".private.md", "hidden")
        check(try repo.snapshot().changes.count == 3, "hidden app data excluded")
        let untracked = try repo.diff(path: "한글 문서.md", scope: .working)
        check(untracked.before == nil && untracked.after == "original\n", "untracked text has exact bytes")
        try repo.stage("[draft].md")
        check(try repo.snapshot().changes.filter(\.staged).map(\.path) == ["[draft].md"], "literal pathspec cannot stage neighboring files")
        try repo.unstage("[draft].md")
        check(try repo.snapshot().changes.allSatisfy { !$0.staged }, "unstage works before first commit")
        try repo.stage("한글 문서.md")
        try repo.commit("initial")
        try write("한글 문서.md", "staged\n")
        try repo.stage("한글 문서.md")
        try write("한글 문서.md", "working\n")
        let snapshot = try repo.snapshot()
        let row = snapshot.changes.first { $0.path == "한글 문서.md" }!
        check(row.staged && row.unstaged, "partial staging appears in both groups")
        let staged = try repo.diff(path: row.path, scope: .staged)
        let working = try repo.diff(path: row.path, scope: .working)
        check(staged.before == "original\n" && staged.after == "staged\n", "staged comparison uses HEAD and index")
        check(working.before == "staged\n" && working.after == "working\n", "working comparison uses index and disk")
        check(working.patch.contains("@@") && working.patch.contains("+working"), "unified hunks available for instructions")
        try repo.unstage(row.path)
        check(try String(contentsOf: root.appendingPathComponent(row.path), encoding: .utf8) == "working\n", "unstage preserves working manuscript")
        try repo.stage(row.path)
        try repo.commit("second")
        let history = try repo.snapshot().commits
        check(history.count == 2 && history.first?.parents == [history[1].id], "graph follows actual commit parents")
        check(try repo.commitPatch(history[0].id).contains("+working"), "commit comparison contains source changes")
        try FileManager.default.removeItem(at: root.appendingPathComponent(row.path))
        check(try repo.diff(path: row.path, scope: .working).after == nil, "deleted manuscript is not recreated")
        try Data([0, 255, 1]).write(to: root.appendingPathComponent("image.png"))
        check(try repo.diff(path: "image.png", scope: .working).binary, "binary content is not an AI text change")
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link.md"), withDestinationURL: root.appendingPathComponent("d.md"))
        do { _ = try repo.diff(path: "link.md", scope: .working); preconditionFailure("symlink accepted") } catch {}
        check(!ProjectGitRepository.safePath("../outside.md") && !ProjectGitRepository.safePath(".git/config"), "unsafe targets rejected")
        let nested = root.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        do { _ = try ProjectGitRepository(project: nested).snapshot(); preconditionFailure("parent Git accepted") } catch {}
        check(true, "parent repository is never managed implicitly")
        print("Git regression passed: \(assertions) assertions")
    }
}
