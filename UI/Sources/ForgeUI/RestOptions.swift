import ForgeCore
import Foundation

/// The rest times offered for an exercise: Off, the app default, or a fixed time.
public enum RestOptions {
    public static let choices: [Int] = [ExerciseBlock.restOff, 0, 30, 45, 60, 90, 120, 150, 180, 240, 300]

    public static func label(for seconds: Int, defaultSeconds: Int) -> String {
        switch seconds {
        case ExerciseBlock.restOff: return "Off"
        case 0: return "Default (\(Units.clock(seconds: defaultSeconds)))"
        default: return Units.clock(seconds: seconds)
        }
    }

    /// What to show on a chip: the time itself ("1:30"), or "Off".
    public static func shortLabel(for seconds: Int, defaultSeconds: Int) -> String {
        seconds == ExerciseBlock.restOff ? "Off" : Units.clock(seconds: seconds > 0 ? seconds : defaultSeconds)
    }
}
