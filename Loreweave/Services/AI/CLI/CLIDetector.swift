//
//  CLIDetector.swift
//  Loreweave
//
//  AI CLI 설치 감지 서비스
//

import Foundation

/// CLI 설치 감지 서비스
final class CLIDetector {
    static let shared = CLIDetector()

    private init() {}

    /// CLI 설치 여부 확인 (which 명령어 사용)
    func checkInstallation(for cliType: AICLIType) async -> CLIInstallationStatus {
        // 1. which 명령어로 PATH에서 찾기
        if let path = await findCLIInPath(cliType.commandName) {
            return .installed(path: path)
        }

        // 2. 일반적인 설치 경로 직접 확인
        for possiblePath in cliType.possiblePaths {
            let expandedPath = NSString(string: possiblePath).expandingTildeInPath
            if FileManager.default.fileExists(atPath: expandedPath) {
                return .installed(path: expandedPath)
            }
        }

        return .notInstalled
    }

    /// PATH에서 CLI 찾기
    private func findCLIInPath(_ commandName: String) async -> String? {
        await withCheckedContinuation { continuation in
            let process = Process()
            let pipe = Pipe()

            process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
            process.arguments = [commandName]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                process.waitUntilExit()

                if process.terminationStatus == 0 {
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !output.isEmpty {
                        continuation.resume(returning: output)
                        return
                    }
                }
            } catch {
                print("CLIDetector: which 명령 실행 실패 - \(error)")
            }

            continuation.resume(returning: nil)
        }
    }

    /// CLI 버전 확인
    func getVersion(for cliType: AICLIType) async -> String? {
        await withCheckedContinuation { continuation in
            let process = Process()
            let pipe = Pipe()

            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [cliType.commandName, "--version"]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                process.waitUntilExit()

                if process.terminationStatus == 0 {
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !output.isEmpty {
                        continuation.resume(returning: output)
                        return
                    }
                }
            } catch {
                print("CLIDetector: 버전 확인 실패 - \(error)")
            }

            continuation.resume(returning: nil)
        }
    }

    /// npm 설치 여부 확인 (Claude CLI 설치에 필요)
    func isNpmInstalled() async -> Bool {
        await findCLIInPath("npm") != nil
    }

    /// Node.js 설치 여부 확인
    func isNodeInstalled() async -> Bool {
        await findCLIInPath("node") != nil
    }
}
