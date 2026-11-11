import ForgeCore
import Foundation
import Testing
@testable import ForgeUI

/// Timings with a few years of data. The bounds are generous guards against regressions, not targets.
@MainActor @Suite(.serialized) struct PerformanceTests {
    static func bigDatabase(workouts: Int = 1500) throws -> Forge {
        let f = try Forge.inMemory()
        var ops: [Op] = (0..<60).map { .putExercise(Exercise(id: "e\($0)", name: "Exercise \($0)", primaryMuscle: ["chest", "lats", "quadriceps"][$0 % 3])) }
        for w in 0..<workouts {
            let blocks = (0..<5).map { b in
                ExerciseBlock(exerciseID: "e\((w + b * 7) % 60)", restSeconds: 90,
                              sets: (0..<4).map { SetEntry(weightKg: Double(40 + $0 * 5), reps: 8, completed: true) })
            }
            ops.append(.putWorkout(Workout(id: "w\(w)", title: "Workout \(w)", startedAt: Int64(1_700_000_000_000 + w * 86_400_000), endedAt: nil, exercises: blocks)))
        }
        try f.perform(ops, author: .importer)
        return f
    }

    private func time(_ label: String, _ body: () throws -> Void) rethrows -> Double {
        let start = ContinuousClock.now
        try body()
        let ms = Double((ContinuousClock.now - start).components.attoseconds) / 1e15 + Double((ContinuousClock.now - start).components.seconds) * 1000
        print("PERF \(label): \(String(format: "%.0f", ms)) ms")
        return ms
    }

    @Test func loadingAThousandWorkouts() throws {
        let f = try Self.bigDatabase()
        let ms = try time("forge.workouts(limit: 1000)") { _ = try f.workouts(limit: 1000) }
        #expect(ms < 2000)
    }

    @Test func reloadingTheWholeAppModel() throws {
        let f = try Self.bigDatabase()
        let m = AppModel(forge: f, draftStore: nil, defaults: UserDefaults(suiteName: "perf-\(UUID().uuidString)")!)
        let ms = time("AppModel.reload()") { m.reload() }
        #expect(ms < 2000)
    }

    @Test func typingIntoAWorkoutWritesTheDraftEveryTime() throws {
        let f = try Self.bigDatabase(workouts: 5)
        final class CountingStore: DraftStore, @unchecked Sendable {
            var saves = 0
            func save(_ workout: Workout) { saves += 1; Thread.sleep(forTimeInterval: 0.002) }   // a draft write costs a couple of ms
            func load() -> Workout? { nil }
            func clear() {}
        }
        let store = CountingStore()
        let routine = Routine(id: "r", title: "R", exercises: (0..<5).map { ExerciseBlock(exerciseID: "e\($0)", sets: (0..<4).map { _ in SetEntry(weightKg: 50, reps: 8) }) })
        let s = try WorkoutSession.start(routine: routine, forge: f, store: store)
        store.saves = 0
        let ms = time("200 keystrokes in a workout") { for i in 0..<200 { s.update(exercise: i % 5, set: i % 4) { $0.reps = i % 15 } } }
        print("PERF draft writes during 200 keystrokes: \(store.saves)")
        #expect(ms < 5000)
    }
}
