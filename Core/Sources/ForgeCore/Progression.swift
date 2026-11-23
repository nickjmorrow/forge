import Foundation

/// What to aim for next on an exercise that progresses in a rep range ("double progression"): add a rep to every working
/// set until all of them reach the top of the range, then add weight and start again at the bottom.
public enum Progression {
    public enum Step: Equatable, Sendable {
        case addReps
        case addWeight
    }

    public struct Suggestion: Equatable, Sendable {
        /// One target per working set of last time, in order.
        public var sets: [SetEntry]
        public var step: Step
    }

    /// Only exercises where a heavier weight means harder work get suggestions.
    public static func applies(to tracking: TrackingType) -> Bool { tracking == .weightReps || tracking == .weightedBodyweight }

    /// The next targets after `previous` (the sets done last time). Warm-ups and sets without a weight and reps are ignored;
    /// nil when nothing is left to go on.
    public static func next(after previous: [SetEntry], range: ClosedRange<Int>, stepKg: Double) -> Suggestion? {
        let working = previous.filter { $0.type != .warmup && $0.weightKg != nil && ($0.reps ?? 0) > 0 }
        guard !working.isEmpty else { return nil }
        let addsWeight = working.allSatisfy { $0.reps! >= range.upperBound }
        let sets = working.map { done in
            SetEntry(type: done.type, weightKg: addsWeight ? done.weightKg! + stepKg : done.weightKg,
                     reps: addsWeight ? range.lowerBound : (done.reps! >= range.upperBound ? done.reps : done.reps! + 1))
        }
        return Suggestion(sets: sets, step: addsWeight ? .addWeight : .addReps)
    }

    /// `planned` with its working sets replaced by the suggestion (a plan with more sets repeats the last target).
    public static func apply(_ suggestion: Suggestion, to planned: [SetEntry]) -> [SetEntry] {
        var result = planned
        var k = 0
        for i in result.indices where result[i].type != .warmup {
            let target = suggestion.sets[min(k, suggestion.sets.count - 1)]
            result[i].weightKg = target.weightKg
            result[i].reps = target.reps
            k += 1
        }
        return result
    }

    /// An off day's weight: `fraction` of the usual, rounded to the nearest `stepKg`, never rounded away to nothing.
    public static func lighter(_ weightKg: Double, fraction: Double = 0.8, stepKg: Double) -> Double {
        guard weightKg > 0, stepKg > 0 else { return weightKg }
        return max(stepKg, (weightKg * fraction / stepKg).rounded() * stepKg)
    }
}
