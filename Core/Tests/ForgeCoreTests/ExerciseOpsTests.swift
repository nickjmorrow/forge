import Foundation
import Testing
@testable import ForgeCore

private func seeded() throws -> Forge {
    let f = try Forge.inMemory()
    let block = ExerciseBlock(exerciseID: "e1", restSeconds: 60, sets: [SetEntry(weightKg: 100, reps: 5, completed: true)])
    try f.perform([
        .putExercise(Exercise(id: "e1", name: "Acme Row")),
        .putExercise(Exercise(id: "e2", name: "Seated Row")),
        .putRoutine(sampleRoutine("r1", "Back", exercises: [block])),
        .putWorkout(Workout(id: "w1", title: "Back day", startedAt: 1000, exercises: [block])),
    ], author: .me)
    return f
}

@Suite struct ExerciseOpsTests {
    @Test func deleteUnusedExerciseSucceeds() throws {
        let f = try seeded()
        try f.deleteExercise(id: "e2", mergeInto: nil, force: false, author: .claude)
        #expect(try f.exercise(id: "e2") == nil)
    }

    @Test func deleteWithHistoryRefusedWithoutTarget() throws {
        let f = try seeded()
        #expect(throws: ForgeError.exerciseHasHistory("e1", workouts: 1, routines: 1)) {
            try f.deleteExercise(id: "e1", mergeInto: nil, force: false, author: .claude)
        }
        #expect(try f.exercise(id: "e1") != nil)
    }

    @Test func mergeRepointsRoutinesAndWorkouts() throws {
        let f = try seeded()
        try f.deleteExercise(id: "e1", mergeInto: "e2", force: false, author: .claude)
        #expect(try f.exercise(id: "e1") == nil)
        #expect(try f.routine(id: "r1")?.exercises.map(\.exerciseID) == ["e2"])
        #expect(try f.workout(id: "w1")?.exercises.map(\.exerciseID) == ["e2"])
        #expect(try f.workout(id: "w1")?.exercises[0].sets[0].weightKg == 100)
    }

    @Test func mergeThenUndoRestoresEverything() throws {
        let f = try seeded()
        let routine = try f.routine(id: "r1"), workout = try f.workout(id: "w1")
        try f.deleteExercise(id: "e1", mergeInto: "e2", force: false, author: .claude)
        try f.undo(author: .claude)
        #expect(try f.exercise(id: "e1")?.name == "Acme Row")
        #expect(try f.routine(id: "r1") == routine)
        #expect(try f.workout(id: "w1") == workout)
    }

    @Test func forceDeleteRemovesBlocksFromRoutinesAndWorkouts() throws {
        let f = try seeded()
        try f.deleteExercise(id: "e1", mergeInto: nil, force: true, author: .claude)
        #expect(try f.exercise(id: "e1") == nil)
        #expect(try f.routine(id: "r1")?.exercises.isEmpty == true)
        #expect(try f.workout(id: "w1")?.exercises.isEmpty == true)
        try f.undo(author: .claude)
        #expect(try f.routine(id: "r1")?.exercises.count == 1)
    }

    @Test func twoExercisesMayShareAName() throws {
        let f = try Forge.inMemory()
        try f.perform([.putExercise(Exercise(id: "a", name: "Bench Press", isCustom: false)),
                       .putExercise(Exercise(id: "b", name: "Bench Press", isCustom: true))], author: .importer)
        #expect(try f.exercises(matching: "bench").count == 2)
    }

    @Test func exercisesMatchNameEquipmentAndMuscle() throws {
        let f = try Forge.inMemory()
        try f.perform([.putExercise(Exercise(id: "a", name: "Row", equipment: "cable", primaryMuscle: "lats", secondaryMuscles: ["biceps"]))], author: .me)
        #expect(try f.exercises(matching: "CABLE").count == 1)
        #expect(try f.exercises(matching: "biceps").count == 1)
        #expect(try f.exercises(matching: "quads").isEmpty)
        #expect(try f.exercises(matching: nil).count == 1)
    }
}

@Suite struct HevyIDCollisionTests {
    @Test func samehevyIDOnAnotherExerciseThrowsAndKeepsTheOriginal() throws {
        let f = try Forge.inMemory()
        try f.perform([.putExercise(Exercise(id: "e1", name: "One", hevyID: "H"))], author: .importer)
        #expect(throws: Error.self) { try f.perform([.putExercise(Exercise(id: "e2", name: "Two", hevyID: "H"))], author: .claude) }
        #expect(try f.exercise(id: "e1")?.name == "One")
        #expect(try f.exercise(id: "e2") == nil)
        try f.perform([.putExercise(Exercise(id: "e1", name: "One renamed", hevyID: "H"))], author: .claude)   // same id still updates
        #expect(try f.exercise(id: "e1")?.name == "One renamed")
    }
}
