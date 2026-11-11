import ForgeCore
import Foundation
import Observation
import os

/// Everything the screens show, plus the actions that change it. Reloads from the database after each action
/// and when another process (the `forge` CLI) changes the file.
@MainActor @Observable
public final class AppModel {
    public let forge: Forge
    public private(set) var exercises: [Exercise] = []
    public private(set) var routines: [Routine] = []
    public private(set) var workouts: [Workout] = []
    public private(set) var bodyweights: [BodyweightEntry] = []
    public private(set) var session: WorkoutSession?
    public var lastSummary: FinishSummary?
    public var lastError: String?
    public private(set) var healthEnabled: Bool
    public private(set) var syncStatus = "Not set up"
    public private(set) var syncing = false
    public var unit: WeightUnit { didSet { defaults.set(unit.rawValue, forKey: "weightUnit") } }
    /// Rest between sets when an exercise has no rest time of its own.
    public var defaultRestSeconds: Int { didSet { defaults.set(defaultRestSeconds, forKey: "defaultRestSeconds") } }

    @ObservationIgnored private let draftStore: DraftStore?
    @ObservationIgnored private let restAlerts: RestAlerting?
    @ObservationIgnored private let health: HealthService?
    @ObservationIgnored private var healthExport: Task<Void, Never>?
    @ObservationIgnored private var syncTransport: SyncTransport?
    @ObservationIgnored private let databasePath: String?
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    @ObservationIgnored private var autoSync: Task<Void, Never>?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var watcher: Task<Void, Never>?
    @ObservationIgnored private var nameByID: [String: String] = [:]
    @ObservationIgnored private var exerciseByID: [String: Exercise] = [:]

    public init(forge: Forge, draftStore: DraftStore?, defaults: UserDefaults = .standard, restAlerts: RestAlerting? = nil,
                health: HealthService? = nil, databasePath: String? = nil, syncTransport: SyncTransport? = nil) {
        self.databasePath = databasePath
        self.syncTransport = syncTransport ?? databasePath.flatMap { SyncConfig.load(besideDatabaseAt: $0)?.transport() }
        self.restAlerts = restAlerts
        self.health = health
        self.healthEnabled = health != nil && defaults.bool(forKey: "healthEnabled")
        self.forge = forge
        self.draftStore = draftStore
        self.defaults = defaults
        self.unit = WeightUnit(rawValue: defaults.string(forKey: "weightUnit") ?? "") ?? .lb
        let savedRest = defaults.integer(forKey: "defaultRestSeconds")
        self.defaultRestSeconds = savedRest > 0 ? savedRest : 90
        if let draftStore { session = WorkoutSession.restore(forge: forge, store: draftStore, defaultRestSeconds: defaultRestSeconds, restAlerts: restAlerts) }
        if self.syncTransport != nil { syncStatus = "Ready" }
        reload()
    }

    /// The default database and draft locations (the Mac app shares the file with the `forge` CLI).
    public static func openDefault(restAlerts: RestAlerting? = nil, health: HealthService? = nil) throws -> AppModel {
        let dir = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Forge", isDirectory: true)
        let path = ProcessInfo.processInfo.environment["FORGE_DB"] ?? dir.appendingPathComponent("forge.sqlite").path
        return try open(path: path, restAlerts: restAlerts, health: health)
    }

    /// Opens (or creates) the database at `path`. A new database is given its own device name, which sync relies on being unique
    /// to each install; an existing one keeps the name it was created with.
    public static func open(path: String, restAlerts: RestAlerting? = nil, health: HealthService? = nil) throws -> AppModel {
        let forge = try Forge.open(path: path, device: "app-" + UUID().uuidString.prefix(8).lowercased())
        let draft = URL(fileURLWithPath: (path as NSString).deletingLastPathComponent).appendingPathComponent("draft.json")
        return AppModel(forge: forge, draftStore: FileDraftStore(url: draft), restAlerts: restAlerts, health: health, databasePath: path)
    }

    public func reload() {
        do {
            exercises = try forge.exercises()
            routines = try forge.routines()
            workouts = try forge.workouts(limit: 1000)
            bodyweights = try forge.bodyweights()
            nameByID = Dictionary(exercises.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
            exerciseByID = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        } catch {
            lastError = "\(error)"
        }
    }

    /// The exercise with this id (a dictionary lookup, cheap enough to call from every row).
    public func exercise(for id: String) -> Exercise? { exerciseByID[id] }

    public func name(for exerciseID: String) -> String { nameByID[exerciseID] ?? "Deleted exercise" }

    private func act(_ body: () throws -> Void) {
        do { try body() } catch { lastError = (error as? ForgeError)?.message ?? "\(error)" }
        reload()
    }

    // MARK: workout

    public func startWorkout(routine: Routine?) {
        guard session == nil else { return }
        // Starting writes only the draft, not the database, so there is nothing to reload: the tap stays instant.
        do { session = try WorkoutSession.start(routine: routine, forge: forge, store: draftStore, defaultRestSeconds: defaultRestSeconds, restAlerts: restAlerts) }
        catch { lastError = (error as? ForgeError)?.message ?? "\(error)" }
    }

    @discardableResult
    public func finishWorkout() throws -> FinishSummary {
        guard let session else { throw WorkoutSessionError.nothingToSave }
        let summary = try session.finish()
        self.session = nil
        lastSummary = summary
        reload()
        if syncConfigured { syncTask = Task { [weak self] in await self?.syncNow() } }
        if healthEnabled, let health, let saved = try? forge.workout(id: summary.workoutID) {
            healthExport = Task { [weak self] in
                do { try await health.exportWorkout(saved) } catch { self?.lastError = "Apple Health: \((error as? ForgeError)?.message ?? "\(error)")" }
            }
        }
        return summary
    }

    public func discardWorkout() {
        session?.discard()
        session = nil
    }

    /// Make sure an in-progress workout is safely on disk (the app is going to the background).
    public func flushWorkoutDraft() { session?.flushDraft() }

    public func deleteWorkout(id: String) { act { try forge.perform([.deleteWorkout(id: id)], author: .me) } }
    public func saveWorkout(_ w: Workout) { act { try forge.perform([.putWorkout(w)], author: .me) } }

    /// Moves a saved workout's end time, for one left running after the last set. Clamped so it never ends before it starts.
    public func setWorkoutEnd(id: String, to end: Date) {
        guard var w = workouts.first(where: { $0.id == id }) else { return }
        w.endedAt = max(w.startedAt, Int64(end.timeIntervalSince1970 * 1000))
        saveWorkout(w)
    }

    // MARK: library and routines

    /// A copy at the end of the list, named "<title> copy".
    public func duplicateRoutine(id: String) {
        guard let r = routines.first(where: { $0.id == id }) else { return }
        saveRoutine(Routine(title: r.title + " copy", folder: r.folder, position: routines.count, exercises: r.exercises))
    }

    /// A new routine from what a workout contained: its exercises, rest times and the sets' weights and reps as the plan.
    @discardableResult
    public func saveWorkoutAsRoutine(id: String) -> Routine? {
        guard let w = workouts.first(where: { $0.id == id }) else { return nil }
        var blocks = w.exercises
        for i in blocks.indices { for j in blocks[i].sets.indices { blocks[i].sets[j].completed = false } }
        let routine = Routine(title: w.title, position: routines.count, exercises: blocks)
        saveRoutine(routine)
        return routine
    }

    // MARK: body, changes and export

    private static let dayFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// Records bodyweight for a day; `value` is in the display unit.
    public func addBodyweight(on date: Date, value: Double) {
        let day = Self.dayFormat.string(from: date)
        act { try forge.setBodyweight(date: day, pounds: unit == .lb ? value : nil, kg: unit == .kg ? value : nil, author: .me) }
    }

    public func deleteBodyweight(date: String) { act { try forge.deleteBodyweight(date: date, author: .me) } }

    /// The change log, newest first: what was changed, by whom (you, Claude or an import), and whether it was undone.
    public func recentChanges(days: Int = 14) -> [Change] {
        let since = Forge.nowMillis() - Int64(days) * 86_400_000
        return ((try? forge.changes(since: since)) ?? []).reversed()
    }

    /// Undoes Claude's most recent change. A change you edited afterwards is skipped rather than overwritten.
    @discardableResult
    public func undoClaudeLastChange() -> UndoResult {
        var result = UndoResult(undone: 0, skipped: [])
        act { result = try forge.undo(author: .claude) }
        return result
    }

    public func exportData() throws -> Data { try forge.exportAll() }

    @discardableResult
    public func addExercise(name: String, equipment: String?, primaryMuscle: String?, tracking: TrackingType = .weightReps) -> Exercise {
        let e = Exercise(name: name, equipment: equipment, primaryMuscle: primaryMuscle, tracking: tracking)
        act { try forge.perform([.putExercise(e)], author: .me) }
        return e
    }

    public func saveExercise(_ e: Exercise) {
        var edited = e
        edited.updatedAt = Forge.nowMillis()
        act { try forge.perform([.putExercise(edited)], author: .me) }
    }

    public func deleteExercise(id: String, mergeInto: String?, force: Bool) throws {
        try forge.deleteExercise(id: id, mergeInto: mergeInto, force: force, author: .me)
        reload()
    }

    public func addStarterLibrary() {
        let existing = Set(exercises.map { $0.name.lowercased() })
        let ops: [Op] = StarterLibrary.exercises.filter { !existing.contains($0.name.lowercased()) }.map {
            .putExercise(Exercise(id: StableIDs.starterExercise($0.name), name: $0.name, equipment: $0.equipment, primaryMuscle: $0.primaryMuscle, secondaryMuscles: $0.secondary,
                                  tracking: $0.tracking, isCustom: false))
        }
        guard !ops.isEmpty else { return }
        act { try forge.perform(ops, author: .me) }
    }

    public func saveRoutine(_ r: Routine) {
        var edited = r
        edited.updatedAt = Forge.nowMillis()
        act { try forge.perform([.putRoutine(edited)], author: .me) }
    }

    public func deleteRoutine(id: String) { act { try forge.perform([.deleteRoutine(id: id)], author: .me) } }
    public func reorderRoutines(_ ids: [String]) { act { try forge.reorderRoutines(ids, author: .me) } }

    // MARK: Sync

    public var syncConfigured: Bool { syncTransport != nil }

    /// Sends this device's changes to the hub and applies everyone else's, then refreshes the screens.
    public func syncNow() async {
        guard let transport = syncTransport else { syncStatus = "Not set up: add your hub in Settings."; return }
        guard !syncing else { return }
        syncing = true
        syncStatus = "Syncing…"
        do {
            let report = try await SyncClient(forge: forge, transport: transport).sync()
            if report.applied > 0 { reload() }      // this runs every 30 seconds; a full reload on the main thread is a dropped frame or two
            let time = Date().formatted(date: .omitted, time: .shortened)
            var status = report.applied > 0 ? "Synced at \(time): \(report.applied) updates from other devices." : "Synced at \(time)."
            if report.failed > 0 { status += " \(report.failed) change(s) from other devices couldn't be applied (they may need a newer app)." }
            syncStatus = status
        } catch {
            syncStatus = "Sync failed: \((error as? ForgeError)?.message ?? "\(error)")"
        }
        syncing = false
    }

    func waitForSync() async { await syncTask?.value }

    public func saveSyncConfig(url: String, token: String, hostHeader: String? = nil) throws {
        guard let parsed = URL(string: url.trimmingCharacters(in: .whitespaces)), parsed.scheme != nil, parsed.host != nil else {
            throw ForgeError.invalid("The hub address should look like https://hub.your-tailnet.ts.net/forge")
        }
        guard let databasePath else { throw ForgeError.invalid("This database can't hold a sync setup") }
        let host = hostHeader?.trimmingCharacters(in: .whitespaces)
        let config = SyncConfig(url: parsed, token: token.trimmingCharacters(in: .whitespaces), hostHeader: (host?.isEmpty ?? true) ? nil : host)
        try config.save(besideDatabaseAt: databasePath)
        syncTransport = config.transport()
        syncStatus = "Ready"
    }

    public func clearSyncConfig() {
        if let databasePath { try? FileManager.default.removeItem(at: SyncConfig.file(besideDatabaseAt: databasePath)) }
        syncTransport = nil
        syncStatus = "Not set up"
    }

    /// Syncs now and then every `interval` seconds while the app is open.
    public func startAutoSync(interval: TimeInterval = 30) {
        autoSync?.cancel()
        autoSync = Task { [weak self] in
            while !Task.isCancelled {
                await self?.syncNow()
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    public func stopAutoSync() {
        autoSync?.cancel()
        autoSync = nil
    }

    // MARK: Apple Health

    public var healthAvailable: Bool { health != nil }

    /// Turns Apple Health on (asking permission and reading the last month of sleep and recovery) or off.
    public func setHealthEnabled(_ on: Bool) async {
        guard let health else { return }
        if on {
            Logger(subsystem: "com.nicholai.forge", category: "health").info("requesting Apple Health authorization")
            do { try await health.requestAuthorization() } catch {
                Logger(subsystem: "com.nicholai.forge", category: "health").error("authorization failed: \(String(describing: error))")
                lastError = "Apple Health: \((error as? ForgeError)?.message ?? "\(error)")"
                return
            }
        }
        Logger(subsystem: "com.nicholai.forge", category: "health").info("authorization finished, enabled = \(on)")
        healthEnabled = on
        defaults.set(on, forKey: "healthEnabled")
        if on { await syncHealth() }
    }

    /// Copies recent sleep, HRV and resting heart rate from Apple Health into the database.
    public func syncHealth() async {
        guard healthEnabled, let health else { return }
        do {
            let rows = try await health.recoveryRows(days: 30)
            try forge.putRecoveries(rows, author: .importer)
        } catch { lastError = "Apple Health: \((error as? ForgeError)?.message ?? "\(error)")" }
    }

    func waitForHealthExport() async { await healthExport?.value }

    /// Sleep and recovery for the morning a workout was done on.
    public func recovery(for workout: Workout, timeZone: TimeZone = .current) -> Recovery? {
        try? forge.recovery(forWorkoutStartedAt: workout.startedAt, timeZone: timeZone)
    }

    // MARK: Hevy

    public func importHevy(apiKey: String) async throws -> ImportReport {
        let client = HevyClient(apiKey: apiKey)
        let templates = try await client.fetchAllTemplates()
        let routines = try await client.fetchAllRoutines()
        let workouts = try await client.fetchAllWorkouts()
        let forge = self.forge
        let report = try await Task.detached {
            try HevyImporter(forge: forge).importAll(templates: templates, routines: routines, workouts: workouts)
        }.value
        reload()
        return report
    }

    // MARK: watching the file

    public func startWatching(interval: TimeInterval = 1) {
        watcher?.cancel()
        var last = (try? forge.dataVersion()) ?? 0
        watcher = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard let self else { return }
                let version = (try? self.forge.dataVersion()) ?? last
                if version != last {
                    last = version
                    self.reload()
                }
            }
        }
    }

    public func stopWatching() {
        watcher?.cancel()
        watcher = nil
    }
}
