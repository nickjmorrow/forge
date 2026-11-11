import Foundation
import GRDB
import Testing
@testable import ForgeCore

func opCount(_ f: Forge) throws -> Int { try f.db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM ops")! } }

func sampleRoutine(_ id: String, _ title: String, exercises: [ExerciseBlock] = []) -> Routine {
    Routine(id: id, title: title, position: 0, exercises: exercises, createdAt: 1, updatedAt: 1)
}

@Suite struct PerformTests {
    @Test func performLogsOneRowPerCall() throws {
        let f = try Forge.inMemory()
        try f.perform([.putExercise(Exercise(name: "A")), .putExercise(Exercise(name: "B")), .putExercise(Exercise(name: "C"))], author: .me)
        #expect(try opCount(f) == 1)
    }

    @Test func failedBatchAppliesNothing() throws {
        let f = try Forge.inMemory()
        let e = Exercise(id: "e1", name: "A")
        #expect(throws: ForgeError.notFound("exercise nope")) {
            try f.perform([.putExercise(e), .deleteExercise(id: "nope")], author: .me)
        }
        #expect(try f.exercise(id: "e1") == nil)
        #expect(try opCount(f) == 0)
    }

    @Test func undoRestoresPreviousRoutine() throws {
        let f = try Forge.inMemory()
        try f.perform([.putRoutine(sampleRoutine("r1", "Legs"))], author: .me)
        try f.perform([.putRoutine(sampleRoutine("r1", "Legs 2"))], author: .me)
        let result = try f.undo(author: nil)
        #expect(result.undone == 1)
        #expect(try f.routine(id: "r1")?.title == "Legs")
    }

    @Test func undoOfDeleteRestoresRoutineWithSets() throws {
        let f = try Forge.inMemory()
        let block = ExerciseBlock(exerciseID: "e1", notes: "n", restSeconds: 90, supersetID: 2, sets: [
            SetEntry(type: .warmup, weightKg: 43.09, reps: 12), SetEntry(type: .normal, weightKg: 61.23, reps: 6, rpe: 8)])
        let r = sampleRoutine("r1", "Chest", exercises: [block])
        try f.perform([.putRoutine(r)], author: .me)
        try f.perform([.deleteRoutine(id: "r1")], author: .claude)
        #expect(try f.routine(id: "r1") == nil)
        _ = try f.undo(author: .claude)
        #expect(try f.routine(id: "r1") == r)
    }

    @Test func undoOnlyTouchesRequestedAuthor() throws {
        let f = try Forge.inMemory()
        try f.perform([.putRoutine(sampleRoutine("r1", "A"))], author: .me)
        try f.perform([.putRoutine(sampleRoutine("r2", "C"))], author: .claude)
        let result = try f.undo(author: .claude)
        #expect(result.undone == 1)
        #expect(try f.routine(id: "r2") == nil)
        #expect(try f.routine(id: "r1") != nil)
    }

    @Test func undoSkipsWhenLaterEditTouchedSameEntity() throws {
        let f = try Forge.inMemory()
        try f.perform([.putRoutine(sampleRoutine("r1", "Start"))], author: .me)
        try f.perform([.putRoutine(sampleRoutine("r1", "Claude title"))], author: .claude)
        try f.perform([.putRoutine(sampleRoutine("r1", "My title"))], author: .me)
        let result = try f.undo(author: .claude)
        #expect(result.undone == 0)
        #expect(result.skipped.count == 1)
        #expect(try f.routine(id: "r1")?.title == "My title")
    }

    @Test func changesListsOpsWithUndoneFlag() throws {
        let f = try Forge.inMemory()
        try f.perform([.putRoutine(sampleRoutine("r1", "Legs"))], author: .claude)
        _ = try f.undo(author: .claude)
        let changes = try f.changes(since: 0, author: .claude)
        #expect(changes.count == 2)
        #expect(changes[0].undone)
        #expect(changes[0].summary.contains("Legs"))
    }
}

@Suite struct BodyweightTests {
    @Test func undoOfNewBodyweightRemovesIt() throws {
        let f = try Forge.inMemory()
        try f.perform([.putBodyweight(date: "2026-10-20", kg: 70)], author: .me)
        try f.perform([.putBodyweight(date: "2026-10-20", kg: 71)], author: .me)
        try f.undo()
        #expect(try f.bodyweight(date: "2026-10-20") == 70)
        try f.undo()
        #expect(try f.bodyweight(date: "2026-10-20") == nil)
    }
}

@Suite struct UndoSafetyTests {
    @Test func laterMergeBlocksUndoOfEarlierRoutineEdit() throws {
        let f = try Forge.inMemory()
        let r = sampleRoutine("r", "Back", exercises: [ExerciseBlock(exerciseID: "X")])
        try f.perform([.putExercise(Exercise(id: "X", name: "X")), .putExercise(Exercise(id: "Y", name: "Y")), .putRoutine(r)], author: .me)
        var edited = r
        edited.title = "Claude edit"
        try f.perform([.putRoutine(edited)], author: .claude)
        try f.perform([.mergeExercises(from: "X", into: "Y")], author: .me)
        let result = try f.undo(author: .claude)
        #expect(result.undone == 0 && result.skipped.count == 1)
        #expect(try f.routine(id: "r")?.exercises.map(\.exerciseID) == ["Y"])
        #expect(try f.exercise(id: "X") == nil)
    }

    private func edit(_ f: Forge, _ title: String, _ author: Author) throws {
        try f.perform([.putRoutine(sampleRoutine("r", title))], author: author)
    }

    @Test func skippedEditStillProtectsItsEntity() throws {
        let f = try Forge.inMemory()
        try edit(f, "v0", .me)
        try edit(f, "claude1", .claude)
        try edit(f, "me2", .me)
        try edit(f, "claude3", .claude)
        #expect(try f.undo(author: .me).undone == 0)        // me2 is blocked by claude3
        #expect(try f.undo(author: .claude).undone == 1)    // claude3 undone -> me2
        #expect(try f.routine(id: "r")?.title == "me2")
        let again = try f.undo(author: .claude)             // claude1 is blocked by me2, which is still applied
        #expect(again.undone == 0 && again.skipped.count == 1)
        #expect(try f.routine(id: "r")?.title == "me2")
    }

    @Test func changesMarkSkippedAsSkippedNotUndone() throws {
        let f = try Forge.inMemory()
        try edit(f, "v0", .me)
        try edit(f, "claude1", .claude)
        try edit(f, "me2", .me)
        _ = try f.undo(author: .claude)
        let claude = try #require(try f.changes(since: 0, author: .claude).first)
        #expect(claude.skipped && !claude.undone)
        #expect(try f.routine(id: "r")?.title == "me2")
    }

    @Test func undoStopsAtFirstBlockedChange() throws {
        let f = try Forge.inMemory()
        try f.perform([.putRoutine(sampleRoutine("a", "A0")), .putRoutine(sampleRoutine("b", "B0"))], author: .me)
        try f.perform([.putRoutine(sampleRoutine("a", "A1"))], author: .claude)
        try f.perform([.putRoutine(sampleRoutine("b", "B1"))], author: .claude)
        try f.perform([.putRoutine(sampleRoutine("b", "Bme"))], author: .me)
        let first = try f.undo(author: .claude)
        #expect(first.undone == 0 && first.skipped.count == 1)
        #expect(try f.routine(id: "a")?.title == "A1")      // the older, unrelated change was not touched
        #expect(try f.undo(author: .claude).undone == 1)    // a second call moves on to it
        #expect(try f.routine(id: "a")?.title == "A0")
        #expect(try f.routine(id: "b")?.title == "Bme")
    }
}
