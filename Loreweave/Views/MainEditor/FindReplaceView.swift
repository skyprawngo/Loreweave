//
//  FindReplaceView.swift
//  Loreweave
//
//  찾기/바꾸기 뷰 - 에디터 상단 슬라이드 다운 형태
//

import SwiftUI

// MARK: - Search Scope

/// 검색 범위
enum SearchScope: String, CaseIterable, Identifiable {
    case currentFile = "currentFile"
    case openTabs = "openTabs"
    case project = "project"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .currentFile: return L10n.get("findReplace.scopeCurrentFile")
        case .openTabs: return L10n.get("findReplace.scopeOpenTabs")
        case .project: return L10n.get("findReplace.scopeProject")
        }
    }

    var icon: String {
        switch self {
        case .currentFile: return "doc"
        case .openTabs: return "square.stack"
        case .project: return "folder"
        }
    }
}

// MARK: - Search Options

/// 검색 옵션
struct SearchOptions {
    var matchCase: Bool = false
    var wholeWord: Bool = false
    var useRegex: Bool = false
}

// MARK: - Find Replace View

struct FindReplaceView: View {
    @Binding var isVisible: Bool
    @Binding var searchText: String
    @Binding var replaceText: String
    @Binding var searchScope: SearchScope
    @Binding var searchOptions: SearchOptions
    @Binding var showReplace: Bool

    /// 검색 결과 개수
    var matchCount: Int = 0

    /// 찾기 액션
    var onFind: () -> Void
    /// 다음 찾기
    var onFindNext: () -> Void
    /// 이전 찾기
    var onFindPrevious: () -> Void
    /// 바꾸기 액션
    var onReplace: () -> Void
    /// 모두 바꾸기 액션
    var onReplaceAll: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // 메인 컨텐츠
            HStack(spacing: 12) {
                // 바꾸기 토글 버튼
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showReplace.toggle()
                    }
                } label: {
                    Image(systemName: showReplace ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppColors.toolbarIcon)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .help(L10n.get("findReplace.replace"))

                // 검색/바꾸기 입력 필드
                VStack(spacing: 8) {
                    // 찾기 필드
                    HStack(spacing: 8) {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(AppColors.toolbarIcon)
                                .font(.system(size: 12))

                            TextField(L10n.get("findReplace.findPlaceholder"), text: $searchText)
                                .textFieldStyle(.plain)
                                .font(.system(size: 13))
                                .onSubmit {
                                    onFind()
                                }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(AppColors.controlBackground)
                        .cornerRadius(6)
                        .frame(minWidth: 200)

                        // 결과 표시
                        if matchCount > 0 {
                            Text(String(format: L10n.get("findReplace.matchCount"), matchCount))
                                .font(.system(size: 11))
                                .foregroundStyle(AppColors.textSecondary)
                                .frame(width: 70)
                        } else if !searchText.isEmpty {
                            Text(L10n.get("findReplace.noResults"))
                                .font(.system(size: 11))
                                .foregroundStyle(AppColors.textTertiary)
                                .frame(width: 70)
                        }

                        // 이전/다음 버튼
                        HStack(spacing: 4) {
                            Button(action: onFindPrevious) {
                                Image(systemName: "chevron.up")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(searchText.isEmpty || matchCount == 0)

                            Button(action: onFindNext) {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(searchText.isEmpty || matchCount == 0)
                        }
                    }

                    // 바꾸기 필드 (조건부 표시)
                    if showReplace {
                        HStack(spacing: 8) {
                            HStack {
                                Image(systemName: "arrow.triangle.swap")
                                    .foregroundStyle(AppColors.toolbarIcon)
                                    .font(.system(size: 12))

                                TextField(L10n.get("findReplace.replacePlaceholder"), text: $replaceText)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 13))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(AppColors.controlBackground)
                            .cornerRadius(6)
                            .frame(minWidth: 200)

                            // 바꾸기 버튼들
                            HStack(spacing: 4) {
                                Button(action: onReplace) {
                                    Text(L10n.get("findReplace.replace"))
                                        .font(.system(size: 11))
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(searchText.isEmpty || matchCount == 0)

                                Button(action: onReplaceAll) {
                                    Text(L10n.get("findReplace.replaceAll"))
                                        .font(.system(size: 11))
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(searchText.isEmpty || matchCount == 0)
                            }
                        }
                    }
                }

                Spacer()

                // 검색 옵션 토글
                HStack(spacing: 8) {
                    // 범위 선택
                    Picker("", selection: $searchScope) {
                        ForEach(SearchScope.allCases) { scope in
                            Label(scope.displayName, systemImage: scope.icon)
                                .tag(scope)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 130)

                    Divider()
                        .frame(height: 20)

                    // 대소문자 구분
                    Toggle(isOn: $searchOptions.matchCase) {
                        Image(systemName: "textformat")
                            .font(.system(size: 11))
                    }
                    .toggleStyle(.button)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(L10n.get("findReplace.matchCase"))

                    // 전체 단어
                    Toggle(isOn: $searchOptions.wholeWord) {
                        Image(systemName: "text.word.spacing")
                            .font(.system(size: 11))
                    }
                    .toggleStyle(.button)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(L10n.get("findReplace.wholeWord"))

                    // 정규식
                    Toggle(isOn: $searchOptions.useRegex) {
                        Image(systemName: "asterisk")
                            .font(.system(size: 11))
                    }
                    .toggleStyle(.button)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(L10n.get("findReplace.useRegex"))
                }

                // 닫기 버튼
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isVisible = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppColors.toolbarIcon)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)

            Divider()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - Preview

#Preview("찾기만") {
    VStack {
        FindReplaceView(
            isVisible: .constant(true),
            searchText: .constant("검색어"),
            replaceText: .constant(""),
            searchScope: .constant(.currentFile),
            searchOptions: .constant(SearchOptions()),
            showReplace: .constant(false),
            matchCount: 5,
            onFind: {},
            onFindNext: {},
            onFindPrevious: {},
            onReplace: {},
            onReplaceAll: {}
        )

        Spacer()
    }
    .frame(width: 800, height: 300)
}

#Preview("찾기 및 바꾸기") {
    VStack {
        FindReplaceView(
            isVisible: .constant(true),
            searchText: .constant("검색어"),
            replaceText: .constant("대체어"),
            searchScope: .constant(.project),
            searchOptions: .constant(SearchOptions(matchCase: true)),
            showReplace: .constant(true),
            matchCount: 12,
            onFind: {},
            onFindNext: {},
            onFindPrevious: {},
            onReplace: {},
            onReplaceAll: {}
        )

        Spacer()
    }
    .frame(width: 800, height: 300)
}
