//
//  SidebarView.swift
//  Loreweave
//

import SwiftUI

struct SidebarView: View {
    @Environment(\.openSettings) private var openSettings
    @State private var fileSystemManager = FileSystemManager.shared
    @State private var projectManager = ProjectManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // 프로젝트 탐색기
            ProjectExplorerView()
                .frame(maxHeight: .infinity)

            // 설정 버튼
            HStack {
                Spacer()
                Button(action: { openSettings() }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                        .foregroundStyle(AppColors.toolbarIcon)
                }
                .buttonStyle(.plain)
                .help(L10n.sidebar.settings)
                .padding(8)
            }
        }
        .navigationTitle(projectManager.currentProject?.name ?? "")
    }
}

#Preview {
    SidebarView()
        .frame(width: 220, height: 600)
}
