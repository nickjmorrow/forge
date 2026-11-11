import Charts
import ForgeCore
import SwiftUI

struct ExerciseDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let exerciseID: String
    @State private var sessions: [ExerciseSession] = []
    @State private var records = PersonalRecords()
    @State private var showEdit = false
    @State private var showMerge = false
    @State private var mergeTarget: Exercise?
    @State private var confirmDelete = false
    @State private var error: String?

    private var exercise: Exercise? { model.exercises.first { $0.id == exerciseID } }

    private struct Point: Identifiable { let date: Date; let value: Double; var id: Date { date } }

    private var points: [Point] {
        sessions.reversed().compactMap { s in
            let best = s.sets.filter { $0.type != .warmup }.compactMap { set -> Double? in
                guard let w = set.weightKg, let r = set.reps, r > 0 else { return nil }
                return e1RM(weightKg: w, reps: r)
            }.max()
            return best.map { Point(date: Format.date(s.startedAt), value: model.unit == .lb ? Units.pounds(fromKg: $0) : $0) }
        }
    }

    var body: some View {
        Group {
            if let exercise {
                List {
                    Section("Records") {
                        LabeledContent("Heaviest", value: Units.format(kg: records.heaviestKg, unit: model.unit).nonEmpty.map { "\($0) \(model.unit.rawValue)" } ?? "–")
                        LabeledContent("Estimated 1-rep max", value: Units.format(kg: records.bestE1RMKg, unit: model.unit).nonEmpty.map { "\($0) \(model.unit.rawValue)" } ?? "–")
                        LabeledContent("Best set volume", value: Units.format(kg: records.bestSetVolumeKg, unit: model.unit).nonEmpty.map { "\($0) \(model.unit.rawValue)" } ?? "–")
                    }.listRowBackground(Theme.card)
                    if points.count > 1 {
                        Section("Estimated 1-rep max") {
                            Chart(points) {
                                LineMark(x: .value("Date", $0.date), y: .value("e1RM", $0.value)).foregroundStyle(Theme.accent)
                                PointMark(x: .value("Date", $0.date), y: .value("e1RM", $0.value)).foregroundStyle(Theme.accent)
                            }
                            .chartYScale(domain: .automatic(includesZero: false))
                            .frame(height: 180)
                        }.listRowBackground(Theme.card)
                    }
                    Section("History") {
                        if sessions.isEmpty { Text("No completed sets yet.").foregroundStyle(Theme.dim) }
                        ForEach(sessions, id: \.workoutID) { s in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(Format.date(s.startedAt).formatted(date: .abbreviated, time: .omitted)).font(.subheadline.weight(.semibold))
                                Text(s.sets.map { SetFormat.describe($0, tracking: exercise.tracking, unit: model.unit) }.joined(separator: "   "))
                                    .font(.footnote).foregroundStyle(Theme.dim)
                            }
                        }
                    }.listRowBackground(Theme.card)
                }
                .themedList()
            .navigationTitle(exercise.name)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button("Edit", systemImage: "pencil") { showEdit = true }
                            Button("Merge into…", systemImage: "arrow.triangle.merge") { showMerge = true }
                            Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
                        } label: { Image(systemName: "ellipsis.circle") }
                    }
                }
                .sheet(isPresented: $showEdit) { ExerciseEditorView(exercise: exercise) }
                .sheet(isPresented: $showMerge) {
                    ExercisePickerView { id in mergeTarget = model.exercises.first { $0.id == id && $0.id != exerciseID } }
                }
                .alert("Merge \(exercise.name)?", isPresented: Binding(get: { mergeTarget != nil }, set: { if !$0 { mergeTarget = nil } })) {
                    Button("Merge", role: .destructive) { merge(into: mergeTarget) }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Its history and routine entries move to \(mergeTarget?.name ?? "the other exercise"), then \(exercise.name) is deleted.")
                }
                .confirmationDialog(deleteTitle(exercise), isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Delete", role: .destructive) { delete(force: false) }
                    Button("Cancel", role: .cancel) {}
                }
                .alert("Can't delete", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                    Button("Delete everywhere", role: .destructive) { delete(force: true) }
                    Button("Cancel", role: .cancel) {}
                } message: { Text(error ?? "") }
            } else {
                ContentUnavailableView("Exercise not found", systemImage: "questionmark.circle")
            }
        }
        .task(id: model.workouts.count) { load() }
        .task(id: exercise?.updatedAt) { load() }
    }

    private func deleteTitle(_ e: Exercise) -> String { "Delete \(e.name)?" }

    private func load() {
        sessions = (try? model.forge.exerciseHistory(exerciseID: exerciseID, limit: 200)) ?? []
        records = (try? model.forge.personalRecords(exerciseID: exerciseID)) ?? PersonalRecords()
    }

    private func merge(into target: Exercise?) {
        guard let target else { return }
        do { try model.deleteExercise(id: exerciseID, mergeInto: target.id, force: false); dismiss() } catch { self.error = "\(error)" }
    }

    private func delete(force: Bool) {
        do { try model.deleteExercise(id: exerciseID, mergeInto: nil, force: force); dismiss() } catch {
            self.error = ((error as? ForgeError)?.message ?? "\(error)") + "\n\nDeleting anyway removes it from those routines and workouts."
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
