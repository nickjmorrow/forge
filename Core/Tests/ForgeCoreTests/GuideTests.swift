import Foundation
import Testing
@testable import ForgeCore

private func sample(_ id: String = "g1", _ title: String = "Warm-up", position: Int = 0) -> Guide {
    Guide(id: id, title: title, notes: "5 reps each way", position: position, sections: [
        GuideSection(title: "Arms", steps: [GuideStep(name: "Wrist circles"), GuideStep(name: "Elbow circles", cue: "Slow and wide")]),
        GuideSection(title: "Legs", steps: [GuideStep(name: "Ankle circles", cue: "Say \"hi\"\nline two 🙂 https://example.com/x?t=1")]),
    ], createdAt: 1, updatedAt: 1)
}

@Suite struct GuideTests {
    @Test func putThenReadRoundTrips() throws {
        let f = try Forge.inMemory()
        try f.perform([.putGuide(sample())], author: .me)
        #expect(try f.guide(id: "g1") == sample())
        #expect(sample().stepCount == 3)
    }

    @Test func emptyGuideAndEmptySectionAreAllowed() throws {
        let f = try Forge.inMemory()
        let empty = Guide(id: "e", title: "Empty", createdAt: 1, updatedAt: 1)
        let hollow = Guide(id: "h", title: "Hollow", position: 1, sections: [GuideSection(title: "A")], createdAt: 1, updatedAt: 1)
        try f.perform([.putGuide(empty), .putGuide(hollow)], author: .me)
        #expect(try f.guides() == [empty, hollow])
        #expect(empty.stepCount == 0 && hollow.stepCount == 0)
    }

    @Test func undoRestoresPreviousAndDeleteIsUndoable() throws {
        let f = try Forge.inMemory()
        try f.perform([.putGuide(sample())], author: .me)
        var v2 = sample(); v2.title = "Changed"; v2.sections.removeLast()
        try f.perform([.putGuide(v2)], author: .claude)
        try f.undo(author: .claude)
        #expect(try f.guide(id: "g1") == sample())
        try f.perform([.deleteGuide(id: "g1")], author: .claude)
        #expect(try f.guide(id: "g1") == nil)
        try f.undo(author: .claude)
        #expect(try f.guide(id: "g1") == sample())
    }

    @Test func undoingTheFirstSaveRemovesTheGuide() throws {
        let f = try Forge.inMemory()
        try f.perform([.putGuide(sample())], author: .claude)
        try f.undo(author: .claude)
        #expect(try f.guides().isEmpty)
    }

    @Test func deleteMissingThrowsNotFound() throws {
        let f = try Forge.inMemory()
        #expect(throws: ForgeError.notFound("guide nope")) { try f.perform([.deleteGuide(id: "nope")], author: .me) }
    }

    @Test func guidesAreOrderedByPositionThenTitle() throws {
        let f = try Forge.inMemory()
        try f.perform([.putGuide(sample("a", "Zed", position: 1)), .putGuide(sample("b", "beta", position: 0)), .putGuide(sample("c", "Alpha", position: 1))], author: .me)
        #expect(try f.guides().map(\.id) == ["b", "c", "a"])
    }

    @Test func changeSummariesNameTheGuide() throws {
        #expect(Op.putGuide(sample()).summary == "Saved guide “Warm-up”")
        #expect(Op.deleteGuide(id: "g1").summary == "Deleted a guide")
        #expect(Op.batch([.putGuide(sample("a")), .putGuide(sample("b"))]).summary == "Saved 2 guides")
        #expect(Op.putGuide(sample()).entityKeys == ["guide:g1"])
    }

    @Test func exportIncludesGuides() throws {
        let f = try Forge.inMemory()
        try f.perform([.putGuide(sample())], author: .me)
        let export = try JSONDecoder().decode(ForgeExport.self, from: try f.exportAll())
        #expect(export.guides == [sample()])
    }

    @Test func anExportFromBeforeGuidesDecodesWithNone() throws {
        let old = #"{"version":1,"exportedAt":"2026-01-01T00:00:00Z","exercises":[],"routines":[],"workouts":[],"bodyweight":[],"recovery":[]}"#
        #expect(try JSONDecoder().decode(ForgeExport.self, from: Data(old.utf8)).guides.isEmpty)
    }
}
