import ForgeCore
import Foundation

/// Where an in-progress workout is kept so it survives the app being killed.
public protocol DraftStore {
    func save(_ workout: Workout)
    func load() -> Workout?
    func clear()
}

public struct FileDraftStore: DraftStore {
    let url: URL

    public init(url: URL) { self.url = url }

    public func save(_ workout: Workout) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(workout) { try? data.write(to: url, options: .atomic) }
    }

    public func load() -> Workout? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Workout.self, from: data)
    }

    public func clear() { try? FileManager.default.removeItem(at: url) }
}
