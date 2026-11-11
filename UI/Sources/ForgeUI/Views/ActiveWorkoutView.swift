import ForgeCore
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// The screen used while lifting: exercises, set rows, rest timer. Leaving is one tap away and writes nothing.
///
/// Every exercise and set has a stable identity, so rows animate in and out and keep their own state, and each card and row is
/// `Equatable` so typing in one set doesn't re-render the other fifty.
public struct ActiveWorkoutView: View {
    @Environment(AppModel.self) private var model
    let session: WorkoutSession
    @State private var showPicker = false
    @State private var swapIndex: Int?
    @State private var confirmLeave = false
    @State private var message: String?

    public init(session: WorkoutSession) { self.session = session }

    private var allSets: [SetEntry] { session.workout.exercises.flatMap(\.sets) }
    private var loggedCount: Int { allSets.filter(\.completed).count }

    public var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ElapsedHeader(startedAt: session.workout.startedAt)
                    ForEach(BlockRowItem.items(workout: session.workout, ids: session.blockIDs, setIDs: session.setIDs)) { row in
                        let block = row.block
                        let exercise = model.exercise(for: block.exerciseID)
                        ExerciseCard(session: session, blockID: row.id, index: row.index, count: session.blockIDs.count, block: block,
                                     setIDs: row.setIDs, previous: session.previous[block.exerciseID] ?? [],
                                     name: model.name(for: block.exerciseID),
                                     caption: [exercise?.primaryMuscle.map(Muscles.title), exercise?.equipment.map(Muscles.title)].compactMap { $0 }.joined(separator: " · "),
                                     tracking: exercise?.tracking ?? .weightReps, unit: model.unit, defaultRest: model.defaultRestSeconds,
                                     onSwap: { swapIndex = session.blockIndex(row.id) })
                            .equatable()
                            .appears(from: .bottom)
                    }
                    Button { showPicker = true } label: { Label("Add Exercise", systemImage: "plus") }
                        .buttonStyle(QuietButtonStyle())
                        .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .motion(value: session.blockIDs)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background)
            .safeAreaInset(edge: .bottom) { RestBar(session: session) }
            .navigationTitle(session.workout.title)
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { leave() } label: { Label("Leave workout", systemImage: "xmark") }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Finish") { finish() }.bold()
                }
                #if os(iOS)
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
                }
                #endif
            }
            .sheet(isPresented: $showPicker) { ExercisePickerView { session.addExercise($0) } }
            .sheet(item: Binding(get: { swapIndex.map(SwapTarget.init) }, set: { swapIndex = $0?.index })) { target in
                ExercisePickerView { session.swapExercise(at: target.index, with: $0) }
            }
            .confirmationDialog("Leave this workout?", isPresented: $confirmLeave, titleVisibility: .visible) {
                Button("Leave Without Saving", role: .destructive) { model.discardWorkout() }
                Button("Keep Working", role: .cancel) {}
            } message: { Text("The \(loggedCount) \(loggedCount == 1 ? "set" : "sets") you've logged won't be saved.") }
            .alert("Can't finish yet", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK") {}
            } message: { Text(message ?? "") }
        }
    }

    /// Nothing logged yet (a misclick) leaves straight away; otherwise it asks first.
    private func leave() {
        if session.hasLoggedSets { confirmLeave = true } else { model.discardWorkout() }
    }

    private func finish() {
        do { try model.finishWorkout() } catch WorkoutSessionError.nothingToSave {
            message = "Complete at least one set before finishing, or leave the workout."
        } catch { message = "\(error)" }
    }

    private struct SwapTarget: Identifiable { let index: Int; var id: Int { index } }
}

/// One exercise card's data, taken together so a card SwiftUI is still animating out never looks itself up by a stale position.
struct BlockRowItem: Identifiable {
    let id: UUID
    let index: Int
    let block: ExerciseBlock
    let setIDs: [UUID]

    static func items(workout: Workout, ids: [UUID], setIDs: [[UUID]]) -> [BlockRowItem] {
        zip(ids, zip(workout.exercises, setIDs)).enumerated().map { i, pair in
            BlockRowItem(id: pair.0, index: i, block: pair.1.0, setIDs: pair.1.1)
        }
    }
}

/// One set row's data, for the same reason.
struct SetRowItem: Identifiable {
    let id: UUID
    let entry: SetEntry
    let previous: SetEntry?
    /// "W", "F", "D", or the set's number among the normal sets.
    let label: String

    static func items(sets: [SetEntry], ids: [UUID], previous: [SetEntry]) -> [SetRowItem] {
        var normalCount = 0
        return zip(ids, sets).enumerated().map { j, pair in
            let label: String
            switch pair.1.type {
            case .warmup: label = "W"
            case .failure: label = "F"
            case .drop: label = "D"
            case .normal: normalCount += 1; label = "\(normalCount)"
            }
            return SetRowItem(id: pair.0, entry: pair.1, previous: j < previous.count ? previous[j] : nil, label: label)
        }
    }
}

private struct ElapsedHeader: View {
    let startedAt: Int64
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = Int(context.date.timeIntervalSince(Format.date(startedAt)))
            HStack(spacing: 6) {
                Image(systemName: "clock")
                Text(Units.clock(seconds: elapsed)).monospacedDigit().contentTransition(.numericText())
                Spacer()
            }
            .font(.subheadline)
            .foregroundStyle(Theme.dim)
            .accessibilityElement(children: .combine)
        }
    }
}

private struct ExerciseCard: View, Equatable {
    let session: WorkoutSession
    let blockID: UUID
    let index: Int
    let count: Int
    let block: ExerciseBlock
    let setIDs: [UUID]
    let previous: [SetEntry]
    let name: String
    let caption: String
    let tracking: TrackingType
    let unit: WeightUnit
    let defaultRest: Int
    let onSwap: () -> Void

    /// Everything the card shows; the session and the closure are how it acts, not what it displays.
    static func == (a: ExerciseCard, b: ExerciseCard) -> Bool {
        a.blockID == b.blockID && a.index == b.index && a.count == b.count && a.block == b.block && a.setIDs == b.setIDs && a.previous == b.previous
            && a.name == b.name && a.caption == b.caption && a.tracking == b.tracking && a.unit == b.unit && a.defaultRest == b.defaultRest
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 4) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.headline)
                    if !caption.isEmpty { Text(caption).font(.caption).foregroundStyle(Theme.dim) }
                }
                Spacer(minLength: 4)
                restChip
                Menu {
                    Button("Swap Exercise", systemImage: "arrow.left.arrow.right", action: onSwap)
                    Button("Move Up", systemImage: "arrow.up") { move(-1) }.disabled(index == 0)
                    Button("Move Down", systemImage: "arrow.down") { move(1) }.disabled(index >= count - 1)
                    Button("Remove Exercise", systemImage: "trash", role: .destructive) { if let i = session.blockIndex(blockID) { session.removeExercise(at: i) } }
                } label: {
                    Image(systemName: "ellipsis").font(.title3).foregroundStyle(Theme.dim).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Exercise options")
            }
            TextField("", text: Binding(get: { block.notes ?? "" }, set: { text in if let i = session.blockIndex(blockID) { session.setNotes(exercise: i, text) } }),
                      prompt: Text("Notes").foregroundStyle(Theme.dim))
                .font(.subheadline)
                .padding(.bottom, 6)
            HStack(spacing: 8) {
                Text("SET").frame(width: 32)
                Text("PREVIOUS").frame(maxWidth: .infinity)
                ForEach(tracking.columns, id: \.self) { Text($0.title(unit: unit, tracking: tracking)).frame(width: 64) }
                Spacer().frame(width: 44)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.dim)
            VStack(spacing: 4) {
                ForEach(SetRowItem.items(sets: block.sets, ids: setIDs, previous: previous)) { row in
                    SetRow(session: session, blockID: blockID, setID: row.id, entry: row.entry, previous: row.previous,
                           label: row.label, tracking: tracking, unit: unit)
                        .equatable()
                        .appears(from: .top)
                }
            }
            .motion(value: setIDs)
            Button { if let i = session.blockIndex(blockID) { session.addSet(toExercise: i) } } label: { Label("Add Set", systemImage: "plus") }
                .buttonStyle(QuietButtonStyle())
                .padding(.top, 6)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
    }

    private func move(_ delta: Int) {
        if let i = session.blockIndex(blockID) { session.moveExercise(from: i, to: min(max(0, i + delta), count - 1)) }
    }

    /// The rest after this exercise's sets, adjustable per exercise: Off, the app default, or a fixed time.
    private var restChip: some View {
        Menu {
            ForEach(RestOptions.choices, id: \.self) { seconds in
                Button {
                    if let i = session.blockIndex(blockID) { session.setRest(exercise: i, seconds: seconds) }
                } label: {
                    if block.restSeconds == seconds { Label(RestOptions.label(for: seconds, defaultSeconds: defaultRest), systemImage: "checkmark") }
                    else { Text(RestOptions.label(for: seconds, defaultSeconds: defaultRest)) }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: block.restSeconds == ExerciseBlock.restOff ? "timer.slash" : "timer")
                Text(RestOptions.shortLabel(for: block.restSeconds, defaultSeconds: defaultRest)).monospacedDigit()
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(block.restSeconds == ExerciseBlock.restOff ? Theme.dim : Theme.accent)
            .padding(.horizontal, 10)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Rest timer")
        .accessibilityValue(RestOptions.label(for: block.restSeconds, defaultSeconds: defaultRest))
    }
}

private struct SetRow: View, Equatable {
    let session: WorkoutSession
    let blockID: UUID
    let setID: UUID
    let entry: SetEntry
    let previous: SetEntry?
    let label: String
    let tracking: TrackingType
    let unit: WeightUnit

    static func == (a: SetRow, b: SetRow) -> Bool {
        a.blockID == b.blockID && a.setID == b.setID && a.entry == b.entry && a.previous == b.previous && a.label == b.label
            && a.tracking == b.tracking && a.unit == b.unit
    }

    private func edit(_ change: (WorkoutSession, Int, Int) -> Void) {
        guard let b = session.blockIndex(blockID), let j = session.setIndex(block: blockID, set: setID) else { return }
        change(session, b, j)
    }

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach([SetType.normal, .warmup, .failure, .drop], id: \.self) { type in
                    Button(type.rawValue.capitalized) { edit { s, b, j in s.update(exercise: b, set: j) { $0.type = type } } }
                }
                Button("Delete Set", systemImage: "trash", role: .destructive) { edit { s, b, j in s.removeSet(exercise: b, set: j) } }
            } label: {
                Text(label).font(.headline.monospacedDigit())
                    .foregroundStyle(entry.type == .normal ? Theme.text : Theme.accent)
                    .frame(width: 32, height: 44)
            }
            .accessibilityLabel("Set \(label) options")
            Text(previous.map { SetFormat.describe($0, tracking: tracking, unit: unit) } ?? "–")
                .font(.footnote.monospacedDigit()).foregroundStyle(Theme.dim).frame(maxWidth: .infinity)
            ForEach(tracking.columns, id: \.self) { column in
                ValueField(placeholder: previous.map { column.text(of: $0, unit: unit) } ?? "", initial: column.text(of: entry, unit: unit)) { text in
                    edit { s, b, j in s.update(exercise: b, set: j) { column.apply(text, to: &$0, unit: unit) } }
                }
                .frame(width: 64)
            }
            Button { edit { s, b, j in s.toggleComplete(exercise: b, set: j) } } label: {
                Image(systemName: entry.completed ? "checkmark.circle.fill" : "circle")
                    .font(.title)
                    .foregroundStyle(entry.completed ? Theme.done : Theme.faint)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: entry.completed)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(entry.completed ? "Set \(label) done" : "Mark set \(label) done")
            #if os(iOS)
            .sensoryFeedback(.success, trigger: entry.completed) { _, done in done }          // the app's heartbeat: a set ticked off
            #endif
        }
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(entry.completed ? Theme.done.opacity(0.12) : Theme.card))
        .swipeToDelete(label: "Delete set \(label)") { edit { s, b, j in s.removeSet(exercise: b, set: j) } }
        .motion(value: entry.completed)
    }
}

private struct RestBar: View {
    let session: WorkoutSession

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let remaining = session.rest.remaining(at: context.date)
            let running = remaining > 0
            Group {
                if running {
                    VStack(spacing: 8) {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("Rest").font(.caption).foregroundStyle(Theme.dim)
                                Text(Units.clock(seconds: remaining))
                                    .font(.title.weight(.bold).monospacedDigit()).foregroundStyle(Theme.accent)
                                    .contentTransition(.numericText(countsDown: true))
                                    .animation(.snappy(duration: 0.2), value: remaining)
                            }
                            Spacer()
                            Button("−15") { session.adjustRest(by: -15) }.buttonStyle(QuietButtonStyle(fills: false))
                            Button("+15") { session.adjustRest(by: 15) }.buttonStyle(QuietButtonStyle(fills: false))
                            Button("Skip") { session.skipRest() }.buttonStyle(AccentButtonStyle(compact: true))
                        }
                        ProgressView(value: Double(remaining), total: Double(max(session.rest.totalSeconds, remaining))).tint(Theme.accent)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.regularMaterial)
                    .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 0.5) }
                    .accessibilityElement(children: .contain)
                    .appears(from: .bottom)
                }
            }
            .motion(value: running)
            #if os(iOS)
            .sensoryFeedback(.impact(weight: .medium), trigger: running) { was, now in was && !now }   // rest is over
            #endif
        }
    }
}
