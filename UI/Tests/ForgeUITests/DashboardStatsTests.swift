import ForgeCore
import Foundation
import Testing
@testable import ForgeUI

private var utc: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    c.firstWeekday = 2
    return c
}

private func ms(_ iso: String) -> Int64 { Int64(ISO8601DateFormatter().date(from: iso)!.timeIntervalSince1970 * 1000) }
private func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

private func workout(_ id: String, _ iso: String, sets: [(Double, Int)], exercise: String = "bench") -> Workout {
    Workout(id: id, title: id, startedAt: ms(iso), endedAt: ms(iso) + 3_600_000,
            exercises: [ExerciseBlock(exerciseID: exercise, sets: sets.map { SetEntry(weightKg: $0.0, reps: $0.1, completed: true) })])
}

@Suite struct DashboardStatsTests {
    @Test func thisWeekCountsWorkoutsSetsAndVolumeSinceMonday() {
        let workouts = [
            workout("mon", "2026-10-19T12:00:00Z", sets: [(100, 5), (100, 5)]),
            workout("tue", "2026-10-20T12:00:00Z", sets: [(50, 10)]),
            workout("lastSun", "2026-10-18T12:00:00Z", sets: [(200, 1)]),
        ]
        let week = DashboardStats.thisWeek(workouts: workouts, now: date("2026-10-21T09:00:00Z"), calendar: utc)
        #expect(week.workouts == 2 && week.sets == 3 && week.volumeKg == 1500)
    }

    @Test func warmupsAndUncompletedSetsDoNotCountTowardSetsOrVolume() {
        var w = workout("a", "2026-10-19T12:00:00Z", sets: [(100, 5)])
        w.exercises[0].sets.append(SetEntry(type: .warmup, weightKg: 40, reps: 10, completed: true))
        w.exercises[0].sets.append(SetEntry(weightKg: 100, reps: 5, completed: false))
        let week = DashboardStats.thisWeek(workouts: [w], now: date("2026-10-21T09:00:00Z"), calendar: utc)
        #expect(week.sets == 1 && week.volumeKg == 500)
    }

    @Test func calendarMarksDaysWithWorkoutsInTheLastWeeks() {
        let workouts = [workout("a", "2026-10-19T12:00:00Z", sets: [(1, 1)]), workout("b", "2026-10-19T18:00:00Z", sets: [(1, 1)]),
                        workout("old", "2025-01-01T12:00:00Z", sets: [(1, 1)])]
        let days = DashboardStats.workoutDays(workouts: workouts, weeks: 12, now: date("2026-10-21T09:00:00Z"), calendar: utc)
        #expect(days[date("2026-10-19T00:00:00Z")] == 2)
        #expect(days.count == 1)
    }

    @Test func weeklyTotalsCountWorkoutsAndHoursPerWeekEndingThisWeek() {
        var unfinished = workout("noEnd", "2026-10-13T12:00:00Z", sets: [(1, 1)])
        unfinished.endedAt = nil
        let workouts = [workout("mon", "2026-10-19T12:00:00Z", sets: [(1, 1)]), workout("tue", "2026-10-20T12:00:00Z", sets: [(1, 1)]),
                        workout("lastWeek", "2026-10-12T12:00:00Z", sets: [(1, 1)]), unfinished,
                        workout("tooOld", "2026-09-01T12:00:00Z", sets: [(1, 1)])]
        let weeks = DashboardStats.weekly(workouts: workouts, weeks: 3, now: date("2026-10-21T09:00:00Z"), calendar: utc)
        #expect(weeks.map(\.weekStart) == [date("2026-10-05T00:00:00Z"), date("2026-10-12T00:00:00Z"), date("2026-10-19T00:00:00Z")])
        #expect(weeks.map(\.workouts) == [0, 2, 2])
        #expect(weeks.map(\.hours) == [0, 1, 2])
    }

    @Test func calendarGridCoversWholeWeeksEndingThisWeek() {
        let grid = DashboardStats.calendarDays(weeks: 3, now: date("2026-10-21T09:00:00Z"), calendar: utc)
        #expect(grid.count == 21)
        #expect(grid.first == date("2026-10-05T00:00:00Z"))
        #expect(grid.last == date("2026-10-25T00:00:00Z"))
    }

    @Test func recentRecordsListExercisesWhoseBestSetIsRecent() throws {
        let f = try Forge.inMemory()
        try f.perform([.putExercise(Exercise(id: "bench", name: "Bench")), .putExercise(Exercise(id: "squat", name: "Squat"))], author: .me)
        try f.perform([
            .putWorkout(workout("old-bench", "2026-08-01T12:00:00Z", sets: [(100, 5)], exercise: "bench")),
            .putWorkout(workout("new-bench", "2026-10-15T12:00:00Z", sets: [(110, 5)], exercise: "bench")),
            .putWorkout(workout("old-squat", "2026-08-01T12:00:00Z", sets: [(150, 5)], exercise: "squat")),
            .putWorkout(workout("new-squat", "2026-10-15T12:00:00Z", sets: [(120, 5)], exercise: "squat")),
        ], author: .me)
        let records = try DashboardStats.recentRecords(forge: f, now: date("2026-10-21T09:00:00Z"), days: 30)
        #expect(records.map(\.name) == ["Bench"])                        // squat's best is from August
        #expect(abs(records[0].e1RMKg - e1RM(weightKg: 110, reps: 5)) < 0.001)
        #expect(records[0].date == date("2026-10-15T12:00:00Z"))
    }
}
