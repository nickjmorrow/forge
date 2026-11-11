import ForgeCore
import SwiftUI

/// Search the library and pick one exercise (or create a new one).
struct ExercisePickerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let onPick: (String) -> Void
    @State private var search = ""
    @State private var muscle: String?
    @State private var showNew = false

    private var muscles: [String] { Array(Set(model.exercises.compactMap(\.primaryMuscle))).sorted() }

    private var results: [Exercise] {
        ExerciseSearch.results(search, in: model.exercises.filter { muscle == nil || $0.primaryMuscle == muscle })
    }

    var body: some View {
        NavigationStack {
            List {
                if !muscles.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            chip("All", selected: muscle == nil) { muscle = nil }
                            ForEach(muscles, id: \.self) { m in chip(Muscles.title(m), selected: muscle == m) { muscle = m } }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 0)).listRowBackground(Color.clear)
                }
                ForEach(results) { e in
                    Button { onPick(e.id); dismiss() } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.name).foregroundStyle(.primary)
                            Text([e.primaryMuscle.map(Muscles.title), e.equipment.map(Muscles.title)].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(Theme.dim)
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Theme.card)
                }
                if results.isEmpty {
                    ContentUnavailableView(model.exercises.isEmpty ? "No exercises yet" : "No matches",
                                           systemImage: "dumbbell",
                                           description: Text(model.exercises.isEmpty ? "Create one, or add the starter set in Settings." : "Try another search."))
                }
            }
            .searchable(text: $search)
            .themedList()
            .navigationTitle("Add Exercise")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { Button("New", systemImage: "plus") { showNew = true } }
            }
            .sheet(isPresented: $showNew) { ExerciseEditorView(exercise: nil) { id in onPick(id); dismiss() } }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 520)
        #endif
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(selected ? .semibold : .regular))
                .padding(.horizontal, 14).frame(minHeight: 44)
                .background(Capsule().fill(selected ? Theme.accent : Theme.field))
                .foregroundStyle(selected ? Theme.background : Theme.text)
        }
        .buttonStyle(.plain)
    }
}
