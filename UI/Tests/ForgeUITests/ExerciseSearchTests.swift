import ForgeCore
import Testing
@testable import ForgeUI

@Suite struct ExerciseSearchTests {
    let library = [
        Exercise(name: "Bench Press (Barbell)", equipment: "barbell", primaryMuscle: "chest"),
        Exercise(name: "Leg Extension", equipment: "machine", primaryMuscle: "quadriceps"),
        Exercise(name: "Single Leg Extension (Machine)", equipment: "machine", primaryMuscle: "quadriceps"),
        Exercise(name: "Lat Pulldown (Cable)", equipment: "cable", primaryMuscle: "lats"),
        Exercise(name: "Squat (Barbell)", equipment: "barbell", primaryMuscle: "quadriceps"),
    ]

    private func names(_ query: String) -> [String] { ExerciseSearch.results(query, in: library).map(\.name) }

    @Test func emptySearchKeepsTheLibraryOrder() {
        #expect(names("  ") == library.map(\.name))
    }

    @Test func wordsMatchInAnyOrder() {
        #expect(names("press bench") == ["Bench Press (Barbell)"])
    }

    @Test func typosAndDroppedLettersStillMatch() {
        #expect(names("extention").first == "Leg Extension")
        #expect(names("bnch") == ["Bench Press (Barbell)"])
        #expect(names("pulldwn") == ["Lat Pulldown (Cable)"])
    }

    @Test func closerMatchesRankFirst() {
        #expect(names("leg ext") == ["Leg Extension", "Single Leg Extension (Machine)"])
    }

    @Test func equipmentAndMuscleCountButLessThanTheName() {
        #expect(names("barbell") == ["Bench Press (Barbell)", "Squat (Barbell)"])
        #expect(names("quad").count == 3)
    }

    @Test func unrelatedTextMatchesNothing() {
        #expect(names("zzz").isEmpty)
        #expect(names("bench zzz").isEmpty)
    }
}
