#if os(macOS)
import SwiftUI

/// The Mac app: a sidebar for reviewing data and managing routines and the library. Workouts are logged on the phone.
public struct MacRootView: View {
    @AppStorage("macSection") private var section: Section = .dashboard

    /// True while the open routine has unsaved edits; switching sections then asks first.
    @State private var routineHasUnsavedEdits = false
    @State private var pendingSection: Section?

    public init() {}

    enum Section: String, CaseIterable, Identifiable {
        case dashboard = "Dashboard", routines = "Routines", history = "History", exercises = "Exercises", settings = "Settings"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .dashboard: return "chart.bar.xaxis"
            case .routines: return "list.bullet.rectangle"
            case .history: return "clock"
            case .exercises: return "dumbbell"
            case .settings: return "gearshape"
            }
        }
    }

    public var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: Binding<Section?>(get: { section }, set: { if let s = $0 { open(s) } })) { s in
                Label(s.rawValue, systemImage: s.icon).tag(s)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 190)
            .scrollContentBackground(.hidden)
            .background(Theme.bar.ignoresSafeArea())   // oxblood instead of the system's neutral sidebar gray
        } detail: {
            switch section {
            case .dashboard: DashboardView()
            case .routines: RoutinesView(hasUnsavedEdits: $routineHasUnsavedEdits)
            case .history: HistoryView()
            case .exercises: ExerciseListView()
            case .settings: SettingsView()
            }
        }
        .forgeTheme()
        .frame(minWidth: 900, minHeight: 600)
        .confirmationDialog("Discard your changes?", isPresented: Binding(get: { pendingSection != nil }, set: { if !$0 { pendingSection = nil } }),
                            titleVisibility: .visible) {
            Button("Discard Changes", role: .destructive) { if let s = pendingSection { section = s } }
            Button("Keep Editing", role: .cancel) {}
        } message: { Text("This routine has edits that haven't been saved.") }
    }

    private func open(_ s: Section) {
        if routineHasUnsavedEdits && s != section { pendingSection = s } else { section = s }
    }
}
#endif
