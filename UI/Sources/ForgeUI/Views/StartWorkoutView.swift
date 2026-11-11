import ForgeCore
import SwiftUI

/// Home of the Workout tab when nothing is in progress: routines to start from, then the last weeks at a glance.
public struct StartWorkoutView: View {
    @Environment(AppModel.self) private var model
    @State private var editing: EditTarget?
    @State private var deleting: Routine?

    public init() {}

    private struct EditTarget: Identifiable { let routine: Routine?; var id: String { routine?.id ?? "new" } }

    public var body: some View {
        NavigationStack {
            List {
                if model.exercises.isEmpty && model.routines.isEmpty && model.workouts.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Welcome to Forge", systemImage: "flame.fill").font(.headline).foregroundStyle(Theme.accent)
                            Text("Bring your history over from Hevy (Settings → Hevy), or start with a set of common exercises and build your own routines.")
                                .font(.subheadline).foregroundStyle(Theme.dim)
                            Button("Add starter exercises") { model.addStarterLibrary() }.buttonStyle(QuietButtonStyle(fills: false))
                        }
                        .padding(.vertical, 4)
                    }.listRowBackground(Theme.card)
                }
                Section("Routines") {
                    ForEach(model.routines) { r in
                        Button { model.startWorkout(routine: r) } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(r.title).font(.headline).foregroundStyle(Theme.text)
                                    Text(r.exercises.map { model.name(for: $0.exerciseID) }.prefix(4).joined(separator: ", ") + (r.exercises.count > 4 ? "…" : ""))
                                        .font(.caption).foregroundStyle(Theme.dim).lineLimit(2)
                                }
                                Spacer(minLength: 8)
                                Image(systemName: "play.fill").font(.footnote).foregroundStyle(Theme.accent).accessibilityHidden(true)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Edit", systemImage: "pencil") { editing = EditTarget(routine: r) }
                            Button("Duplicate", systemImage: "plus.square.on.square") { model.duplicateRoutine(id: r.id) }
                            Button("Delete", systemImage: "trash", role: .destructive) { deleting = r }
                        }
                        .swipeActions {
                            Button("Delete", role: .destructive) { deleting = r }.tint(Theme.danger)
                            Button("Edit") { editing = EditTarget(routine: r) }.tint(Theme.info)
                        }
                    }
                    .onMove { source, destination in
                        var ids = model.routines.map(\.id)
                        ids.move(fromOffsets: source, toOffset: destination)
                        model.reorderRoutines(ids)
                    }
                    Button { editing = EditTarget(routine: nil) } label: { Label("New Routine", systemImage: "plus") }
                }.listRowBackground(Theme.card)
                if !model.workouts.isEmpty {
                    Section {
                        WeeklyActivityView()
                            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                    }.listRowBackground(Color.clear)
                }
            }
            .themedList()
            .navigationTitle("Workout")
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .primaryAction) { EditButton() }
                #endif
            }
            .sheet(item: $editing) { RoutineEditorView(routine: $0.routine) }
            .confirmationDialog("Delete \(deleting?.title ?? "routine")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                                titleVisibility: .visible) {
                Button("Delete Routine", role: .destructive) { if let r = deleting { model.deleteRoutine(id: r.id) } }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Past workouts from it are kept.") }
        }
    }
}
