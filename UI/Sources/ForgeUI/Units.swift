import Foundation

public enum WeightUnit: String, Codable, Sendable, CaseIterable {
    case lb, kg
}

/// Weights are stored in kilograms; people see and type pounds or kilograms.
public enum Units {
    static let poundsPerKg = 2.2046226218

    public static func pounds(fromKg kg: Double) -> Double { kg * poundsPerKg }
    public static func kg(fromPounds lb: Double) -> Double { lb / poundsPerKg }

    /// A weight in the display unit with no trailing zeros ("135", "62.5"); empty when there is no weight.
    public static func format(kg: Double?, unit: WeightUnit) -> String {
        guard let kg else { return "" }
        return unit == .lb ? trimmed(pounds(fromKg: kg), places: 1) : trimmed(kg)
    }

    public static func trimmed(_ value: Double, places: Int = 2) -> String {
        var s = String(format: "%.\(places)f", value)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    /// Kilograms for what was typed in the display unit; nil when empty or not a number.
    public static func parseKg(_ text: String, unit: WeightUnit) -> Double? {
        guard let value = Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) else { return nil }
        return unit == .lb ? kg(fromPounds: value) : value
    }

    /// "1:15", or "1:02:05" past an hour.
    public static func clock(seconds: Int) -> String {
        let s = max(0, seconds)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}

extension Units {
    /// Seconds from "90", "1:30" or "1:02:03"; nil when empty or malformed.
    public static func parseSeconds(_ text: String) -> Int? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, parts.count <= 3, !parts.contains(where: { $0 == nil }) else { return nil }
        return parts.reduce(0) { $0 * 60 + $1! }
    }

    static let metersPerMile = 1609.344

    /// Distance shown in miles with pounds, kilometres with kilograms.
    public static func distanceText(meters: Double?, unit: WeightUnit) -> String {
        guard let meters else { return "" }
        return trimmed(unit == .lb ? meters / metersPerMile : meters / 1000)
    }

    public static func parseMeters(_ text: String, unit: WeightUnit) -> Double? {
        guard let v = Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) else { return nil }
        return unit == .lb ? v * metersPerMile : v * 1000
    }
}
