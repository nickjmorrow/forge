import ForgeCore
import Foundation

public struct SleepInterval: Equatable, Sendable {
    public var start: Date
    public var end: Date
    public init(start: Date, end: Date) { self.start = start; self.end = end }
}

/// Turns raw "asleep" intervals (possibly from several sources, and split by sleep stage) into seconds slept per morning.
public enum SleepAggregator {
    /// Intervals are merged where they overlap or touch, so two devices tracking the same night count once. Each merged span is filed
    /// under the local day it ends on (yyyy-MM-dd); a span that ends at 14:00 or later is a nap and is ignored.
    public static func nightly(intervals: [SleepInterval], calendar: Calendar) -> [String: Int] {
        var merged: [SleepInterval] = []
        for i in intervals.sorted(by: { $0.start < $1.start }) where i.end > i.start {
            if let last = merged.last, i.start <= last.end {
                merged[merged.count - 1].end = max(last.end, i.end)
            } else {
                merged.append(i)
            }
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        var nights: [String: Int] = [:]
        for span in merged where calendar.component(.hour, from: span.end) < 14 {
            nights[formatter.string(from: span.end), default: 0] += Int(span.end.timeIntervalSince(span.start))
        }
        return nights
    }
}

/// Apple Health as the app sees it: write finished workouts, read sleep and recovery.
public protocol HealthService: Sendable {
    func requestAuthorization() async throws
    func exportWorkout(_ workout: Workout) async throws
    /// Recovery rows (source "apple_health") for the last `days` mornings.
    func recoveryRows(days: Int) async throws -> [Recovery]
}
