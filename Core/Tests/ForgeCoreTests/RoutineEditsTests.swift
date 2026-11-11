import Foundation
import Testing
@testable import ForgeCore

private func seeded() throws -> Forge {
    let f = try Forge.inMemory()
    func block(_ id: String) -> ExerciseBlock { ExerciseBlock(exerciseID: id, sets: [SetEntry(weightKg: 50, reps: 8)]) }
    try f.perform([
        .putExercise(Exercise(id: "bench", name: "Bench Press (Barbell)")),
        .putExercise(Exercise(id: "acme", name: "Acme Row")),
        .putExercise(Exercise(id: "acme2", name: "acme curl")),
        .putRoutine(Routine(id: "r1", title: "Chest", position: 0, exercises: [block("bench"), block("acme")], createdAt: 1, updatedAt: 1)),
        .putRoutine(Routine(id: "r2", title: "Back", position: 1, exercises: [block("acme2"), block("bench")], createdAt: 1, updatedAt: 1)),
        .putRoutine(Routine(id: "r3", title: "Legs", position: 2, exercises: [block("bench")], createdAt: 1, updatedAt: 1)),
        .putWorkout(Workout(id: "w1", title: "Old", startedAt: 5, exercises: [block("acme")])),
    ], author: .me)
    return f
}

@Suite struct RoutineEditsTests {
    @Test func reorderRoutinesRewritesPositions() throws {
        let f = try seeded()
        try f.reorderRoutines(["r3", "r1", "r2"], author: .claude)
        #expect(try f.routines().map(\.id) == ["r3", "r1", "r2"])
        #expect(try f.routines().map(\.position) == [0, 1, 2])
    }

    @Test func reorderRejectsMissingOrExtraIds() throws {
        let f = try seeded()
        #expect(throws: ForgeError.self) { try f.reorderRoutines(["r1", "r2"], author: .claude) }
        #expect(throws: ForgeError.self) { try f.reorderRoutines(["r1", "r2", "r3", "r4"], author: .claude) }
        #expect(try f.routines().map(\.id) == ["r1", "r2", "r3"])
    }

    @Test func previewListsAffectedRoutinesWithoutChanging() throws {
        let f = try seeded()
        let preview = try f.previewRemoveExercises(matching: ["acme"])
        #expect(preview.map(\.routineTitle) == ["Chest", "Back"])
        #expect(preview[0].removedExercises == ["Acme Row"])
        #expect(try f.routine(id: "r1")?.exercises.count == 2)
        #expect(try opCount(f) == 1)
    }

    @Test func removeExercisesFromAllRoutinesIsOneUndoableBatch() throws {
        let f = try seeded()
        let ids = try f.exerciseIDs(nameContaining: ["acme"])
        #expect(Set(ids) == ["acme", "acme2"])
        try f.removeExercisesFromRoutines(exerciseIDs: ids, author: .claude)
        #expect(try opCount(f) == 2)
        #expect(try f.routine(id: "r1")?.exercises.map(\.exerciseID) == ["bench"])
        #expect(try f.routine(id: "r2")?.exercises.map(\.exerciseID) == ["bench"])
        #expect(try f.routine(id: "r3")?.exercises.map(\.exerciseID) == ["bench"])
        try f.undo(author: .claude)
        #expect(try f.routine(id: "r1")?.exercises.count == 2)
        #expect(try f.routine(id: "r2")?.exercises.count == 2)
    }

    @Test func removeLeavesWorkoutHistoryUntouched() throws {
        let f = try seeded()
        try f.removeExercisesFromRoutines(exerciseIDs: ["acme"], author: .claude)
        #expect(try f.workout(id: "w1")?.exercises.map(\.exerciseID) == ["acme"])
    }

    @Test func removeWithNoMatchReturnsNilAndLogsNothing() throws {
        let f = try seeded()
        #expect(try f.removeExercisesFromRoutines(exerciseIDs: ["nope"], author: .claude) == nil)
        #expect(try opCount(f) == 1)
    }
}

@Suite struct ReorderEdgeTests {
    @Test func reorderWithNoRoutinesThrowsInsteadOfCrashing() throws {
        let f = try Forge.inMemory()
        #expect(throws: ForgeError.self) { try f.reorderRoutines([], author: .claude) }
    }

    @Test func reorderAlreadyOrderedLogsNothing() throws {
        let f = try Forge.inMemory()
        try f.perform([.putRoutine(Routine(id: "a", title: "A", position: 0, createdAt: 1, updatedAt: 1)),
                       .putRoutine(Routine(id: "b", title: "B", position: 1, createdAt: 1, updatedAt: 1))], author: .me)
        #expect(try f.reorderRoutines(["a", "b"], author: .claude) == nil)
        #expect(try opCount(f) == 1)
    }
}
