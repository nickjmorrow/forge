import Foundation
import Testing
@testable import ForgeCore

/// A two-pose bend: a leg that stays put, a spine and head that move.
private func bend(easing: Figure.Easing = .ease) -> Figure {
    Figure(duration: 4, easing: easing, parts: [
        .init(kind: .line, points: ["hip", "foot"]),
        .init(kind: .curve, points: ["hip", "mid", "sh"]),
        .init(kind: .head, points: ["hd"]),
        .init(kind: .line, points: ["sh", "hand"], tone: .dim),
    ], frames: [
        .init(points: ["hip": [50, 50], "foot": [50, 90], "mid": [50, 38], "sh": [50, 26], "hd": [50, 14], "hand": [52, 50]]),
        .init(points: ["mid": [58, 50], "sh": [60, 66], "hd": [60, 78], "hand": [66, 86]], back: [3]),
    ])
}

@Suite struct FigureTests {
    @Test func poseAtAFrameIsThatFrameWithUnmovedPointsCarriedFromTheFirst() {
        let pose = bend().pose(at: 0.5)
        #expect(pose.points["sh"] == [60, 66])
        #expect(pose.points["foot"] == [50, 90])
        #expect(pose.back == [3])
        #expect(bend().pose(at: 0).points["sh"] == [50, 26])
        #expect(bend().pose(at: 0).back == [])
    }

    @Test func linearEasingIsHalfwayAtTheMidpointAndLoopsBackToTheFirstFrame() {
        let f = bend(easing: .linear)
        #expect(f.pose(at: 0.25).points["sh"] == [55, 46])
        #expect(f.pose(at: 0.75).points["sh"] == [55, 46])
        #expect(f.pose(at: 1).points["sh"] == [50, 26])
        #expect(f.pose(at: 1.25).points["sh"] == [55, 46])
    }

    @Test func easedMotionLingersNearEachPose() {
        let x = bend().pose(at: 0.05).points["sh"]![0]      // a tenth of the way to the next pose in time
        #expect(x > 50 && x < 51)
    }

    @Test func aSingleFrameIsAStillPicture() {
        var f = bend(); f.frames.removeLast()
        #expect(f.pose(at: 0.7).points["sh"] == [50, 26])
    }

    @Test func theStillPoseIsTheSecondFrame() {
        #expect(bend().stillPose.points["sh"] == [60, 66])
    }

    @Test func aSoundFigureValidates() throws {
        try bend().validate()
    }

    @Test(arguments: [
        { (f: inout Figure) in f.frames = [] },
        { (f: inout Figure) in f.duration = 0 },
        { (f: inout Figure) in f.duration = .infinity },
        { (f: inout Figure) in f.parts = [] },
        { (f: inout Figure) in f.parts[0].points = ["hip", "nowhere"] },
        { (f: inout Figure) in f.parts[1].points = ["hip", "sh"] },
        { (f: inout Figure) in f.parts[2].points = [] },
        { (f: inout Figure) in f.parts.append(.init(kind: .floor, points: ["hip"])) },
        { (f: inout Figure) in f.frames[1].points["sh"] = [1] },
        { (f: inout Figure) in f.frames[1].points["sh"] = [.nan, 2] },
        { (f: inout Figure) in f.frames[1].points["sh"] = [5000, 2] },
        { (f: inout Figure) in f.frames[1].back = [9] },
        { (f: inout Figure) in f.frames = Array(repeating: f.frames[0], count: 200) },
    ] as [@Sendable (inout Figure) -> Void])
    func aBrokenFigureIsRefused(_ breakIt: @Sendable (inout Figure) -> Void) {
        var f = bend(); breakIt(&f)
        #expect(throws: ForgeError.self) { try f.validate() }
    }

    @Test func aStepKeepsItsFigureThroughSavingAndReading() throws {
        let forge = try Forge.inMemory()
        let input = GuideInput(id: "g", title: "T", notes: nil, position: nil, sections: [
            .init(title: "A", steps: [.init(name: " Bend ", cue: nil, figure: bend()), .init(name: "Plain", cue: nil, figure: nil)]),
        ])
        let saved = try forge.putGuide(input, author: .claude)
        #expect(saved.sections[0].steps[0].figure == bend())
        #expect(try forge.guide(id: "g")?.sections[0].steps[0].figure == bend())
        #expect(try forge.guide(id: "g")?.sections[0].steps[1].figure == nil)
    }

    @Test func savingAGuideWithABrokenFigureIsRefused() throws {
        let forge = try Forge.inMemory()
        var broken = bend(); broken.parts[0].points = ["nowhere", "hip"]
        let input = GuideInput(id: "g", title: "T", notes: nil, position: nil, sections: [.init(title: nil, steps: [.init(name: "Bend", cue: nil, figure: broken)])])
        #expect(throws: ForgeError.self) { try forge.putGuide(input, author: .claude) }
    }

    @Test func aStepSavedBeforeFiguresExistedStillReads() throws {
        let old = #"{"name":"Bend","cue":"slow"}"#
        let step = try JSONDecoder().decode(GuideStep.self, from: Data(old.utf8))
        #expect(step == GuideStep(name: "Bend", cue: "slow"))
    }

    @Test func toneAndEasingMayBeLeftOutOfTheJSON() throws {
        let json = #"{"duration":3,"parts":[{"kind":"line","points":["a","b"]}],"frames":[{"points":{"a":[1,2],"b":[3,4]}}]}"#
        let f = try JSONDecoder().decode(Figure.self, from: Data(json.utf8))
        #expect(f.easing == .ease && f.parts[0].tone == .main && f.frames[0].back == nil)
        try f.validate()
    }
}
