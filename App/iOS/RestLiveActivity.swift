import ActivityKit
import ForgeUI
import Foundation

/// Starts, updates and ends the rest-timer Live Activity as the workout's rest timer changes.
/// ActivityKit's checks and `Activity.request` are synchronous trips to a system service, so they run on a serial background
/// queue: ticking off a set never waits on them, and updates still apply in order.
final class RestLiveActivity: RestAlerting, @unchecked Sendable {
    private let queue = DispatchQueue(label: "forge.rest-live-activity", qos: .userInitiated)
    private var activity: Activity<RestActivityAttributes>?     // only touched on `queue`
    private var dismissal: DispatchWorkItem?                    // ends the activity when the rest does; only touched on `queue`

    func update(rest: RestTimer) {
        queue.async { [self] in apply(rest) }
    }

    private func apply(_ rest: RestTimer) {
        dismissal?.cancel()
        dismissal = nil
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard let end = rest.endsAt, end.timeIntervalSinceNow > 0 else {
            let finished = activity
            activity = nil
            Task { await finished?.end(nil, dismissalPolicy: .immediate) }
            return
        }
        let item = DispatchWorkItem { [self] in
            let finished = activity
            activity = nil
            Task { await finished?.end(nil, dismissalPolicy: .immediate) }
        }
        dismissal = item
        queue.asyncAfter(deadline: .now() + end.timeIntervalSinceNow + 0.5, execute: item)
        let state = RestActivityAttributes.ContentState(endsAt: end, totalSeconds: rest.totalSeconds)
        if let activity {
            Task { await activity.update(ActivityContent(state: state, staleDate: end)) }
        } else {
            activity = try? Activity.request(attributes: RestActivityAttributes(workoutTitle: "Workout"),
                                             content: ActivityContent(state: state, staleDate: end))
        }
    }
}
