import Foundation

public enum Author: String, Codable, Sendable { case me, claude, importer }

public enum TrackingType: String, Codable, Sendable, CaseIterable {
    case weightReps, repsOnly, weightedBodyweight, assistedBodyweight, duration, weightDuration, distance, distanceDuration
}

public enum SetType: String, Codable, Sendable { case warmup, normal, failure, drop }

public struct SetEntry: Codable, Sendable, Equatable {
    public var type: SetType
    public var weightKg: Double?
    public var reps: Int?
    public var durationSeconds: Int?
    public var distanceMeters: Double?
    public var rpe: Double?
    public var completed: Bool

    public init(type: SetType = .normal, weightKg: Double? = nil, reps: Int? = nil, durationSeconds: Int? = nil,
                distanceMeters: Double? = nil, rpe: Double? = nil, completed: Bool = false) {
        self.type = type; self.weightKg = weightKg; self.reps = reps; self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters; self.rpe = rpe; self.completed = completed
    }
}

/// One exercise inside a routine or a workout, with its sets.
public struct ExerciseBlock: Codable, Sendable, Equatable {
    /// `restSeconds` of -1 means no rest timer for this exercise; 0 means "use the app's default".
    public static let restOff = -1

    public var exerciseID: String
    public var notes: String?
    public var restSeconds: Int
    public var supersetID: Int?
    public var sets: [SetEntry]

    public init(exerciseID: String, notes: String? = nil, restSeconds: Int = 0, supersetID: Int? = nil, sets: [SetEntry] = []) {
        self.exerciseID = exerciseID; self.notes = notes; self.restSeconds = restSeconds
        self.supersetID = supersetID; self.sets = sets
    }
}

public struct Exercise: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var equipment: String?
    public var primaryMuscle: String?
    public var secondaryMuscles: [String]
    public var tracking: TrackingType
    public var isCustom: Bool
    public var hevyID: String?
    public var createdAt: Int64
    public var updatedAt: Int64

    public init(id: String = UUID().uuidString, name: String, equipment: String? = nil, primaryMuscle: String? = nil,
                secondaryMuscles: [String] = [], tracking: TrackingType = .weightReps, isCustom: Bool = true,
                hevyID: String? = nil, createdAt: Int64 = Forge.nowMillis(), updatedAt: Int64 = Forge.nowMillis()) {
        self.id = id; self.name = name; self.equipment = equipment; self.primaryMuscle = primaryMuscle
        self.secondaryMuscles = secondaryMuscles; self.tracking = tracking; self.isCustom = isCustom
        self.hevyID = hevyID; self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

public struct Routine: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var folder: String?
    public var position: Int
    public var exercises: [ExerciseBlock]
    public var hevyID: String?
    public var createdAt: Int64
    public var updatedAt: Int64

    public init(id: String = UUID().uuidString, title: String, folder: String? = nil, position: Int = 0,
                exercises: [ExerciseBlock] = [], hevyID: String? = nil,
                createdAt: Int64 = Forge.nowMillis(), updatedAt: Int64 = Forge.nowMillis()) {
        self.id = id; self.title = title; self.folder = folder; self.position = position
        self.exercises = exercises; self.hevyID = hevyID; self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

public struct Workout: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var startedAt: Int64
    public var endedAt: Int64?
    public var routineID: String?
    public var notes: String?
    public var exercises: [ExerciseBlock]
    public var hevyID: String?

    public init(id: String = UUID().uuidString, title: String, startedAt: Int64, endedAt: Int64? = nil,
                routineID: String? = nil, notes: String? = nil, exercises: [ExerciseBlock] = [], hevyID: String? = nil) {
        self.id = id; self.title = title; self.startedAt = startedAt; self.endedAt = endedAt
        self.routineID = routineID; self.notes = notes; self.exercises = exercises; self.hevyID = hevyID
    }
}
