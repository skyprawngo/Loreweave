//
//  SpotlightView.swift
//  Loreweave
//
//  스포트라이트 검색 필드 (윈도우 타이틀바에 위치)
//

import SwiftUI

struct SpotlightView: View {
    @Binding var text: String
    var placeholder: String = L10n.get("toolbar.searchPlaceholder")
    /// 검색 필드 클릭 시 호출되는 콜백
    var onActivate: (() -> Void)?

    @State private var isFocused: Bool = false
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppColors.toolbarIcon)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($isTextFieldFocused)

            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.toolbarIcon)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(width: 220)
        .onChange(of: isTextFieldFocused) { _, newValue in
            isFocused = newValue
            if newValue {
                onActivate?()
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        SpotlightView(text: .constant(""))
        SpotlightView(text: .constant("검색어"))
    }
    .padding(40)
    .background(Color(nsColor: .windowBackgroundColor))
}
