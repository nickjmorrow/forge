import ForgeCore
import SwiftUI

public struct ExerciseListView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var muscle: String?
    @State private var showNew = false

    public init() {}

    private var results: [Exercise] {
        ExerciseSearch.results(search, in: model.exercises.filter { muscle == nil || $0.primaryMuscle == muscle })
    }

    public var body: some View {
        NavigationStack {
            List {
                ForEach(results) { e in
                    NavigationLink(value: e.id) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(e.name)
                                if e.isCustom { Text("custom").font(.caption2).padding(.horizontal, 5).background(Capsule().fill(Theme.field)) }
                            }
                            Text([e.primaryMuscle.map(Muscles.title), e.equipment.map(Muscles.title)].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(Theme.dim)
                        }
                    }
                    .listRowBackground(Theme.card)
                }
                if results.isEmpty {
                    ContentUnavailableView(model.exercises.isEmpty ? "No exercises yet" : "No matches", systemImage: "dumbbell",
                                           description: Text(model.exercises.isEmpty ? "Add a starter set in Settings, import from Hevy, or create your own." : "Try another search."))
                }
            }
            .searchable(text: $search)
            .themedList()
            .navigationTitle("Exercises")
            .navigationDestination(for: String.self) { ExerciseDetailView(exerciseID: $0) }
            .toolbar {
                ToolbarItem(placement: .primaryAction) { Button("New", systemImage: "plus") { showNew = true } }
                ToolbarItem(placement: .automatic) {
                    Menu {
                        Button("All muscles") { muscle = nil }
                        ForEach(Array(Set(model.exercises.compactMap(\.primaryMuscle))).sorted(), id: \.self) { m in
                            Button(Muscles.title(m)) { muscle = m }
                        }
                    } label: { Label(muscle.map(Muscles.title) ?? "Filter", systemImage: "line.3.horizontal.decrease.circle") }
                }
            }
            .sheet(isPresented: $showNew) { ExerciseEditorView(exercise: nil) }
        }
    }
}
