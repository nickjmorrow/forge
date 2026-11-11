import Foundation
import Testing
import ForgeCore
@testable import forge

private func tempDB() -> String {
    NSTemporaryDirectory() + "forge-test-\(UUID().uuidString)/forge.sqlite"
}

private func seed(_ path: String) throws -> Forge {
    let f = try Forge.open(path: path, device: "test")
    let block = ExerciseBlock(exerciseID: "e1", restSeconds: 60, sets: [SetEntry(weightKg: 100, reps: 5, completed: true)])
    try f.perform([
        .putExercise(Exercise(id: "e1", name: "Acme Row")),
        .putExercise(Exercise(id: "e2", name: "Bench")),
        .putRoutine(Routine(id: "r1", title: "Back", position: 0, exercises: [block], createdAt: 1, updatedAt: 1)),
        .putWorkout(Workout(id: "w1", title: "Back day", startedAt: 1000, exercises: [block])),
    ], author: .me)
    return f
}

private func json(_ s: String) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any])
}

@Suite struct CommandTests {
    @Test func exerciseDeleteWithHistoryExitsNonzeroWithJSONError() async throws {
        let path = tempDB()
        let f = try seed(path)
        let r = await Runner.run(["exercise", "delete", "e1", "--db", path])
        #expect(r.code == 1)
        #expect(r.out.isEmpty)
        #expect(try (json(r.err)["error"] as? String)?.contains("history") == true)
        #expect(try f.exercise(id: "e1") != nil)
    }

    @Test func exerciseDeleteWithMergeIntoSucceeds() async throws {
        let path = tempDB()
        let f = try seed(path)
        let r = await Runner.run(["exercise", "delete", "e1", "--merge-into", "e2", "--db", path])
        #expect(r.code == 0)
        #expect(try f.routine(id: "r1")?.exercises.map(\.exerciseID) == ["e2"])
    }

    @Test func removeExercisePreviewDoesNotChange() async throws {
        let path = tempDB()
        let f = try seed(path)
        let r = await Runner.run(["routine", "remove-exercise", "acme", "--preview", "--db", path])
        #expect(r.code == 0)
        #expect(r.out.contains("Acme Row") && r.out.contains("Back"))
        #expect(try f.routine(id: "r1")?.exercises.count == 1)
    }

    @Test func removeExerciseAppliesAndIsUndoable() async throws {
        let path = tempDB()
        let f = try seed(path)
        let r = await Runner.run(["routine", "remove-exercise", "acme", "--db", path])
        #expect(r.code == 0)
        #expect(try f.routine(id: "r1")?.exercises.isEmpty == true)
        let u = await Runner.run(["undo", "--db", path])
        #expect(u.code == 0)
        #expect(try f.routine(id: "r1")?.exercises.count == 1)
    }

    @Test func sqlRejectsWrites() async throws {
        let path = tempDB()
        let f = try seed(path)
        let r = await Runner.run(["sql", "delete from exercises", "--db", path])
        #expect(r.code == 1)
        #expect(try f.exercises().count == 2)
        let ok = await Runner.run(["sql", "select count(*) as n from exercises", "--db", path])
        #expect(ok.code == 0 && ok.out.contains("\"n\""))
    }

    @Test func undoRevertsLastClaudeChange() async throws {
        let path = tempDB()
        _ = try seed(path)
        let added = await Runner.run(["exercise", "add", "--name", "Foo Curl", "--equipment", "dumbbell", "--db", path])
        #expect(added.code == 0)
        #expect(await Runner.run(["exercise", "list", "--match", "foo", "--db", path]).out.contains("Foo Curl"))
        let u = await Runner.run(["undo", "--db", path])
        #expect(u.code == 0)
        #expect(await Runner.run(["exercise", "list", "--match", "foo", "--db", path]).out.contains("Foo Curl") == false)
    }

    @Test func importHevyFromDirReportsCounts() async throws {
        let path = tempDB()
        let dir = NSTemporaryDirectory() + "hevy-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try #"{"page":1,"page_count":1,"exercise_templates":[{"id":"T1","title":"Squat","type":"weight_reps","primary_muscle_group":"quads","secondary_muscle_groups":[],"equipment":"barbell","is_custom":false}]}"#
            .write(toFile: dir + "/templates.json", atomically: true, encoding: .utf8)
        let r = await Runner.run(["import-hevy", "--from-dir", dir, "--db", path])
        #expect(r.code == 0)
        #expect(try (json(r.out)["exercises"] as? [String: Any])?["added"] as? Int == 1)
    }

    @Test func missingApiKeyIsAJSONError() async throws {
        let path = tempDB()
        let r = await Runner.run(["import-hevy", "--db", path])
        // CI and dev machines may have HEVY_API_KEY set; only assert shape when it is absent.
        if ProcessInfo.processInfo.environment["HEVY_API_KEY"] == nil {
            #expect(r.code == 1)
            #expect(try (json(r.err)["error"] as? String)?.contains("HEVY_API_KEY") == true)
        }
    }

    @Test func defaultAuthorIsClaude() async throws {
        let path = tempDB()
        let f = try seed(path)
        _ = await Runner.run(["exercise", "add", "--name", "X", "--db", path])
        #expect(try f.changes(since: 0, author: .claude).count == 1)
    }

    @Test func routinePutByNameThenShowListAndDelete() async throws {
        let path = tempDB()
        _ = try seed(path)
        let body = #"{"title":"Push","exercises":[{"exercise":"Bench","sets":[{"weightLb":135,"reps":8},{"weightLb":135,"reps":8}]}]}"#
        let put = await Runner.run(["routine", "put", "--json", body, "--db", path])
        #expect(put.code == 0)
        let id = try #require(try json(put.out)["id"] as? String)
        let shown = await Runner.run(["routine", "show", id, "--db", path])
        #expect(shown.out.contains("Bench") && shown.out.contains("\"reps\" : 8"))
        #expect(await Runner.run(["routine", "list", "--db", path]).out.contains("Push"))
        #expect(await Runner.run(["routine", "delete", id, "--db", path]).code == 0)
        #expect(await Runner.run(["routine", "list", "--db", path]).out.contains("Push") == false)
        #expect(await Runner.run(["undo", "--db", path]).code == 0)
        #expect(await Runner.run(["routine", "list", "--db", path]).out.contains("Push"))
    }

    @Test func routinePutWithUnknownExerciseIsAJSONError() async throws {
        let path = tempDB()
        _ = try seed(path)
        let r = await Runner.run(["routine", "put", "--json", #"{"title":"X","exercises":[{"exercise":"Nope"}]}"#, "--db", path])
        #expect(r.code == 1)
        #expect(try (json(r.err)["error"] as? String)?.contains("Nope") == true)
    }

    @Test func workoutPutShowAndDelete() async throws {
        let path = tempDB()
        _ = try seed(path)
        let body = #"{"title":"Back day","startedAt":"2026-10-19T17:00:00Z","endedAt":"2026-10-19T18:00:00Z","exercises":[{"exercise":"Bench","sets":[{"weightLb":185,"reps":5}]}]}"#
        let put = await Runner.run(["workout", "put", "--json", body, "--db", path])
        #expect(put.code == 0)
        let id = try #require(try json(put.out)["id"] as? String)
        #expect(await Runner.run(["workout", "show", id, "--db", path]).out.contains("Bench"))
        #expect(await Runner.run(["workout", "delete", id, "--db", path]).code == 0)
        #expect(await Runner.run(["workout", "show", id, "--db", path]).code == 1)
    }

    @Test func exercisePutAndShowIncludeUsageAndRecords() async throws {
        let path = tempDB()
        _ = try seed(path)
        let made = await Runner.run(["exercise", "put", "--json", #"{"name":"Cable Fly","equipment":"cable","primaryMuscle":"chest"}"#, "--db", path])
        #expect(made.code == 0)
        let shown = await Runner.run(["exercise", "show", "e1", "--db", path])
        #expect(shown.code == 0)
        let obj = try json(shown.out)
        #expect((obj["usage"] as? [String: Any])?["workouts"] as? Int == 1)
        #expect(obj["records"] != nil)
    }

    @Test func bodyweightSetListAndSchema() async throws {
        let path = tempDB()
        _ = try seed(path)
        #expect(await Runner.run(["bodyweight", "set", "2026-10-20", "--lb", "165", "--db", path]).code == 0)
        let list = await Runner.run(["bodyweight", "list", "--db", path])
        #expect(list.out.contains("2026-10-20") && list.out.contains("74.8"))
        let schema = await Runner.run(["schema", "--db", path])
        #expect(schema.code == 0 && schema.out.contains("workout_sets") && schema.out.contains("CREATE TABLE"))
    }

    @Test func recoveryPutListAndRejectBadDates() async throws {
        let path = tempDB()
        _ = try seed(path)
        let body = #"[{"date":"2026-10-20","source":"eight_sleep","sleepSeconds":27000,"sleepScore":75,"hrvMs":60},{"date":"2026-10-19","source":"apple_health","restingHR":58}]"#
        let put = await Runner.run(["recovery", "put", "--json", body, "--db", path])
        #expect(put.code == 0)
        let list = await Runner.run(["recovery", "list", "--db", path])
        #expect(list.out.contains("eight_sleep") && list.out.contains("apple_health"))
        let one = await Runner.run(["recovery", "list", "--from", "2026-10-20", "--db", path])
        #expect(one.out.contains("eight_sleep") && !one.out.contains("apple_health"))
        let single = await Runner.run(["recovery", "put", "--json", #"{"date":"2026-10-21","source":"eight_sleep","sleepScore":70}"#, "--db", path])
        #expect(single.code == 0)
        let bad = await Runner.run(["recovery", "put", "--json", #"[{"date":"tomorrow","source":"x"}]"#, "--db", path])
        #expect(bad.code == 1 && bad.err.contains("2026-10-20"))
    }
}

@Suite struct SyncCommandTests {
    private func hub() throws -> (SyncServer, Forge, UInt16) {
        let hubForge = try Forge.open(path: tempDB(), device: "hub")
        let server = try SyncServer(http: SyncHTTP(hub: SyncHub(forge: hubForge), tokens: ["tok": "anyone"]))
        return (server, hubForge, try server.start())
    }

    @Test func twoDatabasesShareThroughARealServer() async throws {
        let (server, hubForge, port) = try hub()
        defer { server.stop() }
        let a = tempDB(), b = tempDB()
        let url = "http://127.0.0.1:\(port)"
        for db in [a, b] { #expect(await Runner.run(["sync-setup", "--url", url, "--token", "tok", "--db", db]).code == 0) }
        _ = try seed(a)
        let first = await Runner.run(["sync", "--db", a])
        #expect(first.code == 0)
        #expect((try json(first.out)["pushed"] as? Int ?? 0) >= 1)
        let second = await Runner.run(["sync", "--db", b])
        #expect(second.code == 0)
        let routines = await Runner.run(["routine", "list", "--db", b])
        #expect(routines.out.contains("Back"))
        #expect(try hubForge.routine(id: "r1")?.title == "Back")
        // an edit through the CLI on b (as Claude) reaches a
        #expect(await Runner.run(["routine", "remove-exercise", "acme", "--db", b]).code == 0)
        #expect(await Runner.run(["sync", "--db", b]).code == 0)
        #expect(await Runner.run(["sync", "--db", a]).code == 0)
        #expect(try Forge.open(path: a, device: "x").routine(id: "r1")?.exercises.isEmpty == true)
    }

    @Test func syncNeedsSetupFirst() async throws {
        let r = await Runner.run(["sync", "--db", tempDB()])
        #expect(r.code == 1 && r.err.contains("sync-setup"))
    }

    @Test func aWrongTokenIsAClearError() async throws {
        let (server, _, port) = try hub()
        defer { server.stop() }
        let db = tempDB()
        _ = await Runner.run(["sync-setup", "--url", "http://127.0.0.1:\(port)", "--token", "wrong", "--db", db])
        _ = try seed(db)
        let r = await Runner.run(["sync", "--db", db])
        #expect(r.code == 1 && r.err.contains("401"))
    }

    @Test func setupFileIsPrivate() async throws {
        let db = tempDB()
        _ = await Runner.run(["sync-setup", "--url", "http://127.0.0.1:1", "--token", "tok", "--db", db])
        let file = SyncConfig.file(besideDatabaseAt: db).path
        let mode = try FileManager.default.attributesOfItem(atPath: file)[.posixPermissions] as? Int
        #expect(mode == 0o600)
    }

    @Test func exportPrintsEverythingOrWritesAFile() async throws {
        let path = tempDB()
        _ = try seed(path)
        let printed = await Runner.run(["export", "--db", path])
        #expect(printed.code == 0)
        let object = try json(printed.out)
        #expect((object["routines"] as? [Any])?.count == 1 && (object["workouts"] as? [Any])?.count == 1 && (object["exercises"] as? [Any])?.count == 2)
        let file = NSTemporaryDirectory() + "forge-export-\(UUID().uuidString).json"
        let wrote = await Runner.run(["export", "--out", file, "--db", path])
        #expect(wrote.code == 0 && wrote.out.contains("bytes"))
        let data = try Data(contentsOf: URL(fileURLWithPath: file))
        #expect(try JSONSerialization.jsonObject(with: data) is [String: Any])
    }
}
