//
//  SpotlightView.swift
//  Loreweave
//
//  스포트라이트 검색
//  - SpotlightToolbarItem: 툴바에 배치되는 컴팩트 캡슐
//  - SpotlightExpandedOverlay: 확장된 검색 패널 오버레이
//

import SwiftUI

// MARK: - Spotlight Toolbar Item

/// 툴바에 배치되는 스포트라이트 컴팩트 버튼
/// 클릭 시 확장 상태로 전환
struct SpotlightToolbarItem: View {
    @Binding var text: String
    @Binding var isExpanded: Bool

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                isExpanded = true
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppColors.toolbarIcon)

                Text(text.isEmpty ? L10n.get("toolbar.searchPlaceholder") : text)
                    .font(.system(size: 12))
                    .foregroundStyle(text.isEmpty ? AppColors.textTertiary : AppColors.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                // 단축키 힌트
                Text("⌘K")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppColors.textTertiary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(isHovered ? AppColors.addButtonHover : AppColors.controlBackground.opacity(0.6))
                    .cornerRadius(3)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minWidth: 180)
        }
        .buttonStyle(.plain)
        .glassEffect()
        .onHover { isHovered = $0 }
        .help(L10n.get("toolbar.searchPlaceholder"))
    }
}

// MARK: - Spotlight Expanded Overlay

/// 확장된 스포트라이트 검색 오버레이
/// ZStack에서 조건부로 표시
struct SpotlightExpandedOverlay: View {
    @Binding var text: String
    @Binding var isExpanded: Bool

    @FocusState private var isTextFieldFocused: Bool
    @State private var searchResults: [SpotlightSearchResult] = []
    @State private var showContent: Bool = false
    @State private var closingTaskId: UUID?

    private let panelWidth: CGFloat = 500
    private let panelHeight: CGFloat = 360
    private let cornerRadius: CGFloat = 16

    var body: some View {
        ZStack(alignment: .top) {
            // 배경 딤
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    closeSpotlight()
                }

            // 검색 패널
            WindowDragExclusionWrapper {
                VStack(spacing: 0) {
                    searchInputField
                    Divider()
                        .padding(.horizontal, 12)
                    expandedContent
                }
                .frame(width: panelWidth, height: panelHeight)
                .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
                .shadow(color: .black.opacity(0.25), radius: 30, y: 10)
            }
            .padding(.top, 80)
            .scaleEffect(showContent ? 1 : 0.95)
            .opacity(showContent ? 1 : 0)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showContent)
        .onAppear {
            showContent = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTextFieldFocused = true
            }
        }
        .onChange(of: isTextFieldFocused) { _, newValue in
            if !newValue {
                let taskId = UUID()
                closingTaskId = taskId
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    if closingTaskId == taskId && !isTextFieldFocused {
                        closeSpotlight()
                    }
                }
            } else {
                closingTaskId = nil
            }
        }
        .onExitCommand {
            closeSpotlight()
        }
    }

    // MARK: - Search Input Field

    private var searchInputField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(AppColors.toolbarIcon)

            TextField(L10n.get("toolbar.searchPlaceholder"), text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .focused($isTextFieldFocused)
                .onSubmit {
                    performSearch()
                }

            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(AppColors.toolbarIcon)
                }
                .buttonStyle(.plain)
            }

            Text("esc")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppColors.textTertiary)
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(AppColors.controlBackground.opacity(0.8))
                .cornerRadius(4)
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
    }

    // MARK: - Expanded Content

    private var expandedContent: some View {
        Group {
            if text.isEmpty {
                quickActionsView
            } else {
                searchResultsView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Quick Actions View

    private var quickActionsView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.get("spotlight.quickActions"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppColors.textTertiary)
                .textCase(.uppercase)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

            ScrollView {
                VStack(spacing: 0) {
                    quickActionRow(icon: "doc.badge.plus", title: L10n.get("explorer.newFile"), shortcut: "⌘N")
                    quickActionRow(icon: "folder.badge.plus", title: L10n.get("explorer.newFolder"), shortcut: "⇧⌘N")
                    quickActionRow(icon: "arrow.clockwise", title: L10n.get("explorer.refresh"), shortcut: "⌘R")
                    quickActionRow(icon: "sidebar.left", title: L10n.get("shortcut.view.sidebar"), shortcut: "⌘\\")
                    quickActionRow(icon: "sparkle", title: L10n.ai.togglePanel, shortcut: "⌥⌘A")
                }
            }
        }
    }

    private func quickActionRow(icon: String, title: String, shortcut: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(AppColors.toolbarIcon)
                .frame(width: 20)

            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(AppColors.textPrimary)

            Spacer()

            Text(shortcut)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(AppColors.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background(Color.clear)
        .onHover { hovering in
            // TODO: 호버 효과 추가
        }
    }

    // MARK: - Search Results View

    private var searchResultsView: some View {
        VStack(alignment: .leading, spacing: 0) {
            if searchResults.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 24))
                        .foregroundStyle(AppColors.toolbarIcon)

                    Text(L10n.get("spotlight.noResults"))
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(searchResults) { result in
                            searchResultRow(result)
                        }
                    }
                }
            }
        }
    }

    private func searchResultRow(_ result: SpotlightSearchResult) -> some View {
        HStack(spacing: 12) {
            Image(systemName: result.iconName)
                .font(.system(size: 14))
                .foregroundStyle(result.isDirectory ? AppColors.accent : AppColors.toolbarIcon)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.name)
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)

                if let path = result.relativePath {
                    Text(path)
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            selectResult(result)
        }
    }

    // MARK: - Actions

    private func closeSpotlight() {
        closingTaskId = nil
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            showContent = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            isExpanded = false
        }
    }

    private func performSearch() {
        // TODO: 실제 검색 구현
    }

    private func selectResult(_ result: SpotlightSearchResult) {
        closeSpotlight()
    }
}

// MARK: - Spotlight Search Result

struct SpotlightSearchResult: Identifiable {
    let id: UUID
    let name: String
    let relativePath: String?
    let url: URL
    let isDirectory: Bool

    var iconName: String {
        if isDirectory {
            return "folder"
        }
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "md", "markdown": return "doc.text"
        case "txt": return "doc.plaintext"
        case "json": return "curlybraces"
        default: return "doc"
        }
    }
}

// MARK: - Window Drag Exclusion

/// 윈도우 드래그를 차단하는 SwiftUI 래퍼
struct WindowDragExclusionWrapper<Content: View>: NSViewRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeNSView(context: Context) -> NSHostingView<Content> {
        let hostingView = NonDraggableHostingView(rootView: content)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear
        return hostingView
    }

    func updateNSView(_ nsView: NSHostingView<Content>, context: Context) {
        nsView.rootView = content
    }

    class NonDraggableHostingView<V: View>: NSHostingView<V> {
        override var mouseDownCanMoveWindow: Bool { false }
    }
}

// MARK: - Previews

#Preview("Toolbar Item") {
    HStack {
        Spacer()
        SpotlightToolbarItem(text: .constant(""), isExpanded: .constant(false))
        Spacer()
    }
    .frame(width: 600, height: 50)
    .background(Color(nsColor: .windowBackgroundColor))
}

#Preview("Expanded Overlay") {
    ZStack {
        Color(nsColor: .windowBackgroundColor)
        SpotlightExpandedOverlay(text: .constant(""), isExpanded: .constant(true))
    }
    .frame(width: 800, height: 600)
}
