import Foundation
import GRDB

enum Applier {
    /// Applies one op and returns the op that undoes it.
    static func apply(_ op: Op, in db: Database) throws -> Op {
        switch op {
        case let .putExercise(e):
            let previous = try Store.exercise(e.id, db)
            try Store.writeExercise(e, db)
            return previous.map(Op.putExercise) ?? .deleteExercise(id: e.id)
        case let .deleteExercise(id):
            guard let previous = try Store.exercise(id, db) else { throw ForgeError.notFound("exercise \(id)") }
            try db.execute(sql: "DELETE FROM exercises WHERE id = ?", arguments: [id])
            return .putExercise(previous)
        case let .mergeExercises(from, into):
            return try merge(from: from, into: into, in: db)
        case let .putRoutine(r):
            let previous = try Store.routine(r.id, db)
            try Store.writeRoutine(r, db)
            return previous.map(Op.putRoutine) ?? .deleteRoutine(id: r.id)
        case let .deleteRoutine(id):
            guard let previous = try Store.routine(id, db) else { throw ForgeError.notFound("routine \(id)") }
            try db.execute(sql: "DELETE FROM routines WHERE id = ?", arguments: [id])
            return .putRoutine(previous)
        case let .putWorkout(w):
            let previous = try Store.workout(w.id, db)
            try Store.writeWorkout(w, db)
            return previous.map(Op.putWorkout) ?? .deleteWorkout(id: w.id)
        case let .deleteWorkout(id):
            guard let previous = try Store.workout(id, db) else { throw ForgeError.notFound("workout \(id)") }
            try db.execute(sql: "DELETE FROM workouts WHERE id = ?", arguments: [id])
            return .putWorkout(previous)
        case let .putBodyweight(date, kg):
            let previous = try Double.fetchOne(db, sql: "SELECT kg FROM bodyweight WHERE date = ?", arguments: [date])
            try db.execute(sql: "INSERT OR REPLACE INTO bodyweight (date, kg) VALUES (?, ?)", arguments: [date, kg])
            return previous.map { .putBodyweight(date: date, kg: $0) } ?? .deleteBodyweight(date: date)
        case let .deleteBodyweight(date):
            guard let previous = try Double.fetchOne(db, sql: "SELECT kg FROM bodyweight WHERE date = ?", arguments: [date]) else { throw ForgeError.notFound("bodyweight \(date)") }
            try db.execute(sql: "DELETE FROM bodyweight WHERE date = ?", arguments: [date])
            return .putBodyweight(date: date, kg: previous)
        case let .putRecovery(r):
            let previous = try Store.recovery(date: r.date, source: r.source, db)
            try db.execute(sql: """
                INSERT OR REPLACE INTO recovery (date, source, sleep_seconds, sleep_score, hrv_ms, resting_hr) VALUES (?, ?, ?, ?, ?, ?)
                """, arguments: [r.date, r.source, r.sleepSeconds, r.sleepScore, r.hrvMs, r.restingHR])
            return previous.map(Op.putRecovery) ?? .deleteRecovery(date: r.date, source: r.source)
        case let .deleteRecovery(date, source):
            guard let previous = try Store.recovery(date: date, source: source, db) else { throw ForgeError.notFound("recovery \(date) \(source)") }
            try db.execute(sql: "DELETE FROM recovery WHERE date = ? AND source = ?", arguments: [date, source])
            return .putRecovery(previous)
        case let .batch(ops):
            var inverses: [Op] = []
            for o in ops { inverses.append(try apply(o, in: db)) }
            return .batch(inverses.reversed())
        }
    }

    /// Replaces every `mergeExercises` with the routine and workout rewrites plus the delete it amounts to.
    static func expandMerges(_ op: Op, in db: Database) throws -> Op {
        switch op {
        case let .mergeExercises(from, into): return .batch(try mergeEdits(from: from, into: into, in: db))
        case let .batch(ops): return .batch(try ops.map { try expandMerges($0, in: db) })
        default: return op
        }
    }

    private static func mergeEdits(from: String, into: String, in db: Database) throws -> [Op] {
        guard try Store.exercise(from, db) != nil else { throw ForgeError.notFound("exercise \(from)") }
        guard try Store.exercise(into, db) != nil else { throw ForgeError.notFound("exercise \(into)") }
        guard from != into else { throw ForgeError.invalid("cannot merge an exercise into itself") }
        var edits: [Op] = []
        for id in try String.fetchAll(db, sql: "SELECT DISTINCT routine_id FROM routine_exercises WHERE exercise_id = ?", arguments: [from]) {
            guard var r = try Store.routine(id, db) else { continue }
            for i in r.exercises.indices where r.exercises[i].exerciseID == from { r.exercises[i].exerciseID = into }
            edits.append(.putRoutine(r))
        }
        for id in try String.fetchAll(db, sql: "SELECT DISTINCT workout_id FROM workout_exercises WHERE exercise_id = ?", arguments: [from]) {
            guard var w = try Store.workout(id, db) else { continue }
            for i in w.exercises.indices where w.exercises[i].exerciseID == from { w.exercises[i].exerciseID = into }
            edits.append(.putWorkout(w))
        }
        edits.append(.deleteExercise(id: from))
        return edits
    }

    private static func merge(from: String, into: String, in db: Database) throws -> Op {
        guard let fromExercise = try Store.exercise(from, db) else { throw ForgeError.notFound("exercise \(from)") }
        guard try Store.exercise(into, db) != nil else { throw ForgeError.notFound("exercise \(into)") }
        guard from != into else { throw ForgeError.invalid("cannot merge an exercise into itself") }
        var restore: [Op] = [.putExercise(fromExercise)]
        let routineIDs = try String.fetchAll(db, sql: "SELECT DISTINCT routine_id FROM routine_exercises WHERE exercise_id = ?", arguments: [from])
        for id in routineIDs {
            guard var r = try Store.routine(id, db) else { continue }
            restore.append(.putRoutine(r))
            for i in r.exercises.indices where r.exercises[i].exerciseID == from { r.exercises[i].exerciseID = into }
            try Store.writeRoutine(r, db)
        }
        let workoutIDs = try String.fetchAll(db, sql: "SELECT DISTINCT workout_id FROM workout_exercises WHERE exercise_id = ?", arguments: [from])
        for id in workoutIDs {
            guard var w = try Store.workout(id, db) else { continue }
            restore.append(.putWorkout(w))
            for i in w.exercises.indices where w.exercises[i].exerciseID == from { w.exercises[i].exerciseID = into }
            try Store.writeWorkout(w, db)
        }
        try db.execute(sql: "DELETE FROM exercises WHERE id = ?", arguments: [from])
        return .batch(restore)
    }
}
