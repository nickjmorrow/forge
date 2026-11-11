import ForgeCore
import SwiftUI

/// What changed lately and who changed it, with a one-tap undo for Claude's last change.
struct ChangesView: View {
    @Environment(AppModel.self) private var model
    @State private var changes: [Change] = []
    @State private var message: String?

    private func who(_ a: Author) -> String {
        switch a {
        case .me: return "You"
        case .claude: return "Claude"
        case .importer: return "Import or sync"
        }
    }

    var body: some View {
        List {
            Section {
                Button("Undo Claude's last change") {
                    let result = model.undoClaudeLastChange()
                    message = result.undone > 0 ? "Undone." : (result.skipped.isEmpty ? "Claude has nothing left to undo." : "Skipped: you changed it afterwards, so it was left alone.")
                    load()
                }
            } footer: { Text("Changes Claude makes are labelled and can be undone one at a time. One you edited afterwards is never overwritten.") }
            .listRowBackground(Theme.card)
            Section("Last 14 days") {
                ForEach(changes, id: \.id) { c in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(c.summary).font(.subheadline).lineLimit(3)
                        HStack(spacing: 6) {
                            Text(who(c.author)).foregroundStyle(c.author == .claude ? Theme.accent : Theme.dim)
                            Text("·")
                            Text(Format.date(c.createdAt).formatted(date: .abbreviated, time: .shortened))
                            if c.undone { Text("· undone").foregroundStyle(Theme.dim) }
                            if c.skipped { Text("· undo skipped").foregroundStyle(Theme.dim) }
                        }
                        .font(.caption).foregroundStyle(Theme.dim)
                    }
                }
                if changes.isEmpty { Text("Nothing has changed in the last two weeks.").foregroundStyle(Theme.dim) }
            }.listRowBackground(Theme.card)
        }
        .themedList()
        .navigationTitle("Changes")
        .task { load() }
        .alert("Undo", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") {}
        } message: { Text(message ?? "") }
    }

    private func load() { changes = model.recentChanges() }
}
