import SwiftUI

struct AIRevisionPresentation: Identifiable {
    let id = UUID()
    let revision: ManuscriptRevision
    let proposal: String
    let project: URL
    let changes: [ManuscriptRevision.Change]
    init(revision: ManuscriptRevision, proposal: String, project: URL) {
        self.revision = revision; self.proposal = proposal; self.project = project
        self.changes = revision.changes(proposal: proposal)
    }
}

struct AIRevisionView: View {
    let presentation: AIRevisionPresentation
    @Environment(\.dismiss) private var dismiss
    @State private var selected = Set<Int>()
    @State private var error: String?
    private var changes: [ManuscriptRevision.Change] { presentation.changes }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.get("revision.title")).font(.title2)
                Spacer()
                Button(L10n.get("common.close")) { dismiss() }
            }
            Text(presentation.revision.relativePath).foregroundStyle(.secondary)
            Text(L10n.get("revision.explanation")).font(.callout)
            HStack {
                Button(L10n.get("revision.selectAll")) { selected = Set(changes.map(\.id)) }
                Button(L10n.get("revision.rejectAll")) { selected = [] }
            }
            List(changes) { change in
                VStack(alignment: .leading) {
                    Toggle(L10n.get("revision.accept"), isOn: Binding(get: { selected.contains(change.id) }, set: {
                        if $0 { selected.insert(change.id) } else { selected.remove(change.id) }
                    }))
                    HStack(alignment: .top, spacing: 20) {
                        VStack(alignment: .leading) {
                            Text(L10n.get("revision.original")).font(.caption).foregroundStyle(.secondary)
                            Text(change.before).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        VStack(alignment: .leading) {
                            Text(L10n.get("revision.proposed")).font(.caption).foregroundStyle(.secondary)
                            Text(change.after).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }.padding(.vertical, 8)
            }
            if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Spacer()
                Button(L10n.get("revision.apply")) {
                    do {
                        try ManuscriptRevisionBridge.apply(presentation.revision, proposal: presentation.proposal,
                            selected: selected, project: presentation.project)
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }.disabled(selected.isEmpty).keyboardShortcut(.defaultAction)
            }
        }.padding(20).frame(minWidth: 760, minHeight: 520)
    }
}
