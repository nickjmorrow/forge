import Foundation
import Testing
@testable import ForgeCore

@Suite struct RecoveryTests {
    @Test func putMergesFieldsPerDateAndSource() throws {
        let f = try Forge.inMemory()
        try f.putRecoveries([Recovery(date: "2026-10-20", source: "apple_health", sleepSeconds: 7 * 3600)], author: .importer)
        try f.putRecoveries([Recovery(date: "2026-10-20", source: "apple_health", hrvMs: 45, restingHR: 58)], author: .importer)
        let rows = try f.recoveries()
        #expect(rows.count == 1)
        #expect(rows[0].sleepSeconds == 7 * 3600 && rows[0].hrvMs == 45 && rows[0].restingHR == 58 && rows[0].sleepScore == nil)
    }

    @Test func sourcesCoexistForTheSameDate() throws {
        let f = try Forge.inMemory()
        try f.putRecoveries([Recovery(date: "2026-10-20", source: "apple_health", sleepSeconds: 25_000),
                             Recovery(date: "2026-10-20", source: "eight_sleep", sleepSeconds: 26_000, sleepScore: 77)], author: .importer)
        let rows = try f.recoveries()
        #expect(Set(rows.map(\.source)) == ["apple_health", "eight_sleep"])
        #expect(rows.first { $0.source == "eight_sleep" }?.sleepScore == 77)
    }

    @Test func rangeFiltersAndOrdersNewestFirst() throws {
        let f = try Forge.inMemory()
        try f.putRecoveries(["2026-10-18", "2026-10-19", "2026-10-20"].map { Recovery(date: $0, source: "x", sleepSeconds: 1) }, author: .importer)
        #expect(try f.recoveries().map(\.date) == ["2026-10-20", "2026-10-19", "2026-10-18"])
        #expect(try f.recoveries(from: "2026-10-19", to: "2026-10-19").map(\.date) == ["2026-10-19"])
    }

    @Test func oneCallIsOneUndoRestoringPreviousValues() throws {
        let f = try Forge.inMemory()
        try f.putRecoveries([Recovery(date: "2026-10-20", source: "x", sleepSeconds: 100)], author: .importer)
        try f.putRecoveries([Recovery(date: "2026-10-20", source: "x", sleepSeconds: 200), Recovery(date: "2026-10-21", source: "x", sleepSeconds: 300)], author: .claude)
        #expect(try f.recoveries().count == 2)
        try f.undo(author: .claude)
        let rows = try f.recoveries()
        #expect(rows.count == 1 && rows[0].sleepSeconds == 100)
    }

    @Test func unchangedRowsAreNotLoggedAgain() throws {
        let f = try Forge.inMemory()
        let row = Recovery(date: "2026-10-20", source: "apple_health", sleepSeconds: 100, hrvMs: 40)
        try f.putRecoveries([row], author: .importer)
        let n = try opCount(f)
        try f.putRecoveries([row], author: .importer)
        try f.putRecoveries([Recovery(date: "2026-10-20", source: "apple_health", hrvMs: 40)], author: .importer)   // a subset of what is stored
        #expect(try opCount(f) == n)
        try f.putRecoveries([Recovery(date: "2026-10-20", source: "apple_health", hrvMs: 41)], author: .importer)
        #expect(try opCount(f) == n + 1)
    }

    @Test func badDatesAndEmptyLists() throws {
        let f = try Forge.inMemory()
        #expect(throws: ForgeError.self) { try f.putRecoveries([Recovery(date: "yesterday", source: "x", sleepSeconds: 1)], author: .claude) }
        try f.putRecoveries([], author: .claude)
        #expect(try opCount(f) == 0)
    }

    @Test func recoveryNearAWorkoutIsThatMornings() throws {
        let f = try Forge.inMemory()
        try f.putRecoveries([Recovery(date: "2026-10-19", source: "a", sleepSeconds: 6 * 3600), Recovery(date: "2026-10-20", source: "a", sleepSeconds: 8 * 3600)], author: .importer)
        let timezone = TimeZone(identifier: "UTC")!
        let r = try f.recovery(forWorkoutStartedAt: ms("2026-10-20T17:00:00Z"), timeZone: timezone)
        #expect(r?.sleepSeconds == 8 * 3600)                               // the night that ended that morning
        #expect(try f.recovery(forWorkoutStartedAt: ms("2026-10-25T17:00:00Z"), timeZone: timezone) == nil)
    }
}
