import SwiftUI

/// The iPhone app: three tabs; the Workout tab turns into the live workout while one is in progress.
public struct PhoneRootView: View {
    @Environment(AppModel.self) private var model

    public init() {}

    public var body: some View {
        @Bindable var model = model
        TabView {
            Group {
                if let session = model.session { ActiveWorkoutView(session: session) } else { StartWorkoutView() }
            }
            .tabItem { Label("Workout", systemImage: "figure.strengthtraining.traditional") }
            HistoryView().tabItem { Label("History", systemImage: "clock") }
            SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .forgeTheme()
        .sheet(item: $model.lastSummary) { FinishSummaryView(summary: $0).forgeTheme() }
    }
}
