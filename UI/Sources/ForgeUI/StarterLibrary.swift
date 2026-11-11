import ForgeCore
import Foundation

/// A small set of common exercises for a fresh database (a Hevy import brings the full library).
public enum StarterLibrary {
    private static func ex(_ name: String, _ equipment: String, _ primary: String, _ secondary: [String] = [],
                           _ tracking: TrackingType = .weightReps) -> (name: String, equipment: String, primaryMuscle: String?, secondary: [String], tracking: TrackingType) {
        (name, equipment, primary, secondary, tracking)
    }

    public static let exercises = [
        ex("Bench Press (Barbell)", "barbell", "chest", ["triceps", "shoulders"]),
        ex("Incline Bench Press (Dumbbell)", "dumbbell", "chest", ["shoulders", "triceps"]),
        ex("Chest Press (Machine)", "machine", "chest", ["triceps"]),
        ex("Chest Fly (Cable)", "cable", "chest"),
        ex("Push Up", "none", "chest", ["triceps", "shoulders"], .repsOnly),
        ex("Overhead Press (Barbell)", "barbell", "shoulders", ["triceps"]),
        ex("Seated Shoulder Press (Dumbbell)", "dumbbell", "shoulders", ["triceps"]),
        ex("Lateral Raise (Dumbbell)", "dumbbell", "shoulders"),
        ex("Rear Delt Fly (Machine)", "machine", "shoulders", ["upper_back"]),
        ex("Face Pull (Cable)", "cable", "shoulders", ["upper_back"]),
        ex("Deadlift (Barbell)", "barbell", "lower_back", ["glutes", "hamstrings"]),
        ex("Pull Up", "none", "lats", ["biceps"], .repsOnly),
        ex("Lat Pulldown (Cable)", "cable", "lats", ["biceps"]),
        ex("Seated Cable Row", "cable", "upper_back", ["lats", "biceps"]),
        ex("Bent Over Row (Barbell)", "barbell", "upper_back", ["lats", "biceps"]),
        ex("One Arm Row (Dumbbell)", "dumbbell", "lats", ["biceps"]),
        ex("T Bar Row", "barbell", "upper_back", ["lats"]),
        ex("Bicep Curl (Dumbbell)", "dumbbell", "biceps"),
        ex("Hammer Curl (Dumbbell)", "dumbbell", "biceps", ["forearms"]),
        ex("EZ Bar Curl", "barbell", "biceps"),
        ex("Triceps Pushdown (Cable)", "cable", "triceps"),
        ex("Skullcrusher (Barbell)", "barbell", "triceps"),
        ex("Triceps Dip", "none", "triceps", ["chest", "shoulders"], .weightedBodyweight),
        ex("Overhead Triceps Extension (Dumbbell)", "dumbbell", "triceps"),
        ex("Squat (Barbell)", "barbell", "quadriceps", ["glutes", "hamstrings"]),
        ex("Front Squat (Barbell)", "barbell", "quadriceps", ["glutes"]),
        ex("Leg Press (Machine)", "machine", "quadriceps", ["glutes"]),
        ex("Leg Extension (Machine)", "machine", "quadriceps"),
        ex("Seated Leg Curl (Machine)", "machine", "hamstrings"),
        ex("Romanian Deadlift (Barbell)", "barbell", "hamstrings", ["glutes", "lower_back"]),
        ex("Walking Lunge (Dumbbell)", "dumbbell", "quadriceps", ["glutes"]),
        ex("Bulgarian Split Squat (Dumbbell)", "dumbbell", "quadriceps", ["glutes"]),
        ex("Hip Thrust (Barbell)", "barbell", "glutes", ["hamstrings"]),
        ex("Standing Calf Raise (Machine)", "machine", "calves"),
        ex("Seated Calf Raise (Machine)", "machine", "calves"),
        ex("Plank", "none", "abdominals", [], .duration),
        ex("Crunch", "none", "abdominals", [], .repsOnly),
        ex("Hanging Leg Raise", "none", "abdominals", [], .repsOnly),
        ex("Cable Crunch", "cable", "abdominals"),
        ex("Shrug (Dumbbell)", "dumbbell", "traps"),
        ex("Wrist Curl (Barbell)", "barbell", "forearms"),
        ex("Cycling", "machine", "cardio", [], .distanceDuration),
        ex("Running", "none", "cardio", [], .distanceDuration),
    ]
}
