import Foundation
import GRDB

/// Row-level reads and whole-aggregate writes. Routines and workouts are always rewritten as a unit.
enum Store {
    static func recovery(date: String, source: String, _ db: Database) throws -> Recovery? {
        try Row.fetchOne(db, sql: "SELECT * FROM recovery WHERE date = ? AND source = ?", arguments: [date, source]).map(decodeRecovery)
    }

    static func decodeRecovery(_ r: Row) -> Recovery {
        Recovery(date: r["date"], source: r["source"], sleepSeconds: r["sleep_seconds"], sleepScore: r["sleep_score"], hrvMs: r["hrv_ms"], restingHR: r["resting_hr"])
    }

    static func exercise(_ id: String, _ db: Database) throws -> Exercise? {
        try Row.fetchOne(db, sql: "SELECT * FROM exercises WHERE id = ?", arguments: [id]).map(decodeExercise)
    }

    static func decodeExercise(_ r: Row) -> Exercise {
        let secondary = (r["secondary_muscles"] as String?).flatMap { try? JSONDecoder().decode([String].self, from: Data($0.utf8)) } ?? []
        return Exercise(id: r["id"], name: r["name"], equipment: r["equipment"], primaryMuscle: r["primary_muscle"],
                        secondaryMuscles: secondary, tracking: TrackingType(rawValue: r["tracking"]) ?? .weightReps,
                        isCustom: r["is_custom"], hevyID: r["hevy_id"], createdAt: r["created_at"], updatedAt: r["updated_at"])
    }

    static func writeExercise(_ e: Exercise, _ db: Database) throws {
        let secondary = String(decoding: try JSONEncoder().encode(e.secondaryMuscles), as: UTF8.self)
        try db.execute(sql: """
            INSERT INTO exercises (id, name, equipment, primary_muscle, secondary_muscles, tracking, is_custom, hevy_id, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET name = excluded.name, equipment = excluded.equipment, primary_muscle = excluded.primary_muscle,
              secondary_muscles = excluded.secondary_muscles, tracking = excluded.tracking, is_custom = excluded.is_custom,
              hevy_id = excluded.hevy_id, created_at = excluded.created_at, updated_at = excluded.updated_at
            """, arguments: [e.id, e.name, e.equipment, e.primaryMuscle, secondary, e.tracking.rawValue, e.isCustom, e.hevyID, e.createdAt, e.updatedAt])
    }

    static func routine(_ id: String, _ db: Database) throws -> Routine? {
        try Row.fetchOne(db, sql: "SELECT * FROM routines WHERE id = ?", arguments: [id]).map { try decodeRoutine($0, db) }
    }

    static func decodeRoutine(_ r: Row, _ db: Database) throws -> Routine {
        let id: String = r["id"]
        return Routine(id: id, title: r["title"], folder: r["folder"], position: r["position"],
                       exercises: try blocks(table: "routine_exercises", setTable: "routine_sets", keyColumn: "routine_id", key: id, db),
                       hevyID: r["hevy_id"], createdAt: r["created_at"], updatedAt: r["updated_at"])
    }

    static func writeRoutine(_ r: Routine, _ db: Database) throws {
        try db.execute(sql: "DELETE FROM routines WHERE id = ?", arguments: [r.id])
        try db.execute(sql: "INSERT INTO routines (id, title, folder, position, hevy_id, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
                       arguments: [r.id, r.title, r.folder, r.position, r.hevyID, r.createdAt, r.updatedAt])
        try writeBlocks(r.exercises, table: "routine_exercises", setTable: "routine_sets", keyColumn: "routine_id", key: r.id, db)
    }

    static func workout(_ id: String, _ db: Database) throws -> Workout? {
        try Row.fetchOne(db, sql: "SELECT * FROM workouts WHERE id = ?", arguments: [id]).map { try decodeWorkout($0, db) }
    }

    static func decodeWorkout(_ r: Row, _ db: Database) throws -> Workout {
        let id: String = r["id"]
        return Workout(id: id, title: r["title"], startedAt: r["started_at"], endedAt: r["ended_at"], routineID: r["routine_id"],
                       notes: r["notes"],
                       exercises: try blocks(table: "workout_exercises", setTable: "workout_sets", keyColumn: "workout_id", key: id, db),
                       hevyID: r["hevy_id"])
    }

    static func writeWorkout(_ w: Workout, _ db: Database) throws {
        try db.execute(sql: "DELETE FROM workouts WHERE id = ?", arguments: [w.id])
        try db.execute(sql: "INSERT INTO workouts (id, title, started_at, ended_at, routine_id, notes, hevy_id) VALUES (?, ?, ?, ?, ?, ?, ?)",
                       arguments: [w.id, w.title, w.startedAt, w.endedAt, w.routineID, w.notes, w.hevyID])
        try writeBlocks(w.exercises, table: "workout_exercises", setTable: "workout_sets", keyColumn: "workout_id", key: w.id, db)
    }

    static func blocks(table: String, setTable: String, keyColumn: String, key: String, _ db: Database) throws -> [ExerciseBlock] {
        let exerciseRows = try Row.fetchAll(db, sql: "SELECT * FROM \(table) WHERE \(keyColumn) = ? ORDER BY position", arguments: [key])
        let setRows = try Row.fetchAll(db, sql: "SELECT * FROM \(setTable) WHERE \(keyColumn) = ? ORDER BY exercise_position, position", arguments: [key])
        return makeBlocks(exerciseRows: exerciseRows, setRows: setRows)
    }

    /// Builds the exercise blocks of one routine or workout from its already-fetched (ordered) exercise and set rows.
    static func makeBlocks(exerciseRows: [Row], setRows: [Row]) -> [ExerciseBlock] {
        var setsByPosition: [Int: [SetEntry]] = [:]
        for r in setRows {
            let position: Int = r["exercise_position"]
            setsByPosition[position, default: []].append(SetEntry(
                type: SetType(rawValue: r["type"]) ?? .normal, weightKg: r["weight_kg"], reps: r["reps"],
                durationSeconds: r["duration_seconds"], distanceMeters: r["distance_meters"], rpe: r["rpe"], completed: r["completed"]))
        }
        return exerciseRows.map { r in
            let position: Int = r["position"]
            return ExerciseBlock(exerciseID: r["exercise_id"], notes: r["notes"], restSeconds: r["rest_seconds"],
                                 supersetID: r["superset_id"], sets: setsByPosition[position] ?? [])
        }
    }

    /// Same as `makeBlocks`, for rows selected with the explicit column lists in `decodeWorkouts` (read by position).
    static func makeBlocksByIndex(exerciseRows: [Row], setRows: [Row]) -> [ExerciseBlock] {
        var setsByPosition: [Int: [SetEntry]] = [:]
        for r in setRows {
            let type: String = r[2]
            setsByPosition[r[1] as Int, default: []].append(SetEntry(
                type: SetType(rawValue: type) ?? .normal, weightKg: r[3], reps: r[4], durationSeconds: r[5], distanceMeters: r[6], rpe: r[7], completed: r[8]))
        }
        return exerciseRows.map { r in
            ExerciseBlock(exerciseID: r[2], notes: r[3], restSeconds: r[4], supersetID: r[5], sets: setsByPosition[r[1] as Int] ?? [])
        }
    }

    /// Decodes many workouts with two queries (all their exercises, all their sets) instead of two per workout.
    static func decodeWorkouts(_ rows: [Row], _ db: Database) throws -> [Workout] {
        var exercisesByWorkout: [String: [Row]] = [:], setsByWorkout: [String: [Row]] = [:]
        let ids = rows.map { $0["id"] as String }
        for chunk in stride(from: 0, to: ids.count, by: 500).map({ Array(ids[$0..<min($0 + 500, ids.count)]) }) {
            let marks = chunk.map { _ in "?" }.joined(separator: ",")
            // Explicit column lists and index access: decoding by column name dominates when there are tens of thousands of sets.
            for r in try Row.fetchAll(db, sql: "SELECT workout_id, position, exercise_id, notes, rest_seconds, superset_id FROM workout_exercises WHERE workout_id IN (\(marks)) ORDER BY workout_id, position", arguments: StatementArguments(chunk)) {
                exercisesByWorkout[r[0], default: []].append(r)
            }
            for r in try Row.fetchAll(db, sql: "SELECT workout_id, exercise_position, type, weight_kg, reps, duration_seconds, distance_meters, rpe, completed FROM workout_sets WHERE workout_id IN (\(marks)) ORDER BY workout_id, exercise_position, position", arguments: StatementArguments(chunk)) {
                setsByWorkout[r[0], default: []].append(r)
            }
        }
        return rows.map { r in
            let id: String = r["id"]
            return Workout(id: id, title: r["title"], startedAt: r["started_at"], endedAt: r["ended_at"], routineID: r["routine_id"], notes: r["notes"],
                           exercises: makeBlocksByIndex(exerciseRows: exercisesByWorkout[id] ?? [], setRows: setsByWorkout[id] ?? []), hevyID: r["hevy_id"])
        }
    }

    static func writeBlocks(_ blocks: [ExerciseBlock], table: String, setTable: String, keyColumn: String, key: String, _ db: Database) throws {
        for (i, b) in blocks.enumerated() {
            try db.execute(sql: "INSERT INTO \(table) (\(keyColumn), position, exercise_id, notes, rest_seconds, superset_id) VALUES (?, ?, ?, ?, ?, ?)",
                           arguments: [key, i, b.exerciseID, b.notes, b.restSeconds, b.supersetID])
            for (j, s) in b.sets.enumerated() {
                try db.execute(sql: """
                    INSERT INTO \(setTable) (\(keyColumn), exercise_position, position, type, weight_kg, reps, duration_seconds, distance_meters, rpe, completed)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, arguments: [key, i, j, s.type.rawValue, s.weightKg, s.reps, s.durationSeconds, s.distanceMeters, s.rpe, s.completed])
            }
        }
    }
}

extension Forge {
    public func exercise(id: String) throws -> Exercise? { try db.read { try Store.exercise(id, $0) } }
    public func routine(id: String) throws -> Routine? { try db.read { try Store.routine(id, $0) } }
    public func workout(id: String) throws -> Workout? { try db.read { try Store.workout(id, $0) } }
    public func bodyweight(date: String) throws -> Double? {
        try db.read { try Double.fetchOne($0, sql: "SELECT kg FROM bodyweight WHERE date = ?", arguments: [date]) }
    }
}
