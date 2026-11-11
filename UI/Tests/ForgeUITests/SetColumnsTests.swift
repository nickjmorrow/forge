import ForgeCore
import Foundation
import Testing
@testable import ForgeUI

@Suite struct SetColumnsTests {
    @Test func trackingTypesChooseTheirColumns() {
        #expect(TrackingType.weightReps.columns == [.weight, .reps])
        #expect(TrackingType.repsOnly.columns == [.reps])
        #expect(TrackingType.weightedBodyweight.columns == [.weight, .reps])
        #expect(TrackingType.assistedBodyweight.columns == [.weight, .reps])
        #expect(TrackingType.duration.columns == [.duration])
        #expect(TrackingType.weightDuration.columns == [.weight, .duration])
        #expect(TrackingType.distance.columns == [.distance])
        #expect(TrackingType.distanceDuration.columns == [.distance, .duration])
    }

    @Test func columnsReadAndWriteSets() {
        var s = SetEntry()
        SetColumn.weight.apply("135", to: &s, unit: .lb)
        SetColumn.reps.apply("8", to: &s, unit: .lb)
        #expect(abs((s.weightKg ?? 0) - 61.2349) < 0.001 && s.reps == 8)
        #expect(SetColumn.weight.text(of: s, unit: .lb) == "135")
        #expect(SetColumn.reps.text(of: s, unit: .lb) == "8")
        SetColumn.reps.apply("", to: &s, unit: .lb)
        #expect(s.reps == nil)
        SetColumn.duration.apply("1:30", to: &s, unit: .lb)
        #expect(s.durationSeconds == 90 && SetColumn.duration.text(of: s, unit: .lb) == "1:30")
        SetColumn.distance.apply("2", to: &s, unit: .kg)
        #expect(s.distanceMeters == 2000)
    }

    @Test func headersFollowTheUnitAndTracking() {
        #expect(SetColumn.weight.title(unit: .lb, tracking: .weightReps) == "LB")
        #expect(SetColumn.weight.title(unit: .kg, tracking: .assistedBodyweight) == "-KG")
        #expect(SetColumn.weight.title(unit: .lb, tracking: .weightedBodyweight) == "+LB")
        #expect(SetColumn.distance.title(unit: .lb, tracking: .distance) == "MI")
        #expect(SetColumn.duration.title(unit: .lb, tracking: .duration) == "TIME")
    }

    @Test func setsDescribeThemselvesCompactly() {
        #expect(SetFormat.describe(SetEntry(weightKg: 90.718474, reps: 5), tracking: .weightReps, unit: .lb) == "200 × 5")
        #expect(SetFormat.describe(SetEntry(reps: 12), tracking: .repsOnly, unit: .lb) == "12 reps")
        #expect(SetFormat.describe(SetEntry(durationSeconds: 75), tracking: .duration, unit: .lb) == "1:15")
        #expect(SetFormat.describe(SetEntry(), tracking: .weightReps, unit: .lb) == "–")
        #expect(SetFormat.describe(SetEntry(weightKg: 20, reps: 10), tracking: .weightReps, unit: .kg) == "20 × 10")
        #expect(SetFormat.describe(SetEntry(weightKg: 20, durationSeconds: 42), tracking: .weightDuration, unit: .kg) == "20 × 0:42")
        #expect(SetFormat.describe(SetEntry(durationSeconds: 42), tracking: .weightDuration, unit: .kg) == "0:42")
    }
}
