import Foundation
import GRDB

/// Estimated one-rep max (Epley). One rep is the weight itself.
public func e1RM(weightKg: Double, reps: Int) -> Double {
    reps <= 1 ? weightKg : weightKg * (1 + Double(reps) / 30)
}

public struct PersonalRecords: Codable, Sendable, Equatable {
    public var heaviestKg: Double?
    public var bestE1RMKg: Double?
    public var bestSetVolumeKg: Double?

    public init(heaviestKg: Double? = nil, bestE1RMKg: Double? = nil, bestSetVolumeKg: Double? = nil) {
        self.heaviestKg = heaviestKg; self.bestE1RMKg = bestE1RMKg; self.bestSetVolumeKg = bestSetVolumeKg
    }
}

public struct ExerciseSession: Codable, Sendable, Equatable {
    public let workoutID: String
    public let startedAt: Int64
    public let sets: [SetEntry]
}

public struct WeekMuscle: Codable, Sendable, Equatable {
    public let weekStart: String
    public let muscle: String
    public let sets: Int
}

extension Forge {
    /// Completed sets of one exercise grouped by workout, newest workout first.
    public func exerciseHistory(exerciseID: String, limit: Int = 20) throws -> [ExerciseSession] {
        let rows = try db.read { db in
            try Row.fetchAll(db, sql: """
                SELECT w.id AS workout_id, w.started_at, s.* FROM workout_sets s
                JOIN workout_exercises we ON we.workout_id = s.workout_id AND we.position = s.exercise_position
                JOIN workouts w ON w.id = s.workout_id
                WHERE we.exercise_id = ? AND s.completed = 1
                ORDER BY w.started_at DESC, w.id, s.exercise_position, s.position
                """, arguments: [exerciseID])
        }
        var sessions: [ExerciseSession] = []
        var current: (id: String, startedAt: Int64, sets: [SetEntry])?
        for r in rows {
            let id: String = r["workout_id"]
            let set = SetEntry(type: SetType(rawValue: r["type"]) ?? .normal, weightKg: r["weight_kg"], reps: r["reps"],
                               durationSeconds: r["duration_seconds"], distanceMeters: r["distance_meters"], rpe: r["rpe"], completed: true)
            if current?.id == id {
                current!.sets.append(set)
            } else {
                if let c = current { sessions.append(ExerciseSession(workoutID: c.id, startedAt: c.startedAt, sets: c.sets)) }
                current = (id, r["started_at"], [set])
            }
        }
        if let c = current { sessions.append(ExerciseSession(workoutID: c.id, startedAt: c.startedAt, sets: c.sets)) }
        return Array(sessions.prefix(limit))
    }

    /// Completed sets from the most recent workout before `before` that has any, or nil.
    public func lastPerformance(exerciseID: String, before: Int64) throws -> [SetEntry]? {
        try exerciseHistory(exerciseID: exerciseID, limit: .max).first { $0.startedAt < before }?.sets
    }

    /// Records over completed, non-warmup sets with a weight and reps. Always recomputed from history.
    public func personalRecords(exerciseID: String) throws -> PersonalRecords {
        var pr = PersonalRecords()
        for session in try exerciseHistory(exerciseID: exerciseID, limit: .max) {
            for s in session.sets where s.type != .warmup {
                guard let w = s.weightKg, let reps = s.reps, reps > 0 else { continue }
                pr.heaviestKg = max(pr.heaviestKg ?? 0, w)
                pr.bestE1RMKg = max(pr.bestE1RMKg ?? 0, e1RM(weightKg: w, reps: reps))
                pr.bestSetVolumeKg = max(pr.bestSetVolumeKg ?? 0, w * Double(reps))
            }
        }
        return pr
    }

    /// Completed non-warmup sets per primary muscle per week (weeks start Monday, in `timeZone`), oldest week first.
    public func weeklySets(since: Int64, timeZone: TimeZone = .current) throws -> [WeekMuscle] {
        let rows = try db.read { db in
            try Row.fetchAll(db, sql: """
                SELECT w.started_at, COALESCE(e.primary_muscle, 'unknown') AS muscle, COUNT(*) AS n FROM workout_sets s
                JOIN workout_exercises we ON we.workout_id = s.workout_id AND we.position = s.exercise_position
                JOIN workouts w ON w.id = s.workout_id
                LEFT JOIN exercises e ON e.id = we.exercise_id
                WHERE s.completed = 1 AND s.type != 'warmup' AND w.started_at >= ?
                GROUP BY w.id, muscle
                """, arguments: [since])
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.firstWeekday = 2
        let format = DateFormatter()
        format.dateFormat = "yyyy-MM-dd"
        format.timeZone = timeZone
        format.locale = Locale(identifier: "en_US_POSIX")
        var counts: [String: Int] = [:]
        for r in rows {
            let date = Date(timeIntervalSince1970: Double(r["started_at"] as Int64) / 1000)
            let start = calendar.dateInterval(of: .weekOfYear, for: date)!.start
            counts["\(format.string(from: start))|\(r["muscle"] as String)", default: 0] += r["n"] as Int
        }
        return counts.map { key, n in
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            return WeekMuscle(weekStart: parts[0], muscle: parts[1], sets: n)
        }.sorted { ($0.weekStart, $0.muscle) < ($1.weekStart, $1.muscle) }
    }
}
