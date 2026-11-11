import Foundation
import GRDB

/// Sleep and recovery for the morning of `date` (yyyy-MM-dd), from one data source such as "apple_health" or "eight_sleep".
public struct Recovery: Codable, Sendable, Equatable {
    public var date: String
    public var source: String
    public var sleepSeconds: Int?
    public var sleepScore: Double?
    public var hrvMs: Double?
    public var restingHR: Double?

    public init(date: String, source: String, sleepSeconds: Int? = nil, sleepScore: Double? = nil, hrvMs: Double? = nil, restingHR: Double? = nil) {
        self.date = date; self.source = source; self.sleepSeconds = sleepSeconds
        self.sleepScore = sleepScore; self.hrvMs = hrvMs; self.restingHR = restingHR
    }
}

extension Forge {
    static func isDay(_ s: String) -> Bool {
        let parts = s.split(separator: "-")
        return parts.count == 3 && parts[0].count == 4 && parts[1].count == 2 && parts[2].count == 2 && parts.allSatisfy { Int($0) != nil }
    }

    /// Saves recovery rows, overlaying only the fields given onto what is already stored for that date and source.
    /// The whole list is one undoable change.
    public func putRecoveries(_ list: [Recovery], author: Author) throws {
        guard !list.isEmpty else { return }
        for r in list {
            guard Self.isDay(r.date) else { throw ForgeError.invalid("recovery date must look like 2026-10-20, got \"\(r.date)\"") }
            guard !r.source.isEmpty else { throw ForgeError.invalid("recovery needs a source, like apple_health or eight_sleep") }
        }
        let ops: [Op] = try db.read { db in
            try list.compactMap { r -> Op? in
                let existing = try Store.recovery(date: r.date, source: r.source, db)
                var merged = existing ?? Recovery(date: r.date, source: r.source)
                if let v = r.sleepSeconds { merged.sleepSeconds = v }
                if let v = r.sleepScore { merged.sleepScore = v }
                if let v = r.hrvMs { merged.hrvMs = v }
                if let v = r.restingHR { merged.restingHR = v }
                return merged == existing ? nil : .putRecovery(merged)
            }
        }
        guard !ops.isEmpty else { return }
        try perform(ops, author: author)
    }

    /// Recovery rows between two days (inclusive, yyyy-MM-dd), newest first.
    public func recoveries(from: String? = nil, to: String? = nil) throws -> [Recovery] {
        try db.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM recovery WHERE (? IS NULL OR date >= ?) AND (? IS NULL OR date <= ?) ORDER BY date DESC, source",
                             arguments: [from, from, to, to]).map(Store.decodeRecovery)
        }
    }

    /// The recovery row for the morning of the day a workout started, preferring Eight Sleep when both sources have one.
    public func recovery(forWorkoutStartedAt startedAt: Int64, timeZone: TimeZone = .current) throws -> Recovery? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let day = formatter.string(from: Date(timeIntervalSince1970: Double(startedAt) / 1000))
        return try recoveries(from: day, to: day).sorted { ($0.source == "eight_sleep" ? 0 : 1) < ($1.source == "eight_sleep" ? 0 : 1) }.first
    }
}
