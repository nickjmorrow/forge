import Charts
import ForgeCore
import SwiftUI

/// Bodyweight by day: a trend, the entries, and a way to add or delete one.
struct BodyweightView: View {
    @Environment(AppModel.self) private var model
    @State private var adding = false

    private static let dayFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private struct Point: Identifiable { let date: Date; let value: Double; var id: Date { date } }

    private var points: [Point] {
        model.bodyweights.reversed().compactMap { e in
            Self.dayFormat.date(from: e.date).map { Point(date: $0, value: model.unit == .lb ? Units.pounds(fromKg: e.kg) : e.kg) }
        }
    }

    var body: some View {
        List {
            if points.count > 1 {
                Section("Trend") {
                    Chart(points) {
                        LineMark(x: .value("Day", $0.date), y: .value("Weight", $0.value)).foregroundStyle(Theme.accent)
                        PointMark(x: .value("Day", $0.date), y: .value("Weight", $0.value)).foregroundStyle(Theme.accent)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 160)
                }.listRowBackground(Theme.card)
            }
            Section("Entries") {
                ForEach(model.bodyweights, id: \.date) { e in
                    HStack {
                        Text(Self.dayFormat.date(from: e.date)?.formatted(date: .abbreviated, time: .omitted) ?? e.date)
                        Spacer()
                        Text(Units.format(kg: e.kg, unit: model.unit) + " " + model.unit.rawValue).monospacedDigit().foregroundStyle(Theme.dim)
                    }
                    .swipeActions { Button("Delete", role: .destructive) { model.deleteBodyweight(date: e.date) }.tint(Theme.danger) }
                    .contextMenu { Button("Delete", systemImage: "trash", role: .destructive) { model.deleteBodyweight(date: e.date) } }
                }
                if model.bodyweights.isEmpty { Text("No entries yet. Add one with +.").foregroundStyle(Theme.dim) }
            }.listRowBackground(Theme.card)
        }
        .themedList()
        .navigationTitle("Bodyweight")
        .toolbar { ToolbarItem(placement: .primaryAction) { Button("Add entry", systemImage: "plus") { adding = true } } }
        .sheet(isPresented: $adding) { AddBodyweightSheet().forgeTheme() }
    }
}

private struct AddBodyweightSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var day = Date()
    @State private var text = ""

    private var value: Double? { Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")).flatMap { $0 > 0 ? $0 : nil } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Day", selection: $day, in: ...Date(), displayedComponents: .date)
                    HStack {
                        Text("Weight (\(model.unit.rawValue))")
                        Spacer()
                        TextField("", text: $text, prompt: Text("0").foregroundStyle(Theme.dim)).multilineTextAlignment(.trailing).numericKeyboard().frame(width: 100)
                    }
                }.listRowBackground(Theme.card)
            }
            .themedList()
            .navigationTitle("Add Bodyweight")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { if let value { model.addBodyweight(on: day, value: value); dismiss() } }.disabled(value == nil)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 240)
        #endif
    }
}
