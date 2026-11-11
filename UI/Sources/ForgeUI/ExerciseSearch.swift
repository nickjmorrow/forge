import ForgeCore
import Foundation

/// Forgiving exercise search: every typed word has to land on some word of the exercise (name, equipment or muscle), as a
/// prefix, a substring, its letters in order ("bnch" → bench) or with a typo ("extention" → extension). Best matches first.
public enum ExerciseSearch {
    public static func results(_ query: String, in exercises: [Exercise]) -> [Exercise] {
        let tokens = words(query)
        guard !tokens.isEmpty else { return exercises }
        let whole = normalized(query)
        let scored: [(exercise: Exercise, score: Double)] = exercises.compactMap { e in
            guard let s = score(tokens, query: whole, exercise: e) else { return nil }
            return (e, s)
        }
        return scored.sorted(by: ranksBefore).map(\.exercise)
    }

    private static func ranksBefore(_ a: (exercise: Exercise, score: Double), _ b: (exercise: Exercise, score: Double)) -> Bool {
        if a.score != b.score { return a.score > b.score }
        return a.exercise.name.localizedCaseInsensitiveCompare(b.exercise.name) == .orderedAscending
    }

    static func score(_ tokens: [String], query: String, exercise e: Exercise) -> Double? {
        let nameWords = words(e.name)
        let otherWords = [e.equipment, e.primaryMuscle].compactMap { $0 }.flatMap { words($0.replacingOccurrences(of: "_", with: " ")) }
        var total = 0.0
        for token in tokens {
            let best = max(nameWords.map { match(token, $0) }.max() ?? 0, (otherWords.map { match(token, $0) }.max() ?? 0) * 0.5)
            if best == 0 { return nil }
            total += best
        }
        if normalized(e.name).contains(query) { total += 2 }
        return total
    }

    /// How well one typed word fits one word of the exercise; 0 is no match.
    static func match(_ token: String, _ word: String) -> Double {
        if word == token { return 4 }
        if word.hasPrefix(token) { return 3 }
        if word.contains(token) { return 2 }
        guard token.count >= 3 else { return 0 }
        if isSubsequence(token, of: word) { return 1 }
        let allowedTypos = token.count >= 6 ? 2 : 1
        let prefix = String(word.prefix(token.count))
        if editDistance(token, prefix) <= allowedTypos || editDistance(token, word) <= allowedTypos { return 1 }
        return 0
    }

    static func words(_ text: String) -> [String] {
        normalized(text).split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased().trimmingCharacters(in: .whitespaces)
    }

    static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var rest = Substring(haystack)
        for c in needle {
            guard let i = rest.firstIndex(of: c) else { return false }
            rest = rest[rest.index(after: i)...]
        }
        return true
    }

    static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }
}
