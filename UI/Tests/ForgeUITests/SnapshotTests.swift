import ForgeCore
import Foundation
import SwiftUI
import Testing
@testable import ForgeUI

/// Renders screens to PNG files in $FORGE_SNAPSHOT_DIR (when set) so layouts can be looked at without a window server session.
@MainActor @Suite struct SnapshotTests {
    @Test func dashboardRendersToAnImage() throws {
        let forge = try Forge.inMemory()
        let now = ISO8601DateFormatter().date(from: "2026-10-21T15:00:00Z")!
        var ops: [Op] = [.putExercise(Exercise(id: "bench", name: "Bench Press (Barbell)", primaryMuscle: "chest")),
                         .putExercise(Exercise(id: "row", name: "Seated Cable Row", primaryMuscle: "upper_back")),
                         .putExercise(Exercise(id: "squat", name: "Squat (Barbell)", primaryMuscle: "quadriceps"))]
        for week in 0..<14 {
            for (k, ex) in ["bench", "squat", "row"].enumerated() where (week + k) % 5 != 4 {
                let day = now.addingTimeInterval(-Double(week * 7 + (2 - k) * 2) * 86_400)
                let sets = (0..<(3 + (week % 2))).map { _ in SetEntry(weightKg: 60 + Double(14 - week) * 2, reps: 6, completed: true) }
                ops.append(.putWorkout(Workout(title: ex, startedAt: Int64(day.timeIntervalSince1970 * 1000), endedAt: nil,
                                               exercises: [ExerciseBlock(exerciseID: ex, sets: sets)])))
            }
        }
        try forge.perform(ops, author: .me)
        let model = AppModel(forge: forge, draftStore: nil, defaults: UserDefaults(suiteName: "snap-\(UUID().uuidString)")!)
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        let view = DashboardContent(records: try DashboardStats.recentRecords(forge: forge, now: now, days: 30), now: now, calendar: calendar)
            .padding(20)
            .environment(model)
            .frame(width: 900, height: 900)
            .environment(\.colorScheme, .dark)     // ImageRenderer doesn't carry the window's preferred scheme
            .forgeTheme()
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        #expect(image.width == 900)
        if let dir = ProcessInfo.processInfo.environment["FORGE_SNAPSHOT_DIR"] {
            let rep = NSBitmapImageRep(cgImage: image)
            try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: dir).appendingPathComponent("dashboard.png"))
        }
    }
}
