import Foundation

/// Agent- and script-friendly shapes for creating and editing things: exercises can be named instead of identified,
/// weights can be given in pounds, and times are ISO-8601 strings. Resolution happens before anything is written.
public struct SetInput: Codable, Sendable {
    public var type: SetType?
    public var weightKg: Double?
    public var weightLb: Double?
    public var reps: Int?
    public var durationSeconds: Int?
    public var distanceMeters: Double?
    public var rpe: Double?
    public var completed: Bool?
}

public struct BlockInput: Codable, Sendable {
    public var exerciseID: String?
    /// Exercise name (case-insensitive, exact); use `exerciseID` when two exercises share a name.
    public var exercise: String?
    public var notes: String?
    public var restSeconds: Int?
    public var supersetID: Int?
    public var sets: [SetInput]?
}

public struct RoutineInput: Codable, Sendable {
    public var id: String?
    public var title: String
    public var folder: String?
    public var position: Int?
    public var exercises: [BlockInput]?
}

public struct WorkoutInput: Codable, Sendable {
    public var id: String?
    public var title: String
    /// ISO-8601, e.g. 2026-10-19T17:00:00Z
    public var startedAt: String?
    public var endedAt: String?
    public var routineID: String?
    public var notes: String?
    public var exercises: [BlockInput]?
}

public struct ExerciseInput: Codable, Sendable {
    public var id: String?
    public var name: String?
    public var equipment: String?
    public var primaryMuscle: String?
    public var secondaryMuscles: [String]?
    public var tracking: TrackingType?
    public var isCustom: Bool?
}

enum WeightConversion {
    static let poundsPerKg = 2.2046226218
}

extension Forge {
    func resolveExercise(id: String?, name: String?) throws -> String {
        switch (id, name) {
        case let (id?, nil):
            guard try exercise(id: id) != nil else { throw ForgeError.notFound("exercise \(id)") }
            return id
        case let (nil, name?):
            let matches = try exercises().filter { $0.name.lowercased() == name.lowercased() }
            guard let first = matches.first else { throw ForgeError.notFound("exercise named \"\(name)\"") }
            guard matches.count == 1 else {
                let list = matches.map { "\($0.id) (\($0.name)\($0.isCustom ? ", custom" : ""))" }.joined(separator: ", ")
                throw ForgeError.invalid("exercise named \"\(name)\" is ambiguous: \(list). Pass exerciseID.")
            }
            return first.id
        default:
            throw ForgeError.invalid("each exercise needs exactly one of exerciseID or exercise (a name)")
        }
    }

    func blocks(from inputs: [BlockInput]?, setsCompleted: Bool) throws -> [ExerciseBlock] {
        try (inputs ?? []).map { b in
            ExerciseBlock(
                exerciseID: try resolveExercise(id: b.exerciseID, name: b.exercise), notes: b.notes, restSeconds: b.restSeconds ?? 0,
                supersetID: b.supersetID,
                sets: (b.sets ?? []).map { s in
                    SetEntry(type: s.type ?? .normal, weightKg: s.weightKg ?? s.weightLb.map { $0 / WeightConversion.poundsPerKg }, reps: s.reps,
                             durationSeconds: s.durationSeconds, distanceMeters: s.distanceMeters, rpe: s.rpe, completed: s.completed ?? setsCompleted)
                })
        }
    }

    /// Creates a routine, or replaces the one with the same id (keeping its creation time and, unless given, its position).
    @discardableResult
    public func putRoutine(_ input: RoutineInput, author: Author) throws -> Routine {
        let blocks = try blocks(from: input.exercises, setsCompleted: false)
        let now = Forge.nowMillis()
        var routine: Routine
        if let id = input.id, let existing = try self.routine(id: id) {
            routine = existing
            routine.title = input.title
            routine.folder = input.folder ?? existing.folder
            routine.position = input.position ?? existing.position
        } else {
            let count = try routines().count
            routine = Routine(id: input.id ?? UUID().uuidString, title: input.title, folder: input.folder, position: input.position ?? count,
                              createdAt: now)
        }
        routine.exercises = blocks
        routine.updatedAt = now
        try perform([.putRoutine(routine)], author: author)
        return routine
    }

    /// Creates a workout (sets default to completed), or replaces the one with the same id.
    @discardableResult
    public func putWorkout(_ input: WorkoutInput, author: Author) throws -> Workout {
        guard let startText = input.startedAt, let started = HevyJSON.millis(startText) else {
            throw ForgeError.invalid("startedAt must be an ISO-8601 time like 2026-10-19T17:00:00Z")
        }
        var ended: Int64?
        if let endText = input.endedAt {
            guard let e = HevyJSON.millis(endText) else { throw ForgeError.invalid("endedAt must be an ISO-8601 time") }
            ended = e
        }
        let workout = Workout(id: input.id ?? UUID().uuidString, title: input.title, startedAt: started, endedAt: ended, routineID: input.routineID,
                              notes: input.notes, exercises: try blocks(from: input.exercises, setsCompleted: true),
                              hevyID: try input.id.flatMap { try self.workout(id: $0)?.hevyID })
        try perform([.putWorkout(workout)], author: author)
        return workout
    }

    /// Creates an exercise (needs a name), or updates only the given fields of the one with that id.
    @discardableResult
    public func putExercise(_ input: ExerciseInput, author: Author) throws -> Exercise {
        let now = Forge.nowMillis()
        var e: Exercise
        if let id = input.id, let existing = try exercise(id: id) {
            e = existing
            if let name = input.name { e.name = name }
        } else {
            guard let name = input.name, !name.trimmingCharacters(in: .whitespaces).isEmpty else { throw ForgeError.invalid("a new exercise needs a name") }
            e = Exercise(id: input.id ?? UUID().uuidString, name: name, createdAt: now)
        }
        if let v = input.equipment { e.equipment = v }
        if let v = input.primaryMuscle { e.primaryMuscle = v }
        if let v = input.secondaryMuscles { e.secondaryMuscles = v }
        if let v = input.tracking { e.tracking = v }
        if let v = input.isCustom { e.isCustom = v }
        e.updatedAt = now
        try perform([.putExercise(e)], author: author)
        return e
    }

    /// Records bodyweight for a day (yyyy-MM-dd) from pounds or kilograms.
    public func setBodyweight(date: String, pounds: Double?, kg: Double?, author: Author) throws {
        let parts = date.split(separator: "-")
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2, parts.allSatisfy({ Int($0) != nil }) else {
            throw ForgeError.invalid("date must look like 2026-10-20")
        }
        guard let value = kg ?? pounds.map({ $0 / WeightConversion.poundsPerKg }), value > 0 else {
            throw ForgeError.invalid("give a weight in pounds or kg")
        }
        try perform([.putBodyweight(date: date, kg: value)], author: author)
    }
}
