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

private func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }
private func workout(_ id: String, _ iso: String) -> Workout {
    Workout(id: id, title: id, startedAt: Int64(date(iso).timeIntervalSince1970 * 1000))
}

@Suite struct HistoryCalendarTests {
    @Test func aMonthIsPaddedSoWeekdaysLineUpStartingMonday() {
        let cells = HistoryCalendar.cells(forMonthOf: date("2026-10-15T12:00:00Z"), calendar: utc)
        #expect(cells.prefix(3).allSatisfy { $0 == nil })                       // Oct 1 2026 is a Thursday
        #expect(cells[3] == date("2026-10-01T00:00:00Z"))
        #expect(cells.compactMap { $0 }.count == 31 && cells.last! == date("2026-10-31T00:00:00Z"))
        #expect(cells.count == 34)
    }

    @Test func aMonthStartingOnMondayHasNoPadding() {
        let cells = HistoryCalendar.cells(forMonthOf: date("2027-02-10T12:00:00Z"), calendar: utc)
        #expect(cells.first! == date("2027-02-01T00:00:00Z") && cells.count == 28)
    }

    @Test func monthsStepBackAndForwardIncludingAcrossYears() {
        #expect(HistoryCalendar.month(date("2026-01-20T12:00:00Z"), shiftedBy: -1, calendar: utc) == date("2025-12-01T00:00:00Z"))
        #expect(HistoryCalendar.month(date("2026-10-20T12:00:00Z"), shiftedBy: 1, calendar: utc) == date("2026-11-01T00:00:00Z"))
        #expect(HistoryCalendar.month(date("2026-10-20T12:00:00Z"), shiftedBy: 0, calendar: utc) == date("2026-10-01T00:00:00Z"))
    }

    @Test func workoutsAreCountedPerDay() {
        let counts = HistoryCalendar.counts(workouts: [workout("a", "2026-10-19T08:00:00Z"), workout("b", "2026-10-19T20:00:00Z"), workout("c", "2026-10-20T09:00:00Z")], calendar: utc)
        #expect(counts[date("2026-10-19T00:00:00Z")] == 2 && counts[date("2026-10-20T00:00:00Z")] == 1 && counts.count == 2)
    }

    @Test func aDaysWorkoutsAreFilteredNewestFirst() {
        let all = [workout("morning", "2026-10-19T08:00:00Z"), workout("evening", "2026-10-19T20:00:00Z"), workout("other", "2026-10-20T09:00:00Z")]
        #expect(HistoryCalendar.workouts(on: date("2026-10-19T00:00:00Z"), in: all, calendar: utc).map(\.id) == ["evening", "morning"])
        #expect(HistoryCalendar.workouts(on: date("2026-10-25T00:00:00Z"), in: all, calendar: utc).isEmpty)
    }

    @Test func theCalendarOpensOnTheLatestWorkoutsMonthOrToday() {
        let all = [workout("old", "2026-08-02T08:00:00Z"), workout("latest", "2026-09-14T08:00:00Z")]
        #expect(HistoryCalendar.initialMonth(workouts: all, now: date("2026-10-20T12:00:00Z"), calendar: utc) == date("2026-09-01T00:00:00Z"))
        #expect(HistoryCalendar.initialMonth(workouts: [], now: date("2026-10-20T12:00:00Z"), calendar: utc) == date("2026-10-01T00:00:00Z"))
    }
}
