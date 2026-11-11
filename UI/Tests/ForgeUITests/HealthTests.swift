import ForgeCore
import Foundation
import Testing
@testable import ForgeUI

private var utc: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}

private func d(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }
private func span(_ a: String, _ b: String) -> SleepInterval { SleepInterval(start: d(a), end: d(b)) }

@Suite struct SleepAggregatorTests {
    @Test func aNightIsFiledUnderTheMorningItEndsOn() {
        let nights = SleepAggregator.nightly(intervals: [span("2026-10-19T23:00:00Z", "2026-10-20T07:00:00Z")], calendar: utc)
        #expect(nights == ["2026-10-20": 8 * 3600])
    }

    @Test func overlappingSourcesAreMergedNotAdded() {
        let nights = SleepAggregator.nightly(intervals: [span("2026-10-19T23:00:00Z", "2026-10-20T06:00:00Z"),
                                                         span("2026-10-19T23:30:00Z", "2026-10-20T07:00:00Z")], calendar: utc)
        #expect(nights["2026-10-20"] == 8 * 3600)
    }

    @Test func stagesThatTouchAreOneSleep() {
        let nights = SleepAggregator.nightly(intervals: [span("2026-10-19T23:00:00Z", "2026-10-20T02:00:00Z"),
                                                         span("2026-10-20T02:00:00Z", "2026-10-20T06:30:00Z")], calendar: utc)
        #expect(nights["2026-10-20"] == 7 * 3600 + 1800)
    }

    @Test func afternoonNapsAreIgnoredAndNightsStaySeparate() {
        let nights = SleepAggregator.nightly(intervals: [span("2026-10-20T14:00:00Z", "2026-10-20T15:00:00Z"),
                                                         span("2026-10-20T22:30:00Z", "2026-10-21T06:30:00Z"),
                                                         span("2026-10-19T23:00:00Z", "2026-10-20T06:00:00Z")], calendar: utc)
        #expect(nights == ["2026-10-20": 7 * 3600, "2026-10-21": 8 * 3600])
    }

    @Test func gapsBetweenWakingsDoNotCount() {
        let nights = SleepAggregator.nightly(intervals: [span("2026-10-19T23:00:00Z", "2026-10-20T03:00:00Z"),
                                                         span("2026-10-20T04:00:00Z", "2026-10-20T07:00:00Z")], calendar: utc)
        #expect(nights["2026-10-20"] == 7 * 3600)
    }

    @Test func emptyInputIsEmpty() {
        #expect(SleepAggregator.nightly(intervals: [], calendar: utc).isEmpty)
    }
}

private final class SpyHealth: HealthService, @unchecked Sendable {
    var authorized = false
    var exported: [Workout] = []
    var rows: [Recovery] = []
    var failExport = false
    func requestAuthorization() async throws { authorized = true }
    func exportWorkout(_ workout: Workout) async throws {
        if failExport { throw ForgeError.invalid("health said no") }
        exported.append(workout)
    }
    func recoveryRows(days: Int) async throws -> [Recovery] { rows }
}

@MainActor @Suite struct AppModelHealthTests {
    private func model(_ spy: SpyHealth) throws -> AppModel {
        AppModel(forge: try Forge.inMemory(), draftStore: nil, defaults: UserDefaults(suiteName: "health-\(UUID().uuidString)")!, health: spy)
    }

    private func finishOneSet(_ m: AppModel) throws {
        try m.forge.perform([.putExercise(Exercise(id: "e", name: "Squat"))], author: .me)
        m.reload()
        m.startWorkout(routine: nil)
        m.session?.addExercise("e")
        m.session?.update(exercise: 0, set: 0) { $0.weightKg = 100; $0.reps = 5 }
        m.session?.toggleComplete(exercise: 0, set: 0)
        try m.finishWorkout()
    }

    @Test func enablingHealthAsksForPermissionAndSyncsRecovery() async throws {
        let spy = SpyHealth()
        spy.rows = [Recovery(date: "2026-10-20", source: "apple_health", sleepSeconds: 27_000, hrvMs: 45)]
        let m = try model(spy)
        #expect(!m.healthEnabled)
        await m.setHealthEnabled(true)
        #expect(spy.authorized && m.healthEnabled)
        #expect(try m.forge.recoveries().first?.hrvMs == 45)
    }

    @Test func finishedWorkoutsAreExportedOnlyWhenHealthIsOn() async throws {
        let spy = SpyHealth()
        let off = try model(spy)
        try finishOneSet(off)
        await off.waitForHealthExport()
        #expect(spy.exported.isEmpty)

        let on = try model(spy)
        await on.setHealthEnabled(true)
        try finishOneSet(on)
        await on.waitForHealthExport()
        #expect(spy.exported.count == 1 && spy.exported[0].exercises[0].sets[0].reps == 5)
    }

    @Test func healthFailuresAreReportedNotThrown() async throws {
        let spy = SpyHealth()
        spy.failExport = true
        let m = try model(spy)
        await m.setHealthEnabled(true)
        try finishOneSet(m)
        await m.waitForHealthExport()
        #expect(m.lastError?.contains("health said no") == true)
        #expect(m.workouts.count == 1)                        // the workout itself is safe
    }

    @Test func recoveryIsReadFromTheDatabaseForAWorkout() async throws {
        let m = try model(SpyHealth())
        try m.forge.putRecoveries([Recovery(date: "2026-10-20", source: "eight_sleep", sleepScore: 77)], author: .importer)
        let w = Workout(title: "x", startedAt: Int64(ISO8601DateFormatter().date(from: "2026-10-20T17:00:00Z")!.timeIntervalSince1970 * 1000))
        #expect(m.recovery(for: w, timeZone: TimeZone(identifier: "UTC")!)?.sleepScore == 77)
    }
}

private struct HubTransport: SyncTransport {
    let hub: SyncHub
    func pull(since: Int64) async throws -> [RemoteOp] { try hub.pull(since: since) }
    func push(device: String, ops: [OutgoingOp]) async throws -> [SeqAssignment] { try hub.push(device: device, ops: ops) }
}

private struct BrokenTransport: SyncTransport {
    func pull(since: Int64) async throws -> [RemoteOp] { throw SyncHTTPError.status(401, "unauthorized") }
    func push(device: String, ops: [OutgoingOp]) async throws -> [SeqAssignment] { throw SyncHTTPError.status(401, "unauthorized") }
}

@MainActor @Suite struct AppModelSyncTests {
    private func model(_ name: String, transport: SyncTransport?) throws -> AppModel {
        AppModel(forge: try Forge.inMemory(device: name), draftStore: nil, defaults: UserDefaults(suiteName: "sync-\(UUID().uuidString)")!, syncTransport: transport)
    }

    @Test func changesFlowBetweenTwoModelsThroughTheHub() async throws {
        let hub = SyncHub(forge: try Forge.inMemory(device: "hub"))
        let a = try model("A", transport: HubTransport(hub: hub))
        let b = try model("B", transport: HubTransport(hub: hub))
        a.saveRoutine(Routine(id: "r", title: "From the phone"))
        await a.syncNow()
        await b.syncNow()
        #expect(b.routines.map(\.title) == ["From the phone"])     // b reloaded its screens after pulling
        #expect(a.syncStatus.contains("Synced"))
    }

    @Test func aSyncThatBringsNothingNewSkipsTheReload() async throws {
        let hub = SyncHub(forge: try Forge.inMemory(device: "hub"))
        let a = try model("A", transport: HubTransport(hub: hub))
        a.saveRoutine(Routine(id: "r", title: "Mine"))
        try a.forge.perform([.putExercise(Exercise(id: "e", name: "Squat"))], author: .claude)   // not yet picked up
        await a.syncNow()
        #expect(try hub.forge.routines().count == 1)                // it still pushed
        #expect(a.exercises.isEmpty)                                // but didn't re-read everything on the main thread
    }

    @Test func withoutSetupSyncExplainsItselfAndDoesNothing() async throws {
        let m = try model("A", transport: nil)
        #expect(!m.syncConfigured)
        await m.syncNow()
        #expect(m.syncStatus.contains("Not set up"))
        #expect(m.lastError == nil)
    }

    @Test func aFailedSyncIsReportedAndKeepsLocalData() async throws {
        let m = try model("A", transport: BrokenTransport())
        m.saveRoutine(Routine(id: "r", title: "Mine"))
        await m.syncNow()
        #expect(m.syncStatus.contains("failed") && m.syncStatus.contains("401"))
        #expect(m.routines.count == 1)
    }

    @Test func finishingAWorkoutTriggersASyncInTheBackground() async throws {
        let hub = SyncHub(forge: try Forge.inMemory(device: "hub"))
        let a = try model("A", transport: HubTransport(hub: hub))
        try a.forge.perform([.putExercise(Exercise(id: "e", name: "Squat"))], author: .me)
        a.reload()
        a.startWorkout(routine: nil)
        a.session?.addExercise("e")
        a.session?.update(exercise: 0, set: 0) { $0.weightKg = 100; $0.reps = 5 }
        a.session?.toggleComplete(exercise: 0, set: 0)
        try a.finishWorkout()
        await a.waitForSync()
        #expect(try hub.forge.workouts().count == 1)
    }

    @Test func savedSettingsAreKeptBesideTheDatabase() throws {
        let dir = NSTemporaryDirectory() + "forge-ui-sync-\(UUID().uuidString)"
        let path = dir + "/forge.sqlite"
        let m = AppModel(forge: try Forge.open(path: path, device: "x"), draftStore: nil, defaults: UserDefaults(suiteName: "sync-\(UUID().uuidString)")!, databasePath: path)
        #expect(!m.syncConfigured)
        try m.saveSyncConfig(url: "https://hub.example.ts.net/forge", token: "tok")
        #expect(m.syncConfigured)
        #expect(SyncConfig.load(besideDatabaseAt: path)?.token == "tok")
        #expect(throws: ForgeError.self) { try m.saveSyncConfig(url: "not a url", token: "tok") }
        m.clearSyncConfig()
        #expect(!m.syncConfigured && SyncConfig.load(besideDatabaseAt: path) == nil)
    }
}
