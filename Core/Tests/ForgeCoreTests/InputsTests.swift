import Foundation
import Testing
@testable import ForgeCore

private func library() throws -> Forge {
    let f = try Forge.inMemory()
    try f.perform([
        .putExercise(Exercise(id: "bench", name: "Bench Press (Barbell)", primaryMuscle: "chest")),
        .putExercise(Exercise(id: "row1", name: "Row", isCustom: false)),
        .putExercise(Exercise(id: "row2", name: "row", isCustom: true)),
    ], author: .me)
    return f
}

private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T { try JSONDecoder().decode(type, from: Data(json.utf8)) }

@Suite struct InputsTests {
    @Test func routineByNameWithPoundsResolvesAndDefaults() throws {
        let f = try library()
        let input = try decode(RoutineInput.self, #"{"title":"Push","exercises":[{"exercise":"bench press (barbell)","restSeconds":120,"sets":[{"weightLb":200,"reps":5},{"type":"warmup","weightKg":40,"reps":10}]}]}"#)
        let routine = try f.putRoutine(input, author: .claude)
        #expect(routine.title == "Push" && routine.position == 0)
        let block = routine.exercises[0]
        #expect(block.exerciseID == "bench" && block.restSeconds == 120)
        #expect(abs((block.sets[0].weightKg ?? 0) - 90.7185) < 0.001 && block.sets[0].type == .normal && !block.sets[0].completed)
        #expect(block.sets[1].type == .warmup)
        #expect(try f.routine(id: routine.id) == routine)
        #expect(try f.changes(since: 0).count == 2 && (try f.changes(since: 0, author: .claude).count == 1))
    }

    @Test func ambiguousNameListsTheCandidates() throws {
        let f = try library()
        let input = try decode(RoutineInput.self, #"{"title":"Pull","exercises":[{"exercise":"Row"}]}"#)
        do { _ = try f.putRoutine(input, author: .claude); Issue.record("should have thrown") } catch let ForgeError.invalid(message) {
            #expect(message.contains("row1") && message.contains("row2"))
        }
        #expect(try f.routines().isEmpty)
    }

    @Test func unknownExerciseChangesNothing() throws {
        let f = try library()
        let input = try decode(RoutineInput.self, #"{"title":"X","exercises":[{"exercise":"Nonexistent Curl"}]}"#)
        #expect(throws: ForgeError.notFound("exercise named \"Nonexistent Curl\"")) { try f.putRoutine(input, author: .claude) }
        #expect(try f.routines().isEmpty && (try opCount(f)) == 1)
    }

    @Test func exerciseIDWorksAndNeitherNorBothIsRejected() throws {
        let f = try library()
        let ok = try decode(RoutineInput.self, #"{"title":"A","exercises":[{"exerciseID":"bench"}]}"#)
        #expect(try f.putRoutine(ok, author: .claude).exercises[0].exerciseID == "bench")
        let neither = try decode(RoutineInput.self, #"{"title":"B","exercises":[{"notes":"x"}]}"#)
        #expect(throws: ForgeError.self) { try f.putRoutine(neither, author: .claude) }
    }

    @Test func existingIDReplacesAndKeepsCreatedAtAndAppendsNewAtTheEnd() throws {
        let f = try library()
        let first = try f.putRoutine(try decode(RoutineInput.self, #"{"title":"One","exercises":[]}"#), author: .claude)
        let second = try f.putRoutine(try decode(RoutineInput.self, #"{"title":"Two","exercises":[]}"#), author: .claude)
        #expect(first.position == 0 && second.position == 1)
        let renamed = try f.putRoutine(try decode(RoutineInput.self, "{\"id\":\"\(first.id)\",\"title\":\"One v2\",\"exercises\":[{\"exerciseID\":\"bench\"}]}"), author: .claude)
        #expect(renamed.id == first.id && renamed.createdAt == first.createdAt && renamed.position == 0 && renamed.title == "One v2")
        #expect(try f.routines().count == 2)
    }

    @Test func workoutParsesISODatesAndMarksSetsCompleted() throws {
        let f = try library()
        let input = try decode(WorkoutInput.self, #"{"title":"Chest day","startedAt":"2026-10-19T17:00:00Z","endedAt":"2026-10-19T18:05:00Z","exercises":[{"exercise":"Bench Press (Barbell)","sets":[{"weightLb":225,"reps":5}]}]}"#)
        let w = try f.putWorkout(input, author: .claude)
        #expect(w.startedAt == ms("2026-10-19T17:00:00Z") && w.endedAt == ms("2026-10-19T18:05:00Z"))
        #expect(w.exercises[0].sets[0].completed)
        #expect(try f.personalRecords(exerciseID: "bench").heaviestKg.map { abs($0 - 102.0583) < 0.01 } == true)
    }

    @Test func workoutNeedsAReadableStart() throws {
        let f = try library()
        #expect(throws: ForgeError.self) { try f.putWorkout(try decode(WorkoutInput.self, #"{"title":"x","startedAt":"yesterday","exercises":[]}"#), author: .claude) }
        #expect(throws: ForgeError.self) { try f.putWorkout(try decode(WorkoutInput.self, #"{"title":"x","exercises":[]}"#), author: .claude) }
    }

    @Test func exerciseInputCreatesAndThenUpdatesOnlyGivenFields() throws {
        let f = try library()
        let made = try f.putExercise(try decode(ExerciseInput.self, #"{"name":"Cable Fly","equipment":"cable","primaryMuscle":"chest","tracking":"weightReps"}"#), author: .claude)
        #expect(made.isCustom && made.equipment == "cable")
        let updated = try f.putExercise(try decode(ExerciseInput.self, "{\"id\":\"\(made.id)\",\"name\":\"Cable Chest Fly\"}"), author: .claude)
        #expect(updated.name == "Cable Chest Fly" && updated.equipment == "cable" && updated.primaryMuscle == "chest" && updated.createdAt == made.createdAt)
    }

    @Test func bodyweightAcceptsPoundsAndIsUndoable() throws {
        let f = try Forge.inMemory()
        try f.setBodyweight(date: "2026-10-20", pounds: 165, kg: nil, author: .claude)
        #expect(abs((try f.bodyweight(date: "2026-10-20") ?? 0) - 74.8427) < 0.001)
        try f.undo(author: .claude)
        #expect(try f.bodyweight(date: "2026-10-20") == nil)
        #expect(throws: ForgeError.self) { try f.setBodyweight(date: "not a date", pounds: 165, kg: nil, author: .claude) }
    }
}
