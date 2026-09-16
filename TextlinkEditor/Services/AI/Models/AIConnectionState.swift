//
//  AIConnectionState.swift
//  TextlinkEditor
//
//  AI 연결 상태 모델
//

import Foundation

/// AI 어시스턴트 연결 상태
enum AIConnectionState: Equatable {
    /// 비활성화 상태 (초기 상태)
    case inactive

    /// AI 선택 단계
    case selectingAI

    /// CLI 설치 확인 중
    case checkingCLI(AICLIType)

    /// CLI 미설치 - 설치 안내
    case cliNotInstalled(AICLIType)

    /// CLI 설치 중
    case installingCLI(AICLIType)

    /// 연결 준비 완료
    case ready(AICLIType)

    /// 연결됨 (채팅 가능)
    case connected(AICLIType)

    /// 오류 상태
    case error(String)

    /// 현재 선택된 CLI 타입
    var selectedCLIType: AICLIType? {
        switch self {
        case .inactive, .selectingAI:
            return nil
        case .checkingCLI(let type),
             .cliNotInstalled(let type),
             .installingCLI(let type),
             .ready(let type),
             .connected(let type):
            return type
        case .error:
            return nil
        }
    }

    /// 채팅 가능 여부
    var canChat: Bool {
        switch self {
        case .connected:
            return true
        default:
            return false
        }
    }

    /// 로딩 중 여부
    var isLoading: Bool {
        switch self {
        case .checkingCLI, .installingCLI:
            return true
        default:
            return false
        }
    }
}

/// CLI 설치 상태
enum CLIInstallationStatus: Equatable {
    case unknown
    case checking
    case installed(path: String)
    case notInstalled
    case installationFailed(String)
}
