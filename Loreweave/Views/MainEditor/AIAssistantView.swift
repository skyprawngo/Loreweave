//
//  AIAssistantView.swift
//  Loreweave
//
//  AI 첨삭 요청 패널 - 라인별 첨삭 요청 UI
//

import SwiftUI

// MARK: - AI Feedback Request Model

struct AIFeedbackRequest: Identifiable {
    let id = UUID()
    let lineRange: ClosedRange<Int>
    let requestType: FeedbackType
    var status: RequestStatus
    let timestamp: Date
    var response: String?

    enum FeedbackType: String, CaseIterable {
        case refine = "refine"
        case grammar = "grammar"
        case style = "style"
        case continuity = "continuity"

        var icon: String {
            switch self {
            case .refine: return "wand.and.stars"
            case .grammar: return "textformat.abc"
            case .style: return "paintbrush"
            case .continuity: return "link"
            }
        }

        var localizedName: String {
            switch self {
            case .refine: return L10n.get("ai.feedback.refine")
            case .grammar: return L10n.get("ai.feedback.grammar")
            case .style: return L10n.get("ai.feedback.style")
            case .continuity: return L10n.get("ai.feedback.continuity")
            }
        }
    }

    enum RequestStatus {
        case pending
        case processing
        case completed
        case error
    }
}

// MARK: - AI Assistant View

struct AIAssistantView: View {
    var onToggle: (() -> Void)?

    @State private var requests: [AIFeedbackRequest] = []
    @State private var selectedType: AIFeedbackRequest.FeedbackType = .refine
    @State private var startLine: Int = 1
    @State private var endLine: Int = 1
    @State private var customPrompt: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // 헤더 (토글 버튼 포함)
            AIAssistantHeader(onToggle: onToggle)

            // 새 첨삭 요청 영역
            NewFeedbackRequestSection(
                selectedType: $selectedType,
                startLine: $startLine,
                endLine: $endLine,
                customPrompt: $customPrompt,
                onSubmit: submitRequest
            )

            // 요청 목록
            if requests.isEmpty {
                EmptyRequestsView()
            } else {
                FeedbackRequestList(requests: requests)
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppColors.separator, lineWidth: 0.5)
        )
    }

    private func submitRequest() {
        let lineRange = min(startLine, endLine)...max(startLine, endLine)
        let newRequest = AIFeedbackRequest(
            lineRange: lineRange,
            requestType: selectedType,
            status: .pending,
            timestamp: Date()
        )
        requests.insert(newRequest, at: 0)
        let requestId = newRequest.id

        // 요청 처리 시뮬레이션
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let index = requests.firstIndex(where: { $0.id == requestId }) {
                requests[index].status = .processing
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if let index = requests.firstIndex(where: { $0.id == requestId }) {
                requests[index].status = .completed
                requests[index].response = L10n.get("ai.feedback.sampleResponse")
            }
        }
    }
}

// MARK: - Header

struct AIAssistantHeader: View {
    var onToggle: (() -> Void)?

    var body: some View {
        HStack {
            Image(systemName: "pencil.and.outline")
                .foregroundStyle(Color.accentColor)
            Text(L10n.get("ai.feedback.title"))
                .font(.headline)

            Spacer()

            // 패널 닫기 버튼
            if let onToggle = onToggle {
                Button(action: onToggle) {
                    Image(systemName: "sidebar.trailing")
                        .font(.system(size: 14))
                        .foregroundStyle(AppColors.toolbarIcon)
                }
                .buttonStyle(.plain)
                .help(L10n.ai.togglePanel)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - New Feedback Request Section

struct NewFeedbackRequestSection: View {
    @Binding var selectedType: AIFeedbackRequest.FeedbackType
    @Binding var startLine: Int
    @Binding var endLine: Int
    @Binding var customPrompt: String
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 라인 범위 선택
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.get("ai.feedback.lineRange"))
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary)

                    HStack(spacing: 8) {
                        TextField("", value: $startLine, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)

                        Text("~")
                            .foregroundStyle(AppColors.textSecondary)

                        TextField("", value: $endLine, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)

                        Text(L10n.get("ai.feedback.line"))
                            .font(.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }

                Spacer()
            }

            // 첨삭 유형 선택
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.get("ai.feedback.type"))
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)

                HStack(spacing: 8) {
                    ForEach(AIFeedbackRequest.FeedbackType.allCases, id: \.self) { type in
                        FeedbackTypeButton(
                            type: type,
                            isSelected: selectedType == type,
                            action: { selectedType = type }
                        )
                    }
                }
            }

            // 추가 지시사항
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.get("ai.feedback.additionalPrompt"))
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)

                TextField(L10n.get("ai.feedback.promptPlaceholder"), text: $customPrompt, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
            }

            // 요청 버튼
            Button(action: onSubmit) {
                Label(L10n.get("ai.feedback.request"), systemImage: "paperplane.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.accentColor)
        }
        .padding(16)
    }
}

// MARK: - Feedback Type Button

struct FeedbackTypeButton: View {
    let type: AIFeedbackRequest.FeedbackType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: type.icon)
                    .font(.system(size: 16))
                Text(type.localizedName)
                    .font(.system(size: 10))
            }
            .frame(width: 60, height: 50)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? AppColors.accent.opacity(0.15) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? AppColors.accent : AppColors.controlBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? AppColors.accent : AppColors.textSecondary)
    }
}

// MARK: - Empty Requests View

struct EmptyRequestsView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.bubble")
                .font(.system(size: 40))
                .foregroundStyle(AppColors.toolbarIcon)

            Text(L10n.get("ai.feedback.empty"))
                .font(.subheadline)
                .foregroundStyle(AppColors.textSecondary)

            Text(L10n.get("ai.feedback.emptyDescription"))
                .font(.caption)
                .foregroundStyle(AppColors.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Feedback Request List

struct FeedbackRequestList: View {
    let requests: [AIFeedbackRequest]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(requests) { request in
                    FeedbackRequestCard(request: request)
                }
            }
            .padding(16)
        }
    }
}

// MARK: - Feedback Request Card

struct FeedbackRequestCard: View {
    let request: AIFeedbackRequest
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 헤더
            HStack {
                Image(systemName: request.requestType.icon)
                    .foregroundStyle(Color.accentColor)

                Text(request.requestType.localizedName)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                // 라인 범위
                Text(lineRangeText)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(AppColors.accent.opacity(0.1))
                    )
                    .foregroundStyle(AppColors.accent)

                // 상태 표시
                statusIcon
            }

            // 응답 내용
            if let response = request.response {
                Divider()

                Button {
                    withAnimation {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack {
                        Text(isExpanded ? response : String(response.prefix(100)) + (response.count > 100 ? "..." : ""))
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)

                        Spacer()

                        if response.count > 100 {
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption)
                                .foregroundStyle(AppColors.toolbarIcon)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            // 시간
            Text(request.timestamp, style: .time)
                .font(.caption2)
                .foregroundStyle(AppColors.textTertiary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(AppColors.controlBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppColors.controlBorder, lineWidth: 1)
        )
    }

    private var lineRangeText: String {
        if request.lineRange.lowerBound == request.lineRange.upperBound {
            return L10n.get("ai.feedback.line") + " \(request.lineRange.lowerBound)"
        } else {
            return L10n.get("ai.feedback.lines") + " \(request.lineRange.lowerBound)-\(request.lineRange.upperBound)"
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch request.status {
        case .pending:
            Image(systemName: "clock")
                .foregroundStyle(.orange)
        case .processing:
            ProgressView()
                .scaleEffect(0.7)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }
}

#Preview {
    AIAssistantView(onToggle: {})
        .frame(width: 350, height: 600)
}
