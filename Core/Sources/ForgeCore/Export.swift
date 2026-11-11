import Foundation
import GRDB

public struct BodyweightEntry: Codable, Sendable, Equatable {
    public var date: String
    public var kg: Double
    public init(date: String, kg: Double) { self.date = date; self.kg = kg }
}

/// Everything in the database as plain data: a backup you can read, and a way to leave.
public struct ForgeExport: Codable, Sendable {
    public var version = 1
    public var exportedAt: String
    public var exercises: [Exercise]
    public var routines: [Routine]
    public var workouts: [Workout]
    public var bodyweight: [BodyweightEntry]
    public var recovery: [Recovery]
}

extension Forge {
    /// Bodyweight entries, newest first (kilograms).
    public func bodyweights() throws -> [BodyweightEntry] {
        try db.read { db in
            try Row.fetchAll(db, sql: "SELECT date, kg FROM bodyweight ORDER BY date DESC").map { BodyweightEntry(date: $0["date"], kg: $0["kg"]) }
        }
    }

    public func deleteBodyweight(date: String, author: Author) throws {
        try perform([.deleteBodyweight(date: date)], author: author)
    }

    /// Pretty-printed JSON of every exercise, routine, workout, bodyweight entry and recovery row.
    public func exportAll() throws -> Data {
        let export = ForgeExport(exportedAt: ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: Double(clock()) / 1000)),
                                 exercises: try exercises(), routines: try routines(), workouts: try workouts(limit: Int.max),
                                 bodyweight: try bodyweights(), recovery: try recoveries())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(export)
    }
}
