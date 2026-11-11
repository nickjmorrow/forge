import ForgeCore
import Foundation
import Testing
@testable import ForgeUI

/// Rows carry their own data, so a row SwiftUI is still animating out can never index past the end of a shorter list.
@Suite struct ActiveWorkoutRowsTests {
    @Test func setRowsCarryTheirEntryLabelAndPrevious() {
        let ids = [UUID(), UUID(), UUID(), UUID()]
        let sets = [SetEntry(type: .warmup, reps: 10), SetEntry(reps: 8), SetEntry(type: .drop, reps: 6), SetEntry(reps: 5)]
        let rows = SetRowItem.items(sets: sets, ids: ids, previous: [SetEntry(reps: 9), SetEntry(reps: 7)])
        #expect(rows.map(\.id) == ids)
        #expect(rows.map(\.label) == ["W", "1", "D", "2"])
        #expect(rows.map(\.entry) == sets)
        #expect(rows.map(\.previous) == [SetEntry(reps: 9), SetEntry(reps: 7), nil, nil])
    }

    @Test func setRowsNeverOutrunTheSets() {
        let rows = SetRowItem.items(sets: [SetEntry(reps: 8)], ids: [UUID(), UUID()], previous: [])
        #expect(rows.count == 1)
    }

    @Test func exerciseRowsNeverOutrunTheExercises() {
        let workout = Workout(title: "W", startedAt: 0, exercises: [ExerciseBlock(exerciseID: "a", sets: [SetEntry()])])
        let rows = BlockRowItem.items(workout: workout, ids: [UUID(), UUID()], setIDs: [[UUID()], [UUID()]])
        #expect(rows.count == 1)
        #expect(rows.first?.block.exerciseID == "a" && rows.first?.index == 0)
    }
}
