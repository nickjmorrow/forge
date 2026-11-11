import Charts
import ForgeCore
import SwiftUI

/// Mac home: this week at a glance, training calendar, recent records, sleep against training.
public struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @State private var records: [RecordItem] = []
    @State private var recoveries: [Recovery] = []
    private let now: Date
    private let calendar: Calendar

    public init(now: Date = Date(), calendar: Calendar = .current) {
        self.now = now
        var c = calendar
        c.firstWeekday = 2
        self.calendar = c
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                DashboardContent(records: records, recoveries: recoveries, now: now, calendar: calendar)
                    .padding(.horizontal, 28).padding(.vertical, 24)
            }
            .background(Color.screenBackground)
            .navigationTitle("Dashboard")
            .task(id: model.workouts.count) { load() }
        }
    }

    private func load() {
        records = (try? DashboardStats.recentRecords(forge: model.forge, now: now, days: 30)) ?? []
        recoveries = (try? model.forge.recoveries()) ?? []
    }
}

/// The dashboard's cards, with their data passed in so they can be rendered without a navigation container.
struct DashboardContent: View {
    @Environment(AppModel.self) private var model
    let records: [RecordItem]
    var recoveries: [Recovery] = []
    let now: Date
    let calendar: Calendar

    private var week: WeekSummary { DashboardStats.thisWeek(workouts: model.workouts, now: now, calendar: calendar) }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text("This week").font(.title2.bold())
                StatLine(parts: ["\(week.workouts) \(week.workouts == 1 ? "workout" : "workouts")", "\(week.sets) sets",
                                 Format.volume(kg: week.volumeKg, unit: model.unit)])
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 20) {
                    card("Training") { TrainingCalendar(now: now, calendar: calendar) }.fixedSize(horizontal: true, vertical: false)
                    card("Recent records") { recordList }.frame(minWidth: 280)
                }
                VStack(spacing: 20) {
                    card("Training") { TrainingCalendar(now: now, calendar: calendar) }
                    card("Recent records") { recordList }
                }
            }
            if !recoveries.isEmpty {
                card("Sleep and training, last 3 weeks") { SleepChart(recoveries: recoveries, now: now, calendar: calendar) }
            }
        }
    }

    @ViewBuilder private var recordList: some View {
        if records.isEmpty {
            Text("No new records in the last 30 days.").foregroundStyle(Theme.dim)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(records) { r in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: "trophy.fill").font(.caption).foregroundStyle(Theme.gold).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.name).lineLimit(1)
                            Text("1RM ≈ " + Format.volume(kg: r.e1RMKg, unit: model.unit) + "  ·  " + r.date.formatted(.dateTime.month(.abbreviated).day()))
                                .font(.caption.monospacedDigit()).foregroundStyle(Theme.dim)
                        }
                    }
                }
            }
        }
    }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
    }
}

private struct TrainingCalendar: View {
    @Environment(AppModel.self) private var model
    let now: Date
    let calendar: Calendar
    private let weeks = 16

    var body: some View {
        let days = DashboardStats.calendarDays(weeks: weeks, now: now, calendar: calendar)
        let counts = DashboardStats.workoutDays(workouts: model.workouts, weeks: weeks, now: now, calendar: calendar)
        HStack(alignment: .top, spacing: 4) {
            VStack(spacing: 4) {
                ForEach(["M", "T", "W", "T", "F", "S", "S"].indices, id: \.self) { i in
                    Text(["M", "T", "W", "T", "F", "S", "S"][i]).font(.caption2).foregroundStyle(Theme.dim).frame(width: 14, height: 18)
                }
            }
            ForEach(0..<weeks, id: \.self) { w in
                VStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { d in
                        let day = days[w * 7 + d]
                        let n = counts[day] ?? 0
                        RoundedRectangle(cornerRadius: 4)
                            .fill(n == 0 ? Theme.field.opacity(day > now ? 0.4 : 1) : (n > 1 ? Theme.flameTop : Theme.accent))   // hotter with more workouts
                            .frame(width: 18, height: 18)
                    }
                }
            }
        }
    }
}

private struct SleepChart: View {
    @Environment(AppModel.self) private var model
    let recoveries: [Recovery]
    let now: Date
    let calendar: Calendar

    private struct Night: Identifiable { let date: Date; let hours: Double; let trained: Bool; var id: Date { date } }

    private var nights: [Night] {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        let trainedDays = Set(model.workouts.map { f.string(from: Format.date($0.startedAt)) })
        let cutoff = now.addingTimeInterval(-21 * 86_400)
        // One bar per day; prefer Eight Sleep over Apple Health when both exist.
        var best: [String: Recovery] = [:]
        for r in recoveries where r.sleepSeconds != nil {
            if best[r.date] == nil || r.source == "eight_sleep" { best[r.date] = r }
        }
        return best.values.compactMap { r -> Night? in
            guard let day = f.date(from: r.date), day >= cutoff, let s = r.sleepSeconds else { return nil }
            return Night(date: day, hours: Double(s) / 3600, trained: trainedDays.contains(r.date))
        }.sorted { $0.date < $1.date }
    }

    var body: some View {
        Chart(nights) {
            BarMark(x: .value("Day", $0.date, unit: .day), y: .value("Hours", $0.hours))
                .foregroundStyle($0.trained ? Theme.accent : Theme.dim.opacity(0.5))
        }
        .chartYScale(domain: 0...10)
        .frame(height: 140)
        Text("Orange bars are mornings you trained that day.").font(.caption).foregroundStyle(Theme.dim)
    }
}
