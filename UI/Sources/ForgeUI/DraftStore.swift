import ForgeCore
import Foundation

/// An in-progress workout as it is kept on disk: the workout, and its stopwatch when one is going.
public struct WorkoutDraft: Codable, Equatable, Sendable {
    public struct Stopwatch: Codable, Equatable, Sendable {
        public var exerciseIndex: Int
        public var startedAt: Date?
        public var bankedSeconds: TimeInterval
    }

    public var workout: Workout
    public var stopwatch: Stopwatch?

    public init(workout: Workout, stopwatch: Stopwatch? = nil) {
        self.workout = workout
        self.stopwatch = stopwatch
    }
}

/// Where an in-progress workout is kept so it survives the app being killed.
public protocol DraftStore {
    func save(_ draft: WorkoutDraft)
    func load() -> WorkoutDraft?
    func clear()
}

public struct FileDraftStore: DraftStore {
    let url: URL

    public init(url: URL) { self.url = url }

    public func save(_ draft: WorkoutDraft) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(draft) { try? data.write(to: url, options: .atomic) }
    }

    public func load() -> WorkoutDraft? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let draft = try? JSONDecoder().decode(WorkoutDraft.self, from: data) { return draft }
        // A draft written before stopwatches were kept is the bare workout.
        return (try? JSONDecoder().decode(Workout.self, from: data)).map { WorkoutDraft(workout: $0) }
    }

    public func clear() { try? FileManager.default.removeItem(at: url) }
}
