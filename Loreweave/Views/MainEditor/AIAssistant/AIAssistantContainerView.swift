//
//  AIAssistantContainerView.swift
//  Loreweave
//
//  AI 어시스턴트 메인 컨테이너 - 상태별 뷰 분기
//

import SwiftUI

struct AIAssistantContainerView: View {
    @State private var viewModel = AIAssistantViewModel()
    @State private var aiAssistantEnabled = UserSettings.shared.aiAssistantEnabled

    var projectFolderURL: URL?
    /// 상세 뷰 모드 여부 바인딩 (외부에서 관찰 및 수정 가능)
    @Binding var isInDetailView: Bool

    var body: some View {
        VStack(spacing: 0) {
            if let error = viewModel.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled).padding(12)
            }
            if !aiAssistantEnabled {
                AIInactiveView {
                    viewModel.startConnection()
                    aiAssistantEnabled = true
                }
            } else {
                connectionStateView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { viewModel.setProject(projectFolderURL) }
        .onDisappear { viewModel.cancelSend() }
        .onChange(of: projectFolderURL) { _, newValue in viewModel.setProject(newValue) }
        .onChange(of: viewModel.selectedCardId) { _, newValue in
            // 내부 상태 변경 → 외부로 전파
            let newIsInDetailView = newValue != nil
            if isInDetailView != newIsInDetailView {
                isInDetailView = newIsInDetailView
            }
        }
        .onChange(of: isInDetailView) { _, newValue in
            // 외부에서 false로 변경 시 → 내부 상태도 초기화 (뒤로가기 동작)
            if !newValue && viewModel.selectedCardId != nil {
                withAnimation(.easeInOut(duration: 0.25)) {
                    viewModel.selectedCardId = nil
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("aiDraftAction"))) { notification in
            guard let instruction = notification.object as? String else { return }
            viewModel.prepareDraftAction(instruction)
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            syncWithUserSettings()
        }
    }

    // MARK: - Connection State View

    @ViewBuilder
    private var connectionStateView: some View {
        switch viewModel.connectionState {
        case .inactive:
            AIInactiveView(onConnectTapped: viewModel.startConnection)

        case .selectingAI:
            AISetupView(
                selectedCLIType: $viewModel.selectedCLIType,
                onConfirm: viewModel.confirmAISelection,
                onCancel: viewModel.cancelSetup
            )

        case .checkingCLI(let cliType):
            cliInstallGuide(for: cliType, status: .checking)

        case .cliNotInstalled(let cliType), .installingCLI(let cliType):
            cliInstallGuide(for: cliType, status: viewModel.installStatus)

        case .ready(let cliType), .connected(let cliType):
            chatView(for: cliType)

        case .error(let message):
            errorView(message)
        }
    }

    // MARK: - Subviews

    private func cliInstallGuide(for cliType: AICLIType, status: CLIInstallationStatus) -> some View {
        CLIInstallGuideView(
            cliType: cliType,
            installStatus: status,
            onOpenInstallPage: viewModel.openInstallPage,
            onRetryCheck: { viewModel.checkCLIInstallation(cliType) },
            onSelectCLIPath: viewModel.selectCLIPath,
            onCancel: viewModel.cancelSetup
        )
    }

    private func chatView(for cliType: AICLIType) -> some View {
        AIChatView(
            cliType: cliType,
            messages: $viewModel.messages,
            inputText: $viewModel.inputText,
            includeCurrentDocument: $viewModel.includeCurrentDocument,
            taggedCardIds: $viewModel.taggedCardIds,
            selectionState: $viewModel.selectionState,
            selectedCardId: $viewModel.selectedCardId,
            isProcessing: viewModel.isProcessing,
            onSend: { cardId in viewModel.sendMessage(continueFromCardId: cardId) },
            onCancel: viewModel.cancelSend,
            onClearHistory: viewModel.clearHistory,
            onChangeAI: viewModel.changeAI,
            onDisconnect: viewModel.disconnect,
            onDeleteCard: viewModel.deleteCard,
            onTagChanged: viewModel.saveTaggedCards,
            onSelectionResponse: viewModel.sendSelectionResponse,
            projectFolderURL: projectFolderURL,
            onPreviewDocument: viewModel.currentDocumentSnapshot
        )
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.red)

            Text(L10n.get("ai.error.title"))
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            Button(L10n.get("common.retry"), action: viewModel.cancelSetup)
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Sync

    private func syncWithUserSettings() {
        let newEnabled = UserSettings.shared.aiAssistantEnabled
        if aiAssistantEnabled != newEnabled || viewModel.selectedCLIType?.rawValue != UserSettings.shared.aiAssistantCLIType {
            aiAssistantEnabled = newEnabled
            viewModel.loadSavedState()
        }
    }
}

#Preview {
    AIAssistantContainerView(isInDetailView: .constant(false))
        .frame(width: 350, height: 600)
}
