import ForgeCore
import Foundation

/// One editable number in a set row.
public enum SetColumn: Hashable, Sendable {
    case weight, reps, duration, distance

    public func title(unit: WeightUnit, tracking: TrackingType) -> String {
        switch self {
        case .weight:
            let u = unit == .lb ? "LB" : "KG"
            return tracking == .assistedBodyweight ? "-" + u : tracking == .weightedBodyweight ? "+" + u : u
        case .reps: return "REPS"
        case .duration: return "TIME"
        case .distance: return unit == .lb ? "MI" : "KM"
        }
    }

    public func text(of set: SetEntry, unit: WeightUnit) -> String {
        switch self {
        case .weight: return Units.format(kg: set.weightKg, unit: unit)
        case .reps: return set.reps.map(String.init) ?? ""
        case .duration: return set.durationSeconds.map { Units.clock(seconds: $0) } ?? ""
        case .distance: return Units.distanceText(meters: set.distanceMeters, unit: unit)
        }
    }

    /// Writes what was typed into the set; empty or unreadable text clears the value.
    public func apply(_ text: String, to set: inout SetEntry, unit: WeightUnit) {
        switch self {
        case .weight: set.weightKg = Units.parseKg(text, unit: unit)
        case .reps: set.reps = Int(text.trimmingCharacters(in: .whitespaces))
        case .duration: set.durationSeconds = Units.parseSeconds(text)
        case .distance: set.distanceMeters = Units.parseMeters(text, unit: unit)
        }
    }
}

extension TrackingType {
    public var columns: [SetColumn] {
        switch self {
        case .weightReps, .weightedBodyweight, .assistedBodyweight: return [.weight, .reps]
        case .repsOnly: return [.reps]
        case .duration: return [.duration]
        case .weightDuration: return [.weight, .duration]
        case .distance: return [.distance]
        case .distanceDuration: return [.distance, .duration]
        }
    }
}

public enum SetFormat {
    /// "200 × 5", "130 × 0:42", "12 reps", "1:15", or "–" for an empty set.
    public static func describe(_ set: SetEntry, tracking: TrackingType, unit: WeightUnit) -> String {
        let parts = tracking.columns.map { $0.text(of: set, unit: unit) }.filter { !$0.isEmpty }
        guard !parts.isEmpty else { return "–" }
        if tracking.columns.first == .weight { return parts.count == 2 ? "\(parts[0]) × \(parts[1])" : parts[0] }
        if tracking == .repsOnly { return "\(parts[0]) reps" }
        return parts.joined(separator: " · ")
    }
}
