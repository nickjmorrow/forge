import Foundation
import GRDB

public struct Counts: Codable, Sendable, Equatable {
    public var added = 0
    public var skipped = 0
    /// Existing exercises with the same name that were linked to a Hevy template instead of duplicated.
    public var adopted = 0
}

public struct ImportReport: Codable, Sendable, Equatable {
    public var exercises = Counts()
    public var routines = Counts()
    public var workouts = Counts()
    public var warnings: [String] = []
}

/// Imports Hevy data. Records are keyed by Hevy id: ones already present are skipped, never overwritten.
public struct HevyImporter: Sendable {
    let forge: Forge

    public init(forge: Forge) { self.forge = forge }

    static func tracking(for hevyType: String?) -> TrackingType {
        switch hevyType {
        case "reps_only", "bodyweight_reps": return .repsOnly
        case "bodyweight_weighted", "weighted_bodyweight", "bodyweight_weighted_reps": return .weightedBodyweight
        case "bodyweight_assisted", "bodyweight_assisted_reps", "assisted_bodyweight": return .assistedBodyweight
        case "duration": return .duration
        case "weight_duration": return .weightDuration
        case "distance_duration": return .distanceDuration
        case "short_distance_weight", "distance": return .distance
        default: return .weightReps
        }
    }

    static func setType(_ s: String?) -> SetType {
        switch s {
        case "warmup": return .warmup
        case "failure": return .failure
        case "dropset", "drop": return .drop
        default: return .normal
        }
    }

    private func blank(_ s: String?) -> String? { (s?.isEmpty ?? true) ? nil : s }

    public func importAll(templates: [HevyTemplate], routines: [HevyRoutine], workouts: [HevyWorkout]) throws -> ImportReport {
        var report = ImportReport()
        let now = Forge.nowMillis()
        var exerciseIDs: [String: String] = [:]   // Hevy template id -> Forge exercise id
        var routineIDs: [String: String] = [:]    // Hevy routine id -> Forge routine id
        var existingWorkouts: Set<String> = []
        var unlinked: [String: [Exercise]] = [:]   // lowercased name -> local exercises with no Hevy id yet
        var routineCount = 0
        try forge.db.read { db in
            for r in try Row.fetchAll(db, sql: "SELECT id, hevy_id FROM exercises WHERE hevy_id IS NOT NULL") { exerciseIDs[r["hevy_id"]] = r["id"] }
            for r in try Row.fetchAll(db, sql: "SELECT id, hevy_id FROM routines WHERE hevy_id IS NOT NULL") { routineIDs[r["hevy_id"]] = r["id"] }
            existingWorkouts = Set(try String.fetchAll(db, sql: "SELECT hevy_id FROM workouts WHERE hevy_id IS NOT NULL"))
            routineCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM routines") ?? 0
            for r in try Row.fetchAll(db, sql: "SELECT * FROM exercises WHERE hevy_id IS NULL ORDER BY created_at") {
                let e = Store.decodeExercise(r)
                unlinked[e.name.lowercased(), default: []].append(e)
            }
        }

        var exerciseOps: [Op] = []
        for t in templates {
            if exerciseIDs[t.id] != nil { report.exercises.skipped += 1; continue }
            if var local = unlinked[t.title.lowercased()]?.first {
                unlinked[t.title.lowercased()]!.removeFirst()
                local.hevyID = t.id
                exerciseIDs[t.id] = local.id
                exerciseOps.append(.putExercise(local))
                report.exercises.adopted += 1
                continue
            }
            let e = Exercise(id: HevyIDs.exercise(t.id), name: t.title, equipment: t.equipment, primaryMuscle: t.primaryMuscleGroup,
                             secondaryMuscles: t.secondaryMuscleGroups ?? [], tracking: Self.tracking(for: t.type),
                             isCustom: t.isCustom ?? false, hevyID: t.id, createdAt: now, updatedAt: now)
            exerciseIDs[t.id] = e.id
            exerciseOps.append(.putExercise(e))
            report.exercises.added += 1
        }

        func resolve(_ block: HevyExercise) -> String {
            if let id = exerciseIDs[block.exerciseTemplateId] { return id }
            let e = Exercise(id: HevyIDs.exercise(block.exerciseTemplateId), name: block.title, isCustom: true, hevyID: block.exerciseTemplateId, createdAt: now, updatedAt: now)
            exerciseIDs[block.exerciseTemplateId] = e.id
            exerciseOps.append(.putExercise(e))
            report.exercises.added += 1
            report.warnings.append("exercise template \(block.exerciseTemplateId) was not in the template list; created \"\(block.title)\" from the block title")
            return e.id
        }

        func convert(_ blocks: [HevyExercise], completed: Bool) -> [ExerciseBlock] {
            blocks.map { b in
                ExerciseBlock(exerciseID: resolve(b), notes: blank(b.notes), restSeconds: b.restSeconds ?? 0,
                              supersetID: b.supersetId ?? b.supersetsId,
                              sets: b.sets.map { s in
                                  SetEntry(type: Self.setType(s.type), weightKg: s.weightKg, reps: s.reps,
                                           durationSeconds: s.durationSeconds, distanceMeters: s.distanceMeters, rpe: s.rpe,
                                           completed: completed)
                              })
            }
        }

        var routineOps: [Op] = []
        for r in routines {
            if routineIDs[r.id] != nil { report.routines.skipped += 1; continue }
            let routine = Routine(id: HevyIDs.routine(r.id), title: r.title, folder: r.folderId.map { "Hevy folder \($0)" }, position: routineCount + routineOps.count,
                                  exercises: convert(r.exercises, completed: false), hevyID: r.id,
                                  createdAt: HevyJSON.millis(r.createdAt) ?? now, updatedAt: HevyJSON.millis(r.updatedAt) ?? now)
            routineIDs[r.id] = routine.id
            routineOps.append(.putRoutine(routine))
            report.routines.added += 1
        }

        var workoutOps: [Op] = []
        for w in workouts {
            if existingWorkouts.contains(w.id) { report.workouts.skipped += 1; continue }
            guard let started = HevyJSON.millis(w.startTime) else {
                report.warnings.append("workout \(w.id) has an unreadable start time; skipped")
                report.workouts.skipped += 1
                continue
            }
            existingWorkouts.insert(w.id)
            workoutOps.append(.putWorkout(Workout(
                id: HevyIDs.workout(w.id), title: w.title, startedAt: started, endedAt: HevyJSON.millis(w.endTime), routineID: w.routineId.flatMap { routineIDs[$0] },
                notes: blank(w.description), exercises: convert(w.exercises, completed: true), hevyID: w.id)))
            report.workouts.added += 1
        }

        for ops in [exerciseOps, routineOps, workoutOps] where !ops.isEmpty { try forge.perform(ops, author: .importer) }
        return report
    }

    /// Reads `templates.json`, `routines.json` and `workouts.json` from a folder; each holds one page or an array of pages.
    public static func load(directory: URL) throws -> (templates: [HevyTemplate], routines: [HevyRoutine], workouts: [HevyWorkout]) {
        func items<P: HevyPage>(_ name: String, _ type: P.Type) throws -> [P.Item] {
            let url = directory.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else { return [] }
            let data = try Data(contentsOf: url)
            if let pages = try? HevyJSON.decoder.decode([P].self, from: data) { return pages.flatMap(\.items) }
            return try HevyJSON.decoder.decode(P.self, from: data).items
        }
        return (try items("templates.json", HevyTemplatesPage.self), try items("routines.json", HevyRoutinesPage.self),
                try items("workouts.json", HevyWorkoutsPage.self))
    }
}
