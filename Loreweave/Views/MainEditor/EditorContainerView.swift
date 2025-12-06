//
//  EditorContainerView.swift
//  Loreweave
//
//  에디터 컨테이너 뷰 - 여러 EditorPanelView 관리
//  MainEditorView의 하위 컴포넌트
//
//  향후 확장 가능:
//  - 분할 뷰 (수평/수직)
//  - 탭 그룹
//  - 드래그 앤 드롭으로 패널 재배치
//

import SwiftUI

// MARK: - Editor Container View

/// 에디터 컨테이너 - 하나 이상의 EditorPanelView 관리
struct EditorContainerView: View {
    @EnvironmentObject var appCommands: AppCommands

    // 찾기/바꾸기 상태 (MainEditorView에서 전달)
    @Binding var showFindReplace: Bool
    @Binding var findSearchText: String
    @Binding var replaceText: String
    @Binding var searchScope: SearchScope
    @Binding var searchOptions: SearchOptions
    @Binding var showReplaceField: Bool
    @Binding var matchCount: Int

    /// AI 패널 공간 확보를 위한 우측 패딩 (텍스트 에디터 영역에만 적용)
    var trailingPadding: CGFloat = 0

    /// 현재 에디터 패널 수 (향후 분할 뷰 지원용)
    @State private var panelCount: Int = 1

    /// 현재 활성 패널 인덱스
    @State private var activePanelIndex: Int = 0

    var body: some View {
        ZStack(alignment: .top) {
            // 에디터 패널 (현재는 단일 패널)
            EditorPanelView(
                showFindReplace: $showFindReplace,
                findSearchText: $findSearchText,
                replaceText: $replaceText,
                searchScope: $searchScope,
                searchOptions: $searchOptions,
                showReplaceField: $showReplaceField,
                matchCount: $matchCount,
                trailingPadding: trailingPadding
            )
            .environmentObject(appCommands)

            // 찾기/바꾸기 오버레이
            if showFindReplace {
                VStack(spacing: 0) {
                    FindReplaceView(
                        isVisible: $showFindReplace,
                        searchText: $findSearchText,
                        replaceText: $replaceText,
                        searchScope: $searchScope,
                        searchOptions: $searchOptions,
                        showReplace: $showReplaceField,
                        matchCount: matchCount,
                        onFind: { performFind() },
                        onFindNext: { findNext() },
                        onFindPrevious: { findPrevious() },
                        onReplace: { replaceOne() },
                        onReplaceAll: { replaceAll() }
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(AppColors.barBackground)
                            .shadow(color: AppColors.shadowDrop, radius: 8, y: 4)
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        // 에디터 영역의 컨트롤이 항상 활성화 상태로 표시되도록 강제
        .environment(\.controlActiveState, .key)
    }

    // MARK: - Find/Replace Actions

    private func performFind() {
        // EditorPanelView에서 실제 검색 로직 처리
    }

    private func findNext() {
        performFind()
    }

    private func findPrevious() {
        performFind()
    }

    private func replaceOne() {
        // EditorPanelView에서 처리
    }

    private func replaceAll() {
        // EditorPanelView에서 처리
    }

    // MARK: - Panel Management (향후 확장용)

    /// 패널 분할 (수평)
    func splitPanelHorizontally() {
        // TODO: 수평 분할 구현
        panelCount += 1
    }

    /// 패널 분할 (수직)
    func splitPanelVertically() {
        // TODO: 수직 분할 구현
        panelCount += 1
    }

    /// 패널 닫기
    func closePanel(at index: Int) {
        guard panelCount > 1 else { return }
        // TODO: 패널 닫기 구현
        panelCount -= 1
    }

    /// 활성 패널 변경
    func setActivePanel(at index: Int) {
        guard index >= 0 && index < panelCount else { return }
        activePanelIndex = index
    }
}

#Preview {
    EditorContainerView(
        showFindReplace: .constant(false),
        findSearchText: .constant(""),
        replaceText: .constant(""),
        searchScope: .constant(.currentFile),
        searchOptions: .constant(SearchOptions()),
        showReplaceField: .constant(false),
        matchCount: .constant(0),
        trailingPadding: 0
    )
    .environmentObject(AppCommands.shared)
}
