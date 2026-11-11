#if os(macOS)
import SwiftUI

/// The Mac app: a sidebar for reviewing data and managing routines and the library. Workouts are logged on the phone.
public struct MacRootView: View {
    @AppStorage("macSection") private var section: Section = .dashboard

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
            List(Section.allCases, selection: Binding<Section?>(get: { section }, set: { if let s = $0 { section = s } })) { s in
                Label(s.rawValue, systemImage: s.icon).tag(s)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 190)
            .scrollContentBackground(.hidden)
            .background(Theme.bar.ignoresSafeArea())   // ink instead of the system's neutral sidebar gray
        } detail: {
            switch section {
            case .dashboard: DashboardView()
            case .routines: RoutinesView()
            case .history: HistoryView()
            case .exercises: ExerciseListView()
            case .settings: SettingsView()
            }
        }
        .forgeTheme()
        .frame(minWidth: 900, minHeight: 600)
    }
}
#endif
