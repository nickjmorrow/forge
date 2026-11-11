import Foundation

/// Every change to a Forge database is one of these. They are logged, replayed by sync and inverted by undo.
public indirect enum Op: Codable, Sendable, Equatable {
    case putExercise(Exercise)
    case deleteExercise(id: String)
    /// Re-points every routine and workout block from `from` to `into`, then deletes `from`.
    case mergeExercises(from: String, into: String)
    case putRoutine(Routine)
    case deleteRoutine(id: String)
    case putWorkout(Workout)
    case deleteWorkout(id: String)
    case putBodyweight(date: String, kg: Double)
    case deleteBodyweight(date: String)
    case putRecovery(Recovery)
    case deleteRecovery(date: String, source: String)
    case batch([Op])

    var kind: String { Mirror(reflecting: self).children.first?.label ?? "\(self)" }

    /// A short description in plain English, for the changes list.
    var summary: String {
        switch self {
        case let .putExercise(e): return "Saved exercise “\(e.name)”"
        case .deleteExercise: return "Deleted an exercise"
        case .mergeExercises: return "Merged two exercises"
        case let .putRoutine(r): return "Saved routine “\(r.title)”"
        case .deleteRoutine: return "Deleted a routine"
        case let .putWorkout(w): return "Saved workout “\(w.title)”"
        case .deleteWorkout: return "Deleted a workout"
        case let .putBodyweight(date, kg): return "Bodyweight \(kg.formatted(.number.precision(.fractionLength(0...1)))) kg on \(date)"
        case let .deleteBodyweight(date): return "Removed bodyweight for \(date)"
        case let .putRecovery(r): return "Sleep and recovery for \(r.date) (\(r.source))"
        case let .deleteRecovery(date, source): return "Removed recovery for \(date) (\(source))"
        case let .batch(ops):
            let kinds = Set(ops.map(\.kind))
            if ops.count > 1, kinds.count == 1, let noun = ops[0].plural {
                return "\(ops[0].verb) \(ops.count) \(noun)"
            }
            return ops.prefix(4).map(\.summary).joined(separator: "; ") + (ops.count > 4 ? "; and \(ops.count - 4) more" : "")
        }
    }

    private var verb: String {
        switch self {
        case .putExercise, .putRoutine, .putWorkout, .putBodyweight, .putRecovery: return "Saved"
        case .deleteExercise, .deleteRoutine, .deleteWorkout, .deleteBodyweight, .deleteRecovery: return "Deleted"
        default: return "Changed"
        }
    }

    private var plural: String? {
        switch self {
        case .putExercise, .deleteExercise: return "exercises"
        case .putRoutine, .deleteRoutine: return "routines"
        case .putWorkout, .deleteWorkout: return "workouts"
        case .putBodyweight, .deleteBodyweight: return "bodyweight entries"
        case .putRecovery, .deleteRecovery: return "recovery rows"
        default: return nil
        }
    }

    /// Entities this op writes, as "kind:id" keys; used to detect later edits that block an undo.
    var entityKeys: Set<String> {
        switch self {
        case let .putExercise(e): return ["exercise:\(e.id)"]
        case let .deleteExercise(id): return ["exercise:\(id)"]
        case let .mergeExercises(from, into): return ["exercise:\(from)", "exercise:\(into)"]
        case let .putRoutine(r): return ["routine:\(r.id)"]
        case let .deleteRoutine(id): return ["routine:\(id)"]
        case let .putWorkout(w): return ["workout:\(w.id)"]
        case let .deleteWorkout(id): return ["workout:\(id)"]
        case let .putBodyweight(date, _): return ["bodyweight:\(date)"]
        case let .deleteBodyweight(date): return ["bodyweight:\(date)"]
        case let .putRecovery(r): return ["recovery:\(r.date)|\(r.source)"]
        case let .deleteRecovery(date, source): return ["recovery:\(date)|\(source)"]
        case let .batch(ops): return ops.reduce(into: Set<String>()) { $0.formUnion($1.entityKeys) }
        }
    }
}

public enum ForgeError: Error, Equatable {
    case notFound(String)
    case exerciseHasHistory(String, workouts: Int, routines: Int)
    case invalid(String)
}

extension ForgeError {
    /// A sentence an agent or person can act on.
    public var message: String {
        switch self {
        case let .notFound(what): return "not found: \(what)"
        case let .exerciseHasHistory(id, workouts, routines):
            return "exercise \(id) is used in \(workouts) workouts and \(routines) routines (history). Pass --merge-into <exercise id> to move its history, or --force to remove it everywhere."
        case let .invalid(why): return why
        }
    }
}
