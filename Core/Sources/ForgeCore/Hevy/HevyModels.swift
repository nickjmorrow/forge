import Foundation

/// Hevy's REST payloads, decoded with snake_case keys converted to camelCase.
public enum HevyJSON {
    public static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }

    /// Milliseconds since the epoch for an ISO-8601 timestamp, with or without fractional seconds.
    public static func millis(_ s: String?) -> Int64? {
        guard let s else { return nil }
        let date = (try? Date(s, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
            ?? (try? Date(s, strategy: Date.ISO8601FormatStyle()))
        return date.map { Int64($0.timeIntervalSince1970 * 1000) }
    }
}

public struct HevySet: Decodable, Sendable {
    public var type: String?
    public var weightKg: Double?
    public var reps: Int?
    public var distanceMeters: Double?
    public var durationSeconds: Int?
    public var rpe: Double?
}

public struct HevyExercise: Decodable, Sendable {
    public var title: String
    public var notes: String?
    public var exerciseTemplateId: String
    public var supersetId: Int?
    /// Workouts spell it `supersets_id`; routines spell it `superset_id`.
    public var supersetsId: Int?
    public var restSeconds: Int?
    public var sets: [HevySet]
}

public struct HevyRoutine: Decodable, Sendable {
    public var id: String
    public var title: String
    public var folderId: Int?
    public var createdAt: String?
    public var updatedAt: String?
    public var exercises: [HevyExercise]
}

public struct HevyWorkout: Decodable, Sendable {
    public var id: String
    public var title: String
    public var description: String?
    public var startTime: String
    public var endTime: String?
    public var routineId: String?
    public var exercises: [HevyExercise]
}

public struct HevyTemplate: Decodable, Sendable {
    public var id: String
    public var title: String
    public var type: String?
    public var primaryMuscleGroup: String?
    public var secondaryMuscleGroups: [String]?
    public var equipment: String?
    public var isCustom: Bool?
}

public protocol HevyPage: Decodable, Sendable {
    associatedtype Item: Sendable
    var pageCount: Int { get }
    var items: [Item] { get }
}

public struct HevyRoutinesPage: HevyPage {
    public var pageCount: Int
    public var routines: [HevyRoutine]
    public var items: [HevyRoutine] { routines }
}

public struct HevyWorkoutsPage: HevyPage {
    public var pageCount: Int
    public var workouts: [HevyWorkout]
    public var items: [HevyWorkout] { workouts }
}

public struct HevyTemplatesPage: HevyPage {
    public var pageCount: Int
    public var exerciseTemplates: [HevyTemplate]
    public var items: [HevyTemplate] { exerciseTemplates }
}
