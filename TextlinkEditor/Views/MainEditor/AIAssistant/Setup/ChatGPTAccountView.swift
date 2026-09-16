import SwiftUI

struct ChatGPTAccountView: View {
    @Bindable var service: ChatGPTAccountService
    let compact: Bool
    @State private var showingAccount = false

    var body: some View {
        Group {
            if compact {
                Button { showingAccount = true } label: {
                    Image(systemName: "person.crop.circle").frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .help(L10n.get("ai.oauth.manage"))
                .accessibilityLabel(L10n.get("ai.oauth.manage"))
                .popover(isPresented: $showingAccount) { accountContent.frame(width: 300).padding(16) }
            } else { accountContent.padding(20) }
        }
    }

    private var accountContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.get("ai.oauth.title")).font(.headline)
            Text(L10n.get("ai.oauth.description")).font(.caption).foregroundStyle(.secondary)
            if let account = service.account {
                Text(account.email).textSelection(.enabled)
                Text(account.plan.capitalized).font(.caption)
                Button(L10n.get("ai.oauth.checkLimits")) { Task { await service.refreshLimits() } }
                    .disabled(service.isBusy)
                if let limits = service.limits { Text(limits).font(.caption) }
                Button(L10n.get("ai.oauth.logout"), role: .destructive) { Task { await service.logout() } }
                    .disabled(service.isBusy)
            } else if service.loginPending {
                ProgressView().controlSize(.small)
                Text(L10n.get("ai.oauth.waiting")).font(.caption)
                Button(L10n.get("common.cancel")) { service.cancelLogin() }
            } else {
                Button(L10n.get("ai.oauth.login")) { Task { await service.login() } }
                    .buttonStyle(.borderedProminent).disabled(service.isBusy)
                Button(L10n.get("ai.oauth.refresh")) { Task { await service.refresh() } }
                    .disabled(service.isBusy)
            }
            if service.isBusy { ProgressView().controlSize(.small) }
            if let error = service.errorMessage { Text(error).font(.caption).foregroundStyle(.red) }
        }
    }
}
