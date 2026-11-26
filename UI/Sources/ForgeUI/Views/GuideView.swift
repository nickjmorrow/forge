import ForgeCore
import SwiftUI

/// A guide laid out to read: its note, then each section with its steps and their cues.
struct GuideContent: View {
    let guide: Guide

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let notes = guide.notes {
                Text(GuideEdits.linked(notes)).font(.subheadline).foregroundStyle(Theme.dim)
            }
            if guide.sections.isEmpty {
                Text("No steps yet.").font(.subheadline).foregroundStyle(Theme.dim)
            }
            ForEach(Array(guide.sections.enumerated()), id: \.offset) { _, section in
                VStack(alignment: .leading, spacing: 8) {
                    if !section.title.isEmpty {
                        Text(section.title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(Theme.dim)
                            .padding(.horizontal, 4)
                            .accessibilityAddTraits(.isHeader)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        if section.steps.isEmpty {
                            Text("No steps yet.").font(.subheadline).foregroundStyle(Theme.dim).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        ForEach(Array(section.steps.enumerated()), id: \.offset) { i, step in
                            if i > 0 { Rectangle().fill(Theme.line.opacity(0.5)).frame(height: 1).padding(.leading, 14) }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(step.name).font(.body).foregroundStyle(Theme.text)
                                if let cue = step.cue {
                                    Text(GuideEdits.linked(cue)).font(.subheadline).foregroundStyle(Theme.dim)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14).padding(.vertical, 11)
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }
}

/// One line in a list of guides: its name and how long it is.
struct GuideRow: View {
    let guide: Guide

    var body: some View {
        HStack(spacing: 12) {
            Text(guide.title).font(.headline).foregroundStyle(Theme.text)
            Spacer(minLength: 8)
            Text(GuideEdits.stepsLabel(guide.stepCount)).font(.subheadline).foregroundStyle(Theme.dim)
        }
    }
}

/// A new, empty guide to start editing from.
extension Guide {
    static func blank(position: Int) -> Guide { Guide(title: "", position: position, sections: [GuideSection()]) }
}

/// One guide on the phone: read-only until Edit, then the editor with Save and Cancel. Opened with `startsEditing`
/// (or with no guide, to make a new one) it is only an editor, and Save and Cancel close it.
struct GuideView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    private let id: String?
    private let allowsEditing: Bool
    private let editorOnly: Bool
    @State private var draft: Guide?
    /// What the draft started as, to tell whether there is anything to lose.
    @State private var baseline: Guide?
    @State private var confirmDiscard = false
    @State private var conflict: GuideEdits.SaveAction?

    /// A guide to read, found by id each time so it follows changes made elsewhere and outlives its row in a list.
    init(id: String, allowsEditing: Bool) {
        self.id = id
        self.allowsEditing = allowsEditing
        editorOnly = false
    }

    init(guide: Guide?, allowsEditing: Bool = true, startsEditing: Bool = false) {
        id = guide?.id
        self.allowsEditing = allowsEditing
        editorOnly = guide == nil || startsEditing
        let start = editorOnly ? (guide ?? .blank(position: 0)) : nil
        _draft = State(initialValue: start)
        _baseline = State(initialValue: start)
    }

    private var current: Guide? { id.flatMap { id in model.guides.first { $0.id == id } } }
    private var hasChanges: Bool { draft.map { d in baseline.map { GuideEdits.changed(d, from: $0) } ?? true } ?? false }

    var body: some View {
        Group {
            if draft != nil {
                GuideEditor(draft: Binding(get: { draft ?? .blank(position: 0) }, set: { draft = $0 }))
            } else if let guide = current {
                ScrollView { GuideContent(guide: guide).padding(16) }.background(Theme.background)
            } else {
                ContentUnavailableView("This guide was deleted", systemImage: "trash").background(Theme.background)
            }
        }
        .navigationTitle(draft != nil ? (id == nil ? "New Guide" : "Edit Guide") : (current?.title ?? ""))
        .inlineTitle()
        .navigationBarBackButtonHidden(draft != nil)
        .interactiveDismissDisabled(hasChanges)
        .toolbar {
            if let draft {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if hasChanges { confirmDiscard = true } else { stopEditing() } } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save(draft, force: false) }.disabled(!GuideEdits.canSave(draft)) }
            } else if allowsEditing, let guide = current {
                ToolbarItem(placement: .primaryAction) { Button("Edit") { draft = guide; baseline = guide } }
            }
        }
        .confirmationDialog("Discard your changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard Changes", role: .destructive) { stopEditing() }
            Button("Keep Editing", role: .cancel) {}
        }
        .guideSaveConflict($conflict, saveAnyway: { if let draft { save(draft, force: true) } }, discard: stopEditing)
    }

    private func save(_ draft: Guide, force: Bool) {
        let action = force ? .save : GuideEdits.saveAction(draft: draft, baseline: id == nil ? nil : baseline, current: current)
        switch action {
        case .close: stopEditing()
        case .save:
            if model.saveGuide(GuideEdits.toSave(draft, current: current, newPosition: model.guides.count)) { stopEditing() }
        case .changedElsewhere, .deletedElsewhere: conflict = action
        }
    }

    private func stopEditing() {
        if editorOnly { dismiss() } else { draft = nil; baseline = nil }
    }
}

/// Where a row in a list of guides leads. Declared once per navigation stack with `guideDestinations()`.
struct GuideRoute: Hashable {
    let id: String
    let editable: Bool
}

extension View {
    func guideDestinations() -> some View {
        navigationDestination(for: GuideRoute.self) { GuideView(id: $0.id, allowsEditing: $0.editable) }
    }
}

/// The guides, to read during a workout. Nothing here can change a guide or the workout.
struct GuideListSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.guides) { guide in
                    NavigationLink(value: GuideRoute(id: guide.id, editable: false)) { GuideRow(guide: guide) }
                }
                .listRowBackground(Theme.card)
            }
            .themedList()
            .guideDestinations()
            .navigationTitle("Mobility & Flexibility")
            .inlineTitle()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .forgeTheme()
    }
}

/// The "Mobility & Flexibility" rows on the Workout tab's home: open one to read it, or edit, duplicate, delete and reorder.
struct GuidesHomeSection: View {
    @Environment(AppModel.self) private var model
    @State private var editing: EditTarget?
    @State private var deleting: Guide?

    private struct EditTarget: Identifiable { let guide: Guide?; var id: String { guide?.id ?? "new" } }

    var body: some View {
        Section("Mobility & Flexibility") {
            ForEach(model.guides) { guide in
                NavigationLink(value: GuideRoute(id: guide.id, editable: true)) { GuideRow(guide: guide) }
                    .contextMenu {
                        Button("Edit", systemImage: "pencil") { editing = EditTarget(guide: guide) }
                        Button("Duplicate", systemImage: "plus.square.on.square") { model.duplicateGuide(id: guide.id) }
                        Button("Delete", systemImage: "trash", role: .destructive) { deleting = guide }
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) { deleting = guide }.tint(Theme.danger)
                        Button("Edit") { editing = EditTarget(guide: guide) }.tint(Theme.info)
                    }
            }
            .onMove { source, destination in
                var ids = model.guides.map(\.id)
                ids.move(fromOffsets: source, toOffset: destination)
                model.reorderGuides(ids)
            }
            Button { editing = EditTarget(guide: nil) } label: { Label("New Guide", systemImage: "plus") }
                .sheet(item: $editing) { target in
                    NavigationStack { GuideView(guide: target.guide, startsEditing: true) }.forgeTheme()
                }
                .confirmationDialog("Delete \(deleting?.title ?? "guide")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                                    titleVisibility: .visible) {
                    Button("Delete Guide", role: .destructive) { if let g = deleting { model.deleteGuide(id: g.id) } }
                    Button("Cancel", role: .cancel) {}
                }
        }
        .listRowBackground(Theme.card)
    }
}
