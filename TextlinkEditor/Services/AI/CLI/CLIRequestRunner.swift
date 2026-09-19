import Foundation
import Darwin

/// Process and cancellation flags are protected by a lock. Blocking IO never runs on MainActor.
final class CLIRequestRunner: @unchecked Sendable {
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
                    let result = CLIPromptResult(response: parser.response, sessionId: parser.sessionId, usage: parser.usage)
                    DispatchQueue.main.async { continuation.resume(returning: result) }
                } catch {
                    DispatchQueue.main.async { continuation.resume(throwing: error) }
                }
            }
        }
    }
}
