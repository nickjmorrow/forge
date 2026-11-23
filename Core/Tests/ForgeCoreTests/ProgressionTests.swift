import Foundation
import Testing
@testable import ForgeCore

private func done(_ w: Double?, _ r: Int?, _ type: SetType = .normal) -> SetEntry {
    SetEntry(type: type, weightKg: w, reps: r, completed: true)
}

@Suite struct ProgressionTests {
    @Test func addsARepToEverySetBelowTheTop() {
        let next = Progression.next(after: [done(50, 12), done(50, 10), done(50, 9)], range: 8...12, stepKg: 2.5)
        #expect(next?.step == .addReps)
        #expect(next?.sets.map(\.reps) == [12, 11, 10])
        #expect(next?.sets.map(\.weightKg) == [50, 50, 50])
    }

    @Test func addsWeightAndRestartsAtTheBottomOnceEverySetReachesTheTop() {
        let next = Progression.next(after: [done(50, 12), done(50, 13)], range: 8...12, stepKg: 2.5)
        #expect(next?.step == .addWeight)
        #expect(next?.sets.map(\.weightKg) == [52.5, 52.5])
        #expect(next?.sets.map(\.reps) == [8, 8])
    }

    @Test func warmupsAndSetsWithoutNumbersAreIgnored() {
        let next = Progression.next(after: [done(20, 15, .warmup), done(50, 12), done(nil, 5), done(50, nil)], range: 8...12, stepKg: 2.5)
        #expect(next?.sets.count == 1)
        #expect(next?.step == .addWeight)
        #expect(Progression.next(after: [done(20, 15, .warmup)], range: 8...12, stepKg: 2.5) == nil)
        #expect(Progression.next(after: [], range: 8...12, stepKg: 2.5) == nil)
    }

    @Test func applyLeavesWarmupsAndRepeatsTheLastTargetForExtraSets() {
        let suggestion = Progression.Suggestion(sets: [SetEntry(weightKg: 50, reps: 11), SetEntry(weightKg: 50, reps: 10)], step: .addReps)
        let planned = [SetEntry(type: .warmup, weightKg: 20, reps: 15), SetEntry(weightKg: 50, reps: 10), SetEntry(weightKg: 50, reps: 9), SetEntry(weightKg: 50, reps: 9)]
        let result = Progression.apply(suggestion, to: planned)
        #expect(result[0] == planned[0])
        #expect(result.dropFirst().map(\.reps) == [11, 10, 10])
    }

    @Test func onlyExercisesWhereMoreWeightIsHarderGetSuggestions() {
        #expect(Progression.applies(to: .weightReps) && Progression.applies(to: .weightedBodyweight))
        #expect(!Progression.applies(to: .assistedBodyweight) && !Progression.applies(to: .repsOnly) && !Progression.applies(to: .weightDuration))
    }

    @Test func lighterRoundsToTheStepAndNeverToNothing() {
        #expect(Progression.lighter(100, stepKg: 2.5) == 80)
        #expect(Progression.lighter(47.5, stepKg: 2.5) == 37.5)      // 38 rounds to 37.5
        #expect(Progression.lighter(2, stepKg: 2.5) == 2.5)
        #expect(Progression.lighter(0, stepKg: 2.5) == 0)
    }
}

@Suite struct OffDayTests {
    private func forge() throws -> Forge {
        let f = try Forge.inMemory()
        try f.perform([.putExercise(Exercise(id: "bench", name: "Bench"))], author: .me)
        return f
    }

    @Test func offDaysAreKeptInHistoryButAreNeverLastTime() throws {
        let f = try forge()
        let usual = Workout(id: "w1", title: "A", startedAt: 1000, exercises: [ExerciseBlock(exerciseID: "bench", sets: [done(100, 8)])])
        let light = Workout(id: "w2", title: "A", startedAt: 2000, exercises: [ExerciseBlock(exerciseID: "bench", sets: [done(80, 8)])], offDay: true)
        try f.perform([.putWorkout(usual), .putWorkout(light)], author: .me)
        #expect(try f.lastPerformance(exerciseID: "bench", before: 3000)?.map(\.weightKg) == [100])
        #expect(try f.exerciseHistory(exerciseID: "bench").map(\.offDay) == [true, false])
        #expect(try f.workout(id: "w2")?.isOffDay == true)
        #expect(try f.workouts().map(\.isOffDay) == [true, false])
    }

    @Test func offDayAndRepRangeSurviveSavingAndUndo() throws {
        let f = try forge()
        let routine = Routine(id: "r", title: "R", exercises: [ExerciseBlock(exerciseID: "bench", repsMin: 8, repsMax: 12, sets: [SetEntry(weightKg: 50, reps: 8)])])
        try f.perform([.putRoutine(routine)], author: .me)
        #expect(try f.routine(id: "r")?.exercises[0].repRange == 8...12)
        #expect(try f.routine(id: "r") == routine)
        let w = Workout(id: "w", title: "A", startedAt: 1000, exercises: routine.exercises, offDay: true)
        try f.perform([.putWorkout(w)], author: .me)
        #expect(try f.workout(id: "w") == w)
    }

    @Test func workoutsSavedBeforeOffDaysExistedStillDecode() throws {
        let old = #"{"id":"w","title":"A","startedAt":1,"exercises":[{"exerciseID":"bench","restSeconds":0,"sets":[]}]}"#
        let w = try JSONDecoder().decode(Workout.self, from: Data(old.utf8))
        #expect(!w.isOffDay && w.exercises[0].repRange == nil)
    }

    @Test func inputsCarryOffDayAndRejectHalfARepRange() throws {
        let f = try forge()
        let w = try f.putWorkout(try JSONDecoder().decode(WorkoutInput.self, from: Data(#"{"title":"A","startedAt":"2026-10-19T17:00:00Z","offDay":true,"exercises":[{"exercise":"Bench","sets":[{"weightKg":80,"reps":8}]}]}"#.utf8)), author: .claude)
        #expect(w.isOffDay)
        let r = try f.putRoutine(try JSONDecoder().decode(RoutineInput.self, from: Data(#"{"title":"R","exercises":[{"exercise":"Bench","repsMin":8,"repsMax":12}]}"#.utf8)), author: .claude)
        #expect(r.exercises[0].repRange == 8...12)
        for bad in [#"{"exercise":"Bench","repsMin":8}"#, #"{"exercise":"Bench","repsMin":12,"repsMax":8}"#, #"{"exercise":"Bench","repsMin":0,"repsMax":8}"#] {
            let input = try JSONDecoder().decode(RoutineInput.self, from: Data(#"{"title":"R","exercises":[\#(bad)]}"#.utf8))
            #expect(throws: ForgeError.self) { try f.putRoutine(input, author: .claude) }
        }
    }
}

@Suite struct AlternativesTests {
    @Test func alternativesSurviveSavingAndAnEmptyListIsNone() throws {
        let f = try Forge.inMemory()
        try f.perform([.putExercise(Exercise(id: "bench", name: "Bench")), .putExercise(Exercise(id: "press", name: "Machine Press"))], author: .me)
        let routine = Routine(id: "r", title: "R", exercises: [ExerciseBlock(exerciseID: "bench", alternatives: ["press"], sets: [SetEntry(weightKg: 50, reps: 8)]),
                                                                 ExerciseBlock(exerciseID: "press", alternatives: [])])
        try f.perform([.putRoutine(routine)], author: .me)
        #expect(try f.routine(id: "r") == routine)
        #expect(try f.routine(id: "r")?.exercises.map(\.alternatives) == [["press"], nil])
        let w = Workout(id: "w", title: "A", startedAt: 1, exercises: routine.exercises)
        try f.perform([.putWorkout(w)], author: .me)
        #expect(try f.workout(id: "w") == w)
        #expect(try f.workouts().first == w)
    }

    @Test func inputsTakeAlternativesByNameOrIdAndRejectUnknownOnes() throws {
        let f = try Forge.inMemory()
        try f.perform([.putExercise(Exercise(id: "bench", name: "Bench")), .putExercise(Exercise(id: "press", name: "Machine Press")),
                       .putExercise(Exercise(id: "dip", name: "Dip"))], author: .me)
        let input = try JSONDecoder().decode(RoutineInput.self, from: Data(#"{"title":"R","exercises":[{"exercise":"Bench","alternatives":["machine press","dip"]}]}"#.utf8))
        #expect(try f.putRoutine(input, author: .claude).exercises[0].alternatives == ["press", "dip"])
        let bad = try JSONDecoder().decode(RoutineInput.self, from: Data(#"{"title":"R","exercises":[{"exercise":"Bench","alternatives":["Nope"]}]}"#.utf8))
        #expect(throws: ForgeError.self) { try f.putRoutine(bad, author: .claude) }
    }
}
