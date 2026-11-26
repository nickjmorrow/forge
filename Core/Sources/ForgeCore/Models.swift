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
    /// The rep range this exercise progresses in (both set, or neither): reps climb to `repsMax`, then the weight goes up
    /// and reps restart at `repsMin`. Nil means "repeat last time".
    public var repsMin: Int?
    public var repsMax: Int?
    /// Other exercises that can fill this slot instead ("do this or this"): ids, in the order to offer them. Nil when none.
    public var alternatives: [String]?
    public var sets: [SetEntry]

    public init(exerciseID: String, notes: String? = nil, restSeconds: Int = 0, supersetID: Int? = nil,
                repsMin: Int? = nil, repsMax: Int? = nil, alternatives: [String]? = nil, sets: [SetEntry] = []) {
        self.exerciseID = exerciseID; self.notes = notes; self.restSeconds = restSeconds
        self.supersetID = supersetID; self.repsMin = repsMin; self.repsMax = repsMax
        self.alternatives = (alternatives?.isEmpty ?? true) ? nil : alternatives
        self.sets = sets
    }

    public var repRange: ClosedRange<Int>? {
        guard let low = repsMin, let high = repsMax, low >= 1, low <= high else { return nil }
        return low...high
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
    /// A deliberately lighter session. It is kept in history but never becomes "last time": it doesn't change the routine
    /// and isn't what the next workout is compared with. Nil (workouts saved before this existed) means no.
    public var offDay: Bool?

    public init(id: String = UUID().uuidString, title: String, startedAt: Int64, endedAt: Int64? = nil,
                routineID: String? = nil, notes: String? = nil, exercises: [ExerciseBlock] = [], hevyID: String? = nil,
                offDay: Bool? = nil) {
        self.id = id; self.title = title; self.startedAt = startedAt; self.endedAt = endedAt
        self.routineID = routineID; self.notes = notes; self.exercises = exercises; self.hevyID = hevyID
        self.offDay = offDay
    }

    public var isOffDay: Bool { offDay ?? false }
}

/// One movement in a guide: what it is, and optionally how to do it.
public struct GuideStep: Codable, Sendable, Equatable {
    public var name: String
    public var cue: String?
    /// A looping drawing of the movement, if one has been made for it.
    public var figure: Figure?

    public init(name: String, cue: String? = nil, figure: Figure? = nil) { self.name = name; self.cue = cue; self.figure = figure }
}

public struct GuideSection: Codable, Sendable, Equatable {
    /// May be empty: a guide with one untitled section is a flat list.
    public var title: String
    public var steps: [GuideStep]

    public init(title: String = "", steps: [GuideStep] = []) { self.title = title; self.steps = steps }
}

/// A list of steps to read through (a mobility or stretching sequence). Unlike a routine it is never started or logged.
public struct Guide: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    /// A line for the whole guide, such as how many reps of each step.
    public var notes: String?
    public var position: Int
    public var sections: [GuideSection]
    public var createdAt: Int64
    public var updatedAt: Int64

    public init(id: String = UUID().uuidString, title: String, notes: String? = nil, position: Int = 0, sections: [GuideSection] = [],
                createdAt: Int64 = Forge.nowMillis(), updatedAt: Int64 = Forge.nowMillis()) {
        self.id = id; self.title = title; self.notes = notes; self.position = position; self.sections = sections
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    public var stepCount: Int { sections.reduce(0) { $0 + $1.steps.count } }
}
