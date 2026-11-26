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

    private var sampleGuide: Guide {
        Guide(id: "g", title: "Warm-up", notes: "5 to 10 reps in each direction", sections: [
            GuideSection(title: "Arms", steps: [GuideStep(name: "Wrist circles", figure: sampleFigure), GuideStep(name: "Elbow circles", cue: "Slow, as wide as is comfortable."),
                                                GuideStep(name: "Arm swings", cue: "Demo: https://example.com/swings")]),
            GuideSection(title: "", steps: [GuideStep(name: "Ankle circles")]),
            GuideSection(title: "Empty section", steps: []),
        ], createdAt: 1, updatedAt: 1)
    }

    private var sampleFigure: Figure {
        Figure(duration: 4, parts: [
            .init(kind: .ring, points: ["c", "r"], tone: .accent), .init(kind: .line, points: ["hip", "knee", "foot"]),
            .init(kind: .curve, points: ["hip", "mid", "sh"]), .init(kind: .head, points: ["hd"]), .init(kind: .line, points: ["sh", "hand"]),
            .init(kind: .dot, points: ["hand"], tone: .accent),
        ], frames: [
            .init(points: ["c": [70, 50], "r": [8, 12], "hip": [50, 50], "knee": [50, 70], "foot": [50, 90], "mid": [50, 38], "sh": [50, 26], "hd": [50, 14], "hand": [70, 38]]),
            .init(points: ["mid": [58, 50], "sh": [60, 66], "hd": [60, 78], "hand": [70, 62]], back: [4]),
        ])
    }

    @Test func aFigureRendersAtAFixedMoment() throws {
        try png(FigureView(figure: sampleFigure, phase: 0.5).frame(width: 200, height: 200), width: 200, height: 200, name: "figure.png")
    }

    @Test func partsBehindTheBodyArePaintedFirst() {
        let order = FigureDrawing.order(sampleFigure, pose: sampleFigure.pose(at: 0.5))
        #expect(order.map(\.isBack) == [true, false, false, false, false, false])
        #expect(order.first?.part.points == ["sh", "hand"])
        #expect(FigureDrawing.order(sampleFigure, pose: sampleFigure.pose(at: 0)).map(\.part) == sampleFigure.parts)
    }

    /// Set FORGE_FIGURES_JSON to a file of `{"name": figure}` to check a set of figures and (with FORGE_SNAPSHOT_DIR) draw them
    /// as sheets, four moments of each to a row.
    @Test func aLibraryOfFiguresValidatesAndRenders() throws {
        guard let path = ProcessInfo.processInfo.environment["FORGE_FIGURES_JSON"] else { return }
        let library = try JSONDecoder().decode([String: Figure].self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        let names = library.keys.sorted()
        for name in names { try library[name]!.validate() }
        let perSheet = 6
        for (sheet, start) in stride(from: 0, to: names.count, by: perSheet).enumerated() {
            let rows = Array(names[start..<min(start + perSheet, names.count)])
            let view = VStack(alignment: .leading, spacing: 6) {
                ForEach(rows, id: \.self) { name in
                    HStack(spacing: 6) {
                        Text(name).font(.caption).foregroundStyle(Theme.text).frame(width: 110, alignment: .leading)
                        ForEach(0..<4, id: \.self) { i in FigureView(figure: library[name]!, phase: Double(i) / 4).frame(width: 130, height: 130) }
                    }
                }
            }.padding(8).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(Theme.background)
            try png(view, width: 670, height: CGFloat(rows.count) * 136 + 16, name: "figures-\(sheet).png")
        }
    }

    private func png<V: View>(_ view: V, width: CGFloat, height: CGFloat, name: String) throws {
        let renderer = ImageRenderer(content: view.frame(width: width, height: height).environment(\.colorScheme, .dark).forgeTheme())
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        #expect(image.width == Int(width))
        if let dir = ProcessInfo.processInfo.environment["FORGE_SNAPSHOT_DIR"] {
            try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
        }
    }

    @Test func guideRendersToAnImage() throws {
        try png(GuideContent(guide: sampleGuide).padding(16), width: 390, height: 700, name: "guide.png")
    }

    @Test func anEmptyGuideRendersToAnImage() throws {
        try png(GuideContent(guide: Guide(title: "Empty")).padding(16), width: 390, height: 300, name: "guide-empty.png")
    }
}
