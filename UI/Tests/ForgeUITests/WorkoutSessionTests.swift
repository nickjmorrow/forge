import Foundation
import ForgeCore
import Testing
@testable import ForgeUI

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private func lib() throws -> Forge {
    let f = try Forge.inMemory()
    try f.perform([
        .putExercise(Exercise(id: "bench", name: "Bench Press", primaryMuscle: "chest")),
        .putExercise(Exercise(id: "row", name: "Row", primaryMuscle: "lats")),
        .putExercise(Exercise(id: "fly", name: "Fly", primaryMuscle: "chest")),
    ], author: .me)
    return f
}

private func chestRoutine() -> Routine {
    Routine(id: "r1", title: "Chest", exercises: [
        ExerciseBlock(exerciseID: "bench", restSeconds: 120, sets: [
            SetEntry(type: .warmup, weightKg: 40, reps: 10), SetEntry(weightKg: 80, reps: 6), SetEntry(weightKg: 80, reps: 6)]),
        ExerciseBlock(exerciseID: "fly", restSeconds: 0, sets: [SetEntry(weightKg: 20, reps: 12)]),
    ], createdAt: 1, updatedAt: 1)
}

private func done(_ w: Double, _ r: Int) -> SetEntry { SetEntry(weightKg: w, reps: r, completed: true) }

@MainActor @Suite struct WorkoutSessionTests {
    @Test func startFromRoutinePrefillsPlannedSetsUncompleted() throws {
        let f = try lib()
        let s = try WorkoutSession.start(routine: chestRoutine(), forge: f, store: nil, now: t0)
        #expect(s.workout.title == "Chest" && s.workout.routineID == "r1")
        #expect(s.workout.startedAt == Int64(t0.timeIntervalSince1970 * 1000))
        #expect(s.workout.exercises.count == 2 && s.workout.exercises[0].sets.count == 3)
        #expect(s.workout.exercises[0].sets.allSatisfy { !$0.completed })
        #expect(s.workout.exercises[0].sets[1].weightKg == 80)
    }

    @Test func emptyStartHasNoExercises() throws {
        let s = try WorkoutSession.start(routine: nil, forge: try lib(), store: nil, now: t0)
        #expect(s.workout.exercises.isEmpty && s.workout.routineID == nil && s.workout.title.hasSuffix("Workout"))
    }

    @Test func previousSetsComeFromLastPerformance() throws {
        let f = try lib()
        try f.perform([.putWorkout(Workout(id: "old", title: "Old", startedAt: 1000, exercises: [ExerciseBlock(exerciseID: "bench", sets: [done(75, 8)])]))], author: .me)
        let s = try WorkoutSession.start(routine: chestRoutine(), forge: f, store: nil, now: t0)
        #expect(s.previous["bench"]?.first?.weightKg == 75)
        #expect(s.previous["fly"] == nil)
    }

    @Test func completingASetStartsRestWithTheBlocksRest() throws {
        let s = try WorkoutSession.start(routine: chestRoutine(), forge: try lib(), store: nil, now: t0)
        s.toggleComplete(exercise: 0, set: 1, now: t0)
        #expect(s.workout.exercises[0].sets[1].completed)
        #expect(s.rest.remaining(at: t0) == 120)
        s.toggleComplete(exercise: 1, set: 0, now: t0)             // rest 0 -> default
        #expect(s.rest.remaining(at: t0) == 90)
    }

    @Test func uncompletingDoesNotStartTheTimer() throws {
        let s = try WorkoutSession.start(routine: chestRoutine(), forge: try lib(), store: nil, now: t0)
        s.toggleComplete(exercise: 0, set: 1, now: t0)
        s.skipRest()
        s.toggleComplete(exercise: 0, set: 1, now: t0)
        #expect(!s.workout.exercises[0].sets[1].completed)
        #expect(!s.rest.isRunning(at: t0))
    }

    @Test func warmupSetsStartRestToo() throws {
        let s = try WorkoutSession.start(routine: chestRoutine(), forge: try lib(), store: nil, now: t0)
        s.toggleComplete(exercise: 0, set: 0, now: t0)
        #expect(s.rest.isRunning(at: t0))
    }

    @Test func addExerciseGetsOneEmptySetAndDefaultRest() throws {
        let s = try WorkoutSession.start(routine: nil, forge: try lib(), store: nil, now: t0)
        s.addExercise("row")
        #expect(s.workout.exercises.count == 1 && s.workout.exercises[0].sets.count == 1)
        #expect(s.workout.exercises[0].restSeconds == 90)
    }

    @Test func addSetCopiesTheLastSetsValues() throws {
        let s = try WorkoutSession.start(routine: chestRoutine(), forge: try lib(), store: nil, now: t0)
        s.addSet(toExercise: 0)
        let last = s.workout.exercises[0].sets.last!
        #expect(s.workout.exercises[0].sets.count == 4 && last.weightKg == 80 && last.reps == 6 && !last.completed && last.type == .normal)
    }

    @Test func removeSetAndExerciseAndMove() throws {
        let s = try WorkoutSession.start(routine: chestRoutine(), forge: try lib(), store: nil, now: t0)
        s.removeSet(exercise: 0, set: 0)
        #expect(s.workout.exercises[0].sets.count == 2)
        s.moveExercise(from: 1, to: 0)
        #expect(s.workout.exercises.map(\.exerciseID) == ["fly", "bench"])
        s.removeExercise(at: 0)
        #expect(s.workout.exercises.map(\.exerciseID) == ["bench"])
    }

    @Test func swapKeepsPlannedValuesButClearsCompletion() throws {
        let s = try WorkoutSession.start(routine: chestRoutine(), forge: try lib(), store: nil, now: t0)
        s.toggleComplete(exercise: 0, set: 1, now: t0)
        s.swapExercise(at: 0, with: "row")
        #expect(s.workout.exercises[0].exerciseID == "row")
        #expect(s.workout.exercises[0].sets[1].weightKg == 80 && !s.workout.exercises[0].sets[1].completed)
        #expect(s.previous["row"] == nil)
    }

    @Test func updateEditsASet() throws {
        let s = try WorkoutSession.start(routine: chestRoutine(), forge: try lib(), store: nil, now: t0)
        s.update(exercise: 0, set: 1) { $0.weightKg = 85; $0.reps = 5 }
        #expect(s.workout.exercises[0].sets[1].weightKg == 85 && s.workout.exercises[0].sets[1].reps == 5)
    }

    @Test func finishDropsIncompleteSetsAndEmptyExercisesThenSaves() throws {
        let f = try lib()
        let s = try WorkoutSession.start(routine: chestRoutine(), forge: f, store: nil, now: t0)
        s.toggleComplete(exercise: 0, set: 1, now: t0)
        let summary = try s.finish(now: t0.addingTimeInterval(3600))
        let saved = try #require(try f.workout(id: s.workout.id))
        #expect(saved.exercises.count == 1 && saved.exercises[0].sets.count == 1 && saved.exercises[0].sets[0].completed)
        #expect(saved.endedAt == Int64(t0.addingTimeInterval(3600).timeIntervalSince1970 * 1000))
        #expect(summary.durationSeconds == 3600)
        #expect(abs(summary.volumeKg - 480) < 0.001)
        #expect(summary.setCount == 1)
        #expect(try f.changes(since: 0).last?.author == .me)
    }

    @Test func finishWithNothingCompletedSavesNothing() throws {
        let f = try lib()
        let s = try WorkoutSession.start(routine: chestRoutine(), forge: f, store: nil, now: t0)
        #expect(throws: WorkoutSessionError.nothingToSave) { try s.finish(now: t0) }
        #expect(try f.workouts().isEmpty)
    }

    @Test func finishReportsNewPersonalRecords() throws {
        let f = try lib()
        try f.perform([.putWorkout(Workout(id: "old", title: "Old", startedAt: 1000, exercises: [ExerciseBlock(exerciseID: "bench", sets: [done(80, 5)])]))], author: .me)
        let s = try WorkoutSession.start(routine: nil, forge: f, store: nil, now: t0)
        s.addExercise("bench")
        s.update(exercise: 0, set: 0) { $0.weightKg = 90; $0.reps = 5 }
        s.toggleComplete(exercise: 0, set: 0, now: t0)
        let summary = try s.finish(now: t0.addingTimeInterval(600))
        #expect(summary.newRecords == ["Bench Press"])
    }

    @Test func firstEverWorkoutOfAnExerciseIsNotCalledARecord() throws {
        let f = try lib()
        let s = try WorkoutSession.start(routine: nil, forge: f, store: nil, now: t0)
        s.addExercise("bench")
        s.update(exercise: 0, set: 0) { $0.weightKg = 90; $0.reps = 5 }
        s.toggleComplete(exercise: 0, set: 0, now: t0)
        #expect(try s.finish(now: t0.addingTimeInterval(60)).newRecords.isEmpty)
    }

    @Test func finishingUpdatesTheRoutinesNumbersWithoutRemovingAnything() throws {
        let f = try lib()
        try f.perform([.putRoutine(chestRoutine())], author: .me)
        let s = try WorkoutSession.start(routine: chestRoutine(), forge: f, store: nil, now: t0)
        s.update(exercise: 0, set: 1) { $0.weightKg = 85 }
        s.toggleComplete(exercise: 0, set: 1, now: t0)                       // only one of three bench sets, and nothing on the fly
        let summary = try s.finish(now: t0.addingTimeInterval(60))
        let routine = try #require(try f.routine(id: "r1"))
        #expect(routine.exercises.map(\.exerciseID) == ["bench", "fly"])       // no exercise removed
        #expect(routine.exercises[0].sets.count == 3)                        // no set removed
        #expect(routine.exercises[0].sets[1].weightKg == 85)                 // the value used is now the plan
        #expect(routine.exercises[0].sets[2].weightKg == 80)                 // sets not done keep their plan
        #expect(routine.exercises[1].sets[0].weightKg == 20)                 // an exercise not done is untouched
        #expect(summary.routineUpdate?.id == "r1")
    }

    @Test func aWorkoutAsPlannedLeavesTheRoutineAlone() throws {
        let f = try lib()
        try f.perform([.putRoutine(chestRoutine())], author: .me)
        let before = try f.routine(id: "r1")
        let s = try WorkoutSession.start(routine: chestRoutine(), forge: f, store: nil, now: t0)
        s.toggleComplete(exercise: 0, set: 1, now: t0)
        let summary = try s.finish(now: t0.addingTimeInterval(60))
        let after = try f.routine(id: "r1")
        #expect(summary.routineUpdate == nil && after == before)
    }

    @Test func extraSetsDoneAreAddedToThePlan() throws {
        let f = try lib()
        try f.perform([.putRoutine(chestRoutine())], author: .me)
        let s = try WorkoutSession.start(routine: chestRoutine(), forge: f, store: nil, now: t0)
        s.addSet(toExercise: 1)
        s.update(exercise: 1, set: 1) { $0.weightKg = 22; $0.reps = 10 }
        s.toggleComplete(exercise: 1, set: 1, now: t0)
        _ = try s.finish(now: t0.addingTimeInterval(60))
        #expect(try f.routine(id: "r1")?.exercises[1].sets.count == 2)
        #expect(try f.routine(id: "r1")?.exercises[1].sets[1].weightKg == 22)
    }

    @Test func theWorkoutAndTheRoutineUpdateUndoTogether() throws {
        let f = try lib()
        try f.perform([.putRoutine(chestRoutine())], author: .me)
        let s = try WorkoutSession.start(routine: chestRoutine(), forge: f, store: nil, now: t0)
        s.update(exercise: 0, set: 1) { $0.weightKg = 85 }
        s.toggleComplete(exercise: 0, set: 1, now: t0)
        _ = try s.finish(now: t0.addingTimeInterval(60))
        #expect(try f.workouts().count == 1)
        try f.undo(author: .me)
        #expect(try f.workouts().isEmpty)
        #expect(try f.routine(id: "r1")?.exercises[0].sets[1].weightKg == 80)
    }

    @Test func draftSurvivesARestart() throws {
        let f = try lib()
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + "draft-\(UUID().uuidString).json")
        let store = FileDraftStore(url: url)
        let s = try WorkoutSession.start(routine: chestRoutine(), forge: f, store: store, now: t0)
        s.toggleComplete(exercise: 0, set: 1, now: t0)
        s.flushDraft()
        let restored = try #require(WorkoutSession.restore(forge: f, store: FileDraftStore(url: url)))
        #expect(restored.workout == s.workout)
        _ = try restored.finish(now: t0.addingTimeInterval(60))
        restored.flushDraft()
        #expect(WorkoutSession.restore(forge: f, store: FileDraftStore(url: url)) == nil)
    }

    @Test func discardClearsTheDraft() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + "draft-\(UUID().uuidString).json")
        let store = FileDraftStore(url: url)
        let s = try WorkoutSession.start(routine: chestRoutine(), forge: try lib(), store: store, now: t0)
        s.discard()
        s.flushDraft()
        #expect(WorkoutSession.restore(forge: try lib(), store: store) == nil)
    }
}

@MainActor @Suite struct SessionConvenienceTests {
    private func sessionWithHistory() throws -> WorkoutSession {
        let f = try lib()
        try f.perform([.putWorkout(Workout(id: "old", title: "Old", startedAt: 1000, exercises: [ExerciseBlock(exerciseID: "bench", sets: [done(75, 8), done(70, 10)])]))], author: .me)
        let s = try WorkoutSession.start(routine: nil, forge: f, store: nil, now: t0)
        s.addExercise("bench")
        s.addSet(toExercise: 0)
        s.addSet(toExercise: 0)
        for j in 0..<3 { s.update(exercise: 0, set: j) { $0.weightKg = nil; $0.reps = nil } }
        return s
    }

    @Test func completingAnEmptySetFillsItFromTheSameSetLastTime() throws {
        let s = try sessionWithHistory()
        s.toggleComplete(exercise: 0, set: 1, now: t0)
        #expect(s.workout.exercises[0].sets[1].weightKg == 70 && s.workout.exercises[0].sets[1].reps == 10)
    }

    @Test func pastTheLastPreviousSetItUsesTheLastOne() throws {
        let s = try sessionWithHistory()
        s.toggleComplete(exercise: 0, set: 2, now: t0)
        #expect(s.workout.exercises[0].sets[2].weightKg == 70)
    }

    @Test func typedValuesAreNeverOverwritten() throws {
        let s = try sessionWithHistory()
        s.update(exercise: 0, set: 0) { $0.weightKg = 100 }
        s.toggleComplete(exercise: 0, set: 0, now: t0)
        #expect(s.workout.exercises[0].sets[0].weightKg == 100 && s.workout.exercises[0].sets[0].reps == nil)
    }

    @Test func structuralChangesBumpTheRevisionButTypingDoesNot() throws {
        let s = try sessionWithHistory()
        let r0 = s.revision
        s.update(exercise: 0, set: 0) { $0.weightKg = 1 }
        s.toggleComplete(exercise: 0, set: 0, now: t0)
        #expect(s.revision == r0)
        s.removeSet(exercise: 0, set: 2)
        #expect(s.revision == r0 + 1)
        s.moveExercise(from: 0, to: 0)
        s.addExercise("row")
        #expect(s.revision >= r0 + 2)
    }
}


@Suite struct TitleAndFormatTests {
    private func date(hour: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: 30, second: 0, of: Date(timeIntervalSince1970: 1_800_000_000))!
    }

    @Test func emptyWorkoutsAreNamedByTimeOfDay() {
        #expect(WorkoutSession.defaultTitle(at: date(hour: 7)) == "Morning Workout")
        #expect(WorkoutSession.defaultTitle(at: date(hour: 13)) == "Afternoon Workout")
        #expect(WorkoutSession.defaultTitle(at: date(hour: 18)) == "Evening Workout")
        #expect(WorkoutSession.defaultTitle(at: date(hour: 23)) == "Night Workout")
        #expect(WorkoutSession.defaultTitle(at: date(hour: 2)) == "Night Workout")
    }

    @Test func shortDurationsShowSeconds() {
        #expect(Format.duration(seconds: 40) == "40s")
        #expect(Format.duration(seconds: 60) == "1m")
        #expect(Format.duration(seconds: 3900) == "1h 5m")
        #expect(Format.duration(seconds: 0) == "0s")
    }
}

private final class SpyAlerts: RestAlerting {
    var updates: [Date?] = []
    func update(rest: RestTimer) { updates.append(rest.endsAt) }
}

@MainActor @Suite struct RestAlertsTests {
    private func session(_ spy: SpyAlerts) throws -> WorkoutSession {
        let s = try WorkoutSession.start(routine: chestRoutine(), forge: try lib(), store: nil, now: t0, restAlerts: spy)
        spy.updates.removeAll()
        return s
    }

    @Test func completingASetSchedulesTheAlertForTheRestEnd() throws {
        let spy = SpyAlerts()
        let s = try session(spy)
        s.toggleComplete(exercise: 0, set: 1, now: t0)
        #expect(spy.updates == [t0.addingTimeInterval(120)])
    }

    @Test func adjustingAndSkippingUpdateIt() throws {
        let spy = SpyAlerts()
        let s = try session(spy)
        s.toggleComplete(exercise: 0, set: 1, now: t0)
        s.adjustRest(by: 15, now: t0)
        #expect(spy.updates.last == t0.addingTimeInterval(135))
        s.skipRest()
        #expect(spy.updates.last == .some(nil))
    }

    @Test func finishingAndDiscardingClearIt() throws {
        let spy = SpyAlerts()
        let s = try session(spy)
        s.toggleComplete(exercise: 0, set: 1, now: t0)
        _ = try s.finish(now: t0.addingTimeInterval(60))
        #expect(spy.updates.last == .some(nil))
        let spy2 = SpyAlerts()
        let s2 = try session(spy2)
        s2.toggleComplete(exercise: 0, set: 1, now: t0)
        s2.discard()
        #expect(spy2.updates.last == .some(nil))
    }

    @Test func uncompletingASetDoesNotScheduleAnything() throws {
        let spy = SpyAlerts()
        let s = try session(spy)
        s.toggleComplete(exercise: 0, set: 1, now: t0)
        spy.updates.removeAll()
        s.toggleComplete(exercise: 0, set: 1, now: t0)
        #expect(spy.updates.isEmpty)
    }
}

@MainActor @Suite struct LeavingAWorkoutTests {
    @Test func aFreshWorkoutHasNothingToLose() throws {
        let s = try WorkoutSession.start(routine: chestRoutine(), forge: try lib(), store: nil, now: t0)
        #expect(!s.hasLoggedSets)
        s.update(exercise: 0, set: 1) { $0.weightKg = 85 }                  // editing a number is not logging a set
        #expect(!s.hasLoggedSets)
        s.toggleComplete(exercise: 0, set: 1, now: t0)
        #expect(s.hasLoggedSets)
    }

    @Test func leavingWritesNothingAnywhere() throws {
        let f = try lib()
        try f.perform([.putRoutine(chestRoutine())], author: .me)
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + "draft-\(UUID().uuidString).json")
        let s = try WorkoutSession.start(routine: chestRoutine(), forge: f, store: FileDraftStore(url: url), now: t0)
        s.toggleComplete(exercise: 0, set: 1, now: t0)
        let routineBefore = try f.routine(id: "r1")
        let changesBefore = try f.changes(since: 0).count
        s.discard()
        s.flushDraft()
        #expect(try f.workouts().isEmpty)
        #expect(try f.routine(id: "r1") == routineBefore)
        #expect(try f.changes(since: 0).count == changesBefore)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}

@MainActor @Suite struct PerExerciseRestTests {
    private func session() throws -> (WorkoutSession, Forge) {
        let f = try lib()
        try f.perform([.putRoutine(chestRoutine())], author: .me)
        return (try WorkoutSession.start(routine: chestRoutine(), forge: f, store: nil, now: t0), f)
    }

    @Test func eachExerciseCanHaveItsOwnRest() throws {
        let (s, _) = try session()
        s.setRest(exercise: 0, seconds: 45)
        s.toggleComplete(exercise: 0, set: 1, now: t0)
        #expect(s.rest.remaining(at: t0) == 45)
        s.toggleComplete(exercise: 1, set: 0, now: t0)                      // the second exercise keeps its own (default) rest
        #expect(s.rest.remaining(at: t0) == 90)
    }

    @Test func restCanBeTurnedOffForAnExercise() throws {
        let (s, _) = try session()
        s.setRest(exercise: 0, seconds: ExerciseBlock.restOff)
        s.toggleComplete(exercise: 0, set: 1, now: t0)
        #expect(!s.rest.isRunning(at: t0))
        #expect(s.workout.exercises[0].sets[1].completed)
    }

    @Test func aRestChangeBecomesThePlanWhenTheWorkoutFinishes() throws {
        let (s, f) = try session()
        s.setRest(exercise: 0, seconds: 150)
        s.toggleComplete(exercise: 0, set: 1, now: t0)                       // done exactly as planned
        let summary = try s.finish(now: t0.addingTimeInterval(60))
        #expect(summary.routineUpdate != nil)
        #expect(try f.routine(id: "r1")?.exercises[0].restSeconds == 150)
        #expect(try f.routine(id: "r1")?.exercises[0].sets.count == 3)       // nothing removed
    }

    @Test func offIsRememberedInTheRoutineToo() throws {
        let (s, f) = try session()
        s.setRest(exercise: 1, seconds: ExerciseBlock.restOff)
        s.toggleComplete(exercise: 0, set: 1, now: t0)
        _ = try s.finish(now: t0.addingTimeInterval(60))
        #expect(try f.routine(id: "r1")?.exercises[1].restSeconds == ExerciseBlock.restOff)
    }

    @Test func restChoicesAreLabelledForHumans() {
        #expect(RestOptions.label(for: ExerciseBlock.restOff, defaultSeconds: 90) == "Off")
        #expect(RestOptions.label(for: 0, defaultSeconds: 90) == "Default (1:30)")
        #expect(RestOptions.label(for: 150, defaultSeconds: 90) == "2:30")
        #expect(RestOptions.choices.first == ExerciseBlock.restOff && RestOptions.choices.contains(0) && RestOptions.choices.contains(90))
        #expect(RestOptions.choices == RestOptions.choices.sorted())
    }
}


private final class RecordingStore: DraftStore, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var saves: [Workout] = []
    private(set) var clears = 0
    private(set) var savedOnMainThread = false
    func save(_ workout: Workout) {
        lock.lock(); defer { lock.unlock() }
        saves.append(workout)
        if Thread.isMainThread { savedOnMainThread = true }
    }
    func load() -> Workout? { lock.lock(); defer { lock.unlock() }; return saves.last }
    func clear() { lock.lock(); defer { lock.unlock() }; clears += 1; saves.removeAll() }
    var saveCount: Int { lock.lock(); defer { lock.unlock() }; return saves.count }
}

@MainActor @Suite struct DraftSavingTests {
    private func started(_ store: DraftStore) throws -> WorkoutSession {
        try WorkoutSession.start(routine: chestRoutine(), forge: try lib(), store: store, now: t0)
    }

    @Test func typingIsCoalescedIntoFewWrites() throws {
        let store = RecordingStore()
        let s = try started(store)
        s.flushDraft()
        let before = store.saveCount
        for i in 0..<200 { s.update(exercise: 0, set: i % 3) { $0.reps = i % 15 } }
        s.flushDraft()
        #expect(store.saveCount - before <= 2)                          // not 200
        #expect(store.load() == s.workout)                              // and the last one is the latest state
    }

    @Test func tickingASetIsSavedWithoutWaitingForTheTypingDelay() throws {
        let store = RecordingStore()
        let s = try started(store)
        s.toggleComplete(exercise: 0, set: 1, now: t0)
        s.flushDraft()
        #expect(store.load()?.exercises[0].sets[1].completed == true)
    }

    @Test func writesNeverHappenOnTheMainThread() throws {
        let store = RecordingStore()
        let s = try started(store)
        s.toggleComplete(exercise: 0, set: 1, now: t0)
        s.update(exercise: 0, set: 0) { $0.reps = 9 }
        s.flushDraft()
        #expect(store.saveCount > 0 && !store.savedOnMainThread)
    }

    @Test func discardingBeatsAPendingWrite() throws {
        let store = RecordingStore()
        let s = try started(store)
        s.update(exercise: 0, set: 0) { $0.reps = 11 }                  // a typing write is still waiting
        s.discard()
        s.flushDraft()
        #expect(store.load() == nil && store.clears >= 1)
    }

    @Test func finishingClearsTheDraftEvenWithAWritePending() throws {
        let store = RecordingStore()
        let s = try started(store)
        s.toggleComplete(exercise: 0, set: 1, now: t0)
        s.update(exercise: 0, set: 1) { $0.reps = 7 }
        _ = try s.finish(now: t0.addingTimeInterval(60))
        s.flushDraft()
        #expect(store.load() == nil)
    }
}

@MainActor @Suite struct StableIdentityTests {
    private func session() throws -> WorkoutSession {
        try WorkoutSession.start(routine: chestRoutine(), forge: try lib(), store: nil, now: t0)
    }

    private func aligned(_ s: WorkoutSession) -> Bool {
        s.blockIDs.count == s.workout.exercises.count
            && zip(s.setIDs, s.workout.exercises).allSatisfy { $0.count == $1.sets.count }
            && s.setIDs.count == s.workout.exercises.count
    }

    @Test func everyExerciseAndSetGetsAnIdAndTheyStayAligned() throws {
        let s = try session()
        #expect(aligned(s) && Set(s.blockIDs).count == 2 && Set(s.setIDs.flatMap { $0 }).count == 4)
        s.addExercise("row"); s.addSet(toExercise: 0); s.removeSet(exercise: 0, set: 0); s.moveExercise(from: 2, to: 0)
        s.swapExercise(at: 1, with: "fly"); s.removeExercise(at: 2)
        #expect(aligned(s))
    }

    @Test func movingAnExerciseMovesItsIdsWithIt() throws {
        let s = try session()
        let (a, b) = (s.blockIDs[0], s.blockIDs[1])
        let firstSets = s.setIDs[0]
        s.moveExercise(from: 0, to: 1)
        #expect(s.blockIDs == [b, a] && s.setIDs[1] == firstSets)
        #expect(s.blockIndex(a) == 1 && s.blockIndex(b) == 0)
    }

    @Test func removingASetRemovesThatSetsId() throws {
        let s = try session()
        let ids = s.setIDs[0]
        s.removeSet(exercise: 0, set: 1)
        #expect(s.setIDs[0] == [ids[0], ids[2]])
        #expect(s.setIndex(block: s.blockIDs[0], set: ids[2]) == 1 && s.setIndex(block: s.blockIDs[0], set: ids[1]) == nil)
    }

    @Test func newExercisesAndSetsGetFreshIds() throws {
        let s = try session()
        let before = Set(s.blockIDs + s.setIDs.flatMap { $0 })
        s.addExercise("row"); s.addSet(toExercise: 0)
        let after = Set(s.blockIDs + s.setIDs.flatMap { $0 })
        #expect(after.count == before.count + 3 && before.isSubset(of: after))      // one block, its first set, one more set
    }

    @Test func swappingAnExerciseKeepsItsRowIdentity() throws {
        let s = try session()
        let (block, sets) = (s.blockIDs[0], s.setIDs[0])
        s.swapExercise(at: 0, with: "row")
        #expect(s.blockIDs[0] == block && s.setIDs[0] == sets)
    }

    @Test func aRestoredWorkoutGetsConsistentIds() throws {
        let f = try lib()
        let w = Workout(title: "x", startedAt: 1, exercises: chestRoutine().exercises)
        let s = WorkoutSession(forge: f, workout: w, store: nil)
        #expect(aligned(s))
    }
}
