#if os(macOS)
import ForgeCore
import SwiftUI

/// Mac routines: the list on the left (drag to reorder), the whole selected routine on the right, read-only until you press Edit.
struct RoutinesView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: String?
    @State private var created: String?
    @State private var deleting: Routine?
    /// Set by the open routine while it has unsaved edits; leaving it then asks first.
    @Binding var hasUnsavedEdits: Bool
    @State private var pendingLeave: Leave?

    private enum Leave { case select(String), new }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                routineList.frame(width: 240)
                Rectangle().fill(Theme.line.opacity(0.5)).frame(width: 1).ignoresSafeArea()
                detail.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Theme.background)
            .navigationTitle("Routines")
            .toolbar {
                ToolbarItem(placement: .primaryAction) { Button("New Routine", systemImage: "plus") { leave(.new) }.help("New Routine") }
            }
            .onAppear { if selection == nil { selection = model.routines.first?.id } }
            .onChange(of: model.routines.map(\.id)) { _, ids in
                if let s = selection, !ids.contains(s) { selection = ids.first }
            }
            .confirmationDialog("Delete \(deleting?.title ?? "routine")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                                titleVisibility: .visible) {
                Button("Delete Routine", role: .destructive) { if let r = deleting { model.deleteRoutine(id: r.id) } }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Past workouts from it are kept.") }
            .confirmationDialog("Discard your changes?", isPresented: Binding(get: { pendingLeave != nil }, set: { if !$0 { pendingLeave = nil } }),
                                titleVisibility: .visible) {
                Button("Discard Changes", role: .destructive) { if let l = pendingLeave { go(l) } }
                Button("Keep Editing", role: .cancel) {}
            } message: { Text("This routine has edits that haven't been saved.") }
        }
    }

    /// Switching routines with unsaved edits asks first, since the draft would be lost.
    private func leave(_ to: Leave) {
        if case .select(let id) = to, id == selection { return }
        if hasUnsavedEdits { pendingLeave = to } else { go(to) }
    }

    private func go(_ to: Leave) {
        switch to {
        case .select(let id): selection = id
        case .new: newRoutine()
        }
    }

    private var routineList: some View {
        // Selection is drawn here rather than by the system, which would paint it in the Mac's accent color instead of ink.
        List {
            ForEach(model.routines) { r in
                Button { leave(.select(r.id)) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.title.isEmpty ? "Untitled" : r.title).font(.body.weight(.medium)).foregroundStyle(Theme.text).lineLimit(1)
                        Text(RoutineMath.summary(r)).font(.caption).foregroundStyle(Theme.dim)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(selection == r.id ? Theme.raised : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 1, leading: 10, bottom: 1, trailing: 10))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .accessibilityAddTraits(selection == r.id ? .isSelected : [])
                .contextMenu {
                    Button("Duplicate", systemImage: "plus.square.on.square") { model.duplicateRoutine(id: r.id) }
                    Divider()
                    Button("Delete", systemImage: "trash", role: .destructive) { deleting = r }
                }
            }
            .onMove { source, destination in
                var ids = model.routines.map(\.id)
                ids.move(fromOffsets: source, toOffset: destination)
                model.reorderRoutines(ids)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.bar)
    }

    @ViewBuilder private var detail: some View {
        if let routine = model.routines.first(where: { $0.id == selection }) {
            RoutineDetail(routine: routine, startsEditing: created == routine.id, hasUnsavedEdits: $hasUnsavedEdits, onDelete: { deleting = routine })
                .id(routine.id)
        } else if model.routines.isEmpty {
            ContentUnavailableView {
                Label("No routines yet", systemImage: "list.bullet.rectangle")
            } description: {
                Text(model.exercises.isEmpty ? "Add the starter exercises, then build a routine from them." : "A routine is the plan your phone starts a workout from.")
            } actions: {
                if model.exercises.isEmpty { Button("Add Starter Exercises") { model.addStarterLibrary() } }
                Button("New Routine") { leave(.new) }.buttonStyle(AccentButtonStyle(compact: true))
            }
        } else {
            ContentUnavailableView("Select a routine", systemImage: "list.bullet.rectangle")
        }
    }

    private func newRoutine() {
        let routine = Routine(title: "New Routine", position: model.routines.count)
        model.saveRoutine(routine)
        created = routine.id
        selection = routine.id
    }
}

/// One routine laid out whole. It opens read-only; Edit starts a draft that is written only by Save, and Reorder (while editing)
/// collapses every exercise to one draggable line.
private struct RoutineDetail: View {
    @Environment(AppModel.self) private var model
    let routine: Routine
    let onDelete: () -> Void
    /// True while the draft differs from the saved routine, so the list can ask before switching away.
    @Binding var hasUnsavedEdits: Bool
    @State private var draft: Routine
    @State private var editing: Bool
    @State private var reordering = false
    @State private var showPicker = false
    @FocusState private var titleFocused: Bool

    init(routine: Routine, startsEditing: Bool, hasUnsavedEdits: Binding<Bool>, onDelete: @escaping () -> Void) {
        self.routine = routine
        self.onDelete = onDelete
        _hasUnsavedEdits = hasUnsavedEdits
        _draft = State(initialValue: routine)
        _editing = State(initialValue: startsEditing)
    }

    /// What is on screen: the draft while editing, otherwise the saved routine (so changes from Claude, sync or the phone show up).
    private var shown: Routine { editing ? draft : routine }

    var body: some View {
        List {
            header
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 24, leading: 28, bottom: 16, trailing: 28))
            ForEach(Array(shown.exercises.indices), id: \.self) { i in
                if shown.exercises.indices.contains(i) {
                    row(i)
                        .listRowInsets(EdgeInsets(top: reordering ? 6 : 12, leading: 28, bottom: reordering ? 6 : 12, trailing: 28))
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(Theme.line.opacity(0.6))
                }
            }
            .onMove(perform: reordering ? { source, destination in draft.exercises.move(fromOffsets: source, toOffset: destination) } : nil)
            if editing && !reordering {
                Button { showPicker = true } label: { Label("Add Exercise", systemImage: "plus") }
                    .buttonStyle(QuietButtonStyle(fills: false))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 16, leading: 28, bottom: 32, trailing: 28))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .motion(value: reordering)
        .sheet(isPresented: $showPicker) {
            ExercisePickerView { id in
                draft.exercises.append(ExerciseBlock(exerciseID: id, restSeconds: 90, sets: [SetEntry(), SetEntry(), SetEntry()]))
            }
            .forgeTheme()
        }
        .onAppear { if editing { titleFocused = true } }
        .onChange(of: editing ? draft != routine : false) { _, dirty in hasUnsavedEdits = dirty }
        .onDisappear { hasUnsavedEdits = false }
    }

    @ViewBuilder private func row(_ i: Int) -> some View {
        if reordering {
            HStack(spacing: 10) {
                Image(systemName: "line.3.horizontal").font(.body.weight(.medium)).foregroundStyle(Theme.dim).accessibilityHidden(true)
                Text(model.name(for: shown.exercises[i].exerciseID)).font(.headline).lineLimit(1)
                Spacer(minLength: 8)
                Text(RoutineMath.sets(shown.exercises[i].sets.count)).font(.callout).foregroundStyle(Theme.dim)
            }
            .contentShape(Rectangle())
            .help("Drag to reorder")
        } else if editing {
            ExerciseRow(block: block(i), onRemove: { draft.exercises.remove(at: i) })
        } else {
            ExerciseSummaryRow(block: shown.exercises[i])
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            if editing {
                TextField("Routine name", text: $draft.title)
                    .font(.largeTitle.weight(.bold))
                    .textFieldStyle(.plain)
                    .focused($titleFocused)
            } else {
                Text(routine.title.isEmpty ? "Untitled" : routine.title).font(.largeTitle.weight(.bold))
            }
            HStack(spacing: 12) {
                StatLine(parts: [RoutineMath.summary(shown)])
                Spacer(minLength: 12)
                if editing {
                    if draft.exercises.count > 1 {
                        Button(reordering ? "Done Reordering" : "Reorder", systemImage: reordering ? "checkmark" : "arrow.up.arrow.down") { reordering.toggle() }
                            .buttonStyle(QuietButtonStyle(fills: false))
                    }
                    Button("Cancel", action: cancel).buttonStyle(QuietButtonStyle(fills: false)).keyboardShortcut(.cancelAction)
                    Button("Save", action: save).buttonStyle(AccentButtonStyle(compact: true)).keyboardShortcut("s")
                } else {
                    Button("Edit", systemImage: "pencil", action: startEditing).buttonStyle(QuietButtonStyle(fills: false)).keyboardShortcut("e")
                    Menu {
                        Button("Duplicate", systemImage: "plus.square.on.square") { model.duplicateRoutine(id: routine.id) }
                        Divider()
                        Button("Delete Routine", systemImage: "trash", role: .destructive, action: onDelete)
                    } label: { Image(systemName: "ellipsis.circle") }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .tint(Theme.dim)
                        .help("More")
                }
            }
        }
    }

    /// A binding that tolerates the row outliving its exercise for a frame after a removal.
    private func block(_ i: Int) -> Binding<ExerciseBlock> {
        Binding(get: { draft.exercises.indices.contains(i) ? draft.exercises[i] : ExerciseBlock(exerciseID: "") },
                set: { if draft.exercises.indices.contains(i) { draft.exercises[i] = $0 } })
    }

    private func startEditing() {
        draft = routine
        editing = true
    }

    private func cancel() {
        reordering = false
        editing = false
        draft = routine
    }

    private func save() {
        var toSave = draft
        if toSave.title.trimmingCharacters(in: .whitespaces).isEmpty { toSave.title = routine.title }
        reordering = false
        editing = false
        if toSave != routine { model.saveRoutine(toSave) }
    }
}

/// An exercise in a routine as you read it: its rest time and every set as plain text.
private struct ExerciseSummaryRow: View {
    @Environment(AppModel.self) private var model
    let block: ExerciseBlock

    /// "A or B" for the exercises that can be done instead; nil when there are none.
    private var alternativeNames: String? {
        let names = (block.alternatives ?? []).compactMap { model.exercise(for: $0)?.name }
        return names.isEmpty ? nil : names.joined(separator: " or ")
    }

    var body: some View {
        let tracking = model.exercise(for: block.exerciseID)?.tracking ?? .weightReps
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(model.name(for: block.exerciseID)).font(.headline).lineLimit(1)
                Spacer(minLength: 8)
                if let range = block.repRange, Progression.applies(to: tracking) {
                    Label(RepRangeOptions.label(for: range), systemImage: "arrow.up.right")
                        .font(.callout.monospacedDigit()).foregroundStyle(Theme.accent)
                }
                Label("Rest " + RestOptions.shortLabel(for: block.restSeconds, defaultSeconds: model.defaultRestSeconds), systemImage: "timer")
                    .font(.callout.monospacedDigit()).foregroundStyle(Theme.dim)
            }
            if let names = alternativeNames { Text("or " + names).font(.callout).foregroundStyle(Theme.dim).lineLimit(2) }
            FlowLayout(spacing: 8) {
                ForEach(Array(SetRowItem.items(sets: block.sets, ids: block.sets.map { _ in UUID() }, previous: []).enumerated()), id: \.offset) { _, set in
                    HStack(spacing: 6) {
                        Text(set.label).font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(set.entry.type == .normal ? Theme.dim : Theme.accent)
                        Text(SetFormat.describe(set.entry, tracking: tracking, unit: model.unit)).font(.callout.monospacedDigit())
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(Capsule().fill(Theme.field))
                }
            }
        }
    }
}

/// An exercise in a routine being edited: its rest time, and every set as a compact chip you can type into.
private struct ExerciseRow: View {
    @Environment(AppModel.self) private var model
    @Binding var block: ExerciseBlock
    let onRemove: () -> Void
    @State private var pickingAlternative = false

    private var tracking: TrackingType { model.exercise(for: block.exerciseID)?.tracking ?? .weightReps }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text(model.name(for: block.exerciseID)).font(.headline).lineLimit(1)
                    Spacer(minLength: 8)
                    if Progression.applies(to: tracking) {
                        Menu {
                            Picker("Progress in", selection: $block.progression) {
                                ForEach(RepRangeOptions.choices, id: \.self) { Text(RepRangeOptions.label(for: $0)).tag($0) }
                            }
                            .pickerStyle(.inline)
                        } label: {
                            Label(block.repRange.map { RepRangeOptions.label(for: $0) } ?? "No rep range", systemImage: "arrow.up.right")
                                .font(.callout.monospacedDigit())
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .tint(block.repRange == nil ? Theme.dim : Theme.accent)
                        .help("Rep range to progress in: reps climb to the top, then the weight goes up")
                    }
                    Menu {
                        Picker("Rest", selection: $block.restSeconds) {
                            ForEach(RestOptions.choices, id: \.self) { Text(RestOptions.label(for: $0, defaultSeconds: model.defaultRestSeconds)).tag($0) }
                        }
                        .pickerStyle(.inline)
                    } label: {
                        Label("Rest " + RestOptions.shortLabel(for: block.restSeconds, defaultSeconds: model.defaultRestSeconds), systemImage: "timer")
                            .font(.callout.monospacedDigit())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .tint(Theme.dim)
                    .help("Rest between sets")
                    Menu {
                        Button("Add Set", systemImage: "plus", action: addSet)
                        Button("Add Alternative…", systemImage: "arrow.triangle.branch") { pickingAlternative = true }
                        Divider()
                        Button("Remove Exercise", systemImage: "trash", role: .destructive, action: onRemove)
                    } label: { Image(systemName: "ellipsis") }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .tint(Theme.dim)
                        .help("More")
                }
                if let alternatives = block.alternatives {
                    FlowLayout(spacing: 8) {
                        Text("or").font(.callout).foregroundStyle(Theme.dim).frame(height: 26)
                        ForEach(alternatives, id: \.self) { id in
                            HStack(spacing: 4) {
                                Text(model.name(for: id)).font(.callout).lineLimit(1)
                                Button { removeAlternative(id) } label: { Image(systemName: "xmark").font(.caption2.weight(.bold)) }
                                    .buttonStyle(.plain).foregroundStyle(Theme.dim)
                                    .help("Remove this alternative")
                                    .accessibilityLabel("Remove \(model.name(for: id)) as an alternative")
                            }
                            .padding(.horizontal, 10).frame(height: 26)
                            .background(Capsule().fill(Theme.field))
                        }
                    }
                }
                FlowLayout(spacing: 8) {
                    ForEach(Array(block.sets.indices), id: \.self) { j in
                        if block.sets.indices.contains(j) { setChip(j) }
                    }
                    Button(action: addSet) {
                        Image(systemName: "plus").font(.caption.weight(.bold)).frame(width: 30, height: 30)
                            .background(Circle().fill(Theme.field))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
                    .help("Add Set")
                    .accessibilityLabel("Add Set")
                }
            }
        }
        .contentShape(Rectangle())
        .sheet(isPresented: $pickingAlternative) {
            ExercisePickerView { id in
                guard id != block.exerciseID, !(block.alternatives ?? []).contains(id) else { return }
                block.alternatives = (block.alternatives ?? []) + [id]
            }
        }
    }

    private func removeAlternative(_ id: String) {
        let rest = (block.alternatives ?? []).filter { $0 != id }
        block.alternatives = rest.isEmpty ? nil : rest
    }

    private func label(_ j: Int) -> String {
        switch block.sets[j].type {
        case .warmup: return "W"
        case .failure: return "F"
        case .drop: return "D"
        case .normal: return "\(block.sets[..<j].filter { $0.type == .normal }.count + 1)"
        }
    }

    private func setChip(_ j: Int) -> some View {
        let columns = tracking.columns
        return HStack(spacing: 4) {
            Menu {
                ForEach([SetType.normal, .warmup, .failure, .drop], id: \.self) { t in
                    Button(t == .normal ? "Normal" : t.rawValue.capitalized) { block.sets[j].type = t }
                }
                Divider()
                Button("Delete Set", role: .destructive) { block.sets.remove(at: j) }
                    .disabled(block.sets.count == 1)
            } label: {
                Text(label(j)).font(.caption.weight(.semibold).monospacedDigit())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .tint(block.sets[j].type == .normal ? Theme.dim : Theme.accent)
            .frame(minWidth: 18)
            .help("Set type")
            ForEach(Array(columns.enumerated()), id: \.offset) { k, column in
                if k > 0 { Text(columns == [.weight, .reps] ? "×" : "·").font(.caption).foregroundStyle(Theme.faint) }
                ValueField(placeholder: column == .duration ? "0:00" : "0", initial: column.text(of: block.sets[j], unit: model.unit),
                           alignment: column == .reps ? .leading : .trailing, compact: true) { text in
                    guard block.sets.indices.contains(j) else { return }
                    column.apply(text, to: &block.sets[j], unit: model.unit)
                }
                .frame(width: column == .reps ? 28 : 44)
                if let suffix = suffix(column, in: columns) { Text(suffix).font(.caption).foregroundStyle(Theme.dim) }
            }
        }
        .padding(.leading, 6).padding(.trailing, 10)
        .frame(height: 30)
        .background(Capsule().fill(Theme.field))
        .contextMenu {
            Button("Duplicate Set") { block.sets.insert(block.sets[j], at: j + 1) }
            Button("Delete Set", role: .destructive) { block.sets.remove(at: j) }.disabled(block.sets.count == 1)
        }
    }

    /// "200 lb × 6" needs no "reps"; reps on their own do. Times read as times without a unit.
    private func suffix(_ column: SetColumn, in columns: [SetColumn]) -> String? {
        switch column {
        case .weight: return model.unit.rawValue
        case .reps: return columns.contains(.weight) ? nil : "reps"
        case .duration: return nil
        case .distance: return model.unit == .lb ? "mi" : "km"
        }
    }

    private func addSet() {
        block.sets.append(block.sets.last.map { var s = $0; s.completed = false; return s } ?? SetEntry())
    }
}

/// Lays children out left to right and wraps onto a new line when the row is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: rows.map(\.width).max() ?? 0, height: rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for i in row.indices {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows = [Row()]
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty && rows[rows.count - 1].width + spacing + size.width > width { rows.append(Row()) }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(i)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
#endif
