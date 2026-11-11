import ForgeCore
import Foundation
import Observation

public enum WorkoutSessionError: Error, Equatable {
    case nothingToSave
}

public struct FinishSummary: Equatable {
    public var workoutID: String
    public var durationSeconds: Int
    public var volumeKg: Double
    public var setCount: Int
    /// Names of exercises where this workout beat an earlier best (heaviest weight or estimated 1-rep max).
    public var newRecords: [String]
    /// The routine as it is now that this workout's numbers were written into it; nil when nothing differed from the plan.
    /// Finishing only ever changes the weights and reps of sets that were done (and adds extra sets); it never removes an exercise or a set.
    public var routineUpdate: Routine?
}

/// A workout being logged. Every change is written to the draft store so a killed app resumes where it left off.
@MainActor @Observable
public final class WorkoutSession {
    public private(set) var workout: Workout
    /// What was done last time, by exercise id.
    public private(set) var previous: [String: [SetEntry]] = [:]
    public private(set) var rest = RestTimer()
    /// Bumps when rows are added, removed or reordered, so screens holding typed text can rebuild their fields.
    public private(set) var revision = 0
    /// Stable identities for each exercise and each of its sets (not saved), so screens can animate rows and keep their state.
    public private(set) var blockIDs: [UUID] = []
    public private(set) var setIDs: [[UUID]] = []

    @ObservationIgnored private let forge: Forge
    @ObservationIgnored private let saver: DraftSaver?
    @ObservationIgnored private let defaultRestSeconds: Int
    @ObservationIgnored private let restAlerts: RestAlerting?

    public init(forge: Forge, workout: Workout, store: DraftStore?, defaultRestSeconds: Int = 90, restAlerts: RestAlerting? = nil) {
        self.restAlerts = restAlerts
        self.forge = forge
        self.workout = workout
        self.blockIDs = workout.exercises.map { _ in UUID() }
        self.setIDs = workout.exercises.map { $0.sets.map { _ in UUID() } }
        self.saver = store.map { DraftSaver(store: $0) }
        self.defaultRestSeconds = defaultRestSeconds
        for block in workout.exercises { loadPrevious(block.exerciseID) }
    }

    public static func start(routine: Routine?, forge: Forge, store: DraftStore?, now: Date = Date(), defaultRestSeconds: Int = 90,
                             restAlerts: RestAlerting? = nil) throws -> WorkoutSession {
        var blocks = routine?.exercises ?? []
        for i in blocks.indices { for j in blocks[i].sets.indices { blocks[i].sets[j].completed = false } }
        let workout = Workout(title: routine?.title ?? defaultTitle(at: now), startedAt: Self.millis(now), routineID: routine?.id, exercises: blocks)
        let session = WorkoutSession(forge: forge, workout: workout, store: store, defaultRestSeconds: defaultRestSeconds, restAlerts: restAlerts)
        session.persist()
        return session
    }

    public static func restore(forge: Forge, store: DraftStore, defaultRestSeconds: Int = 90, restAlerts: RestAlerting? = nil) -> WorkoutSession? {
        store.load().map { WorkoutSession(forge: forge, workout: $0, store: store, defaultRestSeconds: defaultRestSeconds, restAlerts: restAlerts) }
    }

    /// "Morning Workout", "Afternoon Workout", "Evening Workout" or "Night Workout" for an empty start.
    public nonisolated static func defaultTitle(at date: Date) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12: return "Morning Workout"
        case 12..<17: return "Afternoon Workout"
        case 17..<21: return "Evening Workout"
        default: return "Night Workout"
        }
    }

    static func millis(_ d: Date) -> Int64 { Int64(d.timeIntervalSince1970 * 1000) }

    /// Saved promptly, off the main thread.
    private func persist() { saver?.saveNow(workout) }

    /// For typing: a burst of keystrokes becomes one write.
    private func persistTyping() { saver?.saveSoon(workout) }

    /// Waits until the draft on disk matches what is on screen. Call when the app is leaving the foreground.
    public func flushDraft() { saver?.flush() }

    private func loadPrevious(_ exerciseID: String) {
        previous[exerciseID] = try? forge.lastPerformance(exerciseID: exerciseID, before: workout.startedAt)
    }

    /// Where an exercise or set currently sits (they move when others are added, removed or reordered).
    public func blockIndex(_ id: UUID) -> Int? { blockIDs.firstIndex(of: id) }

    public func setIndex(block: UUID, set: UUID) -> Int? { blockIndex(block).flatMap { setIDs[$0].firstIndex(of: set) } }

    // MARK: editing

    public func addExercise(_ id: String) {
        workout.exercises.append(ExerciseBlock(exerciseID: id, restSeconds: defaultRestSeconds, sets: [SetEntry()]))
        blockIDs.append(UUID())
        setIDs.append([UUID()])
        loadPrevious(id)
        revision += 1
        persist()
    }

    public func removeExercise(at index: Int) {
        guard workout.exercises.indices.contains(index) else { return }
        workout.exercises.remove(at: index)
        blockIDs.remove(at: index)
        setIDs.remove(at: index)
        revision += 1
        persist()
    }

    public func moveExercise(from: Int, to: Int) {
        guard workout.exercises.indices.contains(from), workout.exercises.indices.contains(to) else { return }
        workout.exercises.insert(workout.exercises.remove(at: from), at: to)
        blockIDs.insert(blockIDs.remove(at: from), at: to)
        setIDs.insert(setIDs.remove(at: from), at: to)
        revision += 1
        persist()
    }

    /// Replaces the exercise but keeps the planned weights and reps; completion is cleared.
    public func swapExercise(at index: Int, with id: String) {
        guard workout.exercises.indices.contains(index) else { return }
        workout.exercises[index].exerciseID = id
        for j in workout.exercises[index].sets.indices { workout.exercises[index].sets[j].completed = false }
        loadPrevious(id)
        revision += 1
        persist()
    }

    public func addSet(toExercise index: Int) {
        guard workout.exercises.indices.contains(index) else { return }
        var set = workout.exercises[index].sets.last ?? SetEntry()
        set.completed = false
        if set.type == .warmup { set.type = .normal }
        workout.exercises[index].sets.append(set)
        setIDs[index].append(UUID())
        persist()
    }

    public func removeSet(exercise: Int, set: Int) {
        guard workout.exercises.indices.contains(exercise), workout.exercises[exercise].sets.indices.contains(set) else { return }
        workout.exercises[exercise].sets.remove(at: set)
        setIDs[exercise].remove(at: set)
        revision += 1
        persist()
    }

    public func update(exercise: Int, set: Int, _ edit: (inout SetEntry) -> Void) {
        guard workout.exercises.indices.contains(exercise), workout.exercises[exercise].sets.indices.contains(set) else { return }
        edit(&workout.exercises[exercise].sets[set])
        persistTyping()
    }

    public func setNotes(exercise: Int, _ notes: String?) {
        guard workout.exercises.indices.contains(exercise) else { return }
        workout.exercises[exercise].notes = (notes?.isEmpty ?? true) ? nil : notes
        persistTyping()
    }

    public func toggleComplete(exercise: Int, set: Int, now: Date = Date()) {
        guard workout.exercises.indices.contains(exercise), workout.exercises[exercise].sets.indices.contains(set) else { return }
        let becomesCompleted = !workout.exercises[exercise].sets[set].completed
        if becomesCompleted { fillFromPrevious(exercise: exercise, set: set) }
        workout.exercises[exercise].sets[set].completed = becomesCompleted
        if becomesCompleted {
            let seconds = workout.exercises[exercise].restSeconds
            if seconds >= 0 {                                   // -1 is "no rest timer for this exercise"
                rest.start(seconds: seconds > 0 ? seconds : defaultRestSeconds, now: now)
                restAlerts?.update(rest: rest)
            }
        }
        persist()
    }

    /// An untouched set takes the numbers from the same set last time (or the last set done then).
    private func fillFromPrevious(exercise: Int, set: Int) {
        let current = workout.exercises[exercise].sets[set]
        guard current.weightKg == nil, current.reps == nil, current.durationSeconds == nil, current.distanceMeters == nil,
              let before = previous[workout.exercises[exercise].exerciseID], !before.isEmpty else { return }
        let source = set < before.count ? before[set] : before[before.count - 1]
        workout.exercises[exercise].sets[set].weightKg = source.weightKg
        workout.exercises[exercise].sets[set].reps = source.reps
        workout.exercises[exercise].sets[set].durationSeconds = source.durationSeconds
        workout.exercises[exercise].sets[set].distanceMeters = source.distanceMeters
    }

    /// The rest after this exercise's sets: seconds, 0 for the app default, or `ExerciseBlock.restOff`.
    public func setRest(exercise: Int, seconds: Int) {
        guard workout.exercises.indices.contains(exercise) else { return }
        workout.exercises[exercise].restSeconds = seconds
        persist()
    }

    public func skipRest() {
        rest.skip()
        restAlerts?.update(rest: rest)
    }

    public func adjustRest(by seconds: Int, now: Date = Date()) {
        rest.adjust(by: seconds, now: now)
        restAlerts?.update(rest: rest)
    }

    // MARK: finishing

    /// True once any set has been ticked off. Until then, leaving the workout loses nothing.
    public var hasLoggedSets: Bool { workout.exercises.contains { $0.sets.contains(where: \.completed) } }

    /// Saves the workout, keeping only completed sets and exercises that have one.
    public func finish(now: Date = Date()) throws -> FinishSummary {
        var saved = workout
        let routineUpdate = try routineWithUsedValues(now: now)
        for i in saved.exercises.indices { saved.exercises[i].sets.removeAll { !$0.completed } }
        saved.exercises.removeAll { $0.sets.isEmpty }
        guard !saved.exercises.isEmpty else { throw WorkoutSessionError.nothingToSave }
        saved.endedAt = Self.millis(now)

        var records: [String] = []
        for block in saved.exercises {
            let prior = try forge.personalRecords(exerciseID: block.exerciseID)
            guard let priorHeaviest = prior.heaviestKg else { continue }
            let counted = block.sets.filter { $0.type != .warmup }.compactMap { s -> (Double, Double)? in
                guard let w = s.weightKg, let r = s.reps, r > 0 else { return nil }
                return (w, e1RM(weightKg: w, reps: r))
            }
            let beatsWeight = (counted.map(\.0).max() ?? 0) > priorHeaviest
            let beatsE1RM = (counted.map(\.1).max() ?? 0) > (prior.bestE1RMKg ?? 0)
            if beatsWeight || beatsE1RM, let name = try forge.exercise(id: block.exerciseID)?.name { records.append(name) }
        }

        // The workout and the routine's new numbers are one change, so one undo reverses both.
        try forge.perform([.putWorkout(saved)] + (routineUpdate.map { [Op.putRoutine($0)] } ?? []), author: .me)
        saver?.clear()
        skipRest()
        let sets = saved.exercises.flatMap(\.sets)
        let volume = sets.filter { $0.type != .warmup }.reduce(0.0) { $0 + ($1.weightKg ?? 0) * Double($1.reps ?? 0) }
        return FinishSummary(workoutID: saved.id, durationSeconds: Int((saved.endedAt! - saved.startedAt) / 1000), volumeKg: volume,
                             setCount: sets.count, newRecords: records, routineUpdate: routineUpdate)
    }

    public func discard() {
        saver?.clear()
        skipRest()
    }

    /// The routine with the completed sets' weights and reps written over the plan (sets not done keep theirs); nil when nothing differs.
    private func routineWithUsedValues(now: Date) throws -> Routine? {
        guard let id = workout.routineID, var routine = try forge.routine(id: id) else { return nil }
        var changed = false
        for i in routine.exercises.indices {
            guard let done = workout.exercises.first(where: { $0.exerciseID == routine.exercises[i].exerciseID }) else { continue }
            if done.restSeconds != routine.exercises[i].restSeconds {      // a rest time you changed becomes the plan too
                routine.exercises[i].restSeconds = done.restSeconds
                changed = true
            }
            for (j, set) in done.sets.enumerated() where set.completed {
                var planned = set
                planned.completed = false
                if j < routine.exercises[i].sets.count {
                    let old = routine.exercises[i].sets[j]
                    if old.weightKg != set.weightKg || old.reps != set.reps {
                        routine.exercises[i].sets[j] = planned
                        changed = true
                    }
                } else {
                    routine.exercises[i].sets.append(planned)
                    changed = true
                }
            }
        }
        guard changed else { return nil }
        routine.updatedAt = Self.millis(now)
        return routine
    }
}
