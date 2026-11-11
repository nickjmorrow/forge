import ForgeUI
import SwiftUI

@main
struct ForgeMacApp: App {
    @State private var model: AppModel

    init() {
        do { _model = State(initialValue: try AppModel.openDefault()) } catch { fatalError("Can't open the Forge database: \(error)") }
    }

    var body: some Scene {
        WindowGroup {
            MacRootView().environment(model).onAppear { model.startWatching(); model.startAutoSync() }
        }
        .defaultSize(width: 1180, height: 800)
    }
}
