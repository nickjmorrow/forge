import ForgeCore
import SwiftUI

struct RoutineEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    private let isNew: Bool
    @State private var draft: Routine

    init(routine: Routine?) {
        isNew = routine == nil
        _draft = State(initialValue: routine ?? Routine(title: ""))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section { TextField("Routine name", text: $draft.title) }.listRowBackground(Theme.card)
                BlocksEditor(blocks: $draft.exercises)
            }
            .formStyle(.grouped)
            .themedList()
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
