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
        container {
            Section {
                field("Guide name", text: $draft.title).font(.headline)
                field("Note, e.g. reps or hold time", text: Binding(get: { draft.notes ?? "" }, set: { draft.notes = $0 }), axis: .vertical)
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

    /// A grouped form on the phone. On the Mac a list, where rows can be dragged to reorder (as the routine screen does).
    @ViewBuilder private func container<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        #if os(macOS)
        List { content() }.listStyle(.inset)
        #else
        Form { content() }.formStyle(.grouped)
        #endif
    }

    /// A text field whose description is a placeholder inside it, never a label beside it.
    private func field(_ prompt: String, text: Binding<String>, axis: Axis = .horizontal) -> some View {
        TextField("", text: text, prompt: Text(prompt).foregroundStyle(Theme.faint), axis: axis)
            .labelsHidden()
            .accessibilityLabel(prompt)
            #if os(macOS)
            .textFieldStyle(.plain)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.field))
            #endif
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
                field("Section name (optional)", text: sectionTitle(s)).font(.headline)
                ForEach(Array(draft.sections[s].steps.indices), id: \.self) { i in
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            field("Step", text: stepName(s, i))
                                .focused($focus, equals: .step(section: s, step: i))
                                .onSubmit { if i == draft.sections[s].steps.count - 1, !stepName(s, i).wrappedValue.isEmpty { addStep(to: s) } }
                            field("Cue: how to do it (optional)", text: stepCue(s, i), axis: .vertical)
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

extension View {
    /// Asked when Save would overwrite a change made elsewhere, or bring back a guide deleted elsewhere, while this draft was open.
    func guideSaveConflict(_ conflict: Binding<GuideEdits.SaveAction?>, saveAnyway: @escaping () -> Void, discard: @escaping () -> Void) -> some View {
        let deleted = conflict.wrappedValue == .deletedElsewhere
        return confirmationDialog(deleted ? "This guide was deleted while you were editing" : "This guide was changed while you were editing",
                                  isPresented: Binding(get: { conflict.wrappedValue != nil }, set: { if !$0 { conflict.wrappedValue = nil } }),
                                  titleVisibility: .visible) {
            Button(deleted ? "Save It Anyway" : "Replace With My Version", role: .destructive, action: saveAnyway)
            Button("Discard My Edits", action: discard)
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text(deleted ? "It was deleted on another device or by Claude. Saving brings it back with your edits."
                         : "Another device or Claude saved a newer version. Saving yours replaces it everywhere.")
        }
    }
}
