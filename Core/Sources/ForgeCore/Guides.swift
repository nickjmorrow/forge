import Foundation

/// The shape an agent or script sends to create or replace a guide (always the whole guide).
public struct GuideInput: Codable, Sendable {
    public var id: String?
    public var title: String
    public var notes: String?
    public var position: Int?
    public var sections: [Section]

    public struct Section: Codable, Sendable {
        public var title: String?
        public var steps: [Step]
    }

    public struct Step: Codable, Sendable {
        public var name: String
        public var cue: String?
    }
}

extension Guide {
    /// The guide as it should be saved: surrounding whitespace removed, empty notes and cues dropped.
    /// A blank title or step name is refused.
    public func normalized() throws -> Guide {
        func trimmed(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
        func optional(_ s: String?) -> String? { s.map(trimmed).flatMap { $0.isEmpty ? nil : $0 } }
        var g = self
        g.title = trimmed(title)
        guard !g.title.isEmpty else { throw ForgeError.invalid("a guide needs a title") }
        g.notes = optional(notes)
        g.sections = try sections.map { section in
            GuideSection(title: trimmed(section.title), steps: try section.steps.map { step in
                let name = trimmed(step.name)
                guard !name.isEmpty else { throw ForgeError.invalid("every step in a guide needs a name") }
                return GuideStep(name: name, cue: optional(step.cue))
            })
        }
        return g
    }
}

extension Forge {
    /// Creates a guide, or replaces the one with the same id (keeping its creation time and, unless given, its position).
    @discardableResult
    public func putGuide(_ input: GuideInput, author: Author) throws -> Guide {
        let now = clock()
        let existing = try input.id.flatMap { try guide(id: $0) }
        let guide = try Guide(id: input.id ?? UUID().uuidString, title: input.title, notes: input.notes,
                              position: try input.position ?? existing?.position ?? guides().count,
                              sections: input.sections.map { s in GuideSection(title: s.title ?? "", steps: s.steps.map { GuideStep(name: $0.name, cue: $0.cue) }) },
                              createdAt: existing?.createdAt ?? now, updatedAt: now).normalized()
        try perform([.putGuide(guide)], author: author)
        return guide
    }

    /// Puts the guides in the given order. `ids` must be exactly the existing guide ids. Returns the change id, or nil if nothing moved.
    @discardableResult
    public func reorderGuides(_ ids: [String], author: Author) throws -> Int64? {
        let existing = try guides()
        guard !existing.isEmpty else { throw ForgeError.invalid("there are no guides to reorder") }
        guard ids.count == existing.count, Set(ids) == Set(existing.map(\.id)) else {
            throw ForgeError.invalid("reorder needs exactly the \(existing.count) existing guide ids")
        }
        let byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        let now = clock()
        let ops: [Op] = ids.enumerated().compactMap { i, id in
            var g = byID[id]!
            guard g.position != i else { return nil }
            g.position = i
            g.updatedAt = now
            return .putGuide(g)
        }
        return ops.isEmpty ? nil : try perform(ops, author: author)
    }
}
