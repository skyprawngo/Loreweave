import Foundation

final class CLIDetector {
    static let shared = CLIDetector()
    private init() {}

    static var searchPaths: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let inherited = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        return ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "\(home)/.npm-global/bin", "/usr/bin", "/bin"] + inherited
    }

    /// Detection and execution deliberately share one resolver; no login shell/startup scripts.
    func resolvedPath(for cliType: AICLIType) async -> String? {
        let saved = UserSettings.shared.getAICLIPath()
        if let saved, Self.isValidExecutable(saved, for: cliType) { return saved.path }
        return Self.searchPaths.map { URL(fileURLWithPath: $0).appendingPathComponent(cliType.commandName) }
            .first { Self.isValidExecutable($0, for: cliType) }?.path
    }

    static func isValidExecutable(_ url: URL, for cliType: AICLIType) -> Bool {
        var isDirectory: ObjCBool = false
        return url.lastPathComponent == cliType.commandName &&
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && !isDirectory.boolValue &&
            FileManager.default.isExecutableFile(atPath: url.path)
    }

    func checkInstallation(for cliType: AICLIType) async -> CLIInstallationStatus {
        if let path = await resolvedPath(for: cliType) { return .installed(path: path) }
        return .notInstalled
    }
}
