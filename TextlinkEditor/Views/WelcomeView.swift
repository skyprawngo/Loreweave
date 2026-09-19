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
            ) { options in
                createNewProject(options: options)
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

    private func createNewProject(options: ProjectCreationOptions) {
        guard !newProjectName.trimmingCharacters(in: .whitespaces).isEmpty,
              let directory = selectedDirectory else { return }

        if projectManager.createProject(name: newProjectName, at: directory, options: options) != nil {
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
    let onCreate: (ProjectCreationOptions) -> Void
    let onCancel: () -> Void

    @State private var isShowingFolderOptions = false
    @State private var creationOptions = ProjectCreationOptions()

    /// 최종 폴더명 (미리보기용)
    private var finalFolderName: String {
        let trimmedName = projectName.trimmingCharacters(in: .whitespaces)
        if trimmedName.isEmpty { return "" }

        return trimmedName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 32))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.get("welcome.newProject"))
                        .font(.headline)
                    Text(L10n.get("welcome.createDescription"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow(alignment: .firstTextBaseline) {
                    Text(L10n.get("welcome.projectName"))
                        .gridColumnAlignment(.trailing)
                    HStack(spacing: 4) {
                        TextField(L10n.get("welcome.projectNamePlaceholder"), text: $projectName)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel(L10n.get("welcome.projectName"))
                    }
                }

                GridRow {
                    Text(L10n.get("welcome.saveLocation"))
                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                        Text(selectedDirectory?.path ?? L10n.get("welcome.noLocationSelected"))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .help(selectedDirectory?.path ?? "")
                        Button(L10n.get("welcome.browse")) { selectDirectory() }
                    }
                }
            }

            DisclosureGroup(isExpanded: $isShowingFolderOptions) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(L10n.get("welcome.includeDefaultFolders"), isOn: $creationOptions.includesDefaultFolders)
                        .toggleStyle(.checkbox)

                    Text(L10n.get("welcome.defaultFoldersDescription"))
                        .font(.callout)
                        .foregroundStyle(.secondary)

                }
                .padding(.top, 8)
                .padding(.bottom, 4)
            } label: {
                Button {
                    isShowingFolderOptions.toggle()
                } label: {
                    Text(L10n.get(isShowingFolderOptions ? "welcome.lessOptions" : "welcome.moreOptions"))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .animation(.easeInOut(duration: 0.2), value: isShowingFolderOptions)

            Divider()

            HStack {
                Text(finalFolderName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 12)
                Button(L10n.common.cancel) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button(L10n.get("welcome.create")) { handleCreate() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid)
            }
        }
        .padding(24)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .presentationSizing(.fitted)
    }

    private var isValid: Bool {
        !projectName.trimmingCharacters(in: .whitespaces).isEmpty && selectedDirectory != nil
    }

    private func handleCreate() {
        onCreate(creationOptions)
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
