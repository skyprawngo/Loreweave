import Foundation

enum CollaborationGit {
    /// No shell, hooks, staging, commits, or repository initialization.
    static func staged(project: URL) throws -> [String: String?] {
        let root = try run(["rev-parse", "--show-toplevel"], project: project)
        let reported = URL(fileURLWithPath: String(decoding: root, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        guard reported.resolvingSymlinksInPath().standardizedFileURL == project.resolvingSymlinksInPath().standardizedFileURL else {
            throw CollaborationFailure.gitRoot
        }
        let indexBefore = try run(["ls-files", "--stage", "-z"], project: project)
        let diffArguments = ["diff", "--cached", "--name-only", "--no-renames", "-z", "--"]
        let names = try run(diffArguments, project: project)
        var result: [String: String?] = [:]
        for bytes in names.split(separator: 0) {
            guard let path = String(data: Data(bytes), encoding: .utf8) else { throw CollaborationFailure.gitFailed }
            guard CollaborationStore.validPath(path) else { continue }
            let entries = try run(["ls-files", "--stage", "-z", "--", path], project: project)
            if entries.isEmpty { result[path] = .some(nil); continue }
            let prefix = String(decoding: entries, as: UTF8.self)
            guard prefix.hasPrefix("100644 ") || prefix.hasPrefix("100755 "),
                  prefix.split(separator: "\t", maxSplits: 1).first?.hasSuffix(" 0") == true else { throw CollaborationFailure.gitFailed }
            let contents = try run(["show", ":" + path], project: project)
            guard let text = String(data: contents, encoding: .utf8) else { throw CollaborationFailure.gitFailed }
            result[path] = .some(text)
        }
        guard try run(["ls-files", "--stage", "-z"], project: project) == indexBefore,
              try run(diffArguments, project: project) == names else { throw CollaborationFailure.conflict }
        return result
    }

    private static func run(_ arguments: [String], project: URL) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["--no-optional-locks", "-c", "core.fsmonitor=false", "-c", "core.hooksPath=/dev/null"] + arguments
        process.currentDirectoryURL = project
        process.environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        try process.run()
        var data = Data()
        while let chunk = try output.fileHandleForReading.read(upToCount: 64 * 1024), !chunk.isEmpty {
            data.append(chunk)
            if data.count > 64 * 1024 * 1024 { process.terminate(); throw CollaborationFailure.tooLarge }
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CollaborationFailure.gitFailed }
        return data
    }
}
