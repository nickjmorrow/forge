import Foundation
import Testing
@testable import ForgeCore

private let templatesJSON = """
{"page":1,"page_count":1,"exercise_templates":[
 {"id":"79D0BB3A","title":"Bench Press (Barbell)","type":"weight_reps","primary_muscle_group":"chest","secondary_muscle_groups":["triceps","shoulders"],"equipment":"barbell","is_custom":false},
 {"id":"D8F7F851","title":"Cycling","type":"distance_duration","primary_muscle_group":"cardio","secondary_muscle_groups":[],"equipment":"machine","is_custom":false},
 {"id":"C1","title":"Bench Press (Barbell)","type":"weight_reps","primary_muscle_group":"chest","secondary_muscle_groups":[],"equipment":"barbell","is_custom":true},
 {"id":"A1","title":"Assisted Pull Up","type":"bodyweight_assisted_reps","primary_muscle_group":"lats","secondary_muscle_groups":["biceps"],"equipment":"machine","is_custom":false}
]}
"""

private let routinesJSON = """
{"page":1,"page_count":1,"routines":[
 {"id":"rt1","title":"Upper Body","folder_id":null,"updated_at":"2026-10-13T20:26:39.637Z","created_at":"2026-04-20T16:12:44.396Z","exercises":[
  {"index":0,"title":"Cycling","notes":null,"exercise_template_id":"D8F7F851","superset_id":null,"rest_seconds":0,
   "sets":[{"index":0,"type":"normal","weight_kg":null,"reps":null,"distance_meters":null,"duration_seconds":null,"custom_metric":null}]},
  {"index":1,"title":"Bench Press (Barbell)","notes":"pause","exercise_template_id":"79D0BB3A","superset_id":null,"rest_seconds":120,
   "sets":[{"index":0,"type":"warmup","weight_kg":43.09127515,"reps":12,"distance_meters":null,"duration_seconds":null,"custom_metric":null},
           {"index":1,"type":"normal","weight_kg":61.23496995,"reps":6,"distance_meters":null,"duration_seconds":null,"custom_metric":null}]}
 ]},
 {"id":"rt2","title":"Mystery","updated_at":"2026-10-13T20:26:39.637Z","created_at":"2026-04-20T16:12:44.396Z","exercises":[
  {"index":0,"title":"Odd Machine Fly","notes":null,"exercise_template_id":"ZZZ","superset_id":null,"rest_seconds":60,
   "sets":[{"index":0,"type":"dropset","weight_kg":20,"reps":15}]}
 ]}
]}
"""

private let workoutsJSON = """
{"page":1,"page_count":1,"workouts":[
 {"id":"wk1","title":"Chest day","description":"felt good","start_time":"2026-10-13T22:00:00.000Z","end_time":"2026-10-13T23:05:30.000Z",
  "updated_at":"2026-10-13T23:06:00.000Z","created_at":"2026-10-13T23:06:00.000Z","routine_id":"rt1","exercises":[
  {"index":0,"title":"Bench Press (Barbell)","notes":"","exercise_template_id":"79D0BB3A","supersets_id":3,
   "sets":[{"index":0,"type":"normal","weight_kg":60,"reps":8,"distance_meters":null,"duration_seconds":null,"rpe":8.5}]}
 ]}
]}
"""

private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try HevyJSON.decoder.decode(type, from: Data(json.utf8))
}

private func importFixtures(_ f: Forge) throws -> ImportReport {
    try HevyImporter(forge: f).importAll(
        templates: try decode(HevyTemplatesPage.self, templatesJSON).exerciseTemplates,
        routines: try decode(HevyRoutinesPage.self, routinesJSON).routines,
        workouts: try decode(HevyWorkoutsPage.self, workoutsJSON).workouts)
}

@Suite struct HevyImporterTests {
    @Test func importsRoutinesWithSetsAndNullValues() throws {
        let f = try Forge.inMemory()
        _ = try importFixtures(f)
        let routine = try #require(try f.routines().first { $0.title == "Upper Body" })
        #expect(routine.hevyID == "rt1")
        #expect(routine.exercises.count == 2)
        let cycling = routine.exercises[0]
        #expect(cycling.sets[0].weightKg == nil && cycling.sets[0].reps == nil && cycling.sets[0].completed == false)
        let bench = routine.exercises[1]
        #expect(bench.restSeconds == 120 && bench.notes == "pause")
        #expect(bench.sets[0].type == .warmup && bench.sets[0].weightKg == 43.09127515 && bench.sets[0].reps == 12)
        #expect(bench.sets[1].type == .normal && bench.sets[1].reps == 6)
        #expect(try f.exercise(id: bench.exerciseID)?.name == "Bench Press (Barbell)")
    }

    @Test func reimportAddsNothing() throws {
        let f = try Forge.inMemory()
        let first = try importFixtures(f)
        let second = try importFixtures(f)
        #expect(second.exercises.added == 0 && second.routines.added == 0 && second.workouts.added == 0)
        #expect(second.exercises.skipped >= first.exercises.added - 1)
        #expect(second.routines.skipped == 2 && second.workouts.skipped == 1)
        #expect(try f.exercises().count == 5)
        #expect(try f.routines().count == 2)
    }

    @Test func customAndBuiltInWithSameTitleBothImport() throws {
        let f = try Forge.inMemory()
        _ = try importFixtures(f)
        let benches = try f.exercises(matching: "Bench Press (Barbell)")
        #expect(benches.count == 2)
        #expect(Set(benches.map(\.isCustom)) == [true, false])
    }

    @Test func unknownTemplateIDProducesWarningNotCrash() throws {
        let f = try Forge.inMemory()
        let report = try importFixtures(f)
        #expect(report.warnings.contains { $0.contains("ZZZ") })
        let mystery = try #require(try f.routines().first { $0.title == "Mystery" })
        let placeholder = try #require(try f.exercise(id: mystery.exercises[0].exerciseID))
        #expect(placeholder.name == "Odd Machine Fly" && placeholder.hevyID == "ZZZ")
        #expect(mystery.exercises[0].sets[0].type == .drop)
    }

    @Test func workoutTimestampsRoutineLinkAndCompletion() throws {
        let f = try Forge.inMemory()
        _ = try importFixtures(f)
        let w = try #require(try f.workouts().first)
        #expect(w.startedAt == ms("2026-10-13T22:00:00Z") && w.endedAt == ms("2026-10-13T23:05:30Z"))
        #expect(w.notes == "felt good" && w.hevyID == "wk1")
        #expect(try f.routine(id: w.routineID ?? "")?.hevyID == "rt1")
        #expect(w.exercises[0].supersetID == 3 && w.exercises[0].notes == nil)
        #expect(w.exercises[0].sets[0].completed && w.exercises[0].sets[0].rpe == 8.5)
    }

    @Test func templateTypesMapToTrackingTypes() throws {
        let f = try Forge.inMemory()
        _ = try importFixtures(f)
        #expect(try f.exercises(matching: "Assisted").first?.tracking == .assistedBodyweight)
        #expect(try f.exercises(matching: "Cycling").first?.tracking == .distanceDuration)
        #expect(try f.exercises(matching: "Assisted").first?.secondaryMuscles == ["biceps"])
    }

    @Test func importIsAttributedToImporter() throws {
        let f = try Forge.inMemory()
        _ = try importFixtures(f)
        #expect(try f.changes(since: 0).allSatisfy { $0.author == .importer })
    }

    @Test func sameWorkoutIDTwiceInOneRunImportsOnce() throws {
        let f = try Forge.inMemory()
        let page = try decode(HevyWorkoutsPage.self, workoutsJSON)
        let report = try HevyImporter(forge: f).importAll(
            templates: try decode(HevyTemplatesPage.self, templatesJSON).exerciseTemplates, routines: [],
            workouts: page.workouts + page.workouts)
        #expect(report.workouts.added == 1 && report.workouts.skipped == 1)
        #expect(try f.workouts().count == 1)
    }

    @Test func weightedAndAssistedBodyweightTypesFromHevyMap() {
        #expect(HevyImporter.tracking(for: "bodyweight_weighted") == .weightedBodyweight)
        #expect(HevyImporter.tracking(for: "bodyweight_assisted") == .assistedBodyweight)
    }

    @Test func weightAndDurationFromHevyKeepsTheWeight() {
        #expect(HevyImporter.tracking(for: "weight_duration") == .weightDuration)
        #expect(HevyImporter.tracking(for: "duration") == .duration)
    }

    @Test func anUnlinkedExerciseWithTheSameNameIsAdoptedNotDuplicated() throws {
        let f = try Forge.inMemory()
        try f.perform([.putExercise(Exercise(id: "local", name: "Cycling", isCustom: false))], author: .me)
        let report = try importFixtures(f)
        #expect(report.exercises.adopted == 1)
        #expect(try f.exercises(matching: "Cycling").count == 1)
        #expect(try f.exercise(id: "local")?.hevyID == "D8F7F851")
        let routine = try #require(try f.routines().first { $0.title == "Upper Body" })
        #expect(routine.exercises[0].exerciseID == "local")
    }

    @Test func adoptionHappensOncePerLocalExercise() throws {
        let f = try Forge.inMemory()
        try f.perform([.putExercise(Exercise(id: "local", name: "Bench Press (Barbell)", isCustom: false))], author: .me)
        _ = try importFixtures(f)
        #expect(try f.exercises(matching: "Bench Press (Barbell)").count == 2)   // one adopted, one created for the custom twin
        #expect(try f.exercises().filter { $0.name == "Bench Press (Barbell)" && $0.hevyID == nil }.isEmpty)
    }
}
