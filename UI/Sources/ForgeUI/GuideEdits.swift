import ForgeCore
import Foundation

/// The logic behind the guide screens, kept apart from the views so it can be tested.
enum GuideEdits {
    /// A guide laid flat for reordering: each section's header, then its steps.
    enum Row: Hashable {
        case section(Int)
        case step(section: Int, step: Int)
    }

    static func rows(_ g: Guide) -> [Row] {
        g.sections.enumerated().flatMap { s, section in
            [Row.section(s)] + section.steps.indices.map { Row.step(section: s, step: $0) }
        }
    }

    /// Moves the row at `from` so it sits before the row now at `to` (the convention of SwiftUI's `onMove`; `to` may be the row count).
    /// A step joins the section whose header ends up above it, or goes to the top of the first section if dropped above every header.
    /// A header takes its whole section along; dropped among another section's steps, the section lands after that one.
    static func move(_ g: Guide, from: Int, to: Int) -> Guide {
        let rows = rows(g)
        guard rows.indices.contains(from), (0...rows.count).contains(to) else { return g }
        var result = g
        switch rows[from] {
        case let .section(moving):
            let headersAbove = rows[..<to].filter { if case let .section(s) = $0 { return s != moving } else { return false } }.count
            result.sections.insert(result.sections.remove(at: moving), at: headersAbove)
        case .step:
            var flat = rows
            flat.insert(flat.remove(at: from), at: to > from ? to - 1 : to)
            var sections = g.sections.map { GuideSection(title: $0.title, steps: []) }
            var current = 0, orphans: [GuideStep] = []
            var seenHeader = false
            for row in flat {
                switch row {
                case let .section(s): current = s; seenHeader = true
                case let .step(s, i):
                    let step = g.sections[s].steps[i]
                    if seenHeader { sections[current].steps.append(step) } else { orphans.append(step) }
                }
            }
            sections[0].steps.insert(contentsOf: orphans, at: 0)
            result.sections = sections
        }
        return result
    }

    /// "1 step", "26 steps"
    static func stepsLabel(_ count: Int) -> String { "\(count) \(count == 1 ? "step" : "steps")" }

    /// The text with any web addresses in it made tappable.
    static func linked(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return result }
        for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let url = match.url, url.scheme == "http" || url.scheme == "https",
                  let range = Range(match.range, in: text), let lower = AttributedString.Index(range.lowerBound, within: result),
                  let upper = AttributedString.Index(range.upperBound, within: result) else { continue }
            result[lower..<upper].link = url
        }
        return result
    }

    /// The draft without the steps that were added and left completely empty.
    static func tidied(_ g: Guide) -> Guide {
        func blank(_ s: String?) -> Bool { (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var result = g
        for i in result.sections.indices { result.sections[i].steps.removeAll { blank($0.name) && blank($0.cue) } }
        return result
    }

    /// True once the draft has a title and every step that would be kept has a name.
    static func canSave(_ g: Guide) -> Bool { (try? tidied(g).normalized()) != nil }

    /// Whether saving `draft` would change anything about `original` (stray spaces and empty steps and cues don't count).
    static func changed(_ draft: Guide, from original: Guide) -> Bool {
        guard let a = try? tidied(draft).normalized(), let b = try? tidied(original).normalized() else { return tidied(draft) != tidied(original) }
        return a != b
    }
}
