//
//  WelcomeView.swift
//  TextlinkEditor
//
//  시작 화면 - 프로젝트 선택/생성
//

import SwiftUI

struct WelcomeView: View {
    @Bindable var projectManager: ProjectManager
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @State private var isShowingNewProjectSheet = false
    @State private var newProjectName = ""
    @State private var selectedDirectory: URL?

    var body: some View {
        HStack(spacing: 0) {
            // 왼쪽: 로고 및 액션 버튼
            VStack(spacing: 24) {
                Spacer()

                // 로고
                VStack(spacing: 8) {
                    Image(systemName: "book.pages")
                        .font(.system(size: 64))
                        .foregroundStyle(.accent)

                    Text(L10n.app.name)
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text(L10n.get("welcome.subtitle"))
                        .font(.subheadline)
                        .foregroundStyle(AppColors.textSecondary)
                }

                Spacer()

                // 액션 버튼
                VStack(spacing: 12) {
                    Button {
                        isShowingNewProjectSheet = true
                    } label: {
                        Label(L10n.get("welcome.newProject"), systemImage: "plus.square")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Button {
                        openExistingProject()
                    } label: {
                        Label(L10n.get("welcome.openProject"), systemImage: "folder")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .frame(width: 200)

                Spacer()
            }
            .frame(width: 300)
            .background(ThemeAwareBackground(material: .sidebar, blendingMode: .behindWindow))

            Divider()

            // 오른쪽: 최근 프로젝트 목록
            VStack(alignment: .leading, spacing: 0) {
                // 헤더
                Text(L10n.get("welcome.recentProjects"))
                    .font(.headline)
                    .padding()

                Divider()

                if projectManager.recentProjects.isEmpty {
                    // 빈 상태
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 48))
                            .foregroundStyle(AppColors.toolbarIcon)

                        Text(L10n.get("welcome.noRecentProjects"))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // 프로젝트 목록 (Xcode 스타일)
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(projectManager.recentProjects.enumerated()), id: \.element.id) { index, project in
                                RecentProjectRow(project: project, isEvenRow: index % 2 == 0) {
                                    if projectManager.openProject(project) { openEditorWindow() }
                                } onDelete: {
                                    projectManager.deleteProject(project)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                }
            }
            .frame(minWidth: 400)
            .background(ThemeAwareBackground(material: .contentBackground, blendingMode: .behindWindow))
        }
        .frame(minWidth: 700, minHeight: 450)
        .sheet(isPresented: $isShowingNewProjectSheet) {
            NewProjectSheet(
                projectName: $newProjectName,
                selectedDirectory: $selectedDirectory,
                projectManager: projectManager
            ) {
                createNewProject()
            } onCancel: {
                resetNewProjectState()
            }
        }
        .onAppear {
            // 기본 저장 위치를 Documents로 설정
            if selectedDirectory == nil {
                selectedDirectory = projectManager.defaultSaveDirectory
            }
        }
    }

    private func openExistingProject() {
        if let url = projectManager.showOpenPanel() {
            if projectManager.openProjectFromFile(at: url) != nil {
                openEditorWindow()
            }
        }
    }

    private func openEditorWindow() {
        openWindow(id: "editor")
        dismiss()
    }

    private func createNewProject() {
        guard !newProjectName.trimmingCharacters(in: .whitespaces).isEmpty,
              let directory = selectedDirectory else { return }

        if projectManager.createProject(name: newProjectName, at: directory) != nil {
            resetNewProjectState()
            isShowingNewProjectSheet = false
            openEditorWindow()
        }
    }

    private func resetNewProjectState() {
        newProjectName = ""
        selectedDirectory = projectManager.defaultSaveDirectory
        isShowingNewProjectSheet = false
    }
}

// MARK: - Recent Project Row

struct RecentProjectRow: View {
    let project: Project
    let isEvenRow: Bool
    let onOpen: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    private var backgroundColor: Color {
        if isHovering {
            return AppColors.sidebarItemHover
        } else if isEvenRow {
            return Color(nsColor: .alternatingContentBackgroundColors[0])
        } else {
            return Color(nsColor: .alternatingContentBackgroundColors[1])
        }
    }

    var body: some View {
        Button {
            onOpen()
        } label: {
            HStack(spacing: 12) {
                // 프로젝트 아이콘
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(AppColors.toolbarIcon)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)

                    if let path = project.path {
                        Text(path.deletingLastPathComponent().path)
                            .font(.system(size: 11))
                            .foregroundStyle(AppColors.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer()

                // 날짜
                Text(project.lastOpenedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.textTertiary)

                // 삭제 버튼
                if isHovering {
                    Button {
                        onDelete()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(AppColors.toolbarIcon)
                    }
                    .buttonStyle(.plain)
                    .help(L10n.common.delete)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - New Project Sheet

struct NewProjectSheet: View {
    @Binding var projectName: String
    @Binding var selectedDirectory: URL?
    let projectManager: ProjectManager
    let onCreate: () -> Void
    let onCancel: () -> Void

    @State private var isShowingCustomExtensionAlert = false

    /// 사용자가 커스텀 확장자를 사용하려는지 확인
    private var hasCustomExtension: Bool {
        projectName.contains(".")
    }

    /// 최종 폴더명 (미리보기용)
    private var finalFolderName: String {
        let trimmedName = projectName.trimmingCharacters(in: .whitespaces)
        if trimmedName.isEmpty { return "" }

        if hasCustomExtension {
            return trimmedName
        } else {
            return "\(trimmedName).\(ProjectManager.projectExtension)"
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            Text(L10n.get("welcome.newProject"))
                .font(.headline)

            // 프로젝트 이름
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.get("welcome.projectName"))
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)

                HStack(spacing: 0) {
                    TextField(L10n.get("welcome.projectNamePlaceholder"), text: $projectName)
                        .textFieldStyle(.roundedBorder)

                    // 커스텀 확장자가 없을 때만 .weaveproj 표시
                    if !hasCustomExtension {
                        Text(".\(ProjectManager.projectExtension)")
                            .font(.system(size: 13))
                            .foregroundStyle(AppColors.textSecondary)
                            .padding(.leading, 4)
                    }
                }

                // 최종 폴더명 미리보기
                if !projectName.trimmingCharacters(in: .whitespaces).isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "folder.fill")
                            .font(.caption2)
                        Text(finalFolderName)
                            .font(.caption)
                    }
                    .foregroundStyle(AppColors.textTertiary)
                }
            }
            .frame(width: 350)

            // 저장 위치
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.get("welcome.saveLocation"))
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)

                HStack {
                    if let directory = selectedDirectory {
                        Text(directory.path)
                            .font(.system(size: 12))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(L10n.get("welcome.noLocationSelected"))
                            .font(.system(size: 12))
                            .foregroundStyle(AppColors.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button(L10n.get("welcome.browse")) {
                        selectDirectory()
                    }
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(AppColors.controlBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(AppColors.controlBorder, lineWidth: 1)
                )
            }
            .frame(width: 350)

            // 버튼
            HStack {
                Button(L10n.common.cancel) {
                    onCancel()
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button(L10n.get("welcome.create")) {
                    handleCreate()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
            }
            .frame(width: 350)
        }
        .padding(30)
        .alert(
            L10n.get("welcome.customExtensionWarningTitle"),
            isPresented: $isShowingCustomExtensionAlert
        ) {
            Button(L10n.common.cancel, role: .cancel) {}
            Button(L10n.get("welcome.proceedAnyway"), role: .destructive) {
                onCreate()
            }
        } message: {
            Text(L10n.get("welcome.customExtensionWarningMessage"))
        }
    }

    private var isValid: Bool {
        !projectName.trimmingCharacters(in: .whitespaces).isEmpty && selectedDirectory != nil
    }

    private func handleCreate() {
        if hasCustomExtension {
            isShowingCustomExtensionAlert = true
        } else {
            onCreate()
        }
    }

    private func selectDirectory() {
        if let url = projectManager.showSaveDirectoryPanel() {
            selectedDirectory = url
        }
    }
}

#Preview {
    WelcomeView(projectManager: ProjectManager.shared)
}
