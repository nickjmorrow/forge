import ActivityKit
import Foundation

/// The rest timer as shown on the lock screen and in the Dynamic Island. Shared by the app and the widget extension.
struct RestActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var endsAt: Date
        var totalSeconds: Int
    }

    var workoutTitle: String
}
