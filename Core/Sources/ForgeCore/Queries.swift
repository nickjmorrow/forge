import Foundation
import GRDB

extension Forge {
    /// Exercises whose name, equipment or muscles contain `text` (case-insensitive); all of them when nil.
    public func exercises(matching text: String? = nil) throws -> [Exercise] {
        let all = try db.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM exercises ORDER BY name COLLATE NOCASE, id").map(Store.decodeExercise)
        }
        guard let needle = text?.lowercased(), !needle.isEmpty else { return all }
        return all.filter { e in
            ([e.name, e.equipment, e.primaryMuscle].compactMap { $0 } + e.secondaryMuscles)
                .contains { $0.lowercased().contains(needle) }
        }
    }

    /// How many workouts and routines contain the exercise.
    public func usage(ofExercise id: String) throws -> (workouts: Int, routines: Int) {
        try db.read { db in
            (try Int.fetchOne(db, sql: "SELECT COUNT(DISTINCT workout_id) FROM workout_exercises WHERE exercise_id = ?", arguments: [id]) ?? 0,
             try Int.fetchOne(db, sql: "SELECT COUNT(DISTINCT routine_id) FROM routine_exercises WHERE exercise_id = ?", arguments: [id]) ?? 0)
        }
    }

    /// Deletes an exercise. One that appears in routines or workouts needs `mergeInto` (history moves to that exercise)
    /// or `force` (its blocks are removed everywhere); otherwise this throws and changes nothing.
    @discardableResult
    public func deleteExercise(id: String, mergeInto: String?, force: Bool, author: Author) throws -> Int64 {
        guard try exercise(id: id) != nil else { throw ForgeError.notFound("exercise \(id)") }
        let used = try usage(ofExercise: id)
        if let target = mergeInto { return try perform([.mergeExercises(from: id, into: target)], author: author) }
        guard used.workouts + used.routines > 0 else { return try perform([.deleteExercise(id: id)], author: author) }
        guard force else { throw ForgeError.exerciseHasHistory(id, workouts: used.workouts, routines: used.routines) }
        var ops: [Op] = []
        let (routineIDs, workoutIDs) = try db.read { db in
            (try String.fetchAll(db, sql: "SELECT DISTINCT routine_id FROM routine_exercises WHERE exercise_id = ?", arguments: [id]),
             try String.fetchAll(db, sql: "SELECT DISTINCT workout_id FROM workout_exercises WHERE exercise_id = ?", arguments: [id]))
        }
        for rid in routineIDs {
            guard var r = try routine(id: rid) else { continue }
            r.exercises.removeAll { $0.exerciseID == id }
            ops.append(.putRoutine(r))
        }
        for wid in workoutIDs {
            guard var w = try workout(id: wid) else { continue }
            w.exercises.removeAll { $0.exerciseID == id }
            ops.append(.putWorkout(w))
        }
        ops.append(.deleteExercise(id: id))
        return try perform(ops, author: author)
    }
}

extension Forge {
    /// All routines in display order.
    public func routines() throws -> [Routine] {
        try db.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM routines ORDER BY position, title COLLATE NOCASE, id").map { try Store.decodeRoutine($0, db) }
        }
    }

    /// Workouts, newest first.
    public func workouts(limit: Int = 50, before: Int64? = nil) throws -> [Workout] {
        try db.read { db in
            try Store.decodeWorkouts(try Row.fetchAll(db, sql: "SELECT * FROM workouts WHERE (? IS NULL OR started_at < ?) ORDER BY started_at DESC LIMIT ?",
                                                      arguments: [before, before, limit]), db)
        }
    }
}
