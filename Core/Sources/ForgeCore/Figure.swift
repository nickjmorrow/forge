import Foundation

/// A small looping line drawing that shows a movement: named points in a 100 × 100 box (y grows downward), the strokes
/// that join them, and the poses the points pass through. It is plain data, so it syncs with the step it belongs to.
public struct Figure: Codable, Sendable, Equatable {
    /// Seconds for one loop through every frame and back to the first.
    public var duration: Double
    public var easing: Easing
    /// Drawn in this order, so later parts lie on top.
    public var parts: [Part]
    /// The first frame places every point; later frames list only the points that have moved from the first.
    public var frames: [Frame]

    public enum Easing: String, Codable, Sendable {
        /// Slows into each pose and out of it: for movements that go from one position to another.
        case ease
        /// Constant speed: for circles and swings sampled as many frames.
        case linear
    }

    public enum Tone: String, Codable, Sendable {
        case main
        /// A limb on the far side of the body.
        case dim
        /// A path or marker that shows where a joint travels.
        case accent
    }

    public struct Part: Codable, Sendable, Equatable {
        public var kind: Kind
        public var points: [String]
        public var tone: Tone

        public enum Kind: String, Codable, Sendable {
            /// A limb: a stroke through two or more points.
            case line
            /// A spine: a smooth stroke from the first point to the third that passes through the second.
            case curve
            /// A filled head centred on one point.
            case head
            /// A small filled marker on one point.
            case dot
            /// A dashed oval: centred on the first point, the second point holds its two radii.
            case ring
            /// A thin line between two points for the floor, a wall or a counter.
            case floor
        }

        public init(kind: Kind, points: [String], tone: Tone = .main) { self.kind = kind; self.points = points; self.tone = tone }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            kind = try c.decode(Kind.self, forKey: .kind)
            points = try c.decode([String].self, forKey: .points)
            tone = try c.decodeIfPresent(Tone.self, forKey: .tone) ?? .main
        }
    }

    public struct Frame: Codable, Sendable, Equatable {
        public var points: [String: [Double]]
        /// Parts (by index) that are behind the body in this pose: drawn first and dim.
        public var back: [Int]?

        public init(points: [String: [Double]], back: [Int]? = nil) { self.points = points; self.back = back }
    }

    /// Where every point is at one moment.
    public struct Pose: Sendable, Equatable {
        public var points: [String: [Double]]
        public var back: [Int]
    }

    public init(duration: Double, easing: Easing = .ease, parts: [Part], frames: [Frame]) {
        self.duration = duration; self.easing = easing; self.parts = parts; self.frames = frames
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        duration = try c.decode(Double.self, forKey: .duration)
        easing = try c.decodeIfPresent(Easing.self, forKey: .easing) ?? .ease
        parts = try c.decode([Part].self, forKey: .parts)
        frames = try c.decode([Frame].self, forKey: .frames)
    }

    /// The pose at `phase` of the loop: 0 is the first frame, 1 is the first frame again.
    public func pose(at phase: Double) -> Pose {
        guard let first = frames.first else { return Pose(points: [:], back: []) }
        let count = frames.count
        guard count > 1, phase.isFinite else { return Pose(points: first.points, back: first.back ?? []) }
        let position = (phase - phase.rounded(.down)) * Double(count)
        let from = min(Int(position), count - 1), to = (from + 1) % count
        var t = position - Double(from)
        if easing == .ease { t = t * t * (3 - 2 * t) }
        let a = first.points.merging(frames[from].points) { $1 }, b = first.points.merging(frames[to].points) { $1 }
        var points: [String: [Double]] = [:]
        for (name, p) in a {
            guard let q = b[name], p.count == 2, q.count == 2 else { points[name] = p; continue }
            points[name] = [p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t]
        }
        return Pose(points: points, back: frames[t < 0.5 ? from : to].back ?? [])
    }

    /// One pose that stands for the movement when it can't be animated (Reduce Motion): the second frame, where it has left the start.
    public var stillPose: Pose { pose(at: frames.count > 1 ? 1 / Double(frames.count) : 0) }

    /// Refuses a figure that could not be drawn.
    public func validate() throws {
        func fail(_ what: String) -> ForgeError { .invalid("a step's figure \(what)") }
        guard duration.isFinite, duration >= 0.5, duration <= 60 else { throw fail("needs a duration between 0.5 and 60 seconds") }
        guard let first = frames.first, frames.count <= 64 else { throw fail("needs between 1 and 64 frames") }
        guard !parts.isEmpty, parts.count <= 40 else { throw fail("needs between 1 and 40 parts") }
        for frame in frames {
            guard frame.points.count <= 60 else { throw fail("has too many points") }
            for (name, p) in frame.points {
                guard p.count == 2, p.allSatisfy({ $0.isFinite && $0 >= -100 && $0 <= 200 }) else { throw fail("has a bad position for point “\(name)”") }
                guard first.points[name] != nil else { throw fail("moves point “\(name)”, which the first frame does not place") }
            }
            guard (frame.back ?? []).allSatisfy(parts.indices.contains) else { throw fail("puts a part that does not exist behind the body") }
        }
        for part in parts {
            let wanted: ClosedRange<Int> = switch part.kind {
            case .line: 2...12
            case .curve: 3...3
            case .head, .dot: 1...1
            case .ring, .floor: 2...2
            }
            guard wanted.contains(part.points.count) else { throw fail("has a \(part.kind.rawValue) with the wrong number of points") }
            for name in part.points where first.points[name] == nil { throw fail("uses point “\(name)”, which the first frame does not place") }
        }
    }
}
