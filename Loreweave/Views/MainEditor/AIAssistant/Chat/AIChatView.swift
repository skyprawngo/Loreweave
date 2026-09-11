//
//  AIChatView.swift
//  Loreweave
//
//  AI 채팅 메인 뷰 - VSCode 스타일 레이아웃
//  상단: 대화 카드 영역
//  하단: 컨텍스트 정보 + 입력 영역
//

import SwiftUI
import AppKit

// MARK: - 대화 카드 모델

/// 사용자 질문 + AI 답변을 하나의 카드로 묶는 모델
/// - 세션 뷰 (카드 목록): 각 카드는 독립적인 대화 세션을 나타냄
/// - 채팅 뷰 (카드 내부): 해당 카드의 세션 ID를 사용하여 대화 계속
struct ConversationCard: Identifiable, Equatable {
    let id: UUID
    let userMessage: AIMessage
    var assistantMessage: AIMessage?
    var isTaggedForContext: Bool = false
    /// CLI 세션 ID (카드별 대화 연속성 유지용)
    var cliSessionId: String?

    init(userMessage: AIMessage, assistantMessage: AIMessage? = nil, cliSessionId: String? = nil) {
        self.id = userMessage.conversationId ?? userMessage.id
        self.userMessage = userMessage
        self.assistantMessage = assistantMessage
        self.cliSessionId = cliSessionId
    }

    var isStreaming: Bool {
        assistantMessage?.isStreaming ?? false
    }

    static func == (lhs: ConversationCard, rhs: ConversationCard) -> Bool {
        lhs.id == rhs.id &&
        lhs.assistantMessage?.content == rhs.assistantMessage?.content &&
        lhs.isTaggedForContext == rhs.isTaggedForContext &&
        lhs.cliSessionId == rhs.cliSessionId
    }
}

// MARK: - 다중 줄 입력 뷰

/// 다중 줄 입력을 지원하는 텍스트 입력 뷰 (Shift+Enter로 줄바꿈, Enter로 전송)
/// 텍스트 내용에 따라 높이가 자동으로 확장됩니다 (minHeight ~ maxHeight)
struct MultiLineInputView: NSViewRepresentable {
    @Binding var text: String
    @Binding var contentHeight: CGFloat
    let placeholder: String
    let isDisabled: Bool
    let minHeight: CGFloat
    let maxHeight: CGFloat
    let onSubmit: () -> Void

    init(
        text: Binding<String>,
        contentHeight: Binding<CGFloat>,
        placeholder: String,
        isDisabled: Bool,
        minHeight: CGFloat = 32,
        maxHeight: CGFloat = 120,
        onSubmit: @escaping () -> Void
    ) {
        self._text = text
        self._contentHeight = contentHeight
        self.placeholder = placeholder
        self.isDisabled = isDisabled
        self.minHeight = minHeight
        self.maxHeight = maxHeight
        self.onSubmit = onSubmit
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = InputTextView()

        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.textColor = NSColor(AppColors.textPrimary)
        textView.insertionPointColor = NSColor(AppColors.accent)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 0, height: 4)
        textView.isRichText = false
        textView.allowsUndo = true

        context.coordinator.textView = textView

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear

        // 초기 높이 계산
        DispatchQueue.main.async {
            context.coordinator.updateContentHeight()
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        context.coordinator.parent = self
        if textView.string != text && !textView.hasMarkedText() {
            textView.string = text
            textView.undoManager?.removeAllActions()
            // 텍스트가 외부에서 변경된 경우 높이 재계산
            DispatchQueue.main.async {
                context.coordinator.updateContentHeight()
            }
        }

        textView.isEditable = !isDisabled
        context.coordinator.updatePlaceholder()
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MultiLineInputView
        weak var textView: NSTextView?
        private var placeholderLabel: NSTextField?

        init(_ parent: MultiLineInputView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            updatePlaceholder()
            updateContentHeight()
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if NSEvent.modifierFlags.contains(.shift) {
                    textView.insertNewlineIgnoringFieldEditor(nil)
                    return true
                }
                if textView.hasMarkedText() { return false }
                if !parent.text.isEmpty && !parent.isDisabled {
                    parent.onSubmit()
                }
                return true
            }
            return false
        }

        /// 텍스트 내용에 따른 높이 계산 및 업데이트
        func updateContentHeight() {
            guard let textView = textView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }

            // 레이아웃 강제 수행
            layoutManager.ensureLayout(for: textContainer)

            // 텍스트 콘텐츠의 실제 높이 계산
            let usedRect = layoutManager.usedRect(for: textContainer)
            let insetHeight = textView.textContainerInset.height * 2

            // 계산된 높이 (최소/최대 범위 내)
            let calculatedHeight = usedRect.height + insetHeight
            let clampedHeight = min(max(calculatedHeight, parent.minHeight), parent.maxHeight)

            // 높이가 변경된 경우에만 업데이트
            if abs(parent.contentHeight - clampedHeight) > 0.5 {
                parent.contentHeight = clampedHeight
            }

            // 스크롤 가능 여부 설정 (최대 높이에 도달한 경우)
            if let scrollView = textView.enclosingScrollView {
                scrollView.hasVerticalScroller = calculatedHeight > parent.maxHeight
            }
        }

        func updatePlaceholder() {
            guard let textView = textView else { return }

            if placeholderLabel == nil {
                let label = NSTextField(labelWithString: parent.placeholder)
                label.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
                label.textColor = NSColor.placeholderTextColor
                label.backgroundColor = .clear
                label.isBordered = false
                label.isEditable = false
                label.isSelectable = false
                label.translatesAutoresizingMaskIntoConstraints = false

                textView.addSubview(label)
                NSLayoutConstraint.activate([
                    label.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 5),
                    label.topAnchor.constraint(equalTo: textView.topAnchor, constant: 4)
                ])

                placeholderLabel = label
            }

            placeholderLabel?.stringValue = parent.placeholder
            placeholderLabel?.isHidden = !textView.string.isEmpty
        }
    }
}

private class InputTextView: NSTextView {
    // NSTextView owns composed-character edits, IME groups, selection replacement, and delegate notifications.
    @objc func undo(_ sender: Any?) { undoManager?.undo() }
    @objc func redo(_ sender: Any?) { undoManager?.redo() }
}

// MARK: - 대화 카드 뷰

struct ConversationCardView: View {
    let card: ConversationCard
    let onDelete: () -> Void
    let onToggleTag: () -> Void
    let onCopyQuestion: () -> Void
    let onCopyAnswer: () -> Void

    @State private var isHovered: Bool = false
    private let monoFont = Font.system(.body, design: .monospaced)

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // 메인 카드 콘텐츠
            cardContent

            // 호버 시 액션 버튼 표시
            if isHovered {
                hoverActionButtons
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .contextMenu {
            // 우클릭 컨텍스트 메뉴
            Button(action: onCopyQuestion) {
                Label(L10n.get("ai.chat.copyQuestion"), systemImage: "doc.on.doc")
            }

            if card.assistantMessage != nil {
                Button(action: onCopyAnswer) {
                    Label(L10n.get("ai.chat.copyAnswer"), systemImage: "doc.on.doc.fill")
                }
            }

            Divider()

            Button(action: onToggleTag) {
                Label(
                    card.isTaggedForContext ? L10n.get("ai.chat.untag") : L10n.get("ai.chat.tag"),
                    systemImage: card.isTaggedForContext ? "bookmark.slash.fill" : "bookmark.fill"
                )
            }

            Divider()

            Button(role: .destructive, action: onDelete) {
                Label(L10n.get("common.delete"), systemImage: "trash")
            }
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 사용자 질문 (별도 박스로 감싸기)
            HStack(alignment: .top, spacing: 8) {
                Text(">")
                    .font(monoFont)
                    .foregroundStyle(AppColors.accent)

                Text(card.userMessage.content)
                    .font(monoFont)
                    .foregroundStyle(AppColors.textPrimary)
                    .textSelection(.enabled)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.controlBackground.opacity(0.8))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // AI 답변
            if let assistant = card.assistantMessage {
                ScrollView {
                    Text(assistant.content)
                        .font(monoFont)
                        .foregroundStyle(AppColors.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if assistant.isStreaming {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.5)
                        Text(L10n.get("ai.chat.streaming"))
                            .font(.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
            } else {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.5)
                    Text(L10n.get("ai.chat.waiting"))
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }

            // 태그 표시
            if card.isTaggedForContext {
                HStack(spacing: 4) {
                    Image(systemName: "bookmark.fill")
                        .font(.caption)
                    Text(L10n.get("ai.chat.taggedForContext"))
                        .font(.caption)
                }
                .foregroundStyle(AppColors.accent)
                .padding(.top, 4)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.textEditorBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isHovered ? AppColors.accent.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }

    /// 호버 시 우상단에 표시되는 액션 버튼들
    private var hoverActionButtons: some View {
        HStack(spacing: 4) {
            // 복사 버튼
            Button(action: onCopyQuestion) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.toolbarIcon)
            }
            .buttonStyle(.plain)
            .frame(width: 24, height: 24)
            .background(AppColors.addButtonHover)
            .clipShape(Circle())
            .help(L10n.get("ai.chat.copyQuestion"))

            // 태그 버튼
            Button(action: onToggleTag) {
                Image(systemName: card.isTaggedForContext ? "bookmark.slash.fill" : "bookmark.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(card.isTaggedForContext ? AppColors.accent : AppColors.toolbarIcon)
            }
            .buttonStyle(.plain)
            .frame(width: 24, height: 24)
            .background(AppColors.addButtonHover)
            .clipShape(Circle())
            .help(card.isTaggedForContext ? L10n.get("ai.chat.untag") : L10n.get("ai.chat.tag"))

            // 삭제 버튼
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(.red.opacity(0.8))
            }
            .buttonStyle(.plain)
            .frame(width: 24, height: 24)
            .background(AppColors.addButtonHover)
            .clipShape(Circle())
            .help(L10n.get("common.delete"))
        }
        .padding(8)
    }
}

// MARK: - 선택 옵션 입력 뷰 (키보드 네비게이션 지원)

/// CLI 대화형 선택 UI - 방향키로 옵션 변경, 엔터로 선택 확정
struct SelectionInputView: View {
    let options: [CLISelectionOption]
    let onSelect: (Int) -> Void

    @State private var selectedIndex: Int = 0
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 안내 텍스트
            HStack(spacing: 6) {
                Image(systemName: "keyboard")
                    .font(.caption)
                    .foregroundStyle(AppColors.accent)
                Text(L10n.get("ai.chat.selectOption"))
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)

                Spacer()

                // 키보드 힌트
                HStack(spacing: 4) {
                    Text("↑↓")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(AppColors.textSecondary)
                    Text(L10n.get("ai.chat.arrowKeys"))
                        .font(.caption2)
                        .foregroundStyle(AppColors.textSecondary)
                    Text("⏎")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(AppColors.textSecondary)
                    Text(L10n.get("ai.chat.enterKey"))
                        .font(.caption2)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }

            // 선택 옵션 버튼들
            VStack(spacing: 8) {
                ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                    let isHighlighted = index == selectedIndex

                    Button(action: {
                        onSelect(option.id)
                    }) {
                        HStack(spacing: 10) {
                            // 번호 배지
                            Text("\(option.id)")
                                .font(.system(.caption, design: .monospaced).bold())
                                .foregroundStyle(isHighlighted ? AppColors.background : AppColors.accent)
                                .frame(width: 24, height: 24)
                                .background(isHighlighted ? AppColors.accent : AppColors.controlBackground)
                                .clipShape(Circle())

                            // 옵션 텍스트
                            Text(option.label)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(AppColors.textPrimary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)

                            Spacer()

                            // 현재 선택 표시
                            if isHighlighted {
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(AppColors.accent)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(isHighlighted ? AppColors.accent.opacity(0.1) : AppColors.controlBackground.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isHighlighted ? AppColors.accent : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(AppColors.textEditorBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 16)
        .padding(.bottom, 25)
        .focusable()
        .focused($isFocused)
        .onAppear {
            // 첫 번째 옵션 또는 현재 선택된 옵션으로 초기화
            if let currentIndex = options.firstIndex(where: { $0.isSelected }) {
                selectedIndex = currentIndex
            } else {
                selectedIndex = 0
            }
            // 포커스 설정
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isFocused = true
            }
        }
        .onKeyPress(.upArrow) {
            moveSelection(by: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            moveSelection(by: 1)
            return .handled
        }
        .onKeyPress(.return) {
            confirmSelection()
            return .handled
        }
        .onKeyPress(keys: [.init("1"), .init("2"), .init("3"), .init("4"), .init("5"), .init("6"), .init("7"), .init("8"), .init("9")]) { press in
            // 숫자 키로 직접 선택
            if let digit = Int(press.characters), digit > 0 && digit <= options.count {
                if let option = options.first(where: { $0.id == digit }) {
                    onSelect(option.id)
                    return .handled
                }
            }
            return .ignored
        }
    }

    private func moveSelection(by offset: Int) {
        let newIndex = selectedIndex + offset
        if newIndex >= 0 && newIndex < options.count {
            selectedIndex = newIndex
        }
    }

    private func confirmSelection() {
        guard selectedIndex >= 0 && selectedIndex < options.count else { return }
        let option = options[selectedIndex]
        onSelect(option.id)
    }
}

// MARK: - 에디터 컨텍스트 정보 뷰

/// 현재 열린 탭과 활성 파일 정보를 표시하는 VSCode 스타일 컨텍스트 뷰
struct EditorContextView: View {
    let openTabs: [EditorTab]
    let activeFile: EditorTab?
    let projectPath: URL?

    private var activeFileName: String {
        activeFile?.title ?? "No file"
    }

    private var activeFilePath: String {
        guard let activeFile = activeFile,
              let projectPath = projectPath else {
            return ""
        }

        let filePath = activeFile.url.path
        let projectPathStr = projectPath.path

        if filePath.hasPrefix(projectPathStr) {
            return String(filePath.dropFirst(projectPathStr.count + 1))
        }
        return activeFile.url.lastPathComponent
    }

    private var openTabsCount: Int {
        openTabs.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 활성 파일 정보
            if activeFile != nil {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .font(.caption)
                        .foregroundStyle(AppColors.accent)

                    Text(activeFileName)
                        .font(.system(.caption, design: .monospaced).bold())
                        .foregroundStyle(AppColors.textPrimary)

                    if !activeFilePath.isEmpty && activeFilePath != activeFileName {
                        Text("— \(activeFilePath)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(AppColors.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer()
                }
            }

            // 열린 탭 목록 (축약)
            if openTabsCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "square.stack")
                        .font(.caption2)
                        .foregroundStyle(AppColors.textSecondary)

                    Text(L10n.get("ai.chat.openTabs"))
                        .font(.caption2)
                        .foregroundStyle(AppColors.textSecondary)

                    // 탭 이름들 (최대 3개까지 표시)
                    ForEach(openTabs.prefix(3), id: \.id) { tab in
                        Text(tab.title)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(tab.id == activeFile?.id ? AppColors.accent : AppColors.textSecondary)
                            .lineLimit(1)

                        if tab.id != openTabs.prefix(3).last?.id {
                            Text("·")
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }

                    if openTabsCount > 3 {
                        Text("+\(openTabsCount - 3)")
                            .font(.caption2)
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    Spacer()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppColors.controlBackground.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - 메인 채팅 뷰

struct AIChatView: View {
    let cliType: AICLIType
    @Binding var messages: [AIMessage]
    @Binding var inputText: String
    @Binding var includeCurrentDocument: Bool
    @Binding var taggedCardIds: Set<UUID>
    @Binding var selectionState: CLISelectionState
    @Binding var selectedCardId: UUID?  // 선택된 카드 (상세 뷰 모드) - 외부에서 관리
    let isProcessing: Bool
    /// 메시지 전송 콜백
    /// - Parameter cardId: 채팅 뷰에서 전송 시 해당 카드 ID, 세션 뷰에서 전송 시 nil
    let onSend: (_ cardId: UUID?) -> Void
    let onCancel: () -> Void
    let onClearHistory: () -> Void
    let onChangeAI: () -> Void
    let onDisconnect: () -> Void
    let onDeleteCard: ((UUID) -> Void)?
    let onTagChanged: (() -> Void)?
    let onSelectionResponse: ((Int) -> Void)?
    var projectFolderURL: URL?
    var onPreviewDocument: () -> AIDocumentSnapshot? = { nil }
    @State private var documentPreview: AIDocumentSnapshot?
    @State private var showingDocumentPreview = false

    @State private var currentCardIndex: Int = 0
    @State private var inputHeight: CGFloat = 32  // 입력 박스 높이 (동적)

    // 에디터 탭 매니저에서 정보 가져오기
    private var tabManager: EditorTabManager { EditorTabManager.shared }

    private var openTabs: [EditorTab] {
        tabManager.tabs
    }

    private var activeFile: EditorTab? {
        tabManager.selectedTab
    }

    /// 메시지를 대화 카드로 변환
    private var conversationCards: [ConversationCard] {
        var cards: [ConversationCard] = []
        var currentRoot: UUID?
        for message in messages {
            if message.role == .user {
                let root = message.conversationId ?? message.id
                currentRoot = root
                if !cards.contains(where: { $0.id == root }) {
                    var card = ConversationCard(userMessage: message)
                    card.isTaggedForContext = taggedCardIds.contains(root)
                    cards.append(card)
                }
            } else if message.role == .assistant, let root = message.conversationId ?? currentRoot,
                      let index = cards.firstIndex(where: { $0.id == root }) {
                cards[index].assistantMessage = message
            }
        }
        return cards
    }

    private var detailMessages: [AIMessage] {
        guard let selectedCardId else { return [] }
        var root: UUID?
        return messages.filter { message in
            if message.role == .user { root = message.conversationId ?? message.id }
            return (message.conversationId ?? root) == selectedCardId
        }
    }

    /// 선택된 카드 객체
    private var selectedCard: ConversationCard? {
        guard let id = selectedCardId else { return nil }
        return conversationCards.first { $0.id == id }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 헤더
            if selectedCardId != nil {
                cardDetailHeader
            } else {
                chatHeader
            }

            // 상세 뷰 또는 카드 목록
            if selectedCardId != nil {
                cardDetailView
            } else {
                // 상단: 대화 카드 영역
                cardScrollView

                // 하단: 컨텍스트 + 입력 영역 (VSCode 스타일)
                bottomInputArea
            }
        }
        .frame(maxHeight: .infinity)
        .onChange(of: conversationCards.count) { _, newCount in
            // 새 카드가 추가되면 마지막 카드로 이동
            if newCount > 0 && selectedCardId == nil {
                withAnimation(.easeOut(duration: 0.3)) {
                    currentCardIndex = newCount - 1
                }
            }
        }
    }

    // MARK: - Bottom Input Area (VSCode Style)

    private var bottomInputArea: some View {
        VStack(spacing: 8) {
            documentAttachmentControl
            // 선택 대기 중이면 선택 UI 표시, 아니면 입력 영역 표시
            if selectionState.isWaitingForSelection {
                selectionInputView
            } else {
                cliInputView
            }
        }
        .padding(.top, 16)  // 에디터 좌우 마진과 동일
    }

    private var documentAttachmentControl: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(L10n.get("ai.chat.attachCurrentDocument"), isOn: $includeCurrentDocument)
                .disabled(activeFile == nil || isProcessing)
            if includeCurrentDocument {
                HStack {
                    if let activeFile {
                        Text(activeFile.title).font(.caption).foregroundStyle(AppColors.accent)
                    }
                    Spacer()
                    Button(L10n.get("ai.chat.previewDocument")) {
                        documentPreview = onPreviewDocument()
                        showingDocumentPreview = true
                    }
                    .disabled(isProcessing)
                }
            }
            Text(L10n.get("ai.chat.contextDisclosure"))
                .font(.caption2).foregroundStyle(AppColors.textSecondary)
        }
        .padding(.horizontal, 16)
        .sheet(isPresented: $showingDocumentPreview) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(documentPreview?.name ?? L10n.get("ai.chat.previewDocument"))
                        .font(.headline)
                    Spacer()
                    Button(L10n.get("common.close")) { showingDocumentPreview = false }
                }
                Text(L10n.get("ai.chat.previewDocumentDescription"))
                    .font(.caption).foregroundStyle(AppColors.textSecondary)
                Divider()
                if let documentPreview {
                    ScrollView {
                        Text(documentPreview.content.isEmpty ? L10n.get("ai.chat.emptyDocument") : documentPreview.content)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                } else {
                    Text(L10n.get("ai.error.contextUnavailable"))
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }
            .padding(20)
            .frame(width: 640, height: 480)
        }
    }

    // MARK: - Selection Input View

    private var selectionInputView: some View {
        SelectionInputView(
            options: selectionState.options,
            onSelect: { optionId in
                onSelectionResponse?(optionId)
            }
        )
    }

    // MARK: - Header

    private var chatHeader: some View {
        HStack {
            Image(cliType.iconImageName)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .foregroundStyle(AppColors.accent)
            Text(cliType.displayName)
                .font(.headline)
                .foregroundStyle(AppColors.textPrimary)

            Spacer()

            // 카드 인디케이터
            if conversationCards.count > 1 {
                Text("\(currentCardIndex + 1) / \(conversationCards.count)")
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(.horizontal, 8)
            }

            if isProcessing {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(AppColors.accent)
                    Text(L10n.get("ai.chat.streaming"))
                        .font(.caption)
                        .foregroundStyle(AppColors.accent)
                }
            }

            Menu {
                Button(action: onClearHistory) {
                    Label(L10n.get("ai.chat.clearHistory"), systemImage: "trash")
                }

                Button(action: onChangeAI) {
                    Label(L10n.get("ai.chat.changeAI"), systemImage: "arrow.triangle.2.circlepath")
                }

                Divider()

                Button(role: .destructive, action: onDisconnect) {
                    Label(L10n.get("ai.chat.disconnect"), systemImage: "link.badge.xmark")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(AppColors.toolbarIcon)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Card Detail Header

    private var cardDetailHeader: some View {
        HStack {
            // 뒤로가기 버튼 오버레이 공간 확보
            Spacer()
                .frame(width: 50)

            Spacer()

            // 카드 인덱스 표시
            if let card = selectedCard,
               let index = conversationCards.firstIndex(where: { $0.id == card.id }) {
                Text("\(index + 1) / \(conversationCards.count)")
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }

            if isProcessing {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(AppColors.accent)
                    Text(L10n.get("ai.chat.streaming"))
                        .font(.caption)
                        .foregroundStyle(AppColors.accent)
                }
                .padding(.leading, 8)
            }

            Spacer()
                .frame(width: 16)
        }
        .padding(.vertical, 12)
    }

    // MARK: - Card Detail View

    private var cardDetailView: some View {
        VStack(spacing: 0) {
            if selectedCard != nil {
                // 대화 내용 스크롤 뷰
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(detailMessages) { message in
                            cardDetailMessageView(role: message.role, content: message.content,
                                                  timestamp: message.timestamp, isStreaming: message.isStreaming)
                        }
                    }
                    .padding(.vertical, 16)
                }

                // 하단 입력 영역
                cardDetailInputArea
            }
        }
    }

    /// 상세 뷰 메시지 버블
    private func cardDetailMessageView(
        role: AIMessageRole,
        content: String,
        timestamp: Date,
        isStreaming: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // 역할 및 시간
            HStack {
                Image(systemName: role == .user ? "person.fill" : "sparkles")
                    .font(.caption)
                    .foregroundStyle(role == .user ? AppColors.accent : AppColors.textSecondary)

                Text(role == .user ? L10n.get("ai.chat.user") : L10n.get("ai.chat.assistant"))
                    .font(.caption.bold())
                    .foregroundStyle(role == .user ? AppColors.accent : AppColors.textSecondary)

                Spacer()

                Text(formatTimestamp(timestamp))
                    .font(.caption2)
                    .foregroundStyle(AppColors.textSecondary)
            }

            // 메시지 내용
            Text(content)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(AppColors.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isStreaming {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.5)
                    Text(L10n.get("ai.chat.streaming"))
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        }
        .padding(16)
        .background(role == .user ? AppColors.controlBackground.opacity(0.8) : AppColors.textEditorBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
    }

    /// 채팅 뷰 (카드 내부) 입력 영역 - 기존 세션 계속
    private var cardDetailInputArea: some View {
        VStack(spacing: 8) {
            documentAttachmentControl
            // 선택 대기 중이면 선택 UI 표시
            if selectionState.isWaitingForSelection {
                selectionInputView
            } else {
                // 입력 영역
                HStack(alignment: .top, spacing: 6) {
                    Text(">")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(AppColors.accent)
                        .padding(.top, 6)

                    MultiLineInputView(
                        text: $inputText,
                        contentHeight: $inputHeight,
                        placeholder: L10n.get("ai.chat.continueConversation"),
                        isDisabled: isProcessing,
                        minHeight: 32,
                        maxHeight: 120,
                        onSubmit: { onSend(selectedCardId) }  // 채팅 뷰: 카드 ID = 기존 세션 계속
                    )
                    .frame(height: inputHeight)
                    .animation(.easeOut(duration: 0.15), value: inputHeight)

                    if !isProcessing {
                        Button { onSend(selectedCardId) } label: {
                            Image(systemName: "arrow.up.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .help(L10n.get("ai.chat.send"))
                        .accessibilityLabel(L10n.get("ai.chat.send"))
                        .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    if isProcessing {
                        Button(action: onCancel) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .help(L10n.get("common.cancel"))
                        .padding(.top, 6)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppColors.textEditorBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 16)
                .padding(.bottom, 25)
            }
        }
    }

    /// 타임스탬프 포맷
    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    // MARK: - Card Scroll View

    private var cardScrollView: some View {
        GeometryReader { geometry in
            let cards = conversationCards

            if cards.isEmpty {
                emptyChatView
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 16) {
                            ForEach(cards) { card in
                                ConversationCardView(
                                    card: card,
                                    onDelete: { deleteCard(card) },
                                    onToggleTag: { toggleTag(card) },
                                    onCopyQuestion: { copyQuestion(card) },
                                    onCopyAnswer: { copyAnswer(card) }
                                )
                                .frame(minHeight: geometry.size.height - 32)
                                .id(card.id)
                                .onTapGesture {
                                    // 카드 클릭 시 상세 뷰로 이동
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        selectedCardId = card.id
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.viewAligned)
                    .onChange(of: currentCardIndex) { _, newIndex in
                        if newIndex < cards.count {
                            withAnimation(.easeOut(duration: 0.3)) {
                                proxy.scrollTo(cards[newIndex].id, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
    }

    private var emptyChatView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(cliType.displayName)
                .font(.headline)
                .foregroundStyle(AppColors.accent)

            Text(L10n.get("ai.chat.connectedHint"))
                .font(.caption)
                .foregroundStyle(AppColors.textSecondary)

            Text(L10n.get("ai.chat.emptyDescription"))
                .font(.subheadline)
                .foregroundStyle(AppColors.textSecondary)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    // MARK: - Input View

    /// 세션 뷰 (카드 목록) 입력 영역 - 새 세션 생성
    private var cliInputView: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(">")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(AppColors.accent)
                .padding(.top, 6)

            MultiLineInputView(
                text: $inputText,
                contentHeight: $inputHeight,
                placeholder: L10n.get("ai.chat.inputPlaceholder"),
                isDisabled: isProcessing,
                minHeight: 32,
                maxHeight: 120,
                onSubmit: { onSend(nil) }  // 세션 뷰: nil = 새 세션 생성
            )
            .frame(height: inputHeight)  // 동적 높이 적용
            .animation(.easeOut(duration: 0.15), value: inputHeight)  // 높이 변화 애니메이션

            if !isProcessing {
                Button { onSend(nil) } label: {
                    Image(systemName: "arrow.up.circle.fill")
                }
                .buttonStyle(.plain)
                .help(L10n.get("ai.chat.send"))
                .accessibilityLabel(L10n.get("ai.chat.send"))
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if isProcessing {
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help(L10n.get("common.cancel"))
                .padding(.top, 6)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppColors.textEditorBackground)  // 불투명 배경
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 16)  // 에디터 좌우 마진과 동일
        .padding(.bottom, 25)      // 에디터 상태바 높이와 동일 (font 11pt + padding 12pt)
    }

    // MARK: - Actions

    private func deleteCard(_ card: ConversationCard) {
        withAnimation(.spring(response: 0.3)) {
            // ViewModel 콜백이 있으면 사용, 없으면 직접 삭제
            if let onDelete = onDeleteCard {
                onDelete(card.id)
            } else {
                messages.removeAll { msg in
                    msg.id == card.userMessage.id ||
                    (card.assistantMessage != nil && msg.id == card.assistantMessage!.id)
                }
                taggedCardIds.remove(card.id)
            }
        }
    }

    private func toggleTag(_ card: ConversationCard) {
        withAnimation(.spring(response: 0.3)) {
            if taggedCardIds.contains(card.id) {
                taggedCardIds.remove(card.id)
            } else {
                taggedCardIds.insert(card.id)
            }

            // 태그 변경 콜백 호출
            onTagChanged?()
        }
    }

    private func copyQuestion(_ card: ConversationCard) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(card.userMessage.content, forType: .string)
    }

    private func copyAnswer(_ card: ConversationCard) {
        guard let assistantMessage = card.assistantMessage else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(assistantMessage.content, forType: .string)
    }
}

#Preview {
    AIChatView(
        cliType: .claude,
        messages: .constant([
            AIMessage(role: .user, content: "Hello, how are you?"),
            AIMessage(role: .assistant, content: "I'm doing well, thank you! How can I help you today?"),
            AIMessage(role: .user, content: "Can you explain what Swift is?"),
            AIMessage(role: .assistant, content: "Swift is a powerful and intuitive programming language developed by Apple for building apps for iOS, Mac, Apple TV, and Apple Watch. It's designed to be easy to learn and use, while also being powerful enough for professional developers.")
        ]),
        inputText: .constant(""),
        includeCurrentDocument: .constant(false),
        taggedCardIds: .constant([]),
        selectionState: .constant(.empty),
        selectedCardId: .constant(nil),
        isProcessing: false,
        onSend: { _ in },
        onCancel: {},
        onClearHistory: {},
        onChangeAI: {},
        onDisconnect: {},
        onDeleteCard: nil,
        onTagChanged: nil,
        onSelectionResponse: nil,
        projectFolderURL: nil
    )
    .frame(width: 400, height: 600)
}
