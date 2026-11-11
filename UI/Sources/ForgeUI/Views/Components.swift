import ForgeCore
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

extension View {
    func numericKeyboard() -> some View {
        #if os(iOS)
        return self.keyboardType(.decimalPad)
        #else
        return self
        #endif
    }

    func inlineTitle() -> some View {
        #if os(iOS)
        return self.navigationBarTitleDisplayMode(.inline)
        #else
        return self
        #endif
    }
}

/// A number field that keeps what is being typed (so "62." survives) and reports each edit.
/// 44 pt tall, ink fill, an ember outline while it has focus, placeholders at 7:1.
struct ValueField: View {
    let placeholder: String
    /// What the model currently holds for this field; the field follows it unless it is being typed in.
    let initial: String
    /// Compact fields sit inside a set chip on the Mac routine editor: no box of their own, a raised fill while typing.
    let compact: Bool
    let alignment: TextAlignment
    let onChange: (String) -> Void
    @State private var text: String
    @FocusState private var focused: Bool

    init(placeholder: String = "", initial: String, alignment: TextAlignment = .center, compact: Bool = false, onChange: @escaping (String) -> Void) {
        self.placeholder = placeholder
        self.initial = initial
        self.alignment = alignment
        self.compact = compact
        self.onChange = onChange
        _text = State(initialValue: initial)
    }

    var body: some View {
        let field = TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Theme.dim))
            .focused($focused)
            .multilineTextAlignment(alignment)
            .numericKeyboard()
            .textFieldStyle(.plain)
            .onChange(of: text) { _, new in onChange(new) }
            .onChange(of: initial) { _, new in if !focused, new != text { text = new } }
            .onChange(of: focused) { _, isFocused in if isFocused { selectAllText() } }
        if compact {
            field
                .font(.callout.monospacedDigit())
                .frame(height: 22)
                .padding(.horizontal, 3)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(focused ? Theme.raised : .clear))
        } else {
            field
                .font(.body.monospacedDigit())
                .frame(minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.field))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(focused ? Theme.accent : Theme.line.opacity(0.7), lineWidth: focused ? 1.5 : 1))
        }
    }

    /// Tapping a number selects it, so typing replaces it. Deferred a turn because the tap places the cursor after focus lands.
    private func selectAllText() {
        #if os(iOS)
        DispatchQueue.main.async { UIApplication.shared.sendAction(#selector(UIResponder.selectAll(_:)), to: nil, from: nil, for: nil) }
        #endif
    }
}

enum Format {
    static func date(_ ms: Int64) -> Date { Date(timeIntervalSince1970: Double(ms) / 1000) }

    static func volume(kg: Double, unit: WeightUnit) -> String {
        let value = unit == .lb ? Units.pounds(fromKg: kg) : kg
        return value.formatted(.number.precision(.fractionLength(0))) + " " + unit.rawValue
    }

    static func duration(seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return m > 0 ? "\(m)m" : "\(seconds)s"
    }
}

enum Muscles {
    static let all = ["chest", "shoulders", "triceps", "biceps", "forearms", "lats", "upper_back", "lower_back", "traps", "abdominals",
                      "quadriceps", "hamstrings", "glutes", "calves", "adductors", "abductors", "cardio", "full_body", "other"]

    static func title(_ raw: String) -> String { raw.replacingOccurrences(of: "_", with: " ").capitalized }
}

extension FinishSummary: Identifiable { public var id: String { workoutID } }

/// A summary stated in a sentence-sized line (no tiles): "1h 5m · 12,340 lb · 18 sets".
struct StatLine: View {
    let parts: [String]
    var body: some View {
        Text(parts.joined(separator: "  ·  "))
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(Theme.dim)
    }
}

extension View {
    /// Swipe left to reveal Delete, or swipe all the way to delete at once. For rows outside a `List`, which has its own.
    func swipeToDelete(label: String, perform onDelete: @escaping () -> Void) -> some View { modifier(SwipeToDelete(label: label, onDelete: onDelete)) }
}

private struct SwipeToDelete: ViewModifier {
    let label: String
    let onDelete: () -> Void
    /// The finger's sideways travel; it springs back by itself if the system cancels the drag (a scroll takes over).
    @GestureState(resetTransaction: Transaction(animation: .snappyUI)) private var drag: CGFloat = 0
    @State private var isOpen = false
    private let revealWidth: CGFloat = 76
    private let fullSwipe: CGFloat = 180

    private var offset: CGFloat { min(0, (isOpen ? -revealWidth : 0) + drag) }

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .background(alignment: .trailing) {
                if offset < 0 {
                    Button(role: .destructive) { delete() } label: {
                        Image(systemName: "trash").font(.headline)
                            .frame(width: max(revealWidth, -offset)).frame(maxHeight: .infinity)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.danger))
                            .foregroundStyle(Theme.background)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(label)
                }
            }
            .clipped()          // the row slides under its own edge, not over the card's padding
            // Simultaneous, so a vertical drag that starts on a row still scrolls the workout.
            .simultaneousGesture(
                DragGesture(minimumDistance: 20)
                    .updating($drag) { value, drag, _ in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        drag = value.translation.width
                    }
                    .onEnded { value in
                        // The predicted end, so a quick flick counts as a full swipe.
                        let travel = abs(value.translation.width) > abs(value.translation.height) ? value.predictedEndTranslation.width : 0
                        let end = (isOpen ? -revealWidth : 0) + travel
                        if end < -fullSwipe { delete(); return }
                        withAnimation(.snappyUI) { isOpen = end < -revealWidth / 2 }
                    }
            )
            .accessibilityAction(named: label, onDelete)
    }

    private func delete() {
        withAnimation(.snappyUI) { isOpen = false }
        onDelete()
    }
}
