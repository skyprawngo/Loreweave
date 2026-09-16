//
//  CLIInstaller.swift
//  TextlinkEditor
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

    private init() {}

    /// 설치 페이지 열기 (설치 문서 페이지로 이동)
    func openInstallPage(for cliType: AICLIType) {
        guard let url = cliType.setupDocsURL ?? cliType.installPageURL else { return }
        NSWorkspace.shared.open(url)
    }
}
