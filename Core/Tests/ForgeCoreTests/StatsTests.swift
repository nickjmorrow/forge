import Foundation
import Testing
@testable import ForgeCore

func ms(_ iso: String) -> Int64 { Int64(ISO8601DateFormatter().date(from: iso)!.timeIntervalSince1970 * 1000) }

private func done(_ w: Double?, _ r: Int?, _ type: SetType = .normal) -> SetEntry {
    SetEntry(type: type, weightKg: w, reps: r, completed: true)
}

private func exercisesFixture(_ f: Forge) throws {
    try f.perform([.putExercise(Exercise(id: "bench", name: "Bench", primaryMuscle: "chest")),
                   .putExercise(Exercise(id: "row", name: "Row", primaryMuscle: "lats"))], author: .me)
}

@Suite struct StatsTests {
    @Test func e1RMUsesEpleyAndOneRepIsWeight() {
        #expect(abs(e1RM(weightKg: 100, reps: 5) - 116.667) < 0.01)
        #expect(e1RM(weightKg: 100, reps: 1) == 100)
    }

    @Test func personalRecordsIgnoreWarmupsAndNulls() throws {
        let f = try Forge.inMemory()
        try exercisesFixture(f)
        let sets = [done(200, 5, .warmup), done(100, 5), done(nil, 10), done(120, 1), SetEntry(weightKg: 300, reps: 1, completed: false)]
        try f.perform([.putWorkout(Workout(id: "w1", title: "A", startedAt: 1000, exercises: [ExerciseBlock(exerciseID: "bench", sets: sets)]))], author: .me)
        let pr = try f.personalRecords(exerciseID: "bench")
        #expect(pr.heaviestKg == 120)
        #expect(pr.bestE1RMKg == 120)
        #expect(pr.bestSetVolumeKg == 500)
    }

    @Test func prsRecomputeAfterWorkoutEdit() throws {
        let f = try Forge.inMemory()
        try exercisesFixture(f)
        var w = Workout(id: "w1", title: "A", startedAt: 1000, exercises: [ExerciseBlock(exerciseID: "bench", sets: [done(140, 3), done(100, 5)])])
        try f.perform([.putWorkout(w)], author: .me)
        #expect(try f.personalRecords(exerciseID: "bench").heaviestKg == 140)
        w.exercises[0].sets[0].weightKg = 90
        try f.perform([.putWorkout(w)], author: .me)
        #expect(try f.personalRecords(exerciseID: "bench").heaviestKg == 100)
    }

    @Test func lastPerformanceSkipsIncompleteSets() throws {
        let f = try Forge.inMemory()
        try exercisesFixture(f)
        let older = Workout(id: "w1", title: "old", startedAt: 1000, exercises: [ExerciseBlock(exerciseID: "bench", sets: [done(80, 8)])])
        let newer = Workout(id: "w2", title: "new", startedAt: 2000, exercises: [ExerciseBlock(exerciseID: "bench", sets: [done(90, 6), SetEntry(weightKg: 95, reps: 5, completed: false)])])
        try f.perform([.putWorkout(older), .putWorkout(newer)], author: .me)
        #expect(try f.lastPerformance(exerciseID: "bench", before: 3000)?.map(\.weightKg) == [90])
        #expect(try f.lastPerformance(exerciseID: "bench", before: 2000)?.map(\.weightKg) == [80])
        #expect(try f.lastPerformance(exerciseID: "bench", before: 1000) == nil)
    }

    @Test func emptyHistoryReturnsEmptyNotError() throws {
        let f = try Forge.inMemory()
        let pr = try f.personalRecords(exerciseID: "nothing")
        #expect(pr == PersonalRecords(heaviestKg: nil, bestE1RMKg: nil, bestSetVolumeKg: nil))
        #expect(try f.exerciseHistory(exerciseID: "nothing", limit: 10).isEmpty)
        #expect(try f.lastPerformance(exerciseID: "nothing", before: 5) == nil)
        #expect(try f.weeklySets(since: 0, timeZone: TimeZone(identifier: "UTC")!).isEmpty)
        try f.perform([.putWorkout(Workout(id: "empty", title: "no sets", startedAt: 5))], author: .me)
        #expect(try f.weeklySets(since: 0, timeZone: TimeZone(identifier: "UTC")!).isEmpty)
    }

    @Test func exerciseHistoryIsNewestFirstAndLimited() throws {
        let f = try Forge.inMemory()
        try exercisesFixture(f)
        let ws = (1...3).map { Workout(id: "w\($0)", title: "w", startedAt: Int64($0) * 1000, exercises: [ExerciseBlock(exerciseID: "bench", sets: [done(Double($0) * 10, 5)])]) }
        try f.perform(ws.map(Op.putWorkout), author: .me)
        let history = try f.exerciseHistory(exerciseID: "bench", limit: 2)
        #expect(history.map(\.workoutID) == ["w3", "w2"])
        #expect(history[0].sets[0].weightKg == 30)
    }

    @Test func weeklySetsGroupsByMondayAndPrimaryMuscle() throws {
        let f = try Forge.inMemory()
        try exercisesFixture(f)
        let sun = Workout(id: "sun", title: "s", startedAt: ms("2026-10-18T12:00:00Z"), exercises: [ExerciseBlock(exerciseID: "bench", sets: [done(80, 5), done(80, 5)])])
        let mon = Workout(id: "mon", title: "m", startedAt: ms("2026-10-19T12:00:00Z"), exercises: [
            ExerciseBlock(exerciseID: "bench", sets: [done(80, 5, .warmup), done(80, 5), done(80, 5), done(80, 5)]),
            ExerciseBlock(exerciseID: "row", sets: [done(60, 10), done(60, 10)])])
        let tue = Workout(id: "tue", title: "t", startedAt: ms("2026-10-20T12:00:00Z"), exercises: [ExerciseBlock(exerciseID: "bench", sets: [done(80, 5)])])
        try f.perform([.putWorkout(sun), .putWorkout(mon), .putWorkout(tue)], author: .me)
        let rows = try f.weeklySets(since: 0, timeZone: TimeZone(identifier: "UTC")!)
        #expect(rows == [WeekMuscle(weekStart: "2026-10-12", muscle: "chest", sets: 2),
                         WeekMuscle(weekStart: "2026-10-19", muscle: "chest", sets: 4),
                         WeekMuscle(weekStart: "2026-10-19", muscle: "lats", sets: 2)])
    }
}

@Suite struct WorkoutLoadingTests {
    private func seeded(_ n: Int) throws -> Forge {
        let f = try Forge.inMemory()
        var ops: [Op] = []
        for w in 0..<n {
            let blocks = (0..<3).map { b in
                ExerciseBlock(exerciseID: "e\(b)", notes: b == 1 ? "note \(w)" : nil, restSeconds: 60 + b, supersetID: b == 2 ? 1 : nil,
                              sets: (0..<(b + 1)).map { SetEntry(type: $0 == 0 && b == 0 ? .warmup : .normal, weightKg: Double(w + $0), reps: 5 + $0, rpe: $0 == 1 ? 8 : nil, completed: $0 % 2 == 0) })
            }
            ops.append(.putWorkout(Workout(id: "w\(w)", title: "W\(w)", startedAt: Int64(1000 + w), endedAt: Int64(2000 + w), routineID: w % 2 == 0 ? "r" : nil, notes: "n\(w)", exercises: blocks, hevyID: "h\(w)")))
        }
        ops.append(.putWorkout(Workout(id: "empty", title: "Nothing", startedAt: 5000)))      // a workout with no exercises at all
        try f.perform(ops, author: .me)
        return f
    }

    @Test func theBatchLoadMatchesLoadingEachWorkoutOnItsOwn() throws {
        let f = try seeded(40)
        let all = try f.workouts(limit: 100)
        #expect(all.count == 41 && all.first?.id == "empty")                      // newest first
        for w in all { #expect(try f.workout(id: w.id) == w) }
    }

    @Test func limitAndBeforeStillApply() throws {
        let f = try seeded(40)
        #expect(try f.workouts(limit: 5).count == 5)
        #expect(try f.workouts(limit: 100, before: 1010).allSatisfy { $0.startedAt < 1010 })
        #expect(try f.workouts(limit: 0).isEmpty)
    }

    @Test func aThousandWorkoutsLoadQuickly() throws {
        let f = try seeded(1000)
        let start = ContinuousClock.now
        let loaded = try f.workouts(limit: 1000)
        let elapsed = ContinuousClock.now - start
        #expect(loaded.count == 1000)
        #expect(elapsed < .milliseconds(120))          // debug build; the one-query-per-workout version took ~270 ms
    }
}
