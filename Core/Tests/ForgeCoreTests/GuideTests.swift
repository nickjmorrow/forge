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

    // MARK: input and reorder

    private func input(_ json: String) throws -> GuideInput { try JSONDecoder().decode(GuideInput.self, from: Data(json.utf8)) }

    @Test func putGuideCreatesLastAndKeepsCreatedAtOnReplace() throws {
        let clock = TestClock(1000)
        let f = try Forge.inMemory(clock: { clock.now })
        try f.putGuide(try input(#"{"title":"First","sections":[]}"#), author: .claude)
        let second = try f.putGuide(try input(#"{"title":"Second","notes":"slow","sections":[{"title":"A","steps":[{"name":"One","cue":"c"}]}]}"#), author: .claude)
        #expect(second.position == 1 && second.createdAt == 1000 && second.notes == "slow")
        clock.tick()
        let replaced = try f.putGuide(try input(#"{"id":"\#(second.id)","title":"Second, renamed","sections":[{"steps":[{"name":"Two"}]}]}"#), author: .claude)
        #expect(replaced.createdAt == 1000 && replaced.updatedAt == 2000 && replaced.position == 1)
        #expect(replaced.notes == nil)
        #expect(replaced.sections == [GuideSection(title: "", steps: [GuideStep(name: "Two")])])
        #expect(try f.guides().map(\.title) == ["First", "Second, renamed"])
    }

    @Test func putGuideTrimsAndNilsBlanks() throws {
        let f = try Forge.inMemory()
        let g = try f.putGuide(try input(#"{"title":"  Warm-up ","notes":"","sections":[{"title":" Arms ","steps":[{"name":" Wrist circles ","cue":"  "}]}]}"#), author: .me)
        #expect(g.title == "Warm-up" && g.notes == nil)
        #expect(g.sections == [GuideSection(title: "Arms", steps: [GuideStep(name: "Wrist circles", cue: nil)])])
    }

    @Test(arguments: [#"{"title":"   ","sections":[]}"#, #"{"title":"Ok","sections":[{"title":"A","steps":[{"name":" \n"}]}]}"#])
    func putGuideRejectsBlankTitleAndBlankStepName(_ json: String) throws {
        let f = try Forge.inMemory()
        #expect(throws: ForgeError.self) { try f.putGuide(try input(json), author: .me) }
        #expect(try f.guides().isEmpty)
    }

    @Test func aRawPutWithABlankTitleIsStoredAsGiven() throws {
        // Validation belongs to the input path; ops replayed by sync and undo must never be refused.
        let f = try Forge.inMemory()
        try f.perform([.putGuide(Guide(id: "g", title: "", createdAt: 1, updatedAt: 1))], author: .me)
        #expect(try f.guide(id: "g")?.title == "")
    }

    private func three() throws -> Forge {
        let f = try Forge.inMemory()
        try f.perform([.putGuide(sample("g1", "One", position: 0)), .putGuide(sample("g2", "Two", position: 1)), .putGuide(sample("g3", "Three", position: 2))], author: .me)
        return f
    }

    @Test func reorderGuidesRewritesPositions() throws {
        let f = try three()
        try f.reorderGuides(["g3", "g1", "g2"], author: .claude)
        #expect(try f.guides().map(\.id) == ["g3", "g1", "g2"])
        #expect(try f.guides().map(\.position) == [0, 1, 2])
    }

    @Test(arguments: [["g1"], ["g1", "g2", "g3", "gX"], ["g1", "g1", "g2"]])
    func reorderGuidesRejectsMissingExtraAndDuplicateIds(_ ids: [String]) throws {
        let f = try three()
        #expect(throws: ForgeError.self) { try f.reorderGuides(ids, author: .claude) }
        #expect(try f.guides().map(\.id) == ["g1", "g2", "g3"])
    }

    @Test func reorderGuidesWithNoGuidesIsRejected() throws {
        let f = try Forge.inMemory()
        #expect(throws: ForgeError.invalid("there are no guides to reorder")) { try f.reorderGuides([], author: .claude) }
    }
}
