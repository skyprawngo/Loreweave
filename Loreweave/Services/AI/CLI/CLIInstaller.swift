//
//  CLIInstaller.swift
//  Loreweave
//
//  AI CLI 설치 지원 서비스
//

import Foundation
import AppKit

/// CLI 설치 결과
enum CLIInstallResult {
    case success
    case failed(String)
    case cancelled
    case requiresManualInstall(URL?)
}

/// CLI 설치 서비스
final class CLIInstaller {
    static let shared = CLIInstaller()

    private var installProcess: Process?

    private init() {}

    /// CLI 설치 시도
    func install(_ cliType: AICLIType, progressHandler: @escaping (String) -> Void) async -> CLIInstallResult {
        // 설치 스크립트가 있는 경우
        guard let installScript = cliType.installScript else {
            // 설치 스크립트가 없으면 수동 설치 안내
            return .requiresManualInstall(cliType.installPageURL)
        }

        // Claude CLI의 경우 npm이 필요
        if cliType == .claude {
            let isNpmInstalled = await CLIDetector.shared.isNpmInstalled()
            if !isNpmInstalled {
                progressHandler(L10n.get("ai.install.npmRequired"))
                return .requiresManualInstall(URL(string: "https://nodejs.org/"))
            }
        }

        return await executeInstallScript(installScript, progressHandler: progressHandler)
    }

    /// 설치 스크립트 실행
    private func executeInstallScript(_ script: String, progressHandler: @escaping (String) -> Void) async -> CLIInstallResult {
        await withCheckedContinuation { continuation in
            let process = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", script]
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            // 환경 변수 설정 (PATH 포함)
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:" + (environment["PATH"] ?? "")
            process.environment = environment

            self.installProcess = process

            // 출력 스트리밍
            outputPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                    DispatchQueue.main.async {
                        progressHandler(output)
                    }
                }
            }

            errorPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                    DispatchQueue.main.async {
                        progressHandler(output)
                    }
                }
            }

            do {
                try process.run()
                process.waitUntilExit()

                // 핸들러 정리
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil

                if process.terminationStatus == 0 {
                    continuation.resume(returning: .success)
                } else {
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                    continuation.resume(returning: .failed(errorMessage))
                }
            } catch {
                continuation.resume(returning: .failed(error.localizedDescription))
            }

            self.installProcess = nil
        }
    }

    /// 설치 취소
    func cancelInstallation() {
        installProcess?.terminate()
        installProcess = nil
    }

    /// 설치 페이지 열기
    func openInstallPage(for cliType: AICLIType) {
        guard let url = cliType.installPageURL else { return }
        NSWorkspace.shared.open(url)
    }

    /// Node.js 설치 페이지 열기
    func openNodeJSInstallPage() {
        if let url = URL(string: "https://nodejs.org/") {
            NSWorkspace.shared.open(url)
        }
    }
}
