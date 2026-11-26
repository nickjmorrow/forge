import ForgeCore
import Foundation
import Testing
@testable import ForgeUI

/// Sections A[a1, a2] and B[b1]; as rows: 0 A, 1 a1, 2 a2, 3 B, 4 b1.
private let guide = Guide(id: "g", title: "Warm-up", sections: [
    GuideSection(title: "A", steps: [GuideStep(name: "a1", cue: "first"), GuideStep(name: "a2")]),
    GuideSection(title: "B", steps: [GuideStep(name: "b1")]),
], createdAt: 1, updatedAt: 1)

private func shape(_ g: Guide) -> [String] { g.sections.map { $0.title + "[" + $0.steps.map(\.name).joined(separator: ",") + "]" } }

@Suite struct GuideEditsTests {
    @Test func rowsInterleaveHeadersAndSteps() {
        #expect(GuideEdits.rows(guide) == [.section(0), .step(section: 0, step: 0), .step(section: 0, step: 1), .section(1), .step(section: 1, step: 0)])
        #expect(GuideEdits.rows(Guide(title: "Empty")).isEmpty)
    }

    @Test func movingAStepWithinASection() {
        #expect(shape(GuideEdits.move(guide, from: 1, to: 3)) == ["A[a2,a1]", "B[b1]"])
        #expect(shape(GuideEdits.move(guide, from: 2, to: 1)) == ["A[a2,a1]", "B[b1]"])
    }

    @Test func movingAStepIntoAnotherSectionKeepsItsCue() {
        let moved = GuideEdits.move(guide, from: 1, to: 5)
        #expect(shape(moved) == ["A[a2]", "B[b1,a1]"])
        #expect(moved.sections[1].steps[1].cue == "first")
        #expect(shape(GuideEdits.move(guide, from: 4, to: 2)) == ["A[a1,b1,a2]", "B[]"])
    }

    @Test func movingAStepAboveEveryHeaderLandsAtTheTopOfTheFirstSection() {
        #expect(shape(GuideEdits.move(guide, from: 4, to: 0)) == ["A[b1,a1,a2]", "B[]"])
    }

    @Test func movingASectionCarriesItsSteps() {
        #expect(shape(GuideEdits.move(guide, from: 3, to: 0)) == ["B[b1]", "A[a1,a2]"])
        #expect(shape(GuideEdits.move(guide, from: 0, to: 5)) == ["B[b1]", "A[a1,a2]"])
    }

    @Test func aSectionDroppedAmongAnotherSectionsStepsLandsAfterThatSection() {
        #expect(shape(GuideEdits.move(guide, from: 0, to: 4)) == ["B[b1]", "A[a1,a2]"])
        #expect(shape(GuideEdits.move(guide, from: 3, to: 2)) == ["A[a1,a2]", "B[b1]"])
    }

    @Test(arguments: [(1, 1), (1, 2), (0, 0), (0, 1), (3, 3), (4, 5), (9, 0), (-1, 2), (1, 99)])
    func movingToTheSameSpotOrOutOfRangeChangesNothing(_ from: Int, _ to: Int) {
        #expect(GuideEdits.move(guide, from: from, to: to) == guide)
    }

    @Test func stepsLabelPluralizes() {
        #expect(GuideEdits.stepsLabel(0) == "0 steps")
        #expect(GuideEdits.stepsLabel(1) == "1 step")
        #expect(GuideEdits.stepsLabel(26) == "26 steps")
    }

    @Test func linksInACueBecomeTappable() {
        let text = GuideEdits.linked("Watch https://example.com/x?t=134 first")
        #expect(String(text.characters) == "Watch https://example.com/x?t=134 first")
        #expect(text.runs.compactMap(\.link).map(\.absoluteString) == ["https://example.com/x?t=134"])
        #expect(GuideEdits.linked("No link here, e.g. 5 reps").runs.compactMap(\.link).isEmpty)
    }

    @Test func aDraftCountsAsChangedOnlyWhenWhatWouldBeSavedDiffers() {
        var draft = guide
        #expect(GuideEdits.changed(draft, from: guide) == false)
        draft.title = " Warm-up "
        draft.sections[0].steps[1].cue = "  "
        #expect(GuideEdits.changed(draft, from: guide) == false)
        draft.sections[0].steps[1].cue = "new"
        #expect(GuideEdits.changed(draft, from: guide))
        draft = guide; draft.sections[0].steps.append(GuideStep(name: " ", cue: ""))
        #expect(GuideEdits.changed(draft, from: guide) == false)      // a step added and left empty is dropped on save
        draft.sections[0].steps[2].cue = "a cue with no name"
        #expect(GuideEdits.changed(draft, from: guide))
    }

    @Test func tidyingDropsStepsLeftCompletelyEmpty() {
        var draft = guide
        draft.sections[0].steps.insert(GuideStep(name: "  "), at: 1)
        draft.sections[1].steps.append(GuideStep(name: "", cue: " "))
        #expect(GuideEdits.tidied(draft) == guide)
    }

    @Test func aGuideCanBeSavedOnceItHasATitleAndEveryKeptStepHasAName() {
        var draft = Guide(title: " ", sections: [GuideSection()])
        #expect(GuideEdits.canSave(draft) == false)
        draft.title = "Warm-up"
        #expect(GuideEdits.canSave(draft))
        draft.sections[0].steps = [GuideStep(name: "")]
        #expect(GuideEdits.canSave(draft))                             // empty step: dropped, not an obstacle
        draft.sections[0].steps = [GuideStep(name: "", cue: "Slowly")]
        #expect(GuideEdits.canSave(draft) == false)
    }
}
