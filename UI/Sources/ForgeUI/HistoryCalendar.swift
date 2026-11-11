import ForgeCore
import Foundation

/// The date math behind History's calendar: a month as a grid of days (weeks start Monday), workouts counted per day.
public enum HistoryCalendar {
    public static func monthStart(of date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    public static func month(_ date: Date, shiftedBy months: Int, calendar: Calendar) -> Date {
        let start = monthStart(of: date, calendar: calendar)
        return calendar.date(byAdding: .month, value: months, to: start) ?? start
    }

    /// One entry per grid cell: `nil` for the blanks before the 1st, then each day of the month at the start of that day.
    public static func cells(forMonthOf date: Date, calendar: Calendar) -> [Date?] {
        let start = monthStart(of: date, calendar: calendar)
        let days = calendar.range(of: .day, in: .month, for: start)?.count ?? 30
        let weekday = calendar.component(.weekday, from: start)
        let blanks = (weekday - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: blanks) + (0..<days).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private static func day(of workout: Workout, _ calendar: Calendar) -> Date {
        calendar.startOfDay(for: Date(timeIntervalSince1970: Double(workout.startedAt) / 1000))
    }

    /// Workouts started on each day.
    public static func counts(workouts: [Workout], calendar: Calendar) -> [Date: Int] {
        var counts: [Date: Int] = [:]
        for w in workouts { counts[day(of: w, calendar), default: 0] += 1 }
        return counts
    }

    /// That day's workouts, latest first.
    public static func workouts(on day: Date, in workouts: [Workout], calendar: Calendar) -> [Workout] {
        let target = calendar.startOfDay(for: day)
        return workouts.filter { self.day(of: $0, calendar) == target }.sorted { $0.startedAt > $1.startedAt }
    }

    /// The month of the most recent workout, or this month when there are none.
    public static func initialMonth(workouts: [Workout], now: Date, calendar: Calendar) -> Date {
        let latest = workouts.map(\.startedAt).max().map { Date(timeIntervalSince1970: Double($0) / 1000) } ?? now
        return monthStart(of: latest, calendar: calendar)
    }
}
