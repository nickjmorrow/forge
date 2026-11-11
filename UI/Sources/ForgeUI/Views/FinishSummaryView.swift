import ForgeCore
import SwiftUI

struct FinishSummaryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let summary: FinishSummary

    private var workout: Workout? { model.workouts.first { $0.id == summary.workoutID } }

    private var durationSeconds: Int {
        guard let workout, let end = workout.endedAt else { return summary.durationSeconds }
        return Int((end - workout.startedAt) / 1000)
    }

    private func endBinding(_ workout: Workout) -> Binding<Date> {
        Binding(get: { Format.date(workout.endedAt ?? workout.startedAt) },
                set: { model.setWorkoutEnd(id: workout.id, to: $0) })
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Workout saved").font(.largeTitle.bold())
                        StatLine(parts: [Format.duration(seconds: durationSeconds),
                                         Format.volume(kg: summary.volumeKg, unit: model.unit),
                                         "\(summary.setCount) \(summary.setCount == 1 ? "set" : "sets")"])
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 12, leading: 4, bottom: 4, trailing: 4))
                }
                if let workout {
                    Section {
                        DatePicker("Ended", selection: endBinding(workout), in: Format.date(workout.startedAt)...Date.now)
                    } footer: {
                        Text("Forgot to finish? Set when you actually stopped.").foregroundStyle(Theme.dim)
                    }
                    .listRowBackground(Theme.card)
                }
                if !summary.newRecords.isEmpty {
                    Section("New records") {
                        ForEach(summary.newRecords, id: \.self) { name in
                            Label { Text(name).foregroundStyle(Theme.text) } icon: { Image(systemName: "trophy.fill").foregroundStyle(Theme.gold) }
                        }
                    }
                    .listRowBackground(Theme.card)
                }
                if let routine = summary.routineUpdate {
                    Section {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(routine.title) updated").font(.body)
                                Text("The weights and reps you used are now its plan. Nothing was removed.")
                                    .font(.footnote).foregroundStyle(Theme.dim)
                            }
                        } icon: { Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(Theme.accent) }
                    }
                    .listRowBackground(Theme.card)
                }
            }
            .themedList()
            .safeAreaInset(edge: .bottom) {
                Button("Done") { model.lastSummary = nil; dismiss() }
                    .buttonStyle(AccentButtonStyle())
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.bar)
            }
            .inlineTitle()
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 420)
        #endif
    }
}
