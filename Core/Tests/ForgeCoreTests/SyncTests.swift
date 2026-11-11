import Foundation
import GRDB
import Testing
@testable import ForgeCore

final class TestClock: @unchecked Sendable {
    var now: Int64
    init(_ start: Int64) { now = start }
    func tick(_ by: Int64 = 1000) { now += by }
}

/// Talks to a hub in the same process.
struct LocalTransport: SyncTransport {
    let hub: SyncHub
    let device: String
    func pull(since: Int64) async throws -> [RemoteOp] { try hub.pull(since: since) }
    func push(device: String, ops: [OutgoingOp]) async throws -> [SeqAssignment] { try hub.push(device: device, ops: ops) }
}

private struct World {
    let hub: SyncHub
    let a: Forge, b: Forge
    let clockA: TestClock, clockB: TestClock

    init(clockA ca: Int64 = 1_000_000, clockB cb: Int64 = 1_000_000) throws {
        clockA = TestClock(ca); clockB = TestClock(cb)
        hub = SyncHub(forge: try Forge.inMemory(device: "hub", clock: { 1_000_000 }))
        a = try Forge.inMemory(device: "A", clock: { [clockA] in clockA.now })
        b = try Forge.inMemory(device: "B", clock: { [clockB] in clockB.now })
    }

    @discardableResult func sync(_ f: Forge) async throws -> SyncReport {
        try await SyncClient(forge: f, transport: LocalTransport(hub: hub, device: f.device)).sync()
    }

    func converged() throws -> Bool {
        try a.routines() == b.routines() && a.exercises() == b.exercises() && a.workouts() == b.workouts()
    }
}

private func routine(_ id: String, _ title: String) -> Routine { Routine(id: id, title: title, createdAt: 1, updatedAt: 1) }

@Suite struct SyncTests {
    @Test func aChangeOnOneDeviceAppearsOnTheOther() async throws {
        let w = try World()
        try w.a.perform([.putExercise(Exercise(id: "e", name: "Squat")), .putRoutine(routine("r", "Legs"))], author: .me)
        let report = try await w.sync(w.a)
        #expect(report.pushed == 1)
        try await w.sync(w.b)
        #expect(try w.b.routine(id: "r")?.title == "Legs" && (try w.b.exercise(id: "e")?.name) == "Squat")
        #expect(try w.converged())
    }

    @Test func concurrentEditsConvergeOnTheLaterOne() async throws {
        let w = try World()
        try w.a.perform([.putRoutine(routine("r", "Start"))], author: .me)
        try await w.sync(w.a); try await w.sync(w.b)
        w.clockA.tick(1000); try w.a.perform([.putRoutine(routine("r", "From A"))], author: .me)
        w.clockB.tick(5000); try w.b.perform([.putRoutine(routine("r", "From B, later"))], author: .me)
        try await w.sync(w.a); try await w.sync(w.b); try await w.sync(w.a)
        #expect(try w.a.routine(id: "r")?.title == "From B, later")
        #expect(try w.converged())
    }

    @Test func syncOrderDoesNotChangeTheWinner() async throws {
        let w = try World()
        try w.a.perform([.putRoutine(routine("r", "Start"))], author: .me)
        try await w.sync(w.a); try await w.sync(w.b)
        w.clockB.tick(5000); try w.b.perform([.putRoutine(routine("r", "B later"))], author: .me)
        w.clockA.tick(1000); try w.a.perform([.putRoutine(routine("r", "A earlier"))], author: .me)
        try await w.sync(w.b); try await w.sync(w.a); try await w.sync(w.b)     // B reaches the hub first this time
        #expect(try w.a.routine(id: "r")?.title == "B later" && (try w.converged()))
    }

    @Test func aDeleteLaterThanAnEditWinsAndAnEditLaterThanADeleteWins() async throws {
        for editWins in [false, true] {
            let w = try World()
            try w.a.perform([.putRoutine(routine("r", "Start"))], author: .me)
            try await w.sync(w.a); try await w.sync(w.b)
            if editWins {
                w.clockA.tick(1000); try w.a.perform([.deleteRoutine(id: "r")], author: .me)
                w.clockB.tick(9000); try w.b.perform([.putRoutine(routine("r", "Edited"))], author: .me)
            } else {
                w.clockB.tick(1000); try w.b.perform([.putRoutine(routine("r", "Edited"))], author: .me)
                w.clockA.tick(9000); try w.a.perform([.deleteRoutine(id: "r")], author: .me)
            }
            try await w.sync(w.a); try await w.sync(w.b); try await w.sync(w.a)
            #expect((try w.a.routine(id: "r") != nil) == editWins)
            #expect(try w.converged())
        }
    }

    @Test func aStaleEditCannotResurrectADeletedThing() async throws {
        let w = try World()
        try w.a.perform([.putRoutine(routine("r", "Start"))], author: .me)
        try await w.sync(w.a); try await w.sync(w.b)
        w.clockB.tick(1000); try w.b.perform([.putRoutine(routine("r", "Old edit"))], author: .me)       // B offline
        w.clockA.tick(9000); try w.a.perform([.deleteRoutine(id: "r")], author: .me)
        try await w.sync(w.a)
        try await w.sync(w.b)                                                                              // B's older edit arrives after the delete
        try await w.sync(w.a)
        #expect(try w.a.routine(id: "r") == nil && (try w.b.routine(id: "r")) == nil)
    }

    @Test func aDeviceWhoseClockRunsBehindStillWinsAfterSeeingNewerWork() async throws {
        let w = try World(clockA: 9_000_000, clockB: 1_000_000)        // B's clock is far behind
        try w.a.perform([.putRoutine(routine("r", "From A"))], author: .me)
        try await w.sync(w.a); try await w.sync(w.b)
        try w.b.perform([.putRoutine(routine("r", "B, after seeing A"))], author: .me)   // wall clock says 1_000_000, but B has seen 9_000_000
        try await w.sync(w.b); try await w.sync(w.a)
        #expect(try w.a.routine(id: "r")?.title == "B, after seeing A")
    }

    @Test func syncingAgainSendsNothingNew() async throws {
        let w = try World()
        try w.a.perform([.putRoutine(routine("r", "x"))], author: .me)
        try await w.sync(w.a)
        let again = try await w.sync(w.a)
        #expect(again.pushed == 0)
        #expect(try w.hub.head() == 1)
    }

    @Test func retryingAPushIsIdempotent() async throws {
        let w = try World()
        try w.a.perform([.putRoutine(routine("r", "x"))], author: .me)
        let op = try #require(try w.a.outgoingOps().first)
        let first = try w.hub.push(device: "A", ops: [op])
        let second = try w.hub.push(device: "A", ops: [op])
        #expect(first == second && first.count == 1)
        #expect(try w.hub.head() == 1)
    }

    @Test func mergingExercisesGivesTheOtherDeviceTheSameResult() async throws {
        let w = try World()
        let block = ExerciseBlock(exerciseID: "x", sets: [SetEntry(weightKg: 50, reps: 5, completed: true)])
        try w.a.perform([.putExercise(Exercise(id: "x", name: "Dup")), .putExercise(Exercise(id: "y", name: "Real")),
                         .putRoutine(Routine(id: "r", title: "R", exercises: [block], createdAt: 1, updatedAt: 1)),
                         .putWorkout(Workout(id: "w", title: "W", startedAt: 10, exercises: [block]))], author: .me)
        try await w.sync(w.a); try await w.sync(w.b)
        w.clockA.tick(); try w.a.deleteExercise(id: "x", mergeInto: "y", force: false, author: .claude)
        try await w.sync(w.a); try await w.sync(w.b)
        #expect(try w.b.exercise(id: "x") == nil)
        #expect(try w.b.routine(id: "r")?.exercises.map(\.exerciseID) == ["y"] && (try w.b.workout(id: "w")?.exercises.map(\.exerciseID)) == ["y"])
        #expect(try w.converged())
    }

    @Test func anUndoOnOneDeviceUndoesItEverywhere() async throws {
        let w = try World()
        try w.a.perform([.putRoutine(routine("r", "Temp"))], author: .claude)
        try await w.sync(w.a); try await w.sync(w.b)
        #expect(try w.b.routine(id: "r") != nil)
        w.clockA.tick(); try w.a.undo(author: .claude)
        try await w.sync(w.a); try await w.sync(w.b)
        #expect(try w.b.routine(id: "r") == nil)
    }

    @Test func changesMadeDirectlyOnTheHubAreSequencedAndPulled() async throws {
        let w = try World()
        try w.hub.forge.perform([.putRoutine(routine("hubr", "From the hub"))], author: .claude)      // like the forge CLI on the server
        try await w.sync(w.a)
        #expect(try w.a.routine(id: "hubr")?.title == "From the hub")
        #expect(try w.hub.head() == 1)
    }

    @Test func ownOpsComingBackAreNotAppliedTwice() async throws {
        let w = try World()
        try w.a.perform([.putRoutine(routine("r", "One"))], author: .me)
        try await w.sync(w.a)
        let report = try await w.sync(w.a)
        #expect(report.applied == 0)
        #expect(try w.a.routines().count == 1)
    }

    @Test func aBrokenRemoteOpDoesNotStopTheRest() async throws {
        let w = try World()
        try w.a.perform([.putExercise(Exercise(id: "e1", name: "One", hevyID: "H"))], author: .me)
        try w.b.perform([.putExercise(Exercise(id: "e2", name: "Two", hevyID: "H"))], author: .me)       // same Hevy id, different id
        try await w.sync(w.a)
        try w.b.perform([.putRoutine(routine("after", "After"))], author: .me)
        let report = try await w.sync(w.b)
        #expect(report.failed >= 0)
        #expect(try w.b.routine(id: "after") != nil && (try w.hub.forge.routine(id: "after")) != nil)
    }

    @Test func hevyImportedOnTwoDevicesDoesNotDuplicate() async throws {
        let w = try World()
        let template = HevyTemplate(id: "T1", title: "Squat", type: "weight_reps", primaryMuscleGroup: "quadriceps", secondaryMuscleGroups: [], equipment: "barbell", isCustom: false)
        _ = try HevyImporter(forge: w.a).importAll(templates: [template], routines: [], workouts: [])
        w.clockB.tick()
        _ = try HevyImporter(forge: w.b).importAll(templates: [template], routines: [], workouts: [])
        try await w.sync(w.a); try await w.sync(w.b); try await w.sync(w.a)
        #expect(try w.a.exercises().count == 1 && (try w.b.exercises().count) == 1)
        #expect(try w.converged())
    }
}

@Suite struct DeviceIdentityTests {
    @Test func aDatabaseKeepsItsDeviceNameAcrossOpens() throws {
        let path = NSTemporaryDirectory() + "forge-dev-\(UUID().uuidString)/forge.sqlite"
        let first = try Forge.open(path: path, device: "phone")
        #expect(first.device == "phone")
        let second = try Forge.open(path: path, device: "something-else")
        #expect(second.device == "phone")          // the Mac app and the CLI share one file, so they are one device
    }
}

@Suite struct SyncHTTPTests {
    private func server() throws -> (SyncHTTP, Forge) {
        let hubForge = try Forge.inMemory(device: "hub")
        return (SyncHTTP(hub: SyncHub(forge: hubForge), tokens: ["secret": "iphone"]), hubForge)
    }

    @Test func requestsNeedAKnownToken() throws {
        let (http, _) = try server()
        #expect(http.handle(method: "POST", path: "/sync/pull", query: [:], authorization: nil, body: Data()).status == 401)
        #expect(http.handle(method: "POST", path: "/sync/pull", query: [:], authorization: "Bearer nope", body: Data()).status == 401)
        #expect(http.handle(method: "POST", path: "/sync/pull", query: [:], authorization: "Bearer secret", body: Data()).status == 200)
        #expect(http.handle(method: "POST", path: "/sync/other", query: [:], authorization: "Bearer secret", body: Data()).status == 404)
    }

    @Test func pushThenPullRoundTripsThroughTheJSONAPI() throws {
        let (http, hubForge) = try server()
        let device = try Forge.inMemory(device: "iphone")
        try device.perform([.putRoutine(routine("r", "Legs"))], author: .me)
        let body = try JSONEncoder().encode(SyncHTTP.PushBody(device: "iphone", ops: try device.outgoingOps()))
        let pushed = http.handle(method: "POST", path: "/sync/push", query: [:], authorization: "Bearer secret", body: body)
        #expect(pushed.status == 200)
        #expect(try JSONDecoder().decode([SeqAssignment].self, from: pushed.body).count == 1)
        #expect(try hubForge.routine(id: "r")?.title == "Legs")
        let pulled = http.handle(method: "POST", path: "/sync/pull", query: ["since": "0"], authorization: "Bearer secret", body: Data())
        #expect(try JSONDecoder().decode([RemoteOp].self, from: pulled.body).count == 1)
    }

    @Test func malformedBodiesAreRejected() throws {
        let (http, _) = try server()
        #expect(http.handle(method: "POST", path: "/sync/push", query: [:], authorization: "Bearer secret", body: Data("nope".utf8)).status == 400)
        #expect(http.handle(method: "POST", path: "/sync/pull", query: ["since": "x"], authorization: "Bearer secret", body: Data()).status == 400)
    }
}


@Suite struct SyncRobustnessTests {
    private func world() throws -> (hub: SyncHub, a: Forge, b: Forge, clockA: TestClock, clockB: TestClock) {
        let ca = TestClock(1_000_000), cb = TestClock(1_000_000)
        return (SyncHub(forge: try Forge.inMemory(device: "hub", clock: { 1_000_000 })),
                try Forge.inMemory(device: "A", clock: { ca.now }), try Forge.inMemory(device: "B", clock: { cb.now }), ca, cb)
    }

    private func sync(_ f: Forge, _ hub: SyncHub) async throws -> SyncReport {
        try await SyncClient(forge: f, transport: LocalTransport(hub: hub, device: f.device)).sync()
    }

    @Test func anUnreadableOpDoesNotWedgeAnyone() async throws {
        let w = try world()
        try w.b.perform([.putRoutine(routine("good", "Good"))], author: .me)
        let good = try #require(try w.b.outgoingOps().first)
        let bad = OutgoingOp(localID: 1, author: "me", payload: "not json at all", createdAt: 1, ts: 5)
        let seqs = try w.hub.push(device: "X", ops: [bad, OutgoingOp(localID: 2, author: good.author, payload: good.payload, createdAt: good.createdAt, ts: good.ts)])
        #expect(seqs.count == 2)
        let first = try await sync(w.a, w.hub)
        let received = try w.a.routine(id: "good")
        #expect(first.failed == 1 && received != nil)
        let again = try await sync(w.a, w.hub)
        #expect(again.pulled == 0 && again.failed == 0)
    }

    @Test func anUnknownAuthorIsTolerated() async throws {
        let w = try world()
        try w.b.perform([.putRoutine(routine("r", "R"))], author: .me)
        let op = try #require(try w.b.outgoingOps().first)
        _ = try w.hub.push(device: "B", ops: [OutgoingOp(localID: op.localID, author: "hacker", payload: op.payload, createdAt: op.createdAt, ts: op.ts)])
        let changes = try w.hub.forge.changes(since: 0)
        #expect(changes.count == 1 && changes[0].author == .importer)
        _ = try await sync(w.a, w.hub)
        #expect(try w.a.changes(since: 0).count == 1)
    }

    @Test func theSameHevyIdOnDifferentIdsConvergesWithoutLosingAnything() async throws {
        let w = try world()
        try w.a.perform([.putExercise(Exercise(id: "x1", name: "Squat", hevyID: "H"))], author: .importer)
        w.clockB.tick(5000)
        try w.b.perform([.putExercise(Exercise(id: "x2", name: "Squat", hevyID: "H"))], author: .importer)
        var failed = 0
        for f in [w.a, w.b, w.a, w.b] { failed += try await sync(f, w.hub).failed }
        #expect(failed == 0)
        #expect(try w.a.exercises() == w.b.exercises())
        #expect(try w.a.exercises().count == 2)
        #expect(try w.a.exercises().filter { $0.hevyID == "H" }.map(\.id) == ["x2"])      // the newer write keeps the Hevy id
    }

    @Test func undoIsBlockedByALaterEditFromAnotherDeviceOfTheSameAuthor() async throws {
        let w = try world()
        try w.a.perform([.putRoutine(routine("r", "v1"))], author: .me)
        _ = try await sync(w.a, w.hub); _ = try await sync(w.b, w.hub)
        w.clockA.tick(); try w.a.perform([.putRoutine(routine("r", "v2"))], author: .me)
        _ = try await sync(w.a, w.hub); _ = try await sync(w.b, w.hub)
        w.clockB.tick(5000); try w.b.perform([.putRoutine(routine("r", "v3"))], author: .me)
        _ = try await sync(w.b, w.hub); _ = try await sync(w.a, w.hub)
        let result = try w.a.undo(author: .me)
        #expect(result.undone == 0 && result.skipped.count == 1)
        #expect(try w.a.routine(id: "r")?.title == "v3")
    }

    @Test func twoConnectionsToOneFileDoNotLockEachOtherOut() throws {
        let path = NSTemporaryDirectory() + "forge-busy-\(UUID().uuidString)/forge.sqlite"
        let one = try Forge.open(path: path, device: "one"), two = try Forge.open(path: path, device: "two")
        let lock = NSLock()
        nonisolated(unsafe) var failures = 0
        DispatchQueue.concurrentPerform(iterations: 2) { i in
            let f = i == 0 ? one : two
            for n in 0..<80 {
                do { try f.perform([.putRoutine(Routine(id: "r\(i)-\(n)", title: "x"))], author: .me) } catch { lock.lock(); failures += 1; lock.unlock() }
            }
        }
        #expect(failures == 0)
        #expect(try one.routines().count == 160)
    }

    @Test func firstOpensRacingEachOtherAllSucceed() throws {
        let path = NSTemporaryDirectory() + "forge-first-\(UUID().uuidString)/forge.sqlite"
        let lock = NSLock()
        nonisolated(unsafe) var failures = 0
        DispatchQueue.concurrentPerform(iterations: 4) { i in
            do { _ = try Forge.open(path: path, device: "d\(i)") } catch { lock.lock(); failures += 1; lock.unlock() }
        }
        #expect(failures == 0)
    }
}

@Suite struct MigrationBackfillTests {
    @Test func oldOpsOnOneEntityGetStrictlyIncreasingTimestamps() throws {
        let queue = try DatabaseQueue()
        try Schema.migrator().migrate(queue, upTo: "v3")
        let encoder = JSONEncoder()
        let put = String(decoding: try encoder.encode(Op.putExercise(Exercise(id: "x", name: "Squat"))), as: UTF8.self)
        let del = String(decoding: try encoder.encode(Op.deleteExercise(id: "x")), as: UTF8.self)
        try queue.write { db in
            for payload in [put, del] {
                try db.execute(sql: "INSERT INTO ops (device, author, kind, payload, inverse, created_at) VALUES ('old', 'me', 'x', ?, NULL, 1000)", arguments: [payload])
            }
        }
        try Schema.migrator().migrate(queue)
        let stamps = try queue.read { try Int64.fetchAll($0, sql: "SELECT ts FROM ops ORDER BY local_id") }
        #expect(stamps.count == 2 && stamps[0] < stamps[1])
        let clock = try queue.read { try Int64.fetchOne($0, sql: "SELECT ts FROM clocks WHERE entity = 'exercise:x'") }
        #expect(clock == stamps[1])
    }
}

private final class CapturingProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var last: URLRequest?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.last = request
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("[]".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite(.serialized) struct HTTPTransportTests {
    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CapturingProtocol.self]
        return URLSession(configuration: config)
    }

    @Test func requestsCarryTheTokenAndAnOptionalHostHeader() async throws {
        let transport = HTTPSyncTransport(baseURL: URL(string: "http://100.64.0.1:8452")!, token: "tok", hostHeader: "hub.example.ts.net:8452", session: session())
        _ = try await transport.pull(since: 7)
        let request = try #require(CapturingProtocol.last)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
        #expect(request.value(forHTTPHeaderField: "Host") == "hub.example.ts.net:8452")
        #expect(request.url?.path == "/sync/pull" && request.url?.query == "since=7")
        let plain = HTTPSyncTransport(baseURL: URL(string: "http://100.64.0.1:8452")!, token: "tok", session: session())
        _ = try await plain.pull(since: 0)
        #expect(CapturingProtocol.last?.value(forHTTPHeaderField: "Host") == nil)
    }

    @Test func configRoundTripsTheHostHeader() throws {
        let path = NSTemporaryDirectory() + "forge-cfg-\(UUID().uuidString)/forge.sqlite"
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try SyncConfig(url: URL(string: "http://100.64.0.1:8452")!, token: "t", hostHeader: "hub.example.ts.net:8452").save(besideDatabaseAt: path)
        #expect(SyncConfig.load(besideDatabaseAt: path)?.hostHeader == "hub.example.ts.net:8452")
        try SyncConfig(url: URL(string: "http://x")!, token: "t").save(besideDatabaseAt: path)
        #expect(SyncConfig.load(besideDatabaseAt: path)?.hostHeader == nil)
    }
}
