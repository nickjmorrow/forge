import ForgeCore
import SwiftUI

/// Edits a list of exercises with their sets: used for routines (planned sets) and for past workouts (logged sets).
/// Place it inside a `Form`; it contributes the exercise sections and an "Add Exercise" row.
struct BlocksEditor: View {
    @Environment(AppModel.self) private var model
    @Binding var blocks: [ExerciseBlock]
    var showsRest = true
    var showsCompletion = false
    @State private var showPicker = false
    /// The exercise an alternative is being picked for.
    @State private var alternativeFor: Int?
    @State private var revision = 0

    private func tracking(_ id: String) -> TrackingType { model.exercises.first { $0.id == id }?.tracking ?? .weightReps }

    var body: some View {
        Group {
            ForEach(Array(blocks.indices), id: \.self) { i in
                if blocks.indices.contains(i) { blockSection(i) }
            }
            Section {
                // The sheet hangs off this one button: on the Group it would be attached to every section, and two sheets
                // presenting at once close the whole editor.
                Button { showPicker = true } label: { Label("Add Exercise", systemImage: "plus") }
                    .sheet(isPresented: $showPicker) {
                        ExercisePickerView { id in
                            blocks.append(ExerciseBlock(exerciseID: id, restSeconds: 90, sets: showsCompletion ? [SetEntry(completed: true)] : [SetEntry(), SetEntry(), SetEntry()]))
                            revision += 1
                        }
                    }
            }.listRowBackground(Theme.card)
        }
        .id(revision)
    }

    @ViewBuilder private func blockSection(_ i: Int) -> some View {
        let trackingType = tracking(blocks[i].exerciseID)
        Section {
            if showsRest {
                Picker("Rest", selection: $blocks[i].restSeconds) {
                    ForEach(RestOptions.choices, id: \.self) { Text(RestOptions.label(for: $0, defaultSeconds: model.defaultRestSeconds)).tag($0) }
                }
                if Progression.applies(to: trackingType) {
                    Picker("Progress in", selection: $blocks[i].progression) {
                        ForEach(RepRangeOptions.choices, id: \.self) { Text(RepRangeOptions.label(for: $0)).tag($0) }
                    }
                }
            }
            if showsRest {
                ForEach(blocks[i].alternatives ?? [], id: \.self) { id in
                    HStack {
                        Text("or").foregroundStyle(Theme.dim)
                        Text(model.name(for: id))
                        Spacer()
                        Button("Remove \(model.name(for: id)) as an alternative", systemImage: "minus.circle") { removeAlternative(i, id) }
                            .labelStyle(.iconOnly).buttonStyle(.borderless).foregroundStyle(Theme.dim)
                    }
                }
            }
            ForEach(Array(blocks[i].sets.indices), id: \.self) { j in
                if blocks[i].sets.indices.contains(j) { setRow(i, j, trackingType) }
            }
            Button {
                var next = blocks[i].sets.last ?? SetEntry()
                if showsCompletion { next.completed = true }
                blocks[i].sets.append(next)
                revision += 1
            } label: { Label("Add Set", systemImage: "plus") }
        } header: {
            HStack {
                Text(model.name(for: blocks[i].exerciseID))
                Spacer()
                Menu {
                    if showsRest { Button("Add Alternative", systemImage: "arrow.triangle.branch") { alternativeFor = i } }
                    Button("Move Up", systemImage: "arrow.up") { move(i, by: -1) }.disabled(i == 0)
                    Button("Move Down", systemImage: "arrow.down") { move(i, by: 1) }.disabled(i == blocks.count - 1)
                    Button("Remove", systemImage: "trash", role: .destructive) { blocks.remove(at: i); revision += 1 }
                } label: { Image(systemName: "ellipsis.circle") }
            }
            // On this exercise's own header (the list is lazy, so a row further down may not exist to present from), and only
            // for this exercise, so one sheet presents.
            .sheet(isPresented: Binding(get: { alternativeFor == i }, set: { if !$0 { alternativeFor = nil } })) {
                ExercisePickerView { id in
                    guard blocks.indices.contains(i), id != blocks[i].exerciseID, !(blocks[i].alternatives ?? []).contains(id) else { return }
                    blocks[i].alternatives = (blocks[i].alternatives ?? []) + [id]
                    revision += 1
                }
            }
        }.listRowBackground(Theme.card)
    }

    private func setRow(_ i: Int, _ j: Int, _ trackingType: TrackingType) -> some View {
        HStack(spacing: 8) {
            Menu {
                ForEach([SetType.normal, .warmup, .failure, .drop], id: \.self) { t in
                    Button(t.rawValue.capitalized) { blocks[i].sets[j].type = t; revision += 1 }
                }
                Button("Delete Set", role: .destructive) { blocks[i].sets.remove(at: j); revision += 1 }
            } label: {
                Text(blocks[i].sets[j].type == .normal ? "\(j + 1)" : String(blocks[i].sets[j].type.rawValue.first!).uppercased()).frame(width: 30)
            }
            Spacer()
            ForEach(trackingType.columns, id: \.self) { column in
                ValueField(placeholder: column.title(unit: model.unit, tracking: trackingType),
                           initial: column.text(of: blocks[i].sets[j], unit: model.unit)) { text in
                    guard blocks.indices.contains(i), blocks[i].sets.indices.contains(j) else { return }
                    column.apply(text, to: &blocks[i].sets[j], unit: model.unit)
                }
                .frame(width: 70)
            }
            if showsCompletion {
                Image(systemName: blocks[i].sets[j].completed ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(blocks[i].sets[j].completed ? Theme.done : Theme.dim)
                    .onTapGesture { blocks[i].sets[j].completed.toggle(); revision += 1 }
            }
        }
        .swipeActions(edge: .trailing) {
            Button("Delete", systemImage: "trash", role: .destructive) { blocks[i].sets.remove(at: j); revision += 1 }
        }
    }

    private func removeAlternative(_ i: Int, _ id: String) {
        let rest = (blocks[i].alternatives ?? []).filter { $0 != id }
        blocks[i].alternatives = rest.isEmpty ? nil : rest
        revision += 1
    }

    private func move(_ i: Int, by delta: Int) {
        let to = i + delta
        guard blocks.indices.contains(to) else { return }
        blocks.insert(blocks.remove(at: i), at: to)
        revision += 1
    }
}
