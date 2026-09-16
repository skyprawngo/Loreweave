import SwiftUI

/// Standard macOS buttons retain native hover, pressed, and disabled appearances.
struct NavigationButtonsView: View {
    let onBack: () -> Void
    let onForward: () -> Void
    var canGoBack = true
    var canGoForward = true

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onBack) {
                Label(L10n.get("toolbar.goBack"), systemImage: "chevron.left")
            }
            .disabled(!canGoBack)
            .help(L10n.get("toolbar.goBack"))
            .accessibilityLabel(L10n.get("toolbar.goBack"))
            Button(action: onForward) {
                Label(L10n.get("toolbar.goForward"), systemImage: "chevron.right")
            }
            .disabled(!canGoForward)
            .help(L10n.get("toolbar.goForward"))
            .accessibilityLabel(L10n.get("toolbar.goForward"))
        }
        .buttonStyle(.bordered)
        .labelStyle(.iconOnly)
        .controlSize(.regular)
        .accessibilityElement(children: .contain)
    }
}
