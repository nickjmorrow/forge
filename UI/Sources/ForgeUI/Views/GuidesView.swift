#if os(macOS)
import ForgeCore
import SwiftUI

/// Mac guides: the list on the left (drag to reorder), the whole selected guide on the right, read-only until you press Edit.
struct GuidesView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: String?
    /// The guide just made with New Guide, which opens straight into editing.
    @State private var created: String?
    @State private var deleting: Guide?
    /// Set by the open guide while it has unsaved edits; leaving it then asks first.
    @Binding var hasUnsavedEdits: Bool
    @State private var pendingLeave: Leave?

    private enum Leave { case select(String), new }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                guideList.frame(width: 240)
                Rectangle().fill(Theme.line.opacity(0.5)).frame(width: 1).ignoresSafeArea()
                detail.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Theme.background)
            .navigationTitle("Mobility & Flexibility")
            .onAppear { if selection == nil { selection = model.guides.first?.id } }
            .onChange(of: model.guides.map(\.id)) { _, ids in
                if let s = selection, !ids.contains(s) { selection = ids.first }
            }
            .confirmationDialog("Delete \(deleting?.title ?? "guide")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                                titleVisibility: .visible) {
                Button("Delete Guide", role: .destructive) { if let g = deleting { model.deleteGuide(id: g.id) } }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog("Discard your changes?", isPresented: Binding(get: { pendingLeave != nil }, set: { if !$0 { pendingLeave = nil } }),
                                titleVisibility: .visible) {
                Button("Discard Changes", role: .destructive) { if let l = pendingLeave { go(l) } }
                Button("Keep Editing", role: .cancel) {}
            } message: { Text("This guide has edits that haven't been saved.") }
        }
    }

    /// Switching guides with unsaved edits asks first, since the draft would be lost.
    private func leave(_ to: Leave) {
        if case .select(let id) = to, id == selection { return }
        if hasUnsavedEdits { pendingLeave = to } else { go(to) }
    }

    private func go(_ to: Leave) {
        switch to {
        case .select(let id): selection = id
        case .new:
            let guide = Guide(title: "New Guide", position: model.guides.count, sections: [GuideSection()])
            if model.saveGuide(guide) { created = guide.id; selection = guide.id }
        }
    }

    private var guideList: some View {
        // Selection is drawn here rather than by the system, which would paint it in the Mac's accent color instead of ink.
        List {
            ForEach(model.guides) { g in
                Button { leave(.select(g.id)) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(g.title).font(.body.weight(.medium)).foregroundStyle(Theme.text).lineLimit(1)
                        Text(GuideEdits.stepsLabel(g.stepCount)).font(.caption).foregroundStyle(Theme.dim)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(selection == g.id ? Theme.raised : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 1, leading: 10, bottom: 1, trailing: 10))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .accessibilityAddTraits(selection == g.id ? .isSelected : [])
                .contextMenu {
                    Button("Duplicate", systemImage: "plus.square.on.square") { model.duplicateGuide(id: g.id) }
                    Divider()
                    Button("Delete", systemImage: "trash", role: .destructive) { deleting = g }
                }
            }
            .onMove { source, destination in
                var ids = model.guides.map(\.id)
                ids.move(fromOffsets: source, toOffset: destination)
                model.reorderGuides(ids)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.bar)
    }

    @ViewBuilder private var detail: some View {
        if let guide = model.guides.first(where: { $0.id == selection }) {
            GuideDetail(guide: guide, startsEditing: created == guide.id, hasUnsavedEdits: $hasUnsavedEdits,
                        onNew: { leave(.new) }, onDelete: { deleting = guide })
                .id(guide.id)
        } else {
            ContentUnavailableView {
                Label(model.guides.isEmpty ? "No guides yet" : "Select a guide", systemImage: "book")
            } description: {
                if model.guides.isEmpty { Text("A guide is a list of steps to read through, like a mobility or stretching sequence.") }
            } actions: {
                if model.guides.isEmpty { Button("New Guide") { leave(.new) }.buttonStyle(AccentButtonStyle(compact: true)) }
            }
            .toolbar { ToolbarItem(placement: .primaryAction) { Button("New Guide", systemImage: "plus") { leave(.new) }.help("New Guide") } }
        }
    }
}

/// One guide laid out whole. It opens read-only; Edit starts a draft that is written only by Save.
private struct GuideDetail: View {
    @Environment(AppModel.self) private var model
    let guide: Guide
    let onNew: () -> Void
    let onDelete: () -> Void
    @Binding var hasUnsavedEdits: Bool
    @State private var draft: Guide
    @State private var editing: Bool

    init(guide: Guide, startsEditing: Bool, hasUnsavedEdits: Binding<Bool>, onNew: @escaping () -> Void, onDelete: @escaping () -> Void) {
        self.guide = guide
        self.onNew = onNew
        self.onDelete = onDelete
        _hasUnsavedEdits = hasUnsavedEdits
        _draft = State(initialValue: guide)
        _editing = State(initialValue: startsEditing)
    }

    var body: some View {
        Group {
            if editing {
                GuideEditor(draft: $draft).frame(maxWidth: 640)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(guide.title).font(.largeTitle.weight(.semibold)).foregroundStyle(Theme.text)
                        GuideContent(guide: guide)
                    }
                    .frame(maxWidth: 640, alignment: .leading)
                    .padding(28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .toolbar {
            if editing {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { draft = guide; editing = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { if model.saveGuide(GuideEdits.tidied(draft)) { editing = false } }.disabled(!GuideEdits.canSave(draft))
                }
            } else {
                ToolbarItem(placement: .primaryAction) { Button("Delete", systemImage: "trash", action: onDelete).help("Delete Guide") }
                ToolbarItem(placement: .primaryAction) { Button("Edit") { draft = guide; editing = true } }
                ToolbarItem(placement: .primaryAction) { Button("New Guide", systemImage: "plus", action: onNew).help("New Guide") }
            }
        }
        .onChange(of: editing ? GuideEdits.changed(draft, from: guide) : false) { _, dirty in hasUnsavedEdits = dirty }
        .onDisappear { hasUnsavedEdits = false }
    }
}
#endif
