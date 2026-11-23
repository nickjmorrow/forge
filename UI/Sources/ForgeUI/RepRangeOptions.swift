import ForgeCore
import Foundation

/// The rep ranges offered for an exercise that should progress; nil is "repeat last time".
public enum RepRangeOptions {
    public static let choices: [ClosedRange<Int>?] = [nil, 3...5, 5...8, 6...10, 8...12, 10...15, 12...20]

    public static func label(for range: ClosedRange<Int>?) -> String {
        range.map { "\($0.lowerBound)–\($0.upperBound) reps" } ?? "Repeat last time"
    }
}

extension ExerciseBlock {
    /// The rep range as one value a picker can hold.
    var progression: ClosedRange<Int>? {
        get { repRange }
        set { repsMin = newValue?.lowerBound; repsMax = newValue?.upperBound }
    }
}
