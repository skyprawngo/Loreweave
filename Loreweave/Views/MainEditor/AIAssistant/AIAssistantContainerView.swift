//
//  AIAssistantContainerView.swift
//  Loreweave
//
//  AI 어시스턴트 메인 컨테이너 - 상태별 뷰 분기
//

import SwiftUI

@Observable
final class AIAssistantViewModel {
    var connectionState: AIConnectionState = .inactive
    var selectedCLIType: AICLIType?
    var installStatus: CLIInstallationStatus = .unknown
    var messages: [AIMessage] = []
    var inputText: String = ""
    var isProcessing: Bool = false
    var chatSession: AIChatSession?

    private var projectFolderURL: URL?

    init() {
        loadSavedState()
    }

    /// 저장된 상태 로드
    func loadSavedState() {
        let settings = UserSettings.shared
        if settings.aiAssistantEnabled,
           let cliTypeRaw = AICLIType(rawValue: settings.aiAssistantCLIType) {
            selectedCLIType = cliTypeRaw
            connectionState = .connected(cliTypeRaw)
        }
    }

    /// 프로젝트 설정
    func setProject(_ projectURL: URL?) {
        self.projectFolderURL = projectURL

        // 프로젝트가 있고 연결된 상태면 히스토리 로드
        if let url = projectURL,
           case .connected(let cliType) = connectionState {
            loadChatHistory(cliType: cliType, projectURL: url)
        }
    }

    /// 채팅 히스토리 로드
    private func loadChatHistory(cliType: AICLIType, projectURL: URL) {
        if let session = ChatHistoryManager.shared.loadSession(from: projectURL) {
            chatSession = session
            messages = session.messages
        } else {
            // 새 세션 생성
            chatSession = AIChatSession(
                projectPath: projectURL.path,
                cliType: cliType.rawValue
            )
            messages = []
        }
    }

    /// 연결 시작
    func startConnection() {
        connectionState = .selectingAI
    }

    /// AI 선택 확인
    func confirmAISelection(_ cliType: AICLIType) {
        selectedCLIType = cliType
        connectionState = .checkingCLI(cliType)
        checkCLIInstallation(cliType)
    }

    /// CLI 설치 확인
    func checkCLIInstallation(_ cliType: AICLIType) {
        installStatus = .checking
        Task {
            let status = await CLIDetector.shared.checkInstallation(for: cliType)
            await MainActor.run {
                installStatus = status
                switch status {
                case .installed:
                    completeConnection(cliType)
                case .notInstalled:
                    connectionState = .cliNotInstalled(cliType)
                default:
                    break
                }
            }
        }
    }

    /// 연결 완료
    func completeConnection(_ cliType: AICLIType) {
        // 설정 저장
        UserSettings.shared.aiAssistantEnabled = true
        UserSettings.shared.aiAssistantCLIType = cliType.rawValue

        connectionState = .connected(cliType)

        // 프로젝트가 있으면 히스토리 로드
        if let url = projectFolderURL {
            loadChatHistory(cliType: cliType, projectURL: url)
        }
    }

    /// 연결 해제
    func disconnect() {
        Task {
            await CLIProcessManager.shared.stopSession()
        }

        UserSettings.shared.aiAssistantEnabled = false
        UserSettings.shared.aiAssistantCLIType = ""

        connectionState = .inactive
        selectedCLIType = nil
        messages = []
        chatSession = nil
    }

    /// 취소
    func cancelSetup() {
        connectionState = .inactive
        selectedCLIType = nil
        installStatus = .unknown
    }

    /// 메시지 전송
    func sendMessage() {
        guard !inputText.isEmpty,
              case .connected(let cliType) = connectionState else { return }

        let userMessage = AIMessage(role: .user, content: inputText)
        messages.append(userMessage)

        // 세션에 저장
        if var session = chatSession, let url = projectFolderURL {
            ChatHistoryManager.shared.appendMessage(userMessage, to: &session, projectFolderURL: url)
            chatSession = session
        }

        let prompt = inputText
        inputText = ""
        isProcessing = true

        // AI 응답 placeholder 추가
        let assistantMessage = AIMessage(role: .assistant, content: "", isStreaming: true)
        messages.append(assistantMessage)
        let assistantMessageId = assistantMessage.id

        Task {
            do {
                var fullResponse = ""
                let response = try await CLIProcessManager.shared.sendPrompt(
                    prompt,
                    cliType: cliType,
                    workingDirectory: projectFolderURL
                ) { chunk in
                    fullResponse += chunk
                    // 스트리밍 업데이트
                    Task { @MainActor in
                        if let index = self.messages.firstIndex(where: { $0.id == assistantMessageId }) {
                            self.messages[index] = AIMessage(
                                id: assistantMessageId,
                                role: .assistant,
                                content: fullResponse,
                                timestamp: self.messages[index].timestamp,
                                isStreaming: true
                            )
                        }
                    }
                }

                await MainActor.run {
                    // 최종 응답으로 업데이트
                    if let index = messages.firstIndex(where: { $0.id == assistantMessageId }) {
                        messages[index] = AIMessage(
                            id: assistantMessageId,
                            role: .assistant,
                            content: response,
                            timestamp: messages[index].timestamp,
                            isStreaming: false
                        )

                        // 세션에 저장
                        if var session = chatSession, let url = projectFolderURL {
                            ChatHistoryManager.shared.updateLastMessage(
                                content: response,
                                in: &session,
                                projectFolderURL: url
                            )
                            chatSession = session
                        }
                    }
                    isProcessing = false
                }
            } catch {
                await MainActor.run {
                    // 에러 메시지로 업데이트
                    if let index = messages.firstIndex(where: { $0.id == assistantMessageId }) {
                        messages[index] = AIMessage(
                            id: assistantMessageId,
                            role: .assistant,
                            content: "Error: \(error.localizedDescription)",
                            timestamp: messages[index].timestamp,
                            isStreaming: false
                        )
                    }
                    isProcessing = false
                }
            }
        }
    }

    /// 전송 취소
    func cancelSend() {
        Task {
            await CLIProcessManager.shared.stopSession()
            await MainActor.run {
                isProcessing = false
                // 마지막 스트리밍 메시지 제거
                if let last = messages.last, last.isStreaming {
                    messages.removeLast()
                }
            }
        }
    }

    /// 히스토리 삭제
    func clearHistory() {
        messages = []
        if var session = chatSession, let url = projectFolderURL {
            ChatHistoryManager.shared.clearHistory(in: &session, projectFolderURL: url)
            chatSession = session
        }
    }

    /// CLI 설치
    func installCLI() {
        guard let cliType = selectedCLIType else { return }
        connectionState = .installingCLI(cliType)

        Task {
            let result = await CLIInstaller.shared.install(cliType) { progress in
                // 진행 상황 처리 (필요시 UI 업데이트)
                print("Install progress: \(progress)")
            }

            await MainActor.run {
                switch result {
                case .success:
                    completeConnection(cliType)
                case .failed(let error):
                    installStatus = .installationFailed(error)
                    connectionState = .cliNotInstalled(cliType)
                case .requiresManualInstall:
                    CLIInstaller.shared.openInstallPage(for: cliType)
                    connectionState = .cliNotInstalled(cliType)
                case .cancelled:
                    connectionState = .cliNotInstalled(cliType)
                }
            }
        }
    }

    /// 설치 페이지 열기
    func openInstallPage() {
        guard let cliType = selectedCLIType else { return }
        CLIInstaller.shared.openInstallPage(for: cliType)
    }
}

struct AIAssistantContainerView: View {
    @State private var viewModel = AIAssistantViewModel()
    var projectFolderURL: URL?

    var body: some View {
        Group {
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
                CLIInstallGuideView(
                    cliType: cliType,
                    installStatus: .checking,
                    onInstall: viewModel.installCLI,
                    onOpenInstallPage: viewModel.openInstallPage,
                    onRetryCheck: { viewModel.checkCLIInstallation(cliType) },
                    onCancel: viewModel.cancelSetup
                )

            case .cliNotInstalled(let cliType):
                CLIInstallGuideView(
                    cliType: cliType,
                    installStatus: viewModel.installStatus,
                    onInstall: viewModel.installCLI,
                    onOpenInstallPage: viewModel.openInstallPage,
                    onRetryCheck: { viewModel.checkCLIInstallation(cliType) },
                    onCancel: viewModel.cancelSetup
                )

            case .installingCLI(let cliType):
                CLIInstallGuideView(
                    cliType: cliType,
                    installStatus: .checking,
                    onInstall: {},
                    onOpenInstallPage: {},
                    onRetryCheck: {},
                    onCancel: viewModel.cancelSetup
                )

            case .ready(let cliType), .connected(let cliType):
                AIChatView(
                    cliType: cliType,
                    messages: $viewModel.messages,
                    inputText: $viewModel.inputText,
                    isProcessing: viewModel.isProcessing,
                    onSend: viewModel.sendMessage,
                    onCancel: viewModel.cancelSend,
                    onClearHistory: viewModel.clearHistory,
                    onDisconnect: viewModel.disconnect
                )

            case .error(let message):
                errorView(message)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            viewModel.setProject(projectFolderURL)
        }
        .onChange(of: projectFolderURL) { _, newValue in
            viewModel.setProject(newValue)
        }
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

            Button(action: viewModel.cancelSetup) {
                Text(L10n.get("common.retry"))
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

#Preview {
    AIAssistantContainerView()
        .frame(width: 350, height: 600)
}
