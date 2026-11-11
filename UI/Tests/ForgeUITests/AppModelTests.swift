import Foundation
import ForgeCore
import Testing
@testable import ForgeUI

@MainActor private func model(draft: DraftStore? = nil) throws -> AppModel {
    AppModel(forge: try Forge.inMemory(), draftStore: draft, defaults: UserDefaults(suiteName: "forge-test-\(UUID().uuidString)")!)
}

private final class Flag: @unchecked Sendable { var raised = false }

/// Whether `action` would make a screen that reads what `read` reads redraw.
@MainActor func redraws(_ read: @escaping () -> Void, after action: () async throws -> Void) async rethrows -> Bool {
    let flag = Flag()
    withObservationTracking(read) { flag.raised = true }
    try await action()
    return flag.raised
}

@MainActor @Suite struct AppModelTests {
    @Test func reloadPicksUpChangesMadeThroughTheDatabase() throws {
        let m = try model()
        #expect(m.exercises.isEmpty)
        try m.forge.perform([.putExercise(Exercise(id: "e", name: "Squat"))], author: .claude)
        m.reload()
        #expect(m.exercises.map(\.name) == ["Squat"])
        #expect(m.name(for: "e") == "Squat")
        #expect(m.name(for: "gone") == "Deleted exercise")
    }

    @Test func starterLibraryHasUniqueNamesMusclesAndLoadsOnce() throws {
        let names = StarterLibrary.exercises.map(\.name)
        #expect(names.count >= 40 && Set(names).count == names.count)
        #expect(StarterLibrary.exercises.allSatisfy { $0.primaryMuscle != nil })
        let m = try model()
        m.addStarterLibrary()
        let first = m.exercises.count
        m.addStarterLibrary()
        #expect(first == names.count && m.exercises.count == first)
    }

    @Test func unitDefaultsToPoundsAndIsRemembered() throws {
        let defaults = UserDefaults(suiteName: "forge-test-\(UUID().uuidString)")!
        let m = AppModel(forge: try Forge.inMemory(), draftStore: nil, defaults: defaults)
        #expect(m.unit == .lb)
        m.unit = .kg
        #expect(AppModel(forge: try Forge.inMemory(), draftStore: nil, defaults: defaults).unit == .kg)
    }

    @Test func finishingAWorkoutSavesItAndRefreshesHistory() throws {
        let m = try model()
        try m.forge.perform([.putExercise(Exercise(id: "e", name: "Squat"))], author: .me)
        m.reload()
        m.startWorkout(routine: nil)
        let s = try #require(m.session)
        s.addExercise("e")
        s.update(exercise: 0, set: 0) { $0.weightKg = 100; $0.reps = 5 }
        s.toggleComplete(exercise: 0, set: 0)
        let summary = try m.finishWorkout()
        #expect(m.session == nil && m.lastSummary == summary)
        #expect(m.workouts.count == 1)
    }

    @Test func aForgottenWorkoutsEndCanBeMovedBackButNotBeforeItStarted() throws {
        let m = try model()
        try m.forge.perform([.putWorkout(Workout(id: "w", title: "Legs", startedAt: 1_000_000, endedAt: 90_000_000))], author: .me)
        m.reload()
        m.setWorkoutEnd(id: "w", to: Date(timeIntervalSince1970: 4_600))
        #expect(m.workouts.first?.endedAt == 4_600_000)
        m.setWorkoutEnd(id: "w", to: Date(timeIntervalSince1970: 0))
        #expect(m.workouts.first?.endedAt == 1_000_000)
    }

    @Test func startingAWorkoutDoesNotReReadTheDatabase() throws {
        let m = try model()
        try m.forge.perform([.putExercise(Exercise(id: "e", name: "Squat"))], author: .me)
        m.reload()
        try m.forge.perform([.putExercise(Exercise(id: "f", name: "Bench"))], author: .claude)   // not yet picked up
        m.startWorkout(routine: nil)
        #expect(m.session != nil)
        #expect(m.exercises.map(\.id) == ["e"])          // the tap that starts a workout skips the full reload
    }

    /// Reloading reassigns every list; screens must only redraw for the lists whose contents changed.
    @Test func aChangeRedrawsOnlyTheScreensShowingWhatChanged() async throws {
        let m = try model()
        try m.forge.perform([.putExercise(Exercise(id: "e", name: "Squat"))], author: .me)
        m.reload()
        let library = await redraws({ _ = (m.workouts, m.exercises, m.bodyweights) }) { m.saveRoutine(Routine(id: "r", title: "Legs")) }
        #expect(!library)
        let routines = await redraws({ _ = m.routines }) { m.saveRoutine(Routine(id: "r", title: "Legs and more")) }
        #expect(routines)
        #expect(m.routines.map(\.title) == ["Legs and more"])
    }

    @Test func anInterruptedWorkoutIsRestoredOnLaunch() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + "draft-\(UUID().uuidString).json")
        let first = try model(draft: FileDraftStore(url: url))
        first.startWorkout(routine: nil)
        first.session?.addExercise("anything")
        first.flushWorkoutDraft()                                   // what the app does when it goes to the background
        let second = AppModel(forge: first.forge, draftStore: FileDraftStore(url: url), defaults: UserDefaults(suiteName: "forge-test-\(UUID().uuidString)")!)
        #expect(second.session?.workout.exercises.map(\.exerciseID) == ["anything"])
        second.discardWorkout()
        #expect(second.session == nil)
    }

    @Test func applyingARoutineUpdateRewritesTheRoutine() throws {
        let m = try model()
        let routine = Routine(id: "r", title: "Push", exercises: [ExerciseBlock(exerciseID: "e", sets: [SetEntry(weightKg: 50, reps: 5)])])
        try m.forge.perform([.putExercise(Exercise(id: "e", name: "Press")), .putRoutine(routine)], author: .me)
        m.reload()
        var updated = routine
        updated.exercises[0].sets[0].weightKg = 55
        m.saveRoutine(updated)
        #expect(m.routines.first?.exercises[0].sets[0].weightKg == 55)
    }

    @Test func deletingAnExerciseWithHistoryReportsInsteadOfDeleting() throws {
        let m = try model()
        let block = ExerciseBlock(exerciseID: "e", sets: [SetEntry(weightKg: 1, reps: 1, completed: true)])
        try m.forge.perform([.putExercise(Exercise(id: "e", name: "X")), .putWorkout(Workout(id: "w", title: "w", startedAt: 1, exercises: [block]))], author: .me)
        m.reload()
        #expect(throws: ForgeError.self) { try m.deleteExercise(id: "e", mergeInto: nil, force: false) }
        #expect(m.exercises.count == 1)
        try m.deleteExercise(id: "e", mergeInto: nil, force: true)
        #expect(m.exercises.isEmpty)
    }

    @Test func routineOrderCanBeChanged() throws {
        let m = try model()
        try m.forge.perform([.putRoutine(Routine(id: "a", title: "A", position: 0)), .putRoutine(Routine(id: "b", title: "B", position: 1))], author: .me)
        m.reload()
        m.reorderRoutines(["b", "a"])
        #expect(m.routines.map(\.id) == ["b", "a"])
    }

    @Test func externalWritesAreDetectedByThePoller() async throws {
        let path = NSTemporaryDirectory() + "forge-app-\(UUID().uuidString)/forge.sqlite"
        let m = AppModel(forge: try Forge.open(path: path, device: "app"), draftStore: nil, defaults: UserDefaults(suiteName: "forge-test-\(UUID().uuidString)")!)
        m.startWatching(interval: 0.05)
        let cli = try Forge.open(path: path, device: "cli")
        try cli.perform([.putExercise(Exercise(name: "From the CLI"))], author: .claude)
        for _ in 0..<40 where m.exercises.isEmpty { try await Task.sleep(nanoseconds: 50_000_000) }
        #expect(m.exercises.map(\.name) == ["From the CLI"])
        m.stopWatching()
    }

    @Test func everyInstallGetsItsOwnSyncDeviceName() throws {
        let one = try AppModel.open(path: NSTemporaryDirectory() + "forge-install-\(UUID().uuidString)/forge.sqlite")
        let two = try AppModel.open(path: NSTemporaryDirectory() + "forge-install-\(UUID().uuidString)/forge.sqlite")
        #expect(one.forge.device != two.forge.device)
        #expect(!one.forge.device.isEmpty)
    }

    @Test func starterExercisesHaveTheSameIdsOnEveryDevice() throws {
        let a = try model(), b = try model()
        a.addStarterLibrary(); b.addStarterLibrary()
        #expect(Set(a.exercises.map(\.id)) == Set(b.exercises.map(\.id)))
        #expect(a.exercises.count == StarterLibrary.exercises.count)
    }
}


@MainActor @Suite struct AppModelBasicsTests {
    @Test func bodyweightIsStoredInKilogramsListedAndDeletable() throws {
        let m = try model()
        let day = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 9))!
        m.addBodyweight(on: day, value: 165)                         // pounds, the default unit
        #expect(m.bodyweights.count == 1)
        #expect(m.bodyweights[0].date == "2026-10-20" && abs(m.bodyweights[0].kg - 74.8427) < 0.001)
        m.deleteBodyweight(date: "2026-10-20")
        #expect(m.bodyweights.isEmpty)
    }

    @Test func aRoutineCanBeDuplicated() throws {
        let m = try model()
        let routine = Routine(id: "r", title: "Push", position: 0, exercises: [ExerciseBlock(exerciseID: "e", restSeconds: 90, sets: [SetEntry(weightKg: 50, reps: 8)])])
        try m.forge.perform([.putExercise(Exercise(id: "e", name: "Press")), .putRoutine(routine)], author: .me)
        m.reload()
        m.duplicateRoutine(id: "r")
        #expect(m.routines.count == 2)
        let copy = try #require(m.routines.first { $0.id != "r" })
        #expect(copy.title == "Push copy" && copy.exercises == routine.exercises && copy.position == 1)
    }

    @Test func aFinishedWorkoutCanBecomeARoutine() throws {
        let m = try model()
        let w = Workout(id: "w", title: "Leg day", startedAt: 1000, exercises: [
            ExerciseBlock(exerciseID: "e", notes: "slow", restSeconds: 120, sets: [SetEntry(weightKg: 100, reps: 5, completed: true), SetEntry(type: .warmup, weightKg: 40, reps: 10, completed: true)])])
        try m.forge.perform([.putWorkout(w)], author: .me)
        m.reload()
        let routine = try #require(m.saveWorkoutAsRoutine(id: "w"))
        #expect(routine.title == "Leg day" && m.routines.contains { $0.id == routine.id })
        #expect(routine.exercises[0].sets.count == 2 && routine.exercises[0].sets.allSatisfy { !$0.completed })
        #expect(routine.exercises[0].sets[0].weightKg == 100 && routine.exercises[0].restSeconds == 120 && routine.exercises[0].notes == "slow")
    }

    @Test func theDefaultRestTimeIsRememberedAndUsed() throws {
        let defaults = UserDefaults(suiteName: "forge-test-\(UUID().uuidString)")!
        let m = AppModel(forge: try Forge.inMemory(), draftStore: nil, defaults: defaults)
        #expect(m.defaultRestSeconds == 90)
        m.defaultRestSeconds = 120
        #expect(AppModel(forge: try Forge.inMemory(), draftStore: nil, defaults: defaults).defaultRestSeconds == 120)
        try m.forge.perform([.putExercise(Exercise(id: "e", name: "Squat"))], author: .me)
        m.reload()
        m.startWorkout(routine: nil)
        m.session?.addExercise("e")
        #expect(m.session?.workout.exercises[0].restSeconds == 120)
    }

    @Test func changesCanBeReviewedAndClaudesLastOneUndone() throws {
        let m = try model()
        try m.forge.perform([.putRoutine(Routine(id: "mine", title: "Mine"))], author: .me)
        try m.forge.perform([.putRoutine(Routine(id: "theirs", title: "Claude's"))], author: .claude)
        m.reload()
        #expect(m.recentChanges().first?.author == .claude)
        #expect(m.recentChanges().count == 2)
        let result = m.undoClaudeLastChange()
        #expect(result.undone == 1)
        #expect(m.routines.map(\.id) == ["mine"])
        #expect(m.recentChanges().first?.undone == true || m.recentChanges().count == 3)
    }

    @Test func theWholeDatabaseCanBeExported() throws {
        let m = try model()
        try m.forge.perform([.putRoutine(Routine(id: "r", title: "Pull day"))], author: .me)
        let text = String(decoding: try m.exportData(), as: UTF8.self)
        #expect(text.contains("Pull day") && text.contains("\"version\""))
    }
}
