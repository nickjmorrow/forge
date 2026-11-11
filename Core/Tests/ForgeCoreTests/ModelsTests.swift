import Foundation
import GRDB
import Testing
@testable import ForgeCore

@Suite struct ModelsTests {
    @Test func modelsRoundTripThroughJSON() throws {
        let routine = Routine(
            id: "r1", title: "Upper Body", folder: nil, position: 0,
            exercises: [
                ExerciseBlock(exerciseID: "e1", notes: nil, restSeconds: 90, supersetID: nil, sets: [
                    SetEntry(type: .warmup, weightKg: 43.09, reps: 12, durationSeconds: nil, distanceMeters: nil, rpe: nil, completed: false),
                    SetEntry(type: .normal, weightKg: 61.23, reps: 6, durationSeconds: nil, distanceMeters: nil, rpe: 8, completed: false),
                ]),
                ExerciseBlock(exerciseID: "e2", notes: "slow", restSeconds: 0, supersetID: 1, sets: []),
            ],
            hevyID: nil, createdAt: 1, updatedAt: 2)
        let data = try JSONEncoder().encode(routine)
        #expect(try JSONDecoder().decode(Routine.self, from: data) == routine)
    }

    @Test func inMemoryStoreRunsMigrations() throws {
        let forge = try Forge.inMemory()
        let names = try forge.db.read { try String.fetchAll($0, sql: "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'grdb_%'") }
        let expected: Set<String> = ["exercises", "routines", "routine_exercises", "routine_sets", "workouts", "workout_exercises", "workout_sets", "bodyweight", "ops", "recovery", "clocks", "meta"]
        #expect(Set(names) == expected)
    }
}

@Suite struct FileStoreTests {
    @Test func reopeningAFileDatabaseKeepsDataAndUsesWAL() throws {
        let path = NSTemporaryDirectory() + "forge-core-\(UUID().uuidString)/forge.sqlite"
        do {
            let f = try Forge.open(path: path, device: "a")
            try f.perform([.putExercise(Exercise(id: "e1", name: "Squat"))], author: .me)
        }
        let again = try Forge.open(path: path, device: "b")
        #expect(try again.exercise(id: "e1")?.name == "Squat")
        #expect(try again.db.read { try String.fetchOne($0, sql: "PRAGMA journal_mode") } == "wal")
    }
}

@Suite struct DataVersionTests {
    @Test func dataVersionChangesOnlyWhenAnotherConnectionWrites() throws {
        let path = NSTemporaryDirectory() + "forge-core-\(UUID().uuidString)/forge.sqlite"
        let a = try Forge.open(path: path, device: "a")
        let b = try Forge.open(path: path, device: "b")
        let before = try a.dataVersion()
        try a.perform([.putExercise(Exercise(name: "mine"))], author: .me)
        #expect(try a.dataVersion() == before)                 // own writes are not "external"
        try b.perform([.putExercise(Exercise(name: "theirs"))], author: .claude)
        #expect(try a.dataVersion() != before)
    }
}
