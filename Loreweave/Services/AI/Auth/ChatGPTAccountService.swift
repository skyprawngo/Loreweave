import AppKit
import Observation

/// The official runtime owns OAuth PKCE, callback validation, refresh and macOS Keychain storage.
/// LoreWeave never reads or copies access/refresh tokens from another application's account.
enum LoreCodexEnvironment {
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Loreweave/OpenAI", isDirectory: true)
    }
    static let arguments = ["-c", "cli_auth_credentials_store=\"keyring\"", "-c", "forced_login_method=\"chatgpt\"", "-c", "model_provider=\"openai\""]
    static func environment(root: URL = directory) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        for key in Array(env.keys) where key.hasPrefix("OPENAI_") || key.hasPrefix("CODEX_") { env.removeValue(forKey: key) }
        env["CODEX_HOME"] = root.path
        env["PATH"] = CLIDetector.searchPaths.joined(separator: ":")
        return env
    }
    static func prepare(root: URL = directory) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
}

struct ChatGPTAccount: Equatable {
    let email: String
    let plan: String
    static func parse(_ result: [String: Any]) -> ChatGPTAccount? {
        guard let account = result["account"] as? [String: Any], account["type"] as? String == "chatgpt" else { return nil }
        return ChatGPTAccount(email: account["email"] as? String ?? "ChatGPT", plan: account["planType"] as? String ?? "")
    }
}

@MainActor @Observable
final class ChatGPTAccountService {
    private(set) var account: ChatGPTAccount?
    private(set) var isBusy = false
    private(set) var loginPending = false
    private(set) var errorMessage: String?
    private(set) var limits: String?
    private var rpc: CodexAccountRPC?
    private var loginID: String?
    private var generation = UUID()
    private var expiry: Task<Void, Never>?

    func refresh() async {
        guard !isBusy, !loginPending else { return }
        isBusy = true
        errorMessage = nil
        let owner = generation
        defer { if generation == owner { isBusy = false } }
        do {
            let rpc = try await server()
            let result = try await rpc.request("account/read", ["refreshToken": false])
            guard owner == generation else { return }
            account = ChatGPTAccount.parse(result)
        } catch { if owner == generation { errorMessage = L10n.get("ai.oauth.connectionFailed") } }
    }

    func login() async {
        guard !isBusy, !loginPending else { return }
        isBusy = true
        errorMessage = nil
        let owner = generation
        defer { if owner == generation { isBusy = false } }
        do {
            let rpc = try await server()
            let result = try await rpc.request("account/login/start", ["type": "chatgpt"])
            guard owner == generation else { return }
            guard let id = result["loginId"] as? String, let value = result["authUrl"] as? String,
                  let url = Self.validLoginURL(value) else { throw CodexAccountRPC.Failure.protocolError }
            loginID = id
            loginPending = true
            guard NSWorkspace.shared.open(url) else { cancelLogin(); errorMessage = L10n.get("ai.oauth.browserFailed"); return }
            expiry?.cancel()
            expiry = Task { [weak self] in
                try? await Task.sleep(for: .seconds(300))
                guard !Task.isCancelled, let self, generation == owner, loginID == id else { return }
                cancelLogin()
                errorMessage = L10n.get("ai.oauth.expired")
            }
        } catch { if owner == generation { errorMessage = L10n.get("ai.oauth.connectionFailed") } }
    }

    static func validLoginURL(_ value: String) -> URL? {
        guard let url = URL(string: value), url.scheme == "https", url.user == nil, url.password == nil,
              ["auth.openai.com", "auth0.openai.com", "chatgpt.com"].contains(url.host?.lowercased() ?? "") else { return nil }
        return url
    }

    func cancelLogin() {
        // Closing this private server drops its callback listener and invalidates pending RPCs.
        generation = UUID()
        expiry?.cancel()
        loginID = nil
        loginPending = false
        isBusy = false
        rpc?.close()
        rpc = nil
    }

    func logout() async {
        guard !isBusy else { return }
        cancelLogin()
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let rpc = try await server()
            _ = try await rpc.request("account/logout")
            account = nil
            limits = nil
        } catch { errorMessage = L10n.get("ai.oauth.logoutFailed") }
    }

    func refreshLimits() async {
        guard account != nil, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let rpc = try await server()
            let result = try await rpc.request("account/rateLimits/read")
            let buckets = result["rateLimitsByLimitId"] as? [String: [String: Any]]
            let values = buckets?.sorted(by: { $0.key < $1.key }).map { ($0.key, $0.value) }
                ?? [("Codex", result["rateLimits"] as? [String: Any] ?? [:])]
            limits = values.flatMap { name, bucket in
                ["primary", "secondary"].compactMap { key -> String? in
                    guard let window = bucket[key] as? [String: Any], let used = window["usedPercent"] as? Double else { return nil }
                    let minutes = window["windowDurationMins"] as? Int ?? 0
                    return "\(name) · \(minutes) min · \(Int(max(0, min(100, 100-used))))% " + L10n.get("ai.oauth.remaining")
                }
            }.joined(separator: "\n")
            if limits?.isEmpty == true { limits = L10n.get("ai.oauth.limitsUnavailable") }
        } catch { limits = L10n.get("ai.oauth.limitsUnavailable") }
    }

    private func server() async throws -> CodexAccountRPC {
        if let rpc, rpc.running { return rpc }
        let owner = generation
        guard let path = await CLIDetector.shared.resolvedPath(for: .chatgpt) else { throw CodexAccountRPC.Failure.unavailable }
        guard owner == generation, !Task.isCancelled else { throw CancellationError() }
        let client = CodexAccountRPC()
        client.onNotification = { [weak self] method, params in self?.notification(method, params) }
        try client.start(path: path)
        rpc = client
        do {
            _ = try await client.request("initialize", ["clientInfo": ["name": "loreweave", "title": "LoreWeave", "version": "1.0"]])
            try client.notify("initialized")
            return client
        } catch { client.close(); if rpc === client { rpc = nil }; throw error }
    }

    private func notification(_ method: String, _ params: [String: Any]) {
        guard method == "account/login/completed", let id = params["loginId"] as? String, id == loginID else { return }
        expiry?.cancel()
        loginID = nil
        loginPending = false
        if params["success"] as? Bool == true {
            Task { await refresh() }
        } else { errorMessage = L10n.get("ai.oauth.loginFailed") }
    }
}

/// Bounded JSONL RPC transport; only account APIs are used, no model requests or secret payload logging.
@MainActor
final class CodexAccountRPC {
    enum Failure: Error { case unavailable, protocolError, stopped, timeout }
    private var process: Process?
    private var input: Pipe?
    private var output: Pipe?
    private var pending: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    private var nextID = 0
    private var buffer = Data()
    var onNotification: ((String, [String: Any]) -> Void)?
    var running: Bool { process?.isRunning == true }

    func start(path: String, root: URL = LoreCodexEnvironment.directory) throws {
        try LoreCodexEnvironment.prepare(root: root)
        let task = Process()
        let stdin = Pipe(), stdout = Pipe()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = LoreCodexEnvironment.arguments + ["app-server", "--listen", "stdio://"]
        task.environment = LoreCodexEnvironment.environment(root: root)
        task.currentDirectoryURL = root
        _ = fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        task.standardInput = stdin
        task.standardOutput = stdout
        task.standardError = FileHandle.nullDevice
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let bytes = handle.availableData
            Task { @MainActor [weak self] in
                guard let self else { return }
                if bytes.isEmpty { close() } else { receive(bytes) }
            }
        }
        task.terminationHandler = { [weak self] _ in Task { @MainActor [weak self] in self?.close() } }
        process = task; input = stdin; output = stdout
        do { try task.run() } catch { close(); throw error }
    }

    func request(_ method: String, _ params: [String: Any] = [:]) async throws -> [String: Any] {
        guard running else { throw Failure.stopped }
        nextID += 1
        let id = nextID
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            do { try write(["id": id, "method": method, "params": params]) }
            catch { pending.removeValue(forKey: id)?.resume(throwing: error) }
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(20))
                self?.pending.removeValue(forKey: id)?.resume(throwing: Failure.timeout)
            }
        }
    }

    func notify(_ method: String) throws { try write(["method": method, "params": [:]]) }
    private func write(_ message: [String: Any]) throws {
        guard running, let input else { throw Failure.stopped }
        var data = try JSONSerialization.data(withJSONObject: message)
        data.append(10)
        try input.fileHandleForWriting.write(contentsOf: data)
    }
    private func receive(_ bytes: Data) {
        buffer.append(bytes)
        guard buffer.count <= 2_000_000 else { close(); return }
        while let newline = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<newline]); buffer.removeSubrange(...newline)
            guard let json = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { close(); return }
            if let id = json["id"] as? Int, let reply = pending.removeValue(forKey: id) {
                if let result = json["result"] as? [String: Any] { reply.resume(returning: result) }
                else { reply.resume(throwing: Failure.protocolError) }
            } else if let method = json["method"] as? String {
                onNotification?(method, json["params"] as? [String: Any] ?? [:])
            }
        }
    }
    func close() {
        output?.fileHandleForReading.readabilityHandler = nil
        try? input?.fileHandleForWriting.close()
        try? output?.fileHandleForReading.close()
        if let process, process.isRunning { process.terminate() }
        process = nil; input = nil; output = nil; buffer.removeAll()
        let waiting = pending; pending.removeAll()
        for reply in waiting.values { reply.resume(throwing: Failure.stopped) }
    }
}
