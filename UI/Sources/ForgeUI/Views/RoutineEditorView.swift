import ForgeCore
import SwiftUI

struct RoutineEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    private let isNew: Bool
    @State private var draft: Routine
    /// Reordering shows each exercise as one draggable line; the sets come back when it ends.
    @State private var reordering = false

    init(routine: Routine?) {
        isNew = routine == nil
        _draft = State(initialValue: routine ?? Routine(title: ""))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section { TextField("Routine name", text: $draft.title) }.listRowBackground(Theme.card)
                if draft.exercises.count > 1 {
                    Section {
                        Button { reordering.toggle() } label: {
                            Label(reordering ? "Done Reordering" : "Reorder Exercises", systemImage: reordering ? "checkmark" : "arrow.up.arrow.down")
                        }
                    }.listRowBackground(Theme.card)
                }
                if reordering {
                    Section {
                        ForEach(Array(draft.exercises.indices), id: \.self) { i in
                            HStack {
                                Text(model.name(for: draft.exercises[i].exerciseID)).foregroundStyle(Theme.text)
                                Spacer(minLength: 8)
                                Text(RoutineMath.sets(draft.exercises[i].sets.count)).font(.subheadline).foregroundStyle(Theme.dim)
                            }
                        }
                        .onMove { source, destination in draft.exercises.move(fromOffsets: source, toOffset: destination) }
                    }.listRowBackground(Theme.card)
                } else {
                    BlocksEditor(blocks: $draft.exercises)
                }
            }
            .formStyle(.grouped)
            .themedList()
            #if os(iOS)
            .environment(\.editMode, .constant(reordering ? .active : .inactive))     // shows the drag handles
            #endif
            .motion(value: reordering)
            .navigationTitle(isNew ? "New Routine" : "Edit Routine")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if isNew { draft.position = model.routines.count }
                        model.saveRoutine(draft)
                        dismiss()
                    }
                    .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 560)
        #endif
    }
}

enum RoutineMath {
    /// "6 exercises · 18 sets"
    static func summary(_ r: Routine) -> String {
        "\(r.exercises.count) \(r.exercises.count == 1 ? "exercise" : "exercises") · \(sets(r.exercises.reduce(0) { $0 + $1.sets.count }))"
    }

    /// "1 set", "4 sets"
    static func sets(_ count: Int) -> String { "\(count) \(count == 1 ? "set" : "sets")" }
}
