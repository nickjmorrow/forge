import ArgumentParser
import ForgeCore
import Foundation

struct ForgeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "forge",
        abstract: "Workout tracker data: exercises, routines, workouts, stats. Prints JSON.",
        subcommands: [ExerciseGroup.self, RoutineGroup.self, WorkoutGroup.self, StatsGroup.self, BodyweightGroup.self, RecoveryGroup.self,
                      SchemaCommand.self, ExportCommand.self, SyncSetup.self, SyncCommand.self, SyncServe.self, SQLCommand.self, UndoCommand.self, ChangesCommand.self, ImportHevy.self])
}

// MARK: exercises

struct ExerciseGroup: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "exercise", abstract: "The exercise library.",
                                                    subcommands: [List.self, Show.self, Put.self, Add.self, Delete.self])

    struct List: ParsableCommand {
        @OptionGroup var global: GlobalOptions
        @Option(help: "Keep exercises whose name, equipment or muscles contain this.") var match: String?
        func run() throws { try Output.json(try global.open().exercises(matching: match)) }
    }

    struct Show: ParsableCommand {
        @OptionGroup var global: GlobalOptions
        @Argument var id: String
        struct Usage: Codable { var workouts: Int; var routines: Int }
        struct Detail: Codable { var exercise: Exercise; var usage: Usage; var records: PersonalRecords }
        func run() throws {
            let forge = try global.open()
            guard let e = try forge.exercise(id: id) else { throw ForgeError.notFound("exercise \(id)") }
            let u = try forge.usage(ofExercise: id)
            try Output.json(Detail(exercise: e, usage: Usage(workouts: u.workouts, routines: u.routines), records: try forge.personalRecords(exerciseID: id)))
        }
    }

    struct Put: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Create an exercise, or update the given fields of one by id, from JSON: name, equipment, primaryMuscle, secondaryMuscles, tracking, isCustom, id.")
        @OptionGroup var global: GlobalOptions
        @Option(help: "The exercise as JSON.") var json: String
        func run() throws { try Output.json(try global.open().putExercise(try decodeJSON(ExerciseInput.self, json), author: global.author)) }
    }

    struct Add: ParsableCommand {
        @OptionGroup var global: GlobalOptions
        @Option var name: String
        @Option var equipment: String?
        @Option(help: "Primary muscle.") var muscle: String?
        @Option(help: "Secondary muscle; repeat for several.") var secondary: [String] = []
        @Option var tracking: TrackingType = .weightReps
        func run() throws {
            let forge = try global.open()
            let exercise = Exercise(name: name, equipment: equipment, primaryMuscle: muscle, secondaryMuscles: secondary, tracking: tracking)
            try forge.perform([.putExercise(exercise)], author: global.author)
            try Output.json(exercise)
        }
    }

    struct Delete: ParsableCommand {
        @OptionGroup var global: GlobalOptions
        @Argument var id: String
        @Option(name: .customLong("merge-into"), help: "Move this exercise's history to another exercise id.") var mergeInto: String?
        @Flag(help: "Delete even if it has history, removing it from every routine and workout.") var force = false
        func run() throws {
            let change = try global.open().deleteExercise(id: id, mergeInto: mergeInto, force: force, author: global.author)
            try Output.json(["changeId": change])
        }
    }
}

// MARK: routines

struct RoutineView: Codable {
    struct Block: Codable {
        var exerciseID: String
        var name: String
        var notes: String?
        var restSeconds: Int
        var supersetID: Int?
        var sets: [SetEntry]
    }
    var id: String
    var title: String
    var folder: String?
    var position: Int
    var exercises: [Block]

    init(_ r: Routine, names: [String: String]) {
        id = r.id; title = r.title; folder = r.folder; position = r.position
        exercises = r.exercises.map { Block(exerciseID: $0.exerciseID, name: names[$0.exerciseID] ?? $0.exerciseID, notes: $0.notes,
                                            restSeconds: $0.restSeconds, supersetID: $0.supersetID, sets: $0.sets) }
    }
}

struct RoutineGroup: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "routine", abstract: "Routines.",
                                                    subcommands: [List.self, Show.self, Put.self, Delete.self, Reorder.self, RemoveExercise.self])

    static func names(_ forge: Forge) throws -> [String: String] {
        Dictionary(try forge.exercises().map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
    }

    struct List: ParsableCommand {
        @OptionGroup var global: GlobalOptions
        func run() throws {
            let forge = try global.open()
            let names = try RoutineGroup.names(forge)
            try Output.json(try forge.routines().map { RoutineView($0, names: names) })
        }
    }

    struct Show: ParsableCommand {
        @OptionGroup var global: GlobalOptions
        @Argument var id: String
        func run() throws {
            let forge = try global.open()
            guard let routine = try forge.routine(id: id) else { throw ForgeError.notFound("routine \(id)") }
            try Output.json(RoutineView(routine, names: try RoutineGroup.names(forge)))
        }
    }

    struct Put: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Create a routine, or replace one by id, from JSON. Fields: title, folder, position, id, exercises: [{exercise (name) or exerciseID, notes, restSeconds, supersetID, sets: [{weightLb or weightKg, reps, type (normal|warmup|failure|drop), durationSeconds, distanceMeters, rpe}]}].")
        @OptionGroup var global: GlobalOptions
        @Option(help: "The routine as JSON.") var json: String
        func run() throws {
            let forge = try global.open()
            let r = try forge.putRoutine(try decodeJSON(RoutineInput.self, json), author: global.author)
            try Output.json(RoutineView(r, names: try RoutineGroup.names(forge)))
        }
    }

    struct Delete: ParsableCommand {
        @OptionGroup var global: GlobalOptions
        @Argument var id: String
        func run() throws { try Output.json(["changeId": try global.open().perform([.deleteRoutine(id: id)], author: global.author)]) }
    }

    struct Reorder: ParsableCommand {
        @OptionGroup var global: GlobalOptions
        @Argument(help: "Every routine id, in the new order.") var ids: [String]
        func run() throws { try Output.json(["changeId": try global.open().reorderRoutines(ids, author: global.author)]) }
    }

    struct RemoveExercise: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "remove-exercise",
            abstract: "Remove every exercise whose name contains any NAME from all routines (workout history is untouched).")
        @OptionGroup var global: GlobalOptions
        @Argument var names: [String]
        @Flag(help: "Show what would change without changing it.") var preview = false

        struct Outcome: Codable { var applied: Bool; var changeId: Int64?; var routines: [RoutineChange] }

        func run() throws {
            let forge = try global.open()
            let affected = try forge.previewRemoveExercises(matching: names)
            if preview { return try Output.json(Outcome(applied: false, changeId: nil, routines: affected)) }
            let ids = try forge.exerciseIDs(nameContaining: names)
            let change = try forge.removeExercisesFromRoutines(exerciseIDs: ids, author: global.author)
            try Output.json(Outcome(applied: change != nil, changeId: change, routines: affected))
        }
    }
}

// MARK: workouts and stats

struct WorkoutGroup: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "workout", abstract: "Past workouts.",
                                                    subcommands: [List.self, Show.self, Put.self, Delete.self])

    struct List: ParsableCommand {
        @OptionGroup var global: GlobalOptions
        @Option var limit = 20
        func run() throws {
            let forge = try global.open()
            let names = try RoutineGroup.names(forge)
            try Output.json(try forge.workouts(limit: limit).map { WorkoutView($0, names: names) })
        }
    }

    struct Show: ParsableCommand {
        @OptionGroup var global: GlobalOptions
        @Argument var id: String
        func run() throws {
            let forge = try global.open()
            guard let w = try forge.workout(id: id) else { throw ForgeError.notFound("workout \(id)") }
            try Output.json(WorkoutView(w, names: try RoutineGroup.names(forge)))
        }
    }

    struct Put: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Create a workout, or replace one by id, from JSON. Fields: title, startedAt (ISO-8601, required), endedAt, notes, routineID, id, exercises: [{exercise (name) or exerciseID, notes, restSeconds, sets: [{weightLb or weightKg, reps, type, durationSeconds, distanceMeters, rpe}]}]. Sets default to completed.")
        @OptionGroup var global: GlobalOptions
        @Option(help: "The workout as JSON.") var json: String
        func run() throws {
            let forge = try global.open()
            let w = try forge.putWorkout(try decodeJSON(WorkoutInput.self, json), author: global.author)
            try Output.json(WorkoutView(w, names: try RoutineGroup.names(forge)))
        }
    }

    struct Delete: ParsableCommand {
        @OptionGroup var global: GlobalOptions
        @Argument var id: String
        func run() throws { try Output.json(["changeId": try global.open().perform([.deleteWorkout(id: id)], author: global.author)]) }
    }
}

struct WorkoutView: Codable {
    var id: String
    var title: String
    var startedAt: String
    var endedAt: String?
    var notes: String?
    var routineID: String?
    var exercises: [RoutineView.Block]

    init(_ w: Workout, names: [String: String]) {
        func iso(_ ms: Int64) -> String { ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: Double(ms) / 1000)) }
        id = w.id; title = w.title; startedAt = iso(w.startedAt); endedAt = w.endedAt.map(iso); notes = w.notes; routineID = w.routineID
        exercises = w.exercises.map { RoutineView.Block(exerciseID: $0.exerciseID, name: names[$0.exerciseID] ?? $0.exerciseID, notes: $0.notes,
                                                        restSeconds: $0.restSeconds, supersetID: $0.supersetID, sets: $0.sets) }
    }
}

func decodeJSON<T: Decodable>(_ type: T.Type, _ text: String) throws -> T {
    do { return try JSONDecoder().decode(type, from: Data(text.utf8)) } catch {
        throw ForgeError.invalid("invalid JSON for \(T.self): \(error)")
    }
}

struct BodyweightGroup: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "bodyweight", abstract: "Bodyweight by day.", subcommands: [Set.self, List.self])

    struct Set: ParsableCommand {
        @OptionGroup var global: GlobalOptions
        @Argument(help: "Day, like 2026-10-20.") var date: String
        @Option var lb: Double?
        @Option var kg: Double?
        func run() throws {
            let forge = try global.open()
            try forge.setBodyweight(date: date, pounds: lb, kg: kg, author: global.author)
            try Output.json(try forge.query(sql: "select date, kg from bodyweight where date = '\(date)'"))
        }
    }

    struct List: ParsableCommand {
        @OptionGroup var global: GlobalOptions
        @Option var limit = 90
        func run() throws { try Output.json(try global.open().query(sql: "select date, kg from bodyweight order by date desc", limit: limit)) }
    }
}

struct SchemaCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "schema", abstract: "The database tables, for writing `forge sql` queries (weights are kg, times are milliseconds since epoch).")
    @OptionGroup var global: GlobalOptions
    func run() throws {
        try Output.json(try global.open().query(sql: "select name, sql from sqlite_master where type = 'table' and name not like 'sqlite_%' and name not like 'grdb_%' order by name"))
    }
}

struct StatsGroup: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "stats", abstract: "Progress numbers.",
                                                    subcommands: [PRs.self, History.self, WeeklySets.self])

    struct PRs: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "prs")
        @OptionGroup var global: GlobalOptions
        @Argument var exerciseID: String
        func run() throws { try Output.json(try global.open().personalRecords(exerciseID: exerciseID)) }
    }

    struct History: ParsableCommand {
        @OptionGroup var global: GlobalOptions
        @Argument var exerciseID: String
        @Option var limit = 20
        func run() throws { try Output.json(try global.open().exerciseHistory(exerciseID: exerciseID, limit: limit)) }
    }

    struct WeeklySets: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "weekly-sets")
        @OptionGroup var global: GlobalOptions
        @Option var weeks = 8
        func run() throws {
            let since = Forge.nowMillis() - Int64(weeks) * 7 * 24 * 3600 * 1000
            try Output.json(try global.open().weeklySets(since: since))
        }
    }
}

// MARK: sql, undo, changes, import

struct SQLCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "sql", abstract: "Run one read-only SELECT against the database.")
    @OptionGroup var global: GlobalOptions
    @Argument var statement: String
    @Option var limit = 500
    func run() throws { try Output.json(try global.open().query(sql: statement, limit: limit)) }
}

struct UndoCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "undo", abstract: "Undo the latest change by --author (default claude).")
    @OptionGroup var global: GlobalOptions
    func run() throws { try Output.json(try global.open().undo(author: global.author)) }
}

struct ChangesCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "changes", abstract: "The change log (milliseconds since epoch for --since).")
    @OptionGroup var global: GlobalOptions
    @Option var since: Int64 = 0
    @Option(name: .customLong("by"), help: "Only changes by this author: me, claude or importer.") var by: Author?
    func run() throws { try Output.json(try global.open().changes(since: since, author: by)) }
}

struct ImportHevy: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "import-hevy",
        abstract: "Import exercises, routines and workouts from Hevy (API key in $HEVY_API_KEY, or --from-dir with templates.json, routines.json, workouts.json).")
    @OptionGroup var global: GlobalOptions
    @Option(name: .customLong("from-dir")) var fromDir: String?

    func run() async throws {
        let forge = try global.open()
        let templates: [HevyTemplate], routines: [HevyRoutine], workouts: [HevyWorkout]
        if let fromDir {
            (templates, routines, workouts) = try HevyImporter.load(directory: URL(fileURLWithPath: fromDir))
        } else {
            guard let key = ProcessInfo.processInfo.environment["HEVY_API_KEY"], !key.isEmpty else {
                throw ForgeError.invalid("HEVY_API_KEY is not set (or pass --from-dir)")
            }
            let client = HevyClient(apiKey: key)
            templates = try await client.fetchAllTemplates()
            routines = try await client.fetchAllRoutines()
            workouts = try await client.fetchAllWorkouts()
        }
        let importer = HevyImporter(forge: forge)
        try Output.json(try importer.importAll(templates: templates, routines: routines, workouts: workouts))
    }
}


struct RecoveryGroup: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "recovery", abstract: "Sleep and recovery per morning (Apple Health, Eight Sleep).",
                                                    subcommands: [Put.self, List.self])

    struct Put: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Save recovery rows from JSON: an object or an array of {date (YYYY-MM-DD, the morning), source (apple_health, eight_sleep, …), sleepSeconds, sleepScore, hrvMs, restingHR}. Only the given fields change.")
        @OptionGroup var global: GlobalOptions
        @Option(help: "One row or an array of rows as JSON.") var json: String
        func run() throws {
            let rows: [Recovery]
            if let many = try? JSONDecoder().decode([Recovery].self, from: Data(json.utf8)) { rows = many } else { rows = [try decodeJSON(Recovery.self, json)] }
            let forge = try global.open()
            try forge.putRecoveries(rows, author: global.author)
            try Output.json(["saved": rows.count])
        }
    }

    struct List: ParsableCommand {
        @OptionGroup var global: GlobalOptions
        @Option(help: "First day, YYYY-MM-DD.") var from: String?
        @Option(help: "Last day, YYYY-MM-DD.") var to: String?
        func run() throws { try Output.json(try global.open().recoveries(from: from, to: to)) }
    }
}


struct ExportCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "export", abstract: "Everything as one JSON document (a backup you can read). Prints it, or writes it with --out.")
    @OptionGroup var global: GlobalOptions
    @Option(help: "Write to this file instead of printing.") var out: String?
    func run() throws {
        let data = try global.open().exportAll()
        if let out {
            try data.write(to: URL(fileURLWithPath: (out as NSString).expandingTildeInPath), options: .atomic)
            try Output.json(["wrote": out, "bytes": "\(data.count)"])
        } else {
            Output.current.text += String(decoding: data, as: UTF8.self) + "\n"
        }
    }
}
