#if os(macOS)
import ForgeCore
import SwiftUI

/// Mac routines: the list on the left (drag to reorder), the whole selected routine on the right, edited in place and saved as you go.
struct RoutinesView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: String?
    @State private var created: String?
    @State private var deleting: Routine?

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
                ToolbarItem(placement: .primaryAction) { Button("New Routine", systemImage: "plus", action: newRoutine).help("New Routine") }
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
        }
    }

    private var routineList: some View {
        // Selection is drawn here rather than by the system, which would paint it in the Mac's accent color instead of ink.
        List {
            ForEach(model.routines) { r in
                Button { selection = r.id } label: {
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
            RoutineDetail(routine: routine, focusesTitle: created == routine.id, onDelete: { deleting = routine })
                .id(routine.id)
        } else if model.routines.isEmpty {
            ContentUnavailableView {
                Label("No routines yet", systemImage: "list.bullet.rectangle")
            } description: {
                Text(model.exercises.isEmpty ? "Add the starter exercises, then build a routine from them." : "A routine is the plan your phone starts a workout from.")
            } actions: {
                if model.exercises.isEmpty { Button("Add Starter Exercises") { model.addStarterLibrary() } }
                Button("New Routine", action: newRoutine).buttonStyle(AccentButtonStyle(compact: true))
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

enum RoutineMath {
    /// "6 exercises · 18 sets"
    static func summary(_ r: Routine) -> String {
        let sets = r.exercises.reduce(0) { $0 + $1.sets.count }
        return "\(r.exercises.count) \(r.exercises.count == 1 ? "exercise" : "exercises") · \(sets) \(sets == 1 ? "set" : "sets")"
    }
}

/// One routine laid out whole: a row per exercise with all its sets inline. Edits are saved shortly after you stop typing.
private struct RoutineDetail: View {
    @Environment(AppModel.self) private var model
    let routine: Routine
    let focusesTitle: Bool
    let onDelete: () -> Void
    @State private var draft: Routine
    /// The routine as last saved or adopted; the draft differs from it while there are unsaved edits.
    @State private var baseline: Routine
    @State private var pendingSave: Task<Void, Never>?
    @State private var showPicker = false
    @FocusState private var titleFocused: Bool

    private static let saveDelay: Duration = .milliseconds(600)

    init(routine: Routine, focusesTitle: Bool, onDelete: @escaping () -> Void) {
        self.routine = routine
        self.focusesTitle = focusesTitle
        self.onDelete = onDelete
        _draft = State(initialValue: routine)
        _baseline = State(initialValue: routine)
    }

    var body: some View {
        List {
            header
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 24, leading: 28, bottom: 16, trailing: 28))
            ForEach(Array(draft.exercises.indices), id: \.self) { i in
                if draft.exercises.indices.contains(i) {
                    ExerciseRow(block: block(i), onRemove: { draft.exercises.remove(at: i) })
                        .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 28))
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(Theme.line.opacity(0.6))
                }
            }
            .onMove { source, destination in draft.exercises.move(fromOffsets: source, toOffset: destination) }
            Button { showPicker = true } label: { Label("Add Exercise", systemImage: "plus") }
                .buttonStyle(QuietButtonStyle(fills: false))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 16, leading: 28, bottom: 32, trailing: 28))
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .sheet(isPresented: $showPicker) {
            ExercisePickerView { id in
                draft.exercises.append(ExerciseBlock(exerciseID: id, restSeconds: 90, sets: [SetEntry(), SetEntry(), SetEntry()]))
            }
            .forgeTheme()
        }
        .onAppear { if focusesTitle { titleFocused = true } }
        .onChange(of: draft) { _, new in if new != baseline { scheduleSave() } }
        .onChange(of: routine) { _, saved in
            // A change from elsewhere (Claude, sync, the phone) is shown unless you have unsaved edits here.
            if draft == baseline { draft = saved; baseline = saved }
        }
        .onDisappear { saveNow() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Routine name", text: $draft.title)
                .font(.largeTitle.weight(.bold))
                .textFieldStyle(.plain)
                .focused($titleFocused)
                .onSubmit { saveNow() }
            HStack(spacing: 12) {
                StatLine(parts: [RoutineMath.summary(draft)])
                Spacer(minLength: 12)
                Menu {
                    Button("Duplicate", systemImage: "plus.square.on.square") { saveNow(); model.duplicateRoutine(id: draft.id) }
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

    /// A binding that tolerates the row outliving its exercise for a frame after a removal.
    private func block(_ i: Int) -> Binding<ExerciseBlock> {
        Binding(get: { draft.exercises.indices.contains(i) ? draft.exercises[i] : ExerciseBlock(exerciseID: "") },
                set: { if draft.exercises.indices.contains(i) { draft.exercises[i] = $0 } })
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task {
            try? await Task.sleep(for: Self.saveDelay)
            if !Task.isCancelled { saveNow() }
        }
    }

    private func saveNow() {
        pendingSave?.cancel()
        // A routine deleted while an edit was pending stays deleted rather than being written back.
        guard draft != baseline, model.routines.contains(where: { $0.id == draft.id }) else { return }
        var toSave = draft
        if toSave.title.trimmingCharacters(in: .whitespaces).isEmpty { toSave.title = baseline.title }
        baseline = draft
        model.saveRoutine(toSave)
    }
}

/// An exercise in a routine: drag to reorder, its rest time, and every set as a compact chip you can type into.
private struct ExerciseRow: View {
    @Environment(AppModel.self) private var model
    @Binding var block: ExerciseBlock
    let onRemove: () -> Void

    private var tracking: TrackingType { model.exercise(for: block.exerciseID)?.tracking ?? .weightReps }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.body.weight(.medium))
                .foregroundStyle(Theme.faint)
                .frame(width: 18, height: 26)
                .help("Drag to reorder")
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text(model.name(for: block.exerciseID)).font(.headline).lineLimit(1)
                    Spacer(minLength: 8)
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
                        Divider()
                        Button("Remove Exercise", systemImage: "trash", role: .destructive, action: onRemove)
                    } label: { Image(systemName: "ellipsis") }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .tint(Theme.dim)
                        .help("More")
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
