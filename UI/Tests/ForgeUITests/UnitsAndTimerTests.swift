import Foundation
import Testing
@testable import ForgeUI

@Suite struct UnitsTests {
    @Test func poundsConvertBothWays() {
        #expect(abs(Units.pounds(fromKg: 90.718474) - 200) < 0.001)
        #expect(abs(Units.kg(fromPounds: 200) - 90.7185) < 0.001)
    }

    @Test func weightsFormatWithoutTrailingZeros() {
        #expect(Units.format(kg: 40.82336184920758, unit: .lb) == "90")
        #expect(Units.format(kg: 100.5, unit: .kg) == "100.5")
        #expect(Units.format(kg: 61.235, unit: .lb) == "135")
        #expect(Units.format(kg: nil, unit: .lb) == "")
    }

    @Test func poundsShowOneDecimalAndKilogramsTwo() {
        #expect(Units.format(kg: 87.5, unit: .lb) == "192.9")
        #expect(Units.format(kg: 111, unit: .lb) == "244.7")
        #expect(Units.format(kg: 48.1, unit: .lb) == "106")
        #expect(Units.format(kg: 62.25, unit: .kg) == "62.25")
    }

    @Test func parsingAcceptsDecimalsAndRejectsJunk() {
        #expect(Units.parseKg("135", unit: .lb).map { abs($0 - 61.2349) < 0.001 } == true)
        #expect(Units.parseKg("62.5", unit: .kg) == 62.5)
        #expect(Units.parseKg("", unit: .kg) == nil)
        #expect(Units.parseKg("abc", unit: .kg) == nil)
    }

    @Test func durationsFormatAsClock() {
        #expect(Units.clock(seconds: 75) == "1:15")
        #expect(Units.clock(seconds: 3725) == "1:02:05")
        #expect(Units.clock(seconds: 0) == "0:00")
    }
}

@Suite struct RestTimerTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test func countsDownAndFinishes() {
        var timer = RestTimer()
        timer.start(seconds: 90, now: t0)
        #expect(timer.remaining(at: t0.addingTimeInterval(30)) == 60)
        #expect(timer.isRunning(at: t0.addingTimeInterval(30)))
        #expect(timer.remaining(at: t0.addingTimeInterval(100)) == 0)
        #expect(!timer.isRunning(at: t0.addingTimeInterval(100)))
    }

    @Test func adjustAddsAndClampsAtZero() {
        var timer = RestTimer()
        timer.start(seconds: 20, now: t0)
        timer.adjust(by: 15, now: t0)
        #expect(timer.remaining(at: t0) == 35)
        timer.adjust(by: -60, now: t0)
        #expect(timer.remaining(at: t0) == 0)
    }

    @Test func skipStopsAndIdleTimerIsZero() {
        var timer = RestTimer()
        #expect(timer.remaining(at: t0) == 0 && !timer.isRunning(at: t0))
        timer.start(seconds: 60, now: t0)
        timer.skip()
        #expect(!timer.isRunning(at: t0))
    }

    @Test func startingAgainReplacesTheRunningTimer() {
        var timer = RestTimer()
        timer.start(seconds: 60, now: t0)
        timer.start(seconds: 120, now: t0.addingTimeInterval(10))
        #expect(timer.remaining(at: t0.addingTimeInterval(10)) == 120)
        #expect(timer.totalSeconds == 120)
    }
}

@Suite struct DurationAndDistanceTests {
    @Test func durationsParseSecondsOrClockForms() {
        #expect(Units.parseSeconds("90") == 90)
        #expect(Units.parseSeconds("1:30") == 90)
        #expect(Units.parseSeconds("1:02:03") == 3723)
        #expect(Units.parseSeconds("") == nil)
        #expect(Units.parseSeconds("abc") == nil)
        #expect(Units.parseSeconds("1:xx") == nil)
    }

    @Test func distancesUseKilometresOrMiles() {
        #expect(Units.distanceText(meters: 5000, unit: .kg) == "5")
        #expect(Units.distanceText(meters: 1609.344, unit: .lb) == "1")
        #expect(Units.distanceText(meters: nil, unit: .kg) == "")
        #expect(Units.parseMeters("5", unit: .kg) == 5000)
        #expect(abs((Units.parseMeters("1", unit: .lb) ?? 0) - 1609.344) < 0.001)
        #expect(Units.parseMeters("x", unit: .kg) == nil)
    }
}
