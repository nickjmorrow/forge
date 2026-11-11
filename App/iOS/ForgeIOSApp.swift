import ForgeUI
import SwiftUI

@main
struct ForgeIOSApp: App {
    @State private var model: AppModel

    init() {
        do { _model = State(initialValue: try AppModel.openDefault(restAlerts: CombinedRestAlerts([LocalNotificationRestAlerts(), RestLiveActivity()]), health: HealthKitBridge())) } catch { fatalError("Can't open the Forge database: \(error)") }
    }

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            PhoneRootView().environment(model)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await model.syncHealth() }
                model.startAutoSync()
            } else {
                model.stopAutoSync()
                model.flushWorkoutDraft()
            }
        }
    }
}
