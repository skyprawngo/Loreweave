import SwiftUI

struct FolderOptionsSheet: View {
    let item: FileSystemItem
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIcon: FolderIcon?
    @State private var saveError: String?

    init(item: FileSystemItem) {
        self.item = item
        _selectedIcon = State(initialValue: item.customFolderIcon.flatMap(FolderIcon.init(rawValue:)))
    }

    private var defaultIcon: String { item.sectionType?.iconName ?? "folder" }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: selectedIcon?.rawValue ?? defaultIcon)
                    .font(.system(size: 32))
                    .foregroundStyle(.tint)
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.get("folderOptions.title")).font(.headline)
                    Text(item.name)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .help(item.name)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.get("folderOptions.icon")).font(.headline)
                Text(L10n.get("folderOptions.description"))
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Button { selectedIcon = nil } label: {
                    Label(L10n.get("folderOptions.defaultIcon"), systemImage: defaultIcon)
                }
                .buttonStyle(.bordered)
                .accessibilityAddTraits(selectedIcon == nil ? .isSelected : [])

                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 8) {
                    ForEach(FolderIcon.allCases) { icon in
                        Button { selectedIcon = icon } label: {
                            Image(systemName: icon.rawValue)
                                .font(.system(size: 20))
                                .frame(maxWidth: .infinity)
                                .frame(height: 40)
                                .foregroundStyle(selectedIcon == icon ? Color.accentColor : Color.primary)
                                .background(selectedIcon == icon ? Color.accentColor.opacity(0.12) : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 8))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(selectedIcon == icon ? Color.accentColor : Color.clear, lineWidth: 2)
                                }
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(icon.title)
                        .accessibilityLabel(icon.title)
                        .accessibilityAddTraits(selectedIcon == icon ? .isSelected : [])
                    }
                }
            }

            Divider()
            HStack {
                Spacer()
                Button(L10n.common.cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L10n.common.save) {
                    do {
                        try FileSystemManager.shared.setFolderIcon(selectedIcon, for: item)
                        dismiss()
                    } catch { saveError = error.localizedDescription }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .presentationSizing(.fitted)
        .alert(L10n.get("storage.operationFailed"), isPresented: Binding(
            get: { saveError != nil }, set: { if !$0 { saveError = nil } }
        )) {
            Button(L10n.common.confirm) { saveError = nil }
        } message: { Text(saveError ?? "") }
    }
}
