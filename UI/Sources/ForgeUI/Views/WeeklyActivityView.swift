import Charts
import ForgeCore
import SwiftUI

/// The phone's home charts: workouts and hours trained per week. Touch a bar to read that week.
struct WeeklyActivityView: View {
    @Environment(AppModel.self) private var model
    private static let weeks = 12

    private var totals: [WeekTotals] { DashboardStats.weekly(workouts: model.workouts, weeks: Self.weeks, now: .now) }

    var body: some View {
        let totals = totals
        VStack(spacing: 12) {
            WeekBarChart(title: "Workouts per week", totals: totals, value: { Double($0.workouts) }, format: { "\(Int($0))" },
                         unitLabel: { $0 == 1 ? "workout" : "workouts" })
            WeekBarChart(title: "Hours per week", totals: totals, value: \.hours, format: Self.hours, unitLabel: { _ in "hours" })
        }
    }

    /// "4.5", "12", "0".
    static func hours(_ h: Double) -> String { h.formatted(.number.precision(.fractionLength(0...1))) }
}

private struct WeekBarChart: View {
    let title: String
    let totals: [WeekTotals]
    let value: (WeekTotals) -> Double
    let format: (Double) -> String
    let unitLabel: (Double) -> String
    @State private var selectedDate: Date?

    private var current: WeekTotals? { totals.last }

    /// The week under the finger, else this week.
    private var shown: WeekTotals? {
        guard let selectedDate else { return current }
        let calendar = Calendar.current
        return totals.first { calendar.isDate($0.weekStart, equalTo: selectedDate, toGranularity: .weekOfYear) } ?? current
    }

    private var average: Double {
        let past = totals.dropLast()
        return past.isEmpty ? 0 : past.map(value).reduce(0, +) / Double(past.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.dim)
            header
            Chart(totals) { week in
                BarMark(x: .value("Week", week.weekStart, unit: .weekOfYear), y: .value(title, value(week)), width: .ratio(0.7))
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4))
                    .foregroundStyle(week.id == shown?.id ? Theme.accent : Theme.accent.opacity(0.4))
            }
            .chartXSelection(value: $selectedDate)
            .chartXAxis {
                AxisMarks(values: .stride(by: .weekOfYear, count: 3)) {
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day()).foregroundStyle(Theme.faint)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) {
                    AxisGridLine().foregroundStyle(Theme.line.opacity(0.5))
                    AxisValueLabel().foregroundStyle(Theme.faint)
                }
            }
            .frame(height: 88)
            .accessibilityChartDescriptor(self)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
    }

    private var header: some View {
        let week = shown
        let amount = week.map(value) ?? 0
        let isCurrent = week?.id == current?.id
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(format(amount)).font(.system(.title, design: .rounded).weight(.bold)).monospacedDigit()
                .foregroundStyle(Theme.text).contentTransition(.numericText())
            Text(unitLabel(amount)).font(.subheadline).foregroundStyle(Theme.dim)
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(isCurrent ? "This week" : "Week of \(week?.weekStart.formatted(.dateTime.month(.abbreviated).day()) ?? "")")
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.text)
                Text("\(totals.count - 1)-wk avg \(format(average))").font(.caption).foregroundStyle(Theme.dim)
            }
        }
        .animation(.snappyUI, value: amount)
    }
}

extension WeekBarChart: AXChartDescriptorRepresentable {
    func makeChartDescriptor() -> AXChartDescriptor {
        let values = totals.map(value)
        let x = AXCategoricalDataAxisDescriptor(title: "Week", categoryOrder: totals.map { $0.weekStart.formatted(date: .abbreviated, time: .omitted) })
        let y = AXNumericDataAxisDescriptor(title: title, range: 0...(values.max() ?? 1), gridlinePositions: []) { format($0) }
        let series = AXDataSeriesDescriptor(name: title, isContinuous: false,
                                            dataPoints: zip(totals, values).map { AXDataPoint(x: $0.weekStart.formatted(date: .abbreviated, time: .omitted), y: $1) })
        return AXChartDescriptor(title: title, summary: nil, xAxis: x, yAxis: y, additionalAxes: [], series: [series])
    }
}
