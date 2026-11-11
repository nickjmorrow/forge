import ForgeCore
import SwiftUI

enum WorkoutMath {
    static func volumeKg(_ w: Workout) -> Double {
        w.exercises.flatMap(\.sets).filter { $0.completed && $0.type != .warmup }.reduce(0) { $0 + ($1.weightKg ?? 0) * Double($1.reps ?? 0) }
    }

    static func seconds(_ w: Workout) -> Int? { w.endedAt.map { Int(($0 - w.startedAt) / 1000) } }
}

public struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @State private var month: Date?
    @State private var selectedDay: Date?
    @State private var deleting: Workout?
    @State private var editing: Workout?
    @State private var logging = false
    @State private var madeRoutine: String?

    public init() {}

    private var calendar: Calendar {
        var c = Calendar.current
        c.firstWeekday = 2
        return c
    }

    private var shownMonth: Date { month ?? HistoryCalendar.initialMonth(workouts: model.workouts, now: Date(), calendar: calendar) }

    /// The selected day's workouts, or everything in the month being shown.
    private var rows: [Workout] {
        if let day = selectedDay { return HistoryCalendar.workouts(on: day, in: model.workouts, calendar: calendar) }
        let range = calendar.dateInterval(of: .month, for: shownMonth)
        let from = Int64((range?.start.timeIntervalSince1970 ?? 0) * 1000), to = Int64((range?.end.timeIntervalSince1970 ?? 0) * 1000)
        return model.workouts.filter { $0.startedAt >= from && $0.startedAt < to }.sorted { $0.startedAt > $1.startedAt }
    }

    private var rowsTitle: String {
        selectedDay.map { $0.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()) } ?? shownMonth.formatted(.dateTime.month(.wide).year())
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    CalendarCard(month: shownMonth, counts: HistoryCalendar.counts(workouts: model.workouts, calendar: calendar), calendar: calendar,
                                 selectedDay: $selectedDay, onShift: { delta in
                        month = HistoryCalendar.month(shownMonth, shiftedBy: delta, calendar: calendar)
                        selectedDay = nil
                    })
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 0))
                Section {
                    ForEach(rows) { w in
                        NavigationLink(value: w.id) { WorkoutRow(workout: w) }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("Delete", role: .destructive) { deleting = w }.tint(Theme.danger)
                                Button("Edit") { editing = w }.tint(Theme.info)
                            }
                            .contextMenu {
                                Button("Edit", systemImage: "pencil") { editing = w }
                                Button("Save as Routine", systemImage: "list.bullet.rectangle") { madeRoutine = model.saveWorkoutAsRoutine(id: w.id)?.title }
                                Button("Delete", systemImage: "trash", role: .destructive) { deleting = w }
                            }
                    }
                    if rows.isEmpty {
                        Text(selectedDay == nil ? "No workouts this month." : "No workouts that day.").foregroundStyle(Theme.dim)
                    }
                } header: {
                    HStack {
                        Text(rowsTitle)
                        Spacer()
                        if selectedDay != nil { Button("Show month") { selectedDay = nil }.font(.subheadline) }
                    }
                }
                .listRowBackground(Theme.card)
            }
            .themedList()
            .navigationTitle("History")
            .navigationDestination(for: String.self) { id in
                if let w = model.workouts.first(where: { $0.id == id }) { WorkoutDetailView(workout: w) }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) { Button("Log a past workout", systemImage: "plus") { logging = true } }
            }
            .sheet(isPresented: $logging) {
                WorkoutEditorView(workout: Workout(title: "Workout", startedAt: Int64(Date().timeIntervalSince1970 * 1000)), isNew: true).forgeTheme()
            }
            .sheet(item: $editing) { WorkoutEditorView(workout: $0).forgeTheme() }
            .confirmationDialog("Delete this workout?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("Delete Workout", role: .destructive) { if let w = deleting { model.deleteWorkout(id: w.id) } }
                Button("Keep It", role: .cancel) {}
            } message: { Text("\(deleting?.title ?? "It") and its sets are removed. You can undo this from Settings → Changes.") }
            .alert("Routine saved", isPresented: Binding(get: { madeRoutine != nil }, set: { if !$0 { madeRoutine = nil } })) {
                Button("OK") {}
            } message: { Text("\(madeRoutine ?? "") is now in your routines.") }
        }
    }
}

extension Workout: @retroactive Identifiable {}

/// A month of days; workout days are filled in sun-yellow, and tapping one shows just that day.
private struct CalendarCard: View {
    let month: Date
    let counts: [Date: Int]
    let calendar: Calendar
    @Binding var selectedDay: Date?
    let onShift: (Int) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    private var weekdayLetters: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        return (0..<7).map { symbols[($0 + calendar.firstWeekday - 1) % 7] }
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button { onShift(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44).contentShape(Rectangle()) }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Previous month")
                Spacer()
                Text(month.formatted(.dateTime.month(.wide).year())).font(.headline)
                Spacer()
                Button { onShift(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44).contentShape(Rectangle()) }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Next month")
            }
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(weekdayLetters.enumerated()), id: \.offset) { _, letter in
                    Text(letter).font(.caption2.weight(.semibold)).foregroundStyle(Theme.dim).frame(height: 20)
                }
                ForEach(Array(HistoryCalendar.cells(forMonthOf: month, calendar: calendar).enumerated()), id: \.offset) { _, day in
                    if let day { dayCell(day) } else { Color.clear.frame(height: 40) }
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
        .frame(maxWidth: 520)   // on a wide Mac window a full-width month is mostly empty circles
    }

    private func dayCell(_ day: Date) -> some View {
        let count = counts[day] ?? 0
        let selected = selectedDay.map { calendar.isDate($0, inSameDayAs: day) } ?? false
        let today = calendar.isDateInToday(day)
        return Button {
            guard count > 0 else { return }
            selectedDay = selected ? nil : day
        } label: {
            Text("\(calendar.component(.day, from: day))")
                .font(.subheadline.weight(count > 0 ? .bold : .regular).monospacedDigit())
                .foregroundStyle(count > 0 ? Theme.background : (today ? Theme.accent : Theme.dim))
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(Circle().fill(count > 0 ? (count > 1 ? Theme.flameTop : Theme.accent) : .clear))
                .overlay(Circle().stroke(selected ? Theme.text : (today && count == 0 ? Theme.accent.opacity(0.6) : .clear), lineWidth: 2))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(count == 0)
        .accessibilityLabel(day.formatted(date: .abbreviated, time: .omitted) + (count > 0 ? ", \(count) \(count == 1 ? "workout" : "workouts")" : ""))
    }
}

struct WorkoutRow: View {
    @Environment(AppModel.self) private var model
    let workout: Workout

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(workout.title).font(.headline)
            Text([Format.date(workout.startedAt).formatted(date: .abbreviated, time: .shortened),
                  WorkoutMath.seconds(workout).map(Format.duration(seconds:)),
                  Format.volume(kg: WorkoutMath.volumeKg(workout), unit: model.unit)].compactMap { $0 }.joined(separator: " · "))
                .font(.caption).foregroundStyle(Theme.dim)
            Text(workout.exercises.map { model.name(for: $0.exerciseID) }.joined(separator: ", "))
                .font(.caption).foregroundStyle(Theme.dim).lineLimit(1)
        }
    }
}

struct WorkoutDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let workout: Workout
    @State private var confirmDelete = false
    @State private var editing = false
    @State private var madeRoutine: String?

    var body: some View {
        List {
            Section {
                StatLine(parts: [WorkoutMath.seconds(workout).map(Format.duration(seconds:)),
                                 Format.volume(kg: WorkoutMath.volumeKg(workout), unit: model.unit),
                                 "\(workout.exercises.flatMap(\.sets).count) sets"].compactMap { $0 })
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 0))
            }
            if let r = model.recovery(for: workout) {
                Section("Recovery that morning") {
                    if let sleep = r.sleepSeconds { LabeledContent("Sleep", value: Format.duration(seconds: sleep)) }
                    if let score = r.sleepScore { LabeledContent("Sleep score", value: Units.trimmed(score, places: 0)) }
                    if let hrv = r.hrvMs { LabeledContent("HRV", value: Units.trimmed(hrv, places: 0) + " ms") }
                    if let hr = r.restingHR { LabeledContent("Resting heart rate", value: Units.trimmed(hr, places: 0) + " bpm") }
                    Text(r.source == "eight_sleep" ? "From Eight Sleep" : "From Apple Health").font(.caption).foregroundStyle(Theme.dim)
                }.listRowBackground(Theme.card)
            }
            if let notes = workout.notes { Section("Notes") { Text(notes) }.listRowBackground(Theme.card) }
            ForEach(Array(workout.exercises.enumerated()), id: \.offset) { _, block in
                let tracking = model.exercises.first { $0.id == block.exerciseID }?.tracking ?? .weightReps
                Section(model.name(for: block.exerciseID)) {
                    ForEach(Array(block.sets.enumerated()), id: \.offset) { j, set in
                        HStack {
                            Text(set.type == .normal ? "\(j + 1)" : String(set.type.rawValue.first!).uppercased()).foregroundStyle(Theme.dim).frame(width: 28, alignment: .leading)
                            Text(SetFormat.describe(set, tracking: tracking, unit: model.unit))
                            if let rpe = set.rpe { Spacer(); Text("RPE \(Units.trimmed(rpe))").font(.caption).foregroundStyle(Theme.dim) }
                        }
                    }
                    if let notes = block.notes { Text(notes).font(.footnote).foregroundStyle(Theme.dim) }
                }.listRowBackground(Theme.card)
            }
        }
        .themedList()
            .navigationTitle(workout.title)
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Edit", systemImage: "pencil") { editing = true }
                    Button("Save as Routine", systemImage: "list.bullet.rectangle") { madeRoutine = model.saveWorkoutAsRoutine(id: workout.id)?.title }
                    Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $editing) { WorkoutEditorView(workout: workout).forgeTheme() }
        .alert("Routine saved", isPresented: Binding(get: { madeRoutine != nil }, set: { if !$0 { madeRoutine = nil } })) {
            Button("OK") {}
        } message: { Text("\(madeRoutine ?? "") is now in your routines.") }
        .confirmationDialog("Delete this workout?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Workout", role: .destructive) { model.deleteWorkout(id: workout.id); dismiss() }
            Button("Cancel", role: .cancel) {}
        }
    }
}
