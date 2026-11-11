import ForgeCore
import SwiftUI

/// Fix up a past workout: title, notes, times, exercises and sets.
struct WorkoutEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Workout
    @State private var started: Date
    @State private var ended: Date
    @State private var hasEnd: Bool
    private let isNew: Bool

    init(workout: Workout, isNew: Bool = false) {
        self.isNew = isNew
        _draft = State(initialValue: workout)
        _started = State(initialValue: Format.date(workout.startedAt))
        _ended = State(initialValue: Format.date(workout.endedAt ?? workout.startedAt + 3_600_000))
        _hasEnd = State(initialValue: workout.endedAt != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $draft.title)
                    DatePicker("Started", selection: $started)
                    Toggle("Has an end time", isOn: $hasEnd)
                    if hasEnd { DatePicker("Ended", selection: $ended, in: started...) }
                    TextField("Notes", text: Binding(get: { draft.notes ?? "" }, set: { draft.notes = $0.isEmpty ? nil : $0 }), axis: .vertical)
                }.listRowBackground(Theme.card)
                BlocksEditor(blocks: $draft.exercises, showsRest: false, showsCompletion: true)
            }
            .formStyle(.grouped)
            .themedList()
            .navigationTitle(isNew ? "Log Workout" : "Edit Workout")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        draft.startedAt = Int64(started.timeIntervalSince1970 * 1000)
                        draft.endedAt = hasEnd ? Int64(ended.timeIntervalSince1970 * 1000) : nil
                        model.saveWorkout(draft)
                        dismiss()
                    }
                    .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 620)
        #endif
    }
}
