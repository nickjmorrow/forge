import ForgeCore
import Foundation

public struct WeekSummary: Equatable {
    public var workouts = 0
    public var sets = 0
    public var volumeKg = 0.0
}

/// One calendar week of training, for the phone's home charts.
public struct WeekTotals: Equatable, Identifiable {
    public let weekStart: Date
    public var workouts = 0
    public var seconds = 0
    public var id: Date { weekStart }
    public var hours: Double { Double(seconds) / 3600 }
}

public struct RecordItem: Equatable, Identifiable {
    public let name: String
    public let e1RMKg: Double
    public let date: Date
    public var id: String { name }
}

/// The numbers behind the Mac dashboard.
public enum DashboardStats {
    static func countedSets(_ w: Workout) -> [SetEntry] {
        w.exercises.flatMap(\.sets).filter { $0.completed && $0.type != .warmup }
    }

    public static func weekStart(of date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    public static func thisWeek(workouts: [Workout], now: Date, calendar: Calendar = .current) -> WeekSummary {
        let start = Int64(weekStart(of: now, calendar: calendar).timeIntervalSince1970 * 1000)
        var summary = WeekSummary()
        for w in workouts where w.startedAt >= start {
            let sets = countedSets(w)
            summary.workouts += 1
            summary.sets += sets.count
            summary.volumeKg += sets.reduce(0) { $0 + ($1.weightKg ?? 0) * Double($1.reps ?? 0) }
        }
        return summary
    }

    /// Workouts and time trained in each of the last `weeks` calendar weeks, oldest first, the final one being this week.
    /// A workout counts toward its start week; one with no end time adds no time.
    public static func weekly(workouts: [Workout], weeks: Int, now: Date, calendar: Calendar = .current) -> [WeekTotals] {
        let thisWeek = weekStart(of: now, calendar: calendar)
        var totals = (0..<weeks).compactMap { calendar.date(byAdding: .weekOfYear, value: $0 - (weeks - 1), to: thisWeek) }.map { WeekTotals(weekStart: $0) }
        let index = Dictionary(uniqueKeysWithValues: totals.enumerated().map { ($1.weekStart, $0) })
        for w in workouts {
            guard let i = index[weekStart(of: Date(timeIntervalSince1970: Double(w.startedAt) / 1000), calendar: calendar)] else { continue }
            totals[i].workouts += 1
            if let end = w.endedAt, end > w.startedAt { totals[i].seconds += Int((end - w.startedAt) / 1000) }
        }
        return totals
    }

    /// Every day of the last `weeks` calendar weeks (Monday first), the final week being the current one.
    public static func calendarDays(weeks: Int, now: Date, calendar: Calendar = .current) -> [Date] {
        let thisMonday = weekStart(of: now, calendar: calendar)
        guard let first = calendar.date(byAdding: .day, value: -7 * (weeks - 1), to: thisMonday) else { return [] }
        return (0..<(weeks * 7)).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
    }

    /// How many workouts started on each day of the calendar grid.
    public static func workoutDays(workouts: [Workout], weeks: Int, now: Date, calendar: Calendar = .current) -> [Date: Int] {
        let grid = Set(calendarDays(weeks: weeks, now: now, calendar: calendar))
        var days: [Date: Int] = [:]
        for w in workouts {
            let day = calendar.startOfDay(for: Date(timeIntervalSince1970: Double(w.startedAt) / 1000))
            if grid.contains(day) { days[day, default: 0] += 1 }
        }
        return days
    }

    /// Exercises whose best estimated 1-rep max was set within the last `days` days, newest first.
    public static func recentRecords(forge: Forge, now: Date, days: Int, limit: Int = 8) throws -> [RecordItem] {
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        let cutoffMs = Int64(cutoff.timeIntervalSince1970 * 1000)
        let recent = try forge.workouts(limit: 1000).filter { $0.startedAt >= cutoffMs }
        let names = Dictionary(try forge.exercises().map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        var items: [RecordItem] = []
        for id in Set(recent.flatMap { $0.exercises.map(\.exerciseID) }) {
            var best: (e1rm: Double, startedAt: Int64)?
            for session in try forge.exerciseHistory(exerciseID: id, limit: .max).reversed() {   // oldest first, so ties keep the earliest
                for s in session.sets where s.type != .warmup {
                    guard let w = s.weightKg, let r = s.reps, r > 0 else { continue }
                    let value = e1RM(weightKg: w, reps: r)
                    if value > (best?.e1rm ?? 0) { best = (value, session.startedAt) }
                }
            }
            if let best, best.startedAt >= cutoffMs, let name = names[id] {
                items.append(RecordItem(name: name, e1RMKg: best.e1rm, date: Date(timeIntervalSince1970: Double(best.startedAt) / 1000)))
            }
        }
        return Array(items.sorted { $0.date > $1.date }.prefix(limit))
    }
}
