import SwiftUI

/// Separate native buttons share a capsule; each retains its own label and hit target.
struct NavigationButtonsView: View {
    let onBack: () -> Void
    let onForward: () -> Void
    var canGoBack = true
    var canGoForward = true

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onBack) {
                Image(systemName: "chevron.left").frame(width: 30, height: 30)
            }
            .disabled(!canGoBack)
            .help(L10n.get("toolbar.goBack"))
            .accessibilityLabel(L10n.get("toolbar.goBack"))
            Button(action: onForward) {
                Image(systemName: "chevron.right").frame(width: 30, height: 30)
            }
            .disabled(!canGoForward)
            .help(L10n.get("toolbar.goForward"))
            .accessibilityLabel(L10n.get("toolbar.goForward"))
        }
        .buttonStyle(.plain)
        .font(.system(size: 12, weight: .medium))
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .contain)
    }
}
