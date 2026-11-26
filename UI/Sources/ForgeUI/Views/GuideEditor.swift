import ForgeCore
import SwiftUI

/// The editing form for a guide: name and note, then each section with its steps. Reorder mode shows the whole guide as
/// single draggable lines, so a step can move between sections and a section can move with its steps.
struct GuideEditor: View {
    @Binding var draft: Guide
    @State private var reordering = false
    @State private var deletingSection: Int?
    @FocusState private var focus: GuideEdits.Row?

    var body: some View {
        Form {
            Section {
                TextField("Guide name", text: $draft.title)
                TextField("Note, e.g. reps or hold time", text: Binding(get: { draft.notes ?? "" }, set: { draft.notes = $0 }), axis: .vertical)
            }.listRowBackground(Theme.card)
            if GuideEdits.rows(draft).count > 2 {
                Section {
                    Button { focus = nil; reordering.toggle() } label: {
                        Label(reordering ? "Done Reordering" : "Reorder", systemImage: reordering ? "checkmark" : "arrow.up.arrow.down")
                    }
                }.listRowBackground(Theme.card)
            }
            if reordering { reorderList } else { sections }
        }
        .formStyle(.grouped)
        .themedList()
        #if os(iOS)
        .environment(\.editMode, .constant(reordering ? .active : .inactive))     // shows the drag handles
        #endif
        .motion(value: reordering)
        .confirmationDialog("Delete this section and its steps?", isPresented: Binding(get: { deletingSection != nil }, set: { if !$0 { deletingSection = nil } }),
                            titleVisibility: .visible) {
            Button("Delete Section", role: .destructive) { if let s = deletingSection { removeSection(s) } }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var reorderList: some View {
        Section {
            ForEach(GuideEdits.rows(draft), id: \.self) { row in
                switch row {
                case let .section(s):
                    Text(sectionName(s)).font(.headline).foregroundStyle(Theme.text)
                case let .step(s, i):
                    Text(stepName(s, i).wrappedValue.isEmpty ? "Unnamed step" : stepName(s, i).wrappedValue)
                        .foregroundStyle(Theme.dim).padding(.leading, 16)
                }
            }
            .onMove { source, destination in
                if let from = source.first { draft = GuideEdits.move(draft, from: from, to: destination) }
            }
        } footer: {
            Text("Drag a step to move it, into another section if you like. Drag a section name to move the section with its steps.")
        }
        .listRowBackground(Theme.card)
    }

    @ViewBuilder private var sections: some View {
        ForEach(Array(draft.sections.indices), id: \.self) { s in
            Section {
                TextField("Section name (optional)", text: sectionTitle(s)).font(.headline)
                ForEach(Array(draft.sections[s].steps.indices), id: \.self) { i in
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Step", text: stepName(s, i))
                                .focused($focus, equals: .step(section: s, step: i))
                                .onSubmit { if i == draft.sections[s].steps.count - 1, !stepName(s, i).wrappedValue.isEmpty { addStep(to: s) } }
                            TextField("Cue: how to do it (optional)", text: stepCue(s, i), axis: .vertical)
                                .font(.subheadline).foregroundStyle(Theme.dim)
                        }
                        #if os(macOS)
                        Button { removeStep(s, i) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.plain).foregroundStyle(Theme.dim).help("Delete Step").accessibilityLabel("Delete Step")
                        #endif
                    }
                }
                .onDelete { offsets in draft.sections[s].steps.remove(atOffsets: offsets) }
                Button { addStep(to: s) } label: { Label("Add Step", systemImage: "plus") }
                Button(role: .destructive) {
                    if draft.sections[s].steps.contains(where: { !$0.name.isEmpty }) { deletingSection = s } else { removeSection(s) }
                } label: { Label("Delete Section", systemImage: "trash") }
                    .foregroundStyle(Theme.danger)
            }
            .listRowBackground(Theme.card)
        }
        Section {
            Button { draft.sections.append(GuideSection()); addStep(to: draft.sections.count - 1) } label: { Label("Add Section", systemImage: "plus") }
        }.listRowBackground(Theme.card)
    }

    private func addStep(to s: Int) {
        guard draft.sections.indices.contains(s) else { return }
        draft.sections[s].steps.append(GuideStep(name: ""))
        focus = .step(section: s, step: draft.sections[s].steps.count - 1)
    }

    private func removeStep(_ s: Int, _ i: Int) {
        guard has(s, i) else { return }
        focus = nil
        draft.sections[s].steps.remove(at: i)
    }

    private func removeSection(_ s: Int) {
        guard draft.sections.indices.contains(s) else { return }
        focus = nil
        draft.sections.remove(at: s)
    }

    private func sectionName(_ s: Int) -> String {
        guard draft.sections.indices.contains(s) else { return "" }
        return draft.sections[s].title.isEmpty ? "Untitled section" : draft.sections[s].title
    }

    // A row can be asked for its text once more after it has been removed, so these never index out of range.

    private func has(_ s: Int, _ i: Int) -> Bool { draft.sections.indices.contains(s) && draft.sections[s].steps.indices.contains(i) }

    private func sectionTitle(_ s: Int) -> Binding<String> {
        Binding(get: { draft.sections.indices.contains(s) ? draft.sections[s].title : "" },
                set: { if draft.sections.indices.contains(s) { draft.sections[s].title = $0 } })
    }

    private func stepName(_ s: Int, _ i: Int) -> Binding<String> {
        Binding(get: { has(s, i) ? draft.sections[s].steps[i].name : "" }, set: { if has(s, i) { draft.sections[s].steps[i].name = $0 } })
    }

    private func stepCue(_ s: Int, _ i: Int) -> Binding<String> {
        Binding(get: { has(s, i) ? draft.sections[s].steps[i].cue ?? "" : "" }, set: { if has(s, i) { draft.sections[s].steps[i].cue = $0 } })
    }
}
