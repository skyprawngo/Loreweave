//
//  SettingsView.swift
//  Loreweave
//
//  MainEditorView와 동일한 NavigationSplitView 구조 사용
//

import SwiftUI

// MARK: - Settings Tab Enum

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case ai
    case editor
    case shortcuts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return L10n.get("settings.general")
        case .ai: return L10n.get("settings.ai")
        case .editor: return L10n.sidebar.editor
        case .shortcuts: return L10n.get("settings.shortcuts")
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .ai: return "sparkles"
        case .editor: return "doc.text"
        case .shortcuts: return "keyboard"
        }
    }
}

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, selection: $selectedTab) { tab in
                Label(tab.title, systemImage: tab.icon)
                    .tag(tab)
            }
            .navigationSplitViewColumnWidth(200)
            .listStyle(.sidebar)
        } detail: {
            switch selectedTab {
            case .general:
                GeneralSettingsView()
            case .ai:
                AISettingsView()
            case .editor:
                EditorSettingsView()
            case .shortcuts:
                ShortcutsSettingsView()
            }
        }
        .navigationSplitViewStyle(.prominentDetail)
        .frame(minWidth: 600, minHeight: 400)
        .background(ThemeAwareBackground(material: .contentBackground, blendingMode: .behindWindow))
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @State private var selectedLanguage = LocalizationManager.shared.currentLanguage
    @State private var launchBehavior = UserSettings.shared.appLaunchBehavior
    @State private var appTheme = UserSettings.shared.appTheme
    @State private var permissionManager = PermissionManager.shared
    @State private var projectManager = ProjectManager.shared

    /// 테마 변경 다이얼로그 표시 여부
    @State private var showThemeChangeDialog = false
    /// 선택된 새 테마 (다이얼로그 표시용)
    @State private var pendingTheme: AppTheme?

    /// 저장된 테마가 현재 적용된 테마와 다른지 확인
    private var themeWillChangeOnRestart: Bool {
        appTheme != ThemeManager.shared.appliedTheme
    }

    var body: some View {
        Form {
            // 언어 및 테마 설정
            Section {
                Picker(L10n.get("settings.language"), selection: $selectedLanguage) {
                    ForEach(LocalizationManager.Language.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .onChange(of: selectedLanguage) { _, newValue in
                    LocalizationManager.shared.currentLanguage = newValue
                }

                // 테마 설정
                VStack(alignment: .leading, spacing: 4) {
                    Picker(L10n.get("settings.theme"), selection: $appTheme) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.displayName).tag(theme)
                        }
                    }
                    .onChange(of: appTheme) { oldValue, newValue in
                        // 현재 적용된 테마와 다른 테마를 선택한 경우 다이얼로그 표시
                        if newValue != ThemeManager.shared.appliedTheme {
                            pendingTheme = newValue
                            showThemeChangeDialog = true
                        }
                    }

                    // 재시작 안내 문구
                    if themeWillChangeOnRestart {
                        Text(L10n.get("settings.theme.willApplyOnRestart"))
                            .font(.caption)
                            .foregroundStyle(AppColors.accent)
                    }
                }
                .alert(L10n.get("settings.theme.changeTitle"), isPresented: $showThemeChangeDialog) {
                    Button(L10n.common.cancel, role: .cancel) {
                        // 테마 설정 저장 (다음 재시작 시 적용)
                        if let theme = pendingTheme {
                            UserSettings.shared.appTheme = theme
                        }
                        pendingTheme = nil
                    }
                    Button(L10n.get("settings.theme.quit"), role: .destructive) {
                        // 테마 설정 저장 후 앱 종료
                        if let theme = pendingTheme {
                            UserSettings.shared.appTheme = theme
                        }
                        pendingTheme = nil
                        NSApplication.shared.terminate(nil)
                    }
                } message: {
                    Text(L10n.get("settings.theme.changeMessage"))
                }

                // 시작 동작 설정
                Picker(L10n.get("settings.launch.title"), selection: $launchBehavior) {
                    ForEach(AppLaunchBehavior.allCases) { behavior in
                        Text(behavior.displayName).tag(behavior)
                    }
                }
                .onChange(of: launchBehavior) { _, newValue in
                    UserSettings.shared.appLaunchBehavior = newValue
                }
            }

            // 폴더 접근 권한
            Section {
                if permissionManager.authorizedDirectories.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "folder.badge.questionmark")
                                .font(.system(size: 28))
                                .foregroundStyle(AppColors.toolbarIcon)
                            Text(L10n.get("settings.permissions.noFolders"))
                                .font(.caption)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                        .padding(.vertical, 16)
                        Spacer()
                    }
                } else {
                    ForEach(permissionManager.authorizedDirectories) { directory in
                        HStack(spacing: 10) {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(AppColors.accent)
                                .frame(width: 20)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(directory.displayName)
                                    .font(.body)
                                Text(directory.path)
                                    .font(.caption)
                                    .foregroundStyle(AppColors.textTertiary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }

                            Spacer()

                            Button {
                                permissionManager.removeDirectoryAccess(directory)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(AppColors.toolbarIcon)
                            }
                            .buttonStyle(.plain)
                            .help(L10n.common.delete)
                        }
                    }
                }

                Button {
                    permissionManager.addDirectoryAccess()
                } label: {
                    Label(L10n.get("settings.permissions.addFolder"), systemImage: "plus")
                }
            } header: {
                Text(L10n.get("settings.permissions.title"))
            } footer: {
                Text(L10n.get("settings.permissions.description"))
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - AI Settings

struct AISettingsView: View {
    @State private var openAIKey: String = ""
    @State private var claudeKey: String = ""
    @State private var selectedProvider: String = "claude"

    var body: some View {
        Form {
            // AI 제공자 설정
            Section {
                Picker(L10n.get("settings.aiProvider"), selection: $selectedProvider) {
                    Text("Claude").tag("claude")
                    Text("OpenAI").tag("openai")
                }
            }

            // API 키 설정
            Section {
                SecureField("Claude API Key", text: $claudeKey)
                    .textFieldStyle(.roundedBorder)
                SecureField("OpenAI API Key", text: $openAIKey)
                    .textFieldStyle(.roundedBorder)
            } header: {
                Text("API Keys")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Editor Settings

struct EditorSettingsView: View {
    @State private var fontSize: Double = 16
    @State private var lineSpacing: Double = 8
    @State private var autoSave: Bool = true

    var body: some View {
        Form {
            // 글꼴 설정
            Section {
                HStack {
                    Text(L10n.editor.fontSize)
                    Slider(value: $fontSize, in: 12...24, step: 1)
                        .frame(width: 150)
                    Text("\(Int(fontSize))pt")
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(width: 40, alignment: .trailing)
                }

                HStack {
                    Text(L10n.editor.lineSpacing)
                    Slider(value: $lineSpacing, in: 4...16, step: 2)
                        .frame(width: 150)
                    Text("\(Int(lineSpacing))pt")
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(width: 40, alignment: .trailing)
                }

                Toggle(L10n.get("settings.autoSave"), isOn: $autoSave)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Shortcuts Settings

/// 단축키 테이블 열 ID
enum ShortcutColumnID: String {
    case action = "action"
    case category = "category"
    case shortcut = "shortcut"
    case toggle = "toggle"
}

struct ShortcutsSettingsView: View {
    @State private var shortcutManager = KeyboardShortcutManager.shared
    @State private var searchText: String = ""
    @State private var selectedCategory: ShortcutCategory? = nil
    @State private var editingBinding: ShortcutBinding? = nil

    // 열 가시성 상태
    @SceneStorage("shortcuts.column.action") private var showActionColumn = true
    @SceneStorage("shortcuts.column.category") private var showCategoryColumn = true
    @SceneStorage("shortcuts.column.shortcut") private var showShortcutColumn = true
    @SceneStorage("shortcuts.column.toggle") private var showToggleColumn = true

    /// 필터링된 바인딩 목록
    private var filteredBindings: [ShortcutBinding] {
        var bindings = shortcutManager.bindings

        // 카테고리 필터
        if let category = selectedCategory {
            bindings = bindings.filter { $0.action.category == category }
        }

        // 검색어 필터
        if !searchText.isEmpty {
            bindings = bindings.filter {
                $0.action.displayName.localizedCaseInsensitiveContains(searchText) ||
                $0.displayString.localizedCaseInsensitiveContains(searchText)
            }
        }

        return bindings
    }

    var body: some View {
        VStack(spacing: 0) {
            // 툴바
            shortcutsToolbar

            Divider()

            // 테이블
            shortcutsTable
        }
        .sheet(item: $editingBinding) { binding in
            ShortcutEditSheet(binding: binding) { updatedBinding in
                shortcutManager.updateBinding(updatedBinding)
            }
        }
    }

    // MARK: - Toolbar

    private var shortcutsToolbar: some View {
        HStack(spacing: 12) {
            // 검색
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AppColors.toolbarIcon)
                TextField(L10n.get("settings.shortcuts.search"), text: $searchText)
                    .textFieldStyle(.plain)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(AppColors.toolbarIcon)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .background(AppColors.controlBackground)
            .cornerRadius(6)
            .frame(maxWidth: 200)

            // 카테고리 필터
            Picker("", selection: $selectedCategory) {
                Text(L10n.get("settings.shortcuts.allCategories"))
                    .tag(nil as ShortcutCategory?)

                Divider()

                ForEach(ShortcutCategory.allCases) { category in
                    Text(category.displayName).tag(category as ShortcutCategory?)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 120)

            Spacer()

            // 열 표시/숨기기 메뉴
            Menu {
                Toggle(L10n.get("settings.shortcuts.action"), isOn: $showActionColumn)
                Toggle(L10n.get("settings.shortcuts.category"), isOn: $showCategoryColumn)
                Toggle(L10n.get("settings.shortcuts.shortcut"), isOn: $showShortcutColumn)
                Toggle(L10n.get("settings.shortcuts.toggle"), isOn: $showToggleColumn)

                Divider()

                Button(L10n.get("settings.shortcuts.showAllColumns")) {
                    showActionColumn = true
                    showCategoryColumn = true
                    showShortcutColumn = true
                    showToggleColumn = true
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 30)
            .help(L10n.get("settings.shortcuts.columnVisibility"))

            // 기본값으로 초기화
            Button {
                shortcutManager.resetToDefaults()
            } label: {
                Text(L10n.get("settings.shortcuts.resetAll"))
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - Table

    private var shortcutsTable: some View {
        Table(filteredBindings) {
            // 액션 이름 열
            if showActionColumn {
                TableColumn(L10n.get("settings.shortcuts.action")) { binding in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(binding.isEnabled ? AppColors.savedIndicator : AppColors.textTertiary)
                            .frame(width: 8, height: 8)

                        Text(binding.action.displayName)
                            .lineLimit(1)
                    }
                }
                .width(min: 100, ideal: 180, max: 300)
            }

            // 카테고리 열
            if showCategoryColumn {
                TableColumn(L10n.get("settings.shortcuts.category")) { binding in
                    Text(binding.action.category.displayName)
                        .foregroundStyle(AppColors.textSecondary)
                        .font(.caption)
                }
                .width(min: 60, ideal: 80, max: 120)
            }

            // 단축키 열
            if showShortcutColumn {
                TableColumn(L10n.get("settings.shortcuts.shortcut")) { binding in
                    HStack {
                        if binding.isEnabled || binding.action.isSystemDefault {
                            Text(binding.displayString)
                                .font(.system(.body, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AppColors.controlBackground)
                                .cornerRadius(4)
                        } else {
                            Text("-")
                                .foregroundStyle(AppColors.textTertiary)
                        }

                        Spacer()

                        // 편집 버튼 (시스템 기본 아닌 경우에만)
                        if !binding.action.isSystemDefault {
                            Button {
                                editingBinding = binding
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(AppColors.toolbarIcon)
                        }
                    }
                }
                .width(min: 100, ideal: 160, max: 250)
            }

            // 활성화 토글 열
            if showToggleColumn {
                TableColumn(L10n.get("settings.shortcuts.toggle")) { binding in
                    if binding.action.isSystemDefault {
                        // 시스템 기본 기능 표시
                        Text(L10n.get("settings.shortcuts.systemDefault"))
                            .font(.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    } else {
                        Toggle("", isOn: Binding(
                            get: { binding.isEnabled },
                            set: { _ in
                                shortcutManager.toggleEnabled(for: binding.action)
                            }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    }
                }
                .width(min: 70, ideal: 90, max: 130)
            }
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
    }
}

// MARK: - Shortcut Edit Sheet

struct ShortcutEditSheet: View {
    let binding: ShortcutBinding
    let onSave: (ShortcutBinding) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var shortcutManager = KeyboardShortcutManager.shared

    @State private var key: String
    @State private var useCommand: Bool
    @State private var useShift: Bool
    @State private var useOption: Bool
    @State private var useControl: Bool
    @State private var conflictBinding: ShortcutBinding? = nil

    init(binding: ShortcutBinding, onSave: @escaping (ShortcutBinding) -> Void) {
        self.binding = binding
        self.onSave = onSave

        _key = State(initialValue: binding.key)
        _useCommand = State(initialValue: binding.modifiers.contains(.command))
        _useShift = State(initialValue: binding.modifiers.contains(.shift))
        _useOption = State(initialValue: binding.modifiers.contains(.option))
        _useControl = State(initialValue: binding.modifiers.contains(.control))
    }

    private var currentModifiers: ModifierKeys {
        var modifiers: ModifierKeys = []
        if useCommand { modifiers.insert(.command) }
        if useShift { modifiers.insert(.shift) }
        if useOption { modifiers.insert(.option) }
        if useControl { modifiers.insert(.control) }
        return modifiers
    }

    private var previewString: String {
        let keyDisplay = key.isEmpty ? "?" : (key.count == 1 ? key.uppercased() : key.capitalized)
        return "\(currentModifiers.displayString)\(keyDisplay)"
    }

    var body: some View {
        VStack(spacing: 20) {
            // 헤더
            Text(L10n.get("settings.shortcuts.editTitle"))
                .font(.headline)

            Text(binding.action.displayName)
                .foregroundStyle(AppColors.textSecondary)

            Divider()

            // 단축키 미리보기
            Text(previewString)
                .font(.system(size: 24, weight: .medium, design: .monospaced))
                .padding()
                .background(AppColors.controlBackground)
                .cornerRadius(8)

            // 충돌 경고
            if let conflict = conflictBinding {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(AppColors.warningIndicator)
                    Text(String(format: L10n.get("settings.shortcuts.conflict"), conflict.action.displayName))
                        .foregroundStyle(AppColors.textSecondary)
                        .font(.caption)
                }
            }

            // 키 입력
            HStack {
                Text(L10n.get("settings.shortcuts.key"))
                    .frame(width: 80, alignment: .trailing)

                TextField("", text: $key)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                    .onChange(of: key) { _, newValue in
                        checkConflict()
                    }
            }

            // 수정자 키
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.get("settings.shortcuts.modifiers"))
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)

                HStack(spacing: 16) {
                    Toggle("⌘ Command", isOn: $useCommand)
                        .onChange(of: useCommand) { _, _ in checkConflict() }
                    Toggle("⇧ Shift", isOn: $useShift)
                        .onChange(of: useShift) { _, _ in checkConflict() }
                }

                HStack(spacing: 16) {
                    Toggle("⌥ Option", isOn: $useOption)
                        .onChange(of: useOption) { _, _ in checkConflict() }
                    Toggle("⌃ Control", isOn: $useControl)
                        .onChange(of: useControl) { _, _ in checkConflict() }
                }
            }
            .toggleStyle(.checkbox)

            Divider()

            // 버튼
            HStack {
                Button(L10n.get("settings.shortcuts.resetToDefault")) {
                    shortcutManager.resetToDefault(for: binding.action)
                    dismiss()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(L10n.common.cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(L10n.common.save) {
                    var updatedBinding = binding
                    updatedBinding.key = key
                    updatedBinding.modifiers = currentModifiers
                    onSave(updatedBinding)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(key.isEmpty || conflictBinding != nil)
            }
        }
        .padding(24)
        .frame(width: 400)
        .onAppear {
            checkConflict()
        }
    }

    private func checkConflict() {
        conflictBinding = shortcutManager.findConflict(
            key: key,
            modifiers: currentModifiers,
            excluding: binding.action
        )
    }
}

#Preview("앱 설정") {
    SettingsView()
}
