import SwiftUI

/// Plate: the app icon's engraved plate. Oxblood ground, a vermilion ring, brass line work and a cream flame.
/// Vermilion is the one tint and belongs to things you can act on; brass is kept for records, completion is the green of
/// copper patina, destructive is rose, everything else is oxblood and cream.
public enum Theme {
    // Surfaces, darkest to lightest
    public static let background = Color(hex: 0x140a0c)   // oxblood 950: screens
    public static let bar = Color(hex: 0x1a0d10)          // oxblood 900: bars and sheets
    public static let card = Color(hex: 0x221216)         // oxblood 850: grouped content
    public static let field = Color(hex: 0x2e191e)        // oxblood 800: inputs and quiet buttons
    public static let raised = Color(hex: 0x42242b)       // oxblood 700: pressed and selected fills
    public static let line = Color(hex: 0x57323a)         // oxblood 600: separators and outlines

    // Text. `faint` is 3.9:1 on a card, so it is for decoration and disabled states only, never for reading.
    public static let text = Color(hex: 0xf1e7d3)         // the flame's cream
    public static let dim = Color(hex: 0xc4ab9c)          // 8.1:1 on a card: secondary text and placeholders
    public static let faint = Color(hex: 0x8c706a)

    public static let accent = Color(hex: 0xe8794a)       // vermilion, 6.3:1 on a card
    public static let accentBright = Color(hex: 0xf39566)
    public static let flameTop = Color(hex: 0xf08c55)     // the ring, lit from above: primary buttons only
    public static let flameBottom = Color(hex: 0xd06035)
    public static let gold = Color(hex: 0xdcb565)         // brass: personal records only
    public static let done = Color(hex: 0x86d3aa)         // patina
    public static let danger = Color(hex: 0xff6b8f)       // rose, kept clear of the vermilion accent
    public static let info = Color(hex: 0x86b9d8)         // quenched steel
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255)
    }

    /// Kept as aliases so older call sites read the theme.
    static let forge = Theme.accent
    static var cardBackground: Color { Theme.card }
    static var screenBackground: Color { Theme.background }
}

/// Motion: quick and decelerating, never bouncy. With Reduce Motion on, movement becomes a short fade and state changes still read.
extension Animation {
    static let snappyUI = Animation.snappy(duration: 0.28)
    static let settleUI = Animation.smooth(duration: 0.4)
}

private struct MotionModifier<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: Value
    func body(content: Content) -> some View { content.animation(reduceMotion ? .easeOut(duration: 0.12) : animation, value: value) }
}

private struct AppearTransition: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let edge: Edge
    func body(content: Content) -> some View {
        content.transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: edge).combined(with: .opacity), removal: .opacity.combined(with: .scale(scale: 0.96))))
    }
}

extension View {
    /// Animates changes of `value`, honoring Reduce Motion.
    func motion<Value: Equatable>(_ animation: Animation = .snappyUI, value: Value) -> some View { modifier(MotionModifier(animation: animation, value: value)) }

    /// Rows and bars that arrive from an edge and leave with a fade.
    func appears(from edge: Edge = .bottom) -> some View { modifier(AppearTransition(edge: edge)) }
}

/// The primary action: a lit-vermilion gradient, oxblood label (5.0:1 at the darkest), a 44-pt target.
struct AccentButtonStyle: ButtonStyle {
    var compact = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.background)
            .frame(maxWidth: compact ? nil : .infinity, minHeight: 44)
            .padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(LinearGradient(colors: configuration.isPressed ? [Theme.accentBright, Theme.accent] : [Theme.flameTop, Theme.flameBottom], startPoint: .top, endPoint: .bottom)))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

/// A secondary action: an oxblood fill with a vermilion label.
struct QuietButtonStyle: ButtonStyle {
    var fills = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: fills ? .infinity : nil, minHeight: 44)
            .padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(configuration.isPressed ? Theme.raised : Theme.field))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

extension View {
    /// The app's window-level look: dark, vermilion tint, oxblood ground.
    func forgeTheme() -> some View {
        self.preferredColorScheme(.dark)
            .tint(Theme.accent)                       // buttons and links take the tint; a root foregroundStyle would flatten them to text color
            .background(Theme.background.ignoresSafeArea())
    }

    /// For a `List` or `Form`: oxblood ground instead of the system gray.
    func themedList() -> some View {
        self.scrollContentBackground(.hidden).background(Theme.background.ignoresSafeArea())
    }
}
