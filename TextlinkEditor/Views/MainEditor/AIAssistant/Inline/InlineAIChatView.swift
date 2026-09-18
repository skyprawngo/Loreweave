import SwiftUI

/// Single-use editing command. Captured manuscript state is private execution data,
/// not a chat transcript or a document attachment shown in the editor.
struct InlineAIChatView: View {
    let projectURL: URL
    let revision: ManuscriptRevision
    let onClose: () -> Void
    @State private var draft = ""
    @State private var shortcuts = KeyboardShortcutManager.shared
    @State private var assistant = AIAssistantViewModel.shared
    @FocusState private var focused: Bool
    @Environment(\.openWindow) private var openWindow

    private var connected: Bool {
        if case .connected = assistant.connectionState { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                TextField(L10n.get("ai.inline.placeholder"), text: $draft, axis: .vertical)
                    .lineLimit(1...3).textFieldStyle(.plain).focused($focused)
                if connected {
                    Button(action: send) { Image(systemName: "arrow.up.circle.fill") }
                        .help(L10n.get("ai.chat.send"))
                        .disabled(assistant.isProcessing || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } else {
                    Button { openWindow(id: "settings") } label: { Image(systemName: "gearshape") }
                        .help(L10n.get("ai.inline.settings"))
                }
                Button(action: onClose) { Image(systemName: "xmark") }
                    .help(L10n.get("common.close"))
                    .keyboardShortcut(shortcuts.binding(for: ShortcutAction(rawValue: "ai.inline"))?.keyboardShortcut)
            }
            .buttonStyle(.borderless)
            if let error = assistant.inlineErrorMessage {
                Text(error).font(.caption).foregroundStyle(.red).lineLimit(2)
            }
        }
        .padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ThemeAwareBackground(material: .sidebar, blendingMode: .withinWindow, tintOpacity: 0.22))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor.opacity(0.35)))
        .onAppear { assistant.inlineErrorMessage = nil; focused = true }
    }

    private func send() {
        guard ProjectManager.shared.currentProject?.path == projectURL else { return }
        let previousCount = assistant.messages.count
        assistant.sendMessage(inlineInput: draft, inlineRevision: revision)
        if assistant.messages.count > previousCount { onClose() }
    }
}
