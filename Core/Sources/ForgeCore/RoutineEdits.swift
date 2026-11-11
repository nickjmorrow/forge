import Foundation
import GRDB

/// What a bulk removal would change in one routine.
public struct RoutineChange: Codable, Sendable, Equatable {
    public let routineID: String
    public let routineTitle: String
    public let removedExercises: [String]
}

extension Forge {
    /// Rewrites every routine's position to match `ids`, which must be exactly the existing routine ids.
    /// Returns nil when the order already matches (nothing is logged).
    @discardableResult
    public func reorderRoutines(_ ids: [String], author: Author) throws -> Int64? {
        let existing = try routines()
        guard !existing.isEmpty else { throw ForgeError.invalid("there are no routines to reorder") }
        guard ids.count == existing.count, Set(ids) == Set(existing.map(\.id)) else {
            throw ForgeError.invalid("reorder needs exactly the \(existing.count) existing routine ids")
        }
        let byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        let now = Forge.nowMillis()
        let ops: [Op] = ids.enumerated().compactMap { i, id in
            var r = byID[id]!
            guard r.position != i else { return nil }
            r.position = i
            r.updatedAt = now
            return .putRoutine(r)
        }
        return ops.isEmpty ? nil : try perform(ops, author: author)
    }

    /// Ids of exercises whose name contains any of `needles` (case-insensitive).
    public func exerciseIDs(nameContaining needles: [String]) throws -> [String] {
        let lowered = needles.map { $0.lowercased() }.filter { !$0.isEmpty }
        return try exercises().filter { e in lowered.contains { e.name.lowercased().contains($0) } }.map(\.id)
    }

    /// Which routines would lose which exercises if everything matching `names` were removed. Changes nothing.
    public func previewRemoveExercises(matching names: [String]) throws -> [RoutineChange] {
        try previewRemoval(ofExerciseIDs: Set(try exerciseIDs(nameContaining: names)))
    }

    func previewRemoval(ofExerciseIDs ids: Set<String>) throws -> [RoutineChange] {
        let nameByID = Dictionary(uniqueKeysWithValues: try exercises().map { ($0.id, $0.name) })
        return try routines().compactMap { r in
            let removed = r.exercises.filter { ids.contains($0.exerciseID) }.map { nameByID[$0.exerciseID] ?? $0.exerciseID }
            return removed.isEmpty ? nil : RoutineChange(routineID: r.id, routineTitle: r.title, removedExercises: removed)
        }
    }

    /// Removes the exercises from every routine as one undoable change. Workout history is untouched.
    /// Returns nil when no routine contains any of them.
    @discardableResult
    public func removeExercisesFromRoutines(exerciseIDs: [String], author: Author) throws -> Int64? {
        let ids = Set(exerciseIDs)
        let now = Forge.nowMillis()
        let ops: [Op] = try routines().compactMap { r in
            guard r.exercises.contains(where: { ids.contains($0.exerciseID) }) else { return nil }
            var edited = r
            edited.exercises.removeAll { ids.contains($0.exerciseID) }
            edited.updatedAt = now
            return .putRoutine(edited)
        }
        return ops.isEmpty ? nil : try perform(ops, author: author)
    }
}
