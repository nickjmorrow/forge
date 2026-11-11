import Foundation

/// A rest countdown stored as an end time, so it stays correct while the app is suspended.
public struct RestTimer: Equatable, Sendable {
    public private(set) var totalSeconds = 0
    public private(set) var endsAt: Date?

    public init() {}

    public mutating func start(seconds: Int, now: Date) {
        totalSeconds = max(0, seconds)
        endsAt = now.addingTimeInterval(Double(totalSeconds))
    }

    /// Adds (or removes) seconds on a running timer; does nothing when idle.
    public mutating func adjust(by seconds: Int, now: Date) {
        guard isRunning(at: now), let end = endsAt else { return }
        endsAt = end.addingTimeInterval(Double(seconds))
        totalSeconds = max(0, totalSeconds + seconds)
    }

    public mutating func skip() { endsAt = nil }

    public func remaining(at now: Date) -> Int {
        guard let endsAt else { return 0 }
        return max(0, Int(endsAt.timeIntervalSince(now).rounded(.up)))
    }

    public func isRunning(at now: Date) -> Bool { remaining(at: now) > 0 }
}
