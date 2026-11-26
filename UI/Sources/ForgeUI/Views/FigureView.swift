import ForgeCore
import SwiftUI

/// A step's figure, looping. With Reduce Motion on, or given a `phase`, it is a still picture.
struct FigureView: View {
    let figure: Figure
    /// A fixed moment of the loop (0 to 1) instead of the running animation.
    var phase: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let phase {
                canvas(figure.pose(at: phase))
            } else if reduceMotion {
                canvas(figure.stillPose)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                    canvas(figure.pose(at: timeline.date.timeIntervalSinceReferenceDate / figure.duration))
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.field))
        .accessibilityHidden(true)      // the step's name and cue say what it is
    }

    private func canvas(_ pose: Figure.Pose) -> some View {
        Canvas { context, size in FigureDrawing.draw(figure, pose: pose, in: &context, side: min(size.width, size.height)) }
    }
}

/// How a figure's parts become strokes: one line weight, cream for the body, a faint tone for far-side limbs, vermilion for paths, a thin rule for the floor.
enum FigureDrawing {
    static let lineWidth = 5.0, headRadius = 6.5, dotRadius = 2.2, ringWidth = 1.3, floorWidth = 1.5

    /// The parts in the order they are painted: those behind the body first.
    static func order(_ figure: Figure, pose: Figure.Pose) -> [(part: Figure.Part, isBack: Bool)] {
        let back = Set(pose.back)
        let indexed = figure.parts.enumerated()
        return indexed.filter { back.contains($0.offset) }.map { ($0.element, true) } + indexed.filter { !back.contains($0.offset) }.map { ($0.element, false) }
    }

    static func tint(_ tone: Figure.Tone) -> Color {
        switch tone {
        case .main: Theme.text
        case .dim: Theme.faint
        case .accent: Theme.accent
        }
    }

    static func draw(_ figure: Figure, pose: Figure.Pose, in context: inout GraphicsContext, side: Double) {
        let unit = side / 100
        func point(_ name: String) -> CGPoint? { pose.points[name].flatMap { $0.count == 2 ? CGPoint(x: $0[0] * unit, y: $0[1] * unit) : nil } }
        for (part, isBack) in order(figure, pose: pose) {
            let points = part.points.compactMap(point)
            guard points.count == part.points.count, let first = points.first else { continue }
            let color = isBack ? Theme.faint : tint(part.tone)
            let stroke = StrokeStyle(lineWidth: lineWidth * unit, lineCap: .round, lineJoin: .round)
            switch part.kind {
            case .line:
                var path = Path(); path.addLines(points)
                context.stroke(path, with: .color(color), style: stroke)
            case .curve:
                let end = points[2], through = points[1]
                var path = Path(); path.move(to: first)
                // The control point that makes the curve pass through the middle point at its halfway mark.
                path.addQuadCurve(to: end, control: CGPoint(x: 2 * through.x - (first.x + end.x) / 2, y: 2 * through.y - (first.y + end.y) / 2))
                context.stroke(path, with: .color(color), style: stroke)
            case .head, .dot:
                let r = (part.kind == .head ? headRadius : dotRadius) * unit
                context.fill(Path(ellipseIn: CGRect(x: first.x - r, y: first.y - r, width: 2 * r, height: 2 * r)), with: .color(color))
            case .floor:
                var path = Path(); path.addLines(points)
                context.stroke(path, with: .color(Theme.line), style: StrokeStyle(lineWidth: floorWidth * unit, lineCap: .round))
            case .ring:
                let radii = points[1]
                let path = Path(ellipseIn: CGRect(x: first.x - radii.x, y: first.y - radii.y, width: 2 * radii.x, height: 2 * radii.y))
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: ringWidth * unit, dash: [2.5 * unit, 3 * unit]))
            }
        }
    }
}
