//
//  CLIInstallGuideView.swift
//  Loreweave
//
//  CLI 미설치 시 설치 안내 뷰
//

import SwiftUI

struct CLIInstallGuideView: View {
    let cliType: AICLIType
    let installStatus: CLIInstallationStatus
    let onInstall: () -> Void
    let onOpenInstallPage: () -> Void
    let onRetryCheck: () -> Void
    let onCancel: () -> Void

    @State private var installProgress: String = ""
    @State private var isInstalling = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // 아이콘
            Image(systemName: statusIcon)
                .font(.system(size: 40))
                .foregroundStyle(statusColor)

            // 제목
            Text(statusTitle)
                .font(.headline)
                .foregroundStyle(AppColors.textPrimary)

            // 설명
            Text(statusDescription)
                .font(.subheadline)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            // 설치 진행 상태 (설치 중일 때만)
            if isInstalling {
                VStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)

                    if !installProgress.isEmpty {
                        ScrollView {
                            Text(installProgress)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(AppColors.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 100)
                        .padding(8)
                        .background(AppColors.controlBackground)
                        .cornerRadius(6)
                    }
                }
                .padding(.horizontal, 16)
            }

            // 버튼
            if !isInstalling {
                actionButtons
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var actionButtons: some View {
        VStack(spacing: 12) {
            // 설치 스크립트가 있으면 자동 설치 버튼
            if cliType.installScript != nil {
                Button(action: {
                    isInstalling = true
                    onInstall()
                }) {
                    Label(L10n.get("ai.install.auto"), systemImage: "arrow.down.circle")
                        .frame(minWidth: 200)
                }
                .buttonStyle(.borderedProminent)
            }

            // 수동 설치 페이지 열기
            Button(action: onOpenInstallPage) {
                Label(L10n.get("ai.install.openPage"), systemImage: "safari")
                    .frame(minWidth: 200)
            }
            .buttonStyle(.bordered)

            // 재확인 버튼
            Button(action: onRetryCheck) {
                Label(L10n.get("ai.install.recheck"), systemImage: "arrow.clockwise")
                    .frame(minWidth: 200)
            }
            .buttonStyle(.bordered)

            // 취소 버튼
            Button(action: onCancel) {
                Text(L10n.get("common.cancel"))
                    .frame(minWidth: 200)
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppColors.textSecondary)
        }
    }

    private var statusIcon: String {
        switch installStatus {
        case .checking:
            return "magnifyingglass"
        case .notInstalled:
            return "exclamationmark.triangle"
        case .installationFailed:
            return "xmark.circle"
        default:
            return "questionmark.circle"
        }
    }

    private var statusColor: Color {
        switch installStatus {
        case .checking:
            return AppColors.accent
        case .notInstalled:
            return .orange
        case .installationFailed:
            return .red
        default:
            return AppColors.textSecondary
        }
    }

    private var statusTitle: String {
        switch installStatus {
        case .checking:
            return L10n.get("ai.install.checking")
        case .notInstalled:
            return L10n.get("ai.install.notInstalled").replacingOccurrences(of: "{cli}", with: cliType.displayName)
        case .installationFailed(let error):
            return L10n.get("ai.install.failed")
        default:
            return ""
        }
    }

    private var statusDescription: String {
        switch installStatus {
        case .checking:
            return L10n.get("ai.install.checkingDescription")
        case .notInstalled:
            return L10n.get("ai.install.notInstalledDescription").replacingOccurrences(of: "{cli}", with: cliType.displayName)
        case .installationFailed(let error):
            return error
        default:
            return ""
        }
    }
}

#Preview {
    CLIInstallGuideView(
        cliType: .claude,
        installStatus: .notInstalled,
        onInstall: {},
        onOpenInstallPage: {},
        onRetryCheck: {},
        onCancel: {}
    )
    .frame(width: 320, height: 500)
}
