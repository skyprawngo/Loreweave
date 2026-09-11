import Foundation
import Darwin

struct CLIPromptResult {
    let response: String
    let sessionId: String?
}

/// Each panel owns its runner. No process or callback is shared across projects/windows.
@MainActor
final class CLIProcessManager {
    private var runner: CLIRequestRunner?

    func sendPrompt(_ prompt: String, cliType: AICLIType, workingDirectory: URL?,
                    sessionId: String? = nil,
                    streamHandler: @escaping @MainActor @Sendable (String) -> Void) async throws -> CLIPromptResult {
        guard runner == nil else { throw CLIError.busy }
        guard let path = await CLIDetector.shared.resolvedPath(for: cliType) else {
            throw CLIError.notFound
        }
        try Task.checkCancellation()
        guard runner == nil else { throw CLIError.busy }
        // stdin avoids shell interpretation, argv length limits, and prompt exposure in process listings.
        let arguments: [String]
        switch cliType {
        case .claude:
            var args = ["-p", "--output-format", "stream-json", "--verbose", "--include-partial-messages",
                        "--safe-mode", "--tools", ""]
            if let sessionId { args += ["--resume", sessionId] }
            arguments = args
        case .chatgpt:
            try LoreCodexEnvironment.prepare()
            var args = LoreCodexEnvironment.arguments + ["--ask-for-approval", "never", "exec", "--json", "--sandbox", "read-only",
                        "--ignore-user-config", "--ignore-rules", "--skip-git-repo-check"]
            if let sessionId { args += ["resume", sessionId] }
            args.append("-")
            arguments = args
        }
        let current = CLIRequestRunner(path: path, arguments: arguments, prompt: prompt,
                                       workingDirectory: workingDirectory, environment: cliType == .chatgpt ? LoreCodexEnvironment.environment() : nil, streamHandler: streamHandler)
        runner = current
        defer { if runner === current { runner = nil } }
        return try await withTaskCancellationHandler {
            try await current.run()
        } onCancel: {
            current.cancel()
        }
    }

    func cancel() { runner?.cancel() }

    enum CLIError: LocalizedError {
        case notFound, unsupportedProvider, terminalUnavailable, busy, timeout, invalidOutput, authentication, incompatibleCLI, failed(Int32)
        var errorDescription: String? {
            switch self {
            case .notFound: return L10n.get("ai.error.cliNotFound")
            case .unsupportedProvider: return L10n.get("ai.error.unsupportedProvider")
            case .terminalUnavailable: return L10n.get("ai.error.terminalUnavailable")
            case .busy: return L10n.get("ai.error.busy")
            case .timeout: return L10n.get("ai.error.timeout")
            case .invalidOutput: return L10n.get("ai.error.invalidOutput")
            case .authentication: return L10n.get("ai.error.authentication")
            case .incompatibleCLI: return L10n.get("ai.error.incompatibleCLI")
            case .failed(let status): return L10n.get("ai.error.processFailed").replacingOccurrences(of: "{status}", with: String(status))
            }
        }
    }
}

/// JSONL is framed as bytes, so a pipe read may split any UTF-8 scalar safely.
struct CLIJSONStream {
    private var pending = Data()
    private(set) var response = ""
    private(set) var sessionId: String?
    private(set) var completed = false
    private(set) var failed = false
    private(set) var malformed = false
    private(set) var authenticationFailure = false

    mutating func append(_ data: Data) -> [String] {
        pending.append(data)
        var chunks: [String] = []
        while let newline = pending.firstIndex(of: 10) {
            let line = Data(pending[..<newline])
            pending.removeSubrange(...newline)
            if let chunk = consume(line) { chunks.append(chunk) }
        }
        return chunks
    }

    mutating func finish() {
        if !pending.isEmpty { _ = consume(pending); pending.removeAll() }
    }

    private mutating func consume(_ line: Data) -> String? {
        guard !line.isEmpty else { return nil }
        guard let json = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else {
            malformed = true
            return nil
        }
        if let id = json["session_id"] as? String { sessionId = id }
        switch json["type"] as? String {
        case "thread.started":
            sessionId = json["thread_id"] as? String
        case "item.completed":
            if let item = json["item"] as? [String: Any], item["type"] as? String == "agent_message",
               let text = item["text"] as? String {
                let chunk = response.isEmpty ? text : "\n\n" + text
                response += chunk
                return chunk
            }
        case "turn.completed": completed = true
        case "turn.failed", "error":
            failed = true
            authenticationFailure = Self.isAuthenticationFailure(String(decoding: line, as: UTF8.self))
        case "stream_event":
            if let event = json["event"] as? [String: Any],
               let delta = event["delta"] as? [String: Any],
               delta["type"] as? String == "text_delta", let text = delta["text"] as? String {
                response += text
                return text
            }
        case "result":
            completed = true
            failed = json["is_error"] as? Bool == true || (json["subtype"] as? String).map { $0 != "success" } == true
            if let result = json["result"] as? String { response = result }
            if failed { authenticationFailure = Self.isAuthenticationFailure(String(decoding: line, as: UTF8.self)) }
        default: break
        }
        return nil
    }
    static func isAuthenticationFailure(_ text: String) -> Bool {
        let lower = text.lowercased()
        return ["authentication", "not logged in", "login required", "please log in", "invalid api key", "unauthorized"].contains(where: lower.contains)
    }

}

/// Process and cancellation flags are protected by a lock. Blocking IO never runs on MainActor.
private final class CLIRequestRunner: @unchecked Sendable {
    private let path: String
    private let arguments: [String]
    private let workingDirectory: URL?
    private let input = Pipe()
    private let output = Pipe()
    private let errorOutput = Pipe()
    private let lock = NSLock()
    private var pid: pid_t = 0
    private var finished = false
    private var cancelled = false
    private var timedOut = false
    private let environment: [String: String]?
    private let prompt: String
    private let streamHandler: @MainActor @Sendable (String) -> Void

    init(path: String, arguments: [String], prompt: String, workingDirectory: URL?, environment: [String: String]? = nil,
         streamHandler: @escaping @MainActor @Sendable (String) -> Void) {
        self.environment = environment
        self.path = path
        self.arguments = arguments
        self.prompt = prompt
        self.workingDirectory = workingDirectory
        self.streamHandler = streamHandler
    }

    func cancel() {
        lock.lock()
        cancelled = true
        if pid > 0 && !finished { kill(-pid, SIGTERM) }
        lock.unlock()
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [self] in
            lock.lock()
            if pid > 0 && !finished { kill(-pid, SIGKILL) }
            lock.unlock()
        }
    }

    /// A separate process group owns CLI wrappers and their descendants. No shell is involved.
    private func spawn() throws {
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        posix_spawn_file_actions_init(&actions)
        posix_spawnattr_init(&attributes)
        defer {
            posix_spawn_file_actions_destroy(&actions)
            posix_spawnattr_destroy(&attributes)
        }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF))
        var signalMask = sigset_t()
        sigemptyset(&signalMask)
        posix_spawnattr_setsigmask(&attributes, &signalMask)
        var defaults = sigset_t()
        sigemptyset(&defaults)
        for signal in [SIGINT, SIGTERM, SIGPIPE, SIGHUP] { sigaddset(&defaults, signal) }
        posix_spawnattr_setsigdefault(&attributes, &defaults)
        posix_spawnattr_setpgroup(&attributes, 0)
        posix_spawn_file_actions_adddup2(&actions, input.fileHandleForReading.fileDescriptor, STDIN_FILENO)
        posix_spawn_file_actions_adddup2(&actions, output.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, errorOutput.fileHandleForWriting.fileDescriptor, STDERR_FILENO)
        if let workingDirectory {
            let code: Int32
            if #available(macOS 26.0, *) { code = posix_spawn_file_actions_addchdir(&actions, workingDirectory.path) }
            else { code = posix_spawn_file_actions_addchdir_np(&actions, workingDirectory.path) }
            if code != 0 { throw NSError(domain: NSPOSIXErrorDomain, code: Int(code)) }
        }
        var environment = self.environment ?? ProcessInfo.processInfo.environment
        environment["PATH"] = CLIDetector.searchPaths.joined(separator: ":") + ":" + (environment["PATH"] ?? "")
        let argv = ([path] + arguments).map { strdup($0) } + [nil]
        let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { argv.forEach { free($0) }; envp.forEach { free($0) } }
        lock.lock()
        defer { lock.unlock() }
        if cancelled { throw CancellationError() }
        var child: pid_t = 0
        let status = argv.withUnsafeBufferPointer { args in
            envp.withUnsafeBufferPointer { env in
                posix_spawn(&child, path, &actions, &attributes, args.baseAddress!, env.baseAddress!)
            }
        }
        guard status == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(status)) }
        pid = child
        try? input.fileHandleForReading.close()
        try? output.fileHandleForWriting.close()
        try? errorOutput.fileHandleForWriting.close()
    }

    func run() async throws -> CLIPromptResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                defer {
                    lock.lock()
                    // The leader may have exited before descendants closed inherited pipes.
                    // These groups belong only to this request, never to another app/window.
                    if pid > 0 { kill(-pid, SIGKILL) }
                    finished = true
                    lock.unlock()
                    try? output.fileHandleForReading.close()
                    try? errorOutput.fileHandleForReading.close()
                }
                do {
                    try spawn()
                    let timeout = DispatchWorkItem { [self] in
                        lock.lock()
                        guard !finished else { lock.unlock(); return }
                        timedOut = true
                        lock.unlock()
                        cancel()
                    }
                    DispatchQueue.global().asyncAfter(deadline: .now() + 300, execute: timeout)
                    defer { timeout.cancel() }
                    let stdoutFD = output.fileHandleForReading.fileDescriptor
                    let stderrFD = errorOutput.fileHandleForReading.fileDescriptor
                    _ = fcntl(stdoutFD, F_SETFL, O_NONBLOCK)
                    _ = fcntl(stderrFD, F_SETFL, O_NONBLOCK)
                    _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
                    DispatchQueue.global().async { [self] in
                        try? input.fileHandleForWriting.write(contentsOf: Data(prompt.utf8))
                        try? input.fileHandleForWriting.close()
                    }
                    var parser = CLIJSONStream()
                    var diagnostics = Data()
                    var buffer = [UInt8](repeating: 0, count: 65536)
                    var status: Int32 = 0
                    var exited = false
                    while true {
                        var descriptors = [pollfd(fd: stdoutFD, events: Int16(POLLIN), revents: 0),
                                           pollfd(fd: stderrFD, events: Int16(POLLIN), revents: 0)]
                        _ = poll(&descriptors, 2, 50)
                        var consumed = false
                        let count = Darwin.read(stdoutFD, &buffer, buffer.count)
                        if count > 0 {
                            consumed = true
                            for chunk in parser.append(Data(buffer.prefix(count))) {
                                DispatchQueue.main.async { [streamHandler] in streamHandler(chunk) }
                            }
                        }
                        // Diagnostics can contain private prompts; never log/persist raw stderr.
                        let errorCount = Darwin.read(stderrFD, &buffer, buffer.count)
                        if errorCount > 0 {
                            consumed = true
                            if diagnostics.count < 8192 { diagnostics.append(contentsOf: buffer.prefix(min(errorCount, 8192 - diagnostics.count))) }
                        }
                        if !exited { exited = waitpid(pid, &status, WNOHANG) == pid }
                        if exited && !consumed { break }
                        if !consumed { usleep(10_000) } // IO backoff, not response completion
                    }
                    parser.finish()
                    lock.lock()
                    let wasCancelled = cancelled
                    let wasTimedOut = timedOut
                    lock.unlock()
                    if wasTimedOut { throw CLIProcessManager.CLIError.timeout }
                    if wasCancelled { throw CancellationError() }
                    let exitCode: Int32 = (status & 0x7f) == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f)
                    guard exitCode == 0, !parser.failed else {
                        let diagnosticText = String(decoding: diagnostics, as: UTF8.self).lowercased()
                        if parser.authenticationFailure || CLIJSONStream.isAuthenticationFailure(diagnosticText) {
                            throw CLIProcessManager.CLIError.authentication
                        }
                        if ["unknown option", "unexpected argument", "unrecognized option"].contains(where: diagnosticText.contains) {
                            throw CLIProcessManager.CLIError.incompatibleCLI
                        }
                        throw CLIProcessManager.CLIError.failed(exitCode)
                    }
                    guard parser.completed, !parser.malformed else { throw CLIProcessManager.CLIError.invalidOutput }
                    let result = CLIPromptResult(response: parser.response, sessionId: parser.sessionId)
                    DispatchQueue.main.async { continuation.resume(returning: result) }
                } catch {
                    DispatchQueue.main.async { continuation.resume(throwing: error) }
                }
            }
        }
    }
}
