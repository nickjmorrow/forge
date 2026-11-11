#if os(iOS)
import ForgeCore
import Foundation
import HealthKit

/// Apple Health on iPhone: saves finished workouts as strength-training workouts and reads sleep, HRV and resting heart rate.
public final class HealthKitBridge: HealthService, @unchecked Sendable {
    private let store = HKHealthStore()

    public init() {}

    public static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        [HKCategoryType(.sleepAnalysis), HKQuantityType(.heartRateVariabilitySDNN), HKQuantityType(.restingHeartRate), HKQuantityType(.bodyMass)]
    }

    public func requestAuthorization() async throws {
        guard Self.isAvailable else { throw ForgeError.invalid("Apple Health isn't available on this device") }
        try await store.requestAuthorization(toShare: [HKObjectType.workoutType()], read: readTypes)
    }

    public func exportWorkout(_ workout: Workout) async throws {
        guard Self.isAvailable, let end = workout.endedAt else { return }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        let start = Date(timeIntervalSince1970: Double(workout.startedAt) / 1000)
        try await builder.beginCollection(at: start)
        try await builder.addMetadata([HKMetadataKeyWorkoutBrandName: "Forge", "ForgeWorkoutTitle": workout.title])
        try await builder.endCollection(at: Date(timeIntervalSince1970: Double(end) / 1000))
        _ = try await builder.finishWorkout()
    }

    public func recoveryRows(days: Int) async throws -> [Recovery] {
        guard Self.isAvailable else { return [] }
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        let since = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: Date()))!
        var rows: [String: Recovery] = [:]
        func row(_ date: String) -> Recovery { rows[date] ?? Recovery(date: date, source: "apple_health") }

        // Sleep: every "asleep" stage sample, merged per night.
        let asleep: Set<Int> = [HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue, HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                                HKCategoryValueSleepAnalysis.asleepDeep.rawValue, HKCategoryValueSleepAnalysis.asleepREM.rawValue]
        let sleepQuery = HKSampleQueryDescriptor(predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: HKQuery.predicateForSamples(withStart: since, end: nil))],
                                                 sortDescriptors: [SortDescriptor(\.startDate)])
        let samples = try await sleepQuery.result(for: store)
        let intervals = samples.filter { asleep.contains($0.value) }.map { SleepInterval(start: $0.startDate, end: $0.endDate) }
        for (date, seconds) in SleepAggregator.nightly(intervals: intervals, calendar: calendar) {
            var r = row(date)
            r.sleepSeconds = seconds
            rows[date] = r
        }

        // HRV and resting heart rate: the day's average.
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for (type, unit, assign) in [
            (HKQuantityType(.heartRateVariabilitySDNN), HKUnit.secondUnit(with: .milli), { (r: inout Recovery, v: Double) in r.hrvMs = v }),
            (HKQuantityType(.restingHeartRate), HKUnit.count().unitDivided(by: .minute()), { (r: inout Recovery, v: Double) in r.restingHR = v }),
        ] {
            let query = HKStatisticsCollectionQueryDescriptor(predicate: .quantitySample(type: type, predicate: HKQuery.predicateForSamples(withStart: since, end: nil)),
                                                              options: .discreteAverage, anchorDate: calendar.startOfDay(for: since),
                                                              intervalComponents: DateComponents(day: 1))
            let collection = try await query.result(for: store)
            collection.enumerateStatistics(from: since, to: Date()) { stats, _ in
                guard let value = stats.averageQuantity()?.doubleValue(for: unit) else { return }
                let date = formatter.string(from: stats.startDate)
                var r = row(date)
                assign(&r, value)
                rows[date] = r
            }
        }
        return rows.values.sorted { $0.date < $1.date }
    }
}
#endif
