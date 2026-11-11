import Foundation
import Testing
@testable import ForgeCore

@Suite struct ExportAndBodyweightTests {
    @Test func bodyweightsComeBackNewestFirst() throws {
        let f = try Forge.inMemory()
        try f.setBodyweight(date: "2026-10-18", pounds: 166, kg: nil, author: .me)
        try f.setBodyweight(date: "2026-10-20", pounds: nil, kg: 75, author: .me)
        let rows = try f.bodyweights()
        #expect(rows.map(\.date) == ["2026-10-20", "2026-10-18"])
        #expect(rows[0].kg == 75 && abs(rows[1].kg - 75.3) < 0.1)
    }

    @Test func deletingABodyweightEntryIsUndoable() throws {
        let f = try Forge.inMemory()
        try f.setBodyweight(date: "2026-10-20", pounds: nil, kg: 75, author: .me)
        try f.deleteBodyweight(date: "2026-10-20", author: .me)
        #expect(try f.bodyweights().isEmpty)
        try f.undo(author: .me)
        #expect(try f.bodyweights().count == 1)
        #expect(throws: ForgeError.self) { try f.deleteBodyweight(date: "2000-01-01", author: .me) }
    }

    @Test func theExportHoldsEverythingAsReadableJSON() throws {
        let f = try Forge.inMemory()
        let block = ExerciseBlock(exerciseID: "e", sets: [SetEntry(weightKg: 100, reps: 5, completed: true)])
        try f.perform([.putExercise(Exercise(id: "e", name: "Squat")), .putRoutine(Routine(id: "r", title: "Legs", exercises: [block])),
                       .putWorkout(Workout(id: "w", title: "Legs day", startedAt: 1000, exercises: [block]))], author: .me)
        try f.setBodyweight(date: "2026-10-20", pounds: nil, kg: 75, author: .me)
        try f.putRecoveries([Recovery(date: "2026-10-20", source: "eight_sleep", sleepSeconds: 27_000)], author: .importer)
        let data = try f.exportAll()
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["version"] as? Int == 1)
        #expect((object["exercises"] as? [Any])?.count == 1 && (object["routines"] as? [Any])?.count == 1)
        #expect((object["workouts"] as? [Any])?.count == 1 && (object["bodyweight"] as? [Any])?.count == 1 && (object["recovery"] as? [Any])?.count == 1)
        let decoded = try JSONDecoder().decode(ForgeExport.self, from: data)
        #expect(decoded.workouts[0].exercises[0].sets[0].weightKg == 100)
        #expect(!decoded.exportedAt.isEmpty)
    }

    @Test func anEmptyDatabaseExportsCleanly() throws {
        let decoded = try JSONDecoder().decode(ForgeExport.self, from: try Forge.inMemory().exportAll())
        #expect(decoded.exercises.isEmpty && decoded.workouts.isEmpty && decoded.routines.isEmpty)
    }
}

@Suite struct ChangeSummaryTests {
    @Test func singleChangesReadAsPlainEnglish() {
        #expect(Op.putWorkout(Workout(title: "Legs", startedAt: 1)).summary == "Saved workout “Legs”")
        #expect(Op.putRoutine(Routine(title: "Push")).summary == "Saved routine “Push”")
        #expect(Op.putExercise(Exercise(name: "Squat")).summary == "Saved exercise “Squat”")
        #expect(Op.deleteRoutine(id: "r").summary == "Deleted a routine")
        #expect(Op.deleteWorkout(id: "w").summary == "Deleted a workout")
        #expect(Op.deleteExercise(id: "e").summary == "Deleted an exercise")
        #expect(Op.putBodyweight(date: "2026-10-20", kg: 75).summary == "Bodyweight 75 kg on 2026-10-20")
    }

    @Test func batchesOfOneKindAreCounted() {
        let routines = Op.batch([.putRoutine(Routine(title: "A")), .putRoutine(Routine(title: "B")), .putRoutine(Routine(title: "C"))])
        #expect(routines.summary == "Saved 3 routines")
        #expect(Op.batch(Array(repeating: Op.putWorkout(Workout(title: "x", startedAt: 1)), count: 24)).summary == "Saved 24 workouts")
    }

    @Test func mixedBatchesListWhatTheyContain() {
        let mixed = Op.batch([.putRoutine(Routine(title: "Push")), .deleteExercise(id: "e")])
        #expect(mixed.summary == "Saved routine “Push”; Deleted an exercise")
    }
}
