//
//  CLIProcessManager.swift
//  Loreweave
//
//  AI CLI 프로세스 관리
//

import Foundation

/// CLI 프로세스 관리자
@Observable
final class CLIProcessManager {
    static let shared = CLIProcessManager()

    private var activeProcess: Process?
    private var outputPipe: Pipe?
    private var inputPipe: Pipe?

    /// 현재 실행 중인 CLI 타입
    private(set) var activeCLIType: AICLIType?

    /// 프로세스 실행 중 여부
    var isRunning: Bool {
        activeProcess?.isRunning ?? false
    }

    private init() {}

    /// CLI 프로세스 시작 (대화형 모드)
    func startSession(
        cliType: AICLIType,
        workingDirectory: URL?,
        outputHandler: @escaping (String) -> Void
    ) async throws {
        // 기존 프로세스가 있으면 종료
        await stopSession()

        let process = Process()
        let outputPipe = Pipe()
        let inputPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [cliType.commandName]
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        process.standardInput = inputPipe

        // 작업 디렉토리 설정
        if let workingDirectory {
            process.currentDirectoryURL = workingDirectory
        }

        // 환경 변수 설정
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:" + (environment["PATH"] ?? "")
        process.environment = environment

        // 출력 핸들러 설정
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty, let output = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    outputHandler(output)
                }
            }
        }

        self.activeProcess = process
        self.outputPipe = outputPipe
        self.inputPipe = inputPipe
        self.activeCLIType = cliType

        try process.run()
    }

    /// 메시지 전송
    func sendMessage(_ message: String) {
        guard let inputPipe, isRunning else { return }

        let messageWithNewline = message + "\n"
        if let data = messageWithNewline.data(using: .utf8) {
            inputPipe.fileHandleForWriting.write(data)
        }
    }

    /// 세션 종료
    func stopSession() async {
        outputPipe?.fileHandleForReading.readabilityHandler = nil

        if let process = activeProcess, process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }

        activeProcess = nil
        outputPipe = nil
        inputPipe = nil
        activeCLIType = nil
    }

    /// 단일 명령 실행 (비대화형)
    func executeCommand(
        cliType: AICLIType,
        arguments: [String],
        workingDirectory: URL?
    ) async throws -> String {
        let process = Process()
        let outputPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [cliType.commandName] + arguments
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        if let workingDirectory {
            process.currentDirectoryURL = workingDirectory
        }

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:" + (environment["PATH"] ?? "")
        process.environment = environment

        try process.run()
        process.waitUntilExit()

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// 프롬프트 전송 및 응답 수신 (스트리밍)
    func sendPrompt(
        _ prompt: String,
        cliType: AICLIType,
        workingDirectory: URL?,
        streamHandler: @escaping (String) -> Void
    ) async throws -> String {
        let process = Process()
        let outputPipe = Pipe()
        let inputPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")

        // Claude CLI는 프롬프트를 인자로 받음
        switch cliType {
        case .claude:
            process.arguments = [cliType.commandName, "-p", prompt]
        case .chatgpt:
            process.arguments = [cliType.commandName, prompt]
        }

        process.standardOutput = outputPipe
        process.standardError = outputPipe
        process.standardInput = inputPipe

        if let workingDirectory {
            process.currentDirectoryURL = workingDirectory
        }

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:" + (environment["PATH"] ?? "")
        process.environment = environment

        var fullOutput = ""

        // 스트리밍 출력 핸들러
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty, let output = String(data: data, encoding: .utf8) {
                fullOutput += output
                DispatchQueue.main.async {
                    streamHandler(output)
                }
            }
        }

        try process.run()

        // 비동기로 프로세스 완료 대기
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async {
                process.waitUntilExit()
                outputPipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume()
            }
        }

        return fullOutput
    }
}
