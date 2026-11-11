import ForgeCore
import SwiftUI

/// Create or edit an exercise. `onSaved` receives the exercise id.
struct ExerciseEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    private let original: Exercise?
    private let onSaved: (String) -> Void
    @State private var name: String
    @State private var equipment: String
    @State private var muscle: String
    @State private var tracking: TrackingType

    static let equipmentChoices = ["barbell", "dumbbell", "machine", "cable", "kettlebell", "band", "none", "other"]

    init(exercise: Exercise?, onSaved: @escaping (String) -> Void = { _ in }) {
        original = exercise
        self.onSaved = onSaved
        _name = State(initialValue: exercise?.name ?? "")
        _equipment = State(initialValue: exercise?.equipment ?? "none")
        _muscle = State(initialValue: exercise?.primaryMuscle ?? "other")
        _tracking = State(initialValue: exercise?.tracking ?? .weightReps)
    }

    var body: some View {
        NavigationStack {
            Form {
              Section {
                TextField("Name", text: $name)
                Picker("Equipment", selection: $equipment) {
                    ForEach(Self.equipmentChoices + (Self.equipmentChoices.contains(equipment) ? [] : [equipment]), id: \.self) { Text(Muscles.title($0)).tag($0) }
                }
                Picker("Primary muscle", selection: $muscle) {
                    ForEach(Muscles.all + (Muscles.all.contains(muscle) ? [] : [muscle]), id: \.self) { Text(Muscles.title($0)).tag($0) }
                }
                Picker("Tracks", selection: $tracking) {
                    Text("Weight & reps").tag(TrackingType.weightReps)
                    Text("Reps only").tag(TrackingType.repsOnly)
                    Text("Bodyweight + weight").tag(TrackingType.weightedBodyweight)
                    Text("Assisted bodyweight").tag(TrackingType.assistedBodyweight)
                    Text("Duration").tag(TrackingType.duration)
                    Text("Weight & duration").tag(TrackingType.weightDuration)
                    Text("Distance").tag(TrackingType.distance)
                    Text("Distance & duration").tag(TrackingType.distanceDuration)
                }
              }.listRowBackground(Theme.card)
            }
            .formStyle(.grouped)
            .themedList()
            .navigationTitle(original == nil ? "New Exercise" : "Edit Exercise")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 320)
        #endif
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if var e = original {
            e.name = trimmed; e.equipment = equipment; e.primaryMuscle = muscle; e.tracking = tracking
            model.saveExercise(e)
            onSaved(e.id)
        } else {
            onSaved(model.addExercise(name: trimmed, equipment: equipment, primaryMuscle: muscle, tracking: tracking).id)
        }
        dismiss()
    }
}
