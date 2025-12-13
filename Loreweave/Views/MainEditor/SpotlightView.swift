//
//  SpotlightView.swift
//  Loreweave
//
//  스포트라이트 검색 오버레이
//  툴바 영역에 항상 표시되며, 클릭 시 제자리에서 확장
//

import SwiftUI

/// 스포트라이트 오버레이 (축소/확장 통합)
/// MainEditorView의 ZStack 상단에 배치
struct SpotlightOverlay: View {
    @Binding var text: String
    @Binding var isExpanded: Bool

    @FocusState private var isTextFieldFocused: Bool
    @State private var searchResults: [SpotlightSearchResult] = []
    /// 확장 콘텐츠 표시 여부 (지연 애니메이션용)
    @State private var showExpandedContent: Bool = false
    /// 닫기 작업 취소용 ID
    @State private var closingTaskId: UUID?

    /// 컴팩트 상태 크기 (NavigationButtonsView와 동일한 높이: buttonSize 28 + padding 8 = 36)
    private let compactWidth: CGFloat = 220
    private let compactHeight: CGFloat = 36

    /// 확장 상태 크기
    private let expandedWidth: CGFloat = 400
    private let expandedHeight: CGFloat = 320

    /// 코너 곡률 (캡슐 형태 - 컴팩트 높이의 절반)
    private let cornerRadius: CGFloat = 18

    /// 현재 상태에 따른 너비
    private var currentWidth: CGFloat {
        isExpanded ? expandedWidth : compactWidth
    }

    /// 현재 상태에 따른 높이
    private var currentHeight: CGFloat {
        isExpanded ? expandedHeight : compactHeight
    }

    var body: some View {
        ZStack(alignment: .top) {
            // 확장 시 배경 딤 + 클릭으로 닫기
            if isExpanded {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture {
                        closeSpotlight()
                    }
            }

            // 스포트라이트 패널 (축소/확장 공유)
            spotlightPanel
                .frame(width: currentWidth, height: currentHeight)
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
                .shadow(
                    color: .black.opacity(isExpanded ? 0.25 : 0.1),
                    radius: isExpanded ? 20 : 8,
                    y: isExpanded ? 10 : 4
                )
                .contentShape(Rectangle())
                .gesture(
                    TapGesture()
                        .onEnded {
                            // 컴팩트 상태에서 싱글 클릭으로 확장 + 포커스
                            if !isExpanded {
                                expandSpotlight()
                            }
                        },
                    including: .all // 윈도우 드래그 제스처보다 우선
                )
                .background {
                    // 윈도우 드래그 영역에서 제외
                    WindowDragExclusionView()
                }
                .padding(.top, 8) // 툴바 상단 패딩
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isExpanded)
        .onChange(of: isExpanded) { _, newValue in
            if newValue {
                // 확장 시: 이전 닫기 작업 취소 + 콘텐츠 페이드인
                closingTaskId = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    guard isExpanded else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        showExpandedContent = true
                    }
                }
            } else {
                // 축소 시: 즉시 콘텐츠 숨김
                showExpandedContent = false
            }
        }
        .onChange(of: isTextFieldFocused) { _, newValue in
            // 스포트라이트가 이미 확장된 상태에서만 포커스 변화에 반응
            // 컴팩트 상태에서는 탭 제스처로만 확장되어야 함
            guard isExpanded else { return }

            if newValue {
                // 포커스 획득 시: 닫기 작업 취소
                closingTaskId = nil
            } else {
                // 포커스 해제 시: 지연 후 닫기 (재포커스 시 취소됨)
                let taskId = UUID()
                closingTaskId = taskId
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    // 이 작업이 취소되지 않았고 여전히 포커스가 없으면 닫기
                    if closingTaskId == taskId && !isTextFieldFocused {
                        closeSpotlight()
                    }
                }
            }
        }
        .onExitCommand {
            if isExpanded {
                closeSpotlight()
            }
        }
    }

    // MARK: - Spotlight Panel

    private var spotlightPanel: some View {
        VStack(spacing: 0) {
            // 검색 입력 필드 (항상 표시)
            searchInputField

            // 확장 콘텐츠 (패널 확장 후 페이드인)
            if isExpanded {
                Divider()
                    .padding(.horizontal, 8)
                    .opacity(showExpandedContent ? 1 : 0)

                expandedContent
                    .opacity(showExpandedContent ? 1 : 0)
                    .scaleEffect(showExpandedContent ? 1 : 0.95, anchor: .top)
            }
        }
        .clipped()
    }

    // MARK: - Search Input Field

    private var searchInputField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: isExpanded ? 14 : 12, weight: .medium))
                .foregroundStyle(AppColors.toolbarIcon)

            TextField(L10n.get("toolbar.searchPlaceholder"), text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: isExpanded ? 14 : 13))
                .focused($isTextFieldFocused)
                .onSubmit {
                    performSearch()
                }

            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.toolbarIcon)
                }
                .buttonStyle(.plain)
            }

            if isExpanded {
                // ESC 키 힌트
                Text("esc")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(AppColors.textTertiary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(AppColors.controlBackground.opacity(0.8))
                    .cornerRadius(3)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: isExpanded ? 36 : compactHeight) // 확장 시에도 검색 필드 높이 유지
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
            // 섹션 헤더
            Text(L10n.get("spotlight.quickActions"))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppColors.textTertiary)
                .textCase(.uppercase)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 6)

            // 빠른 액션 목록
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
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(AppColors.toolbarIcon)
                .frame(width: 18)

            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(AppColors.textPrimary)

            Spacer()

            Text(shortcut)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(AppColors.textTertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    // MARK: - Search Results View

    private var searchResultsView: some View {
        VStack(alignment: .leading, spacing: 0) {
            if searchResults.isEmpty {
                // 검색 결과 없음
                VStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 20))
                        .foregroundStyle(AppColors.toolbarIcon)

                    Text(L10n.get("spotlight.noResults"))
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // 검색 결과 목록
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
        HStack(spacing: 10) {
            Image(systemName: result.iconName)
                .font(.system(size: 12))
                .foregroundStyle(result.isDirectory ? AppColors.accent : AppColors.toolbarIcon)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(result.name)
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)

                if let path = result.relativePath {
                    Text(path)
                        .font(.system(size: 10))
                        .foregroundStyle(AppColors.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            selectResult(result)
        }
    }

    // MARK: - Actions

    private func expandSpotlight() {
        closingTaskId = nil
        isExpanded = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard isExpanded else { return }
            isTextFieldFocused = true
        }
    }

    private func closeSpotlight() {
        closingTaskId = nil
        isTextFieldFocused = false
        isExpanded = false
    }

    private func performSearch() {
        // TODO: 실제 검색 구현
        // FileSystemManager를 통해 프로젝트 내 파일 검색
    }

    private func selectResult(_ result: SpotlightSearchResult) {
        // TODO: 검색 결과 선택 시 파일 열기
        closeSpotlight()
    }
}

/// 스포트라이트 검색 결과 모델
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

/// 윈도우 드래그 영역에서 제외하는 NSView 래퍼
/// 툴바 영역에서 스포트라이트 클릭이 윈도우 이동으로 처리되는 것을 방지
struct WindowDragExclusionView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NonDraggableView()
        view.wantsLayer = true
        view.layer?.backgroundColor = .clear
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    class NonDraggableView: NSView {
        override var mouseDownCanMoveWindow: Bool { false }

        // hitTest를 오버라이드하지 않음 - SwiftUI 제스처 처리에 맡김
    }
}

#Preview("Compact") {
    ZStack(alignment: .top) {
        Color(nsColor: .windowBackgroundColor)

        SpotlightOverlay(text: .constant(""), isExpanded: .constant(false))
    }
    .frame(width: 600, height: 200)
}

#Preview("Expanded") {
    ZStack(alignment: .top) {
        Color(nsColor: .windowBackgroundColor)

        SpotlightOverlay(text: .constant(""), isExpanded: .constant(true))
    }
    .frame(width: 600, height: 500)
}
