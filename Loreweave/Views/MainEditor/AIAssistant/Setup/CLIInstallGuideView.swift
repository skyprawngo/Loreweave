//
//  CLIInstallGuideView.swift
//  Loreweave
//
//  CLI 미설치 시 설치 안내 뷰
//

import SwiftUI
import AppKit

struct CLIInstallGuideView: View {
    let cliType: AICLIType
    let installStatus: CLIInstallationStatus
    let onOpenInstallPage: () -> Void
    let onRetryCheck: () -> Void
    let onSelectCLIPath: (URL) -> Void
    let onCancel: () -> Void

    @State private var showingFilePicker = false
    @State private var showCopiedFeedback = false

    /// CLI 기본 설치 경로
    private var defaultCLIPath: String {
        cliType.possiblePaths.first ?? "~/.local/bin/\(cliType.commandName)"
    }

    var body: some View {
        VStack(spacing: 0) {
            // 헤더
            HStack {
                Image(cliType.iconImageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .foregroundStyle(AppColors.accent)
                Text(cliType.displayName)
                    .font(.headline)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // 콘텐츠
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

                // 버튼
                actionButtons

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.unixExecutable, .item],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    onSelectCLIPath(url)
                }
            case .failure(let error):
                print("File picker error: \(error)")
            }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        VStack(spacing: 12) {
            // 다시 확인 버튼 (설치 후 확인용)
            Button(action: onRetryCheck) {
                Label(L10n.get("ai.install.retryCheck"), systemImage: "arrow.clockwise")
                    .frame(minWidth: 200)
            }
            .buttonStyle(.borderedProminent)

            // CLI 파일 직접 선택
            Button(action: { showingFilePicker = true }) {
                Label(L10n.get("ai.install.selectCLI"), systemImage: "folder")
                    .frame(minWidth: 200)
            }
            .buttonStyle(.bordered)

            // 경로 복사 버튼
            Button(action: copyPathToClipboard) {
                Label(
                    showCopiedFeedback ? L10n.get("ai.install.pathCopied") : L10n.get("ai.install.copyPath"),
                    systemImage: showCopiedFeedback ? "checkmark" : "doc.on.doc"
                )
                .frame(minWidth: 200)
            }
            .buttonStyle(.bordered)

            // 설치 페이지 열기
            Button(action: onOpenInstallPage) {
                Label(L10n.get("ai.install.openPage"), systemImage: "safari")
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

    private func copyPathToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(defaultCLIPath, forType: .string)

        showCopiedFeedback = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showCopiedFeedback = false
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
        case .installationFailed:
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
        onOpenInstallPage: {},
        onRetryCheck: {},
        onSelectCLIPath: { _ in },
        onCancel: {}
    )
    .frame(width: 320, height: 500)
}
