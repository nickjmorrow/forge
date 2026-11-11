import Foundation
import GRDB

enum Schema {
    static func migrator() -> DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            try db.execute(sql: """
            CREATE TABLE exercises (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              equipment TEXT,
              primary_muscle TEXT,
              secondary_muscles TEXT NOT NULL DEFAULT '[]',
              tracking TEXT NOT NULL,
              is_custom INTEGER NOT NULL DEFAULT 1,
              hevy_id TEXT UNIQUE,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            );
            CREATE TABLE routines (
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              folder TEXT,
              position INTEGER NOT NULL,
              hevy_id TEXT UNIQUE,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            );
            CREATE TABLE routine_exercises (
              routine_id TEXT NOT NULL REFERENCES routines(id) ON DELETE CASCADE,
              position INTEGER NOT NULL,
              exercise_id TEXT NOT NULL,
              notes TEXT,
              rest_seconds INTEGER NOT NULL DEFAULT 0,
              superset_id INTEGER,
              PRIMARY KEY (routine_id, position)
            );
            CREATE INDEX routine_exercises_exercise ON routine_exercises(exercise_id);
            CREATE TABLE routine_sets (
              routine_id TEXT NOT NULL,
              exercise_position INTEGER NOT NULL,
              position INTEGER NOT NULL,
              type TEXT NOT NULL,
              weight_kg REAL, reps INTEGER, duration_seconds INTEGER, distance_meters REAL, rpe REAL,
              completed INTEGER NOT NULL DEFAULT 0,
              PRIMARY KEY (routine_id, exercise_position, position),
              FOREIGN KEY (routine_id, exercise_position) REFERENCES routine_exercises(routine_id, position) ON DELETE CASCADE
            );
            CREATE TABLE workouts (
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              started_at INTEGER NOT NULL,
              ended_at INTEGER,
              routine_id TEXT,
              notes TEXT,
              hevy_id TEXT UNIQUE
            );
            CREATE INDEX workouts_started ON workouts(started_at);
            CREATE TABLE workout_exercises (
              workout_id TEXT NOT NULL REFERENCES workouts(id) ON DELETE CASCADE,
              position INTEGER NOT NULL,
              exercise_id TEXT NOT NULL,
              notes TEXT,
              rest_seconds INTEGER NOT NULL DEFAULT 0,
              superset_id INTEGER,
              PRIMARY KEY (workout_id, position)
            );
            CREATE INDEX workout_exercises_exercise ON workout_exercises(exercise_id);
            CREATE TABLE workout_sets (
              workout_id TEXT NOT NULL,
              exercise_position INTEGER NOT NULL,
              position INTEGER NOT NULL,
              type TEXT NOT NULL,
              weight_kg REAL, reps INTEGER, duration_seconds INTEGER, distance_meters REAL, rpe REAL,
              completed INTEGER NOT NULL DEFAULT 0,
              PRIMARY KEY (workout_id, exercise_position, position),
              FOREIGN KEY (workout_id, exercise_position) REFERENCES workout_exercises(workout_id, position) ON DELETE CASCADE
            );
            CREATE TABLE bodyweight (date TEXT PRIMARY KEY, kg REAL NOT NULL);
            CREATE TABLE ops (
              local_id INTEGER PRIMARY KEY AUTOINCREMENT,
              device TEXT NOT NULL,
              author TEXT NOT NULL,
              kind TEXT NOT NULL,
              payload TEXT NOT NULL,
              inverse TEXT,
              created_at INTEGER NOT NULL,
              undone_by INTEGER,
              undoes INTEGER
            );
            """)
        }
        m.registerMigration("v2") { db in
            // A change whose undo was skipped stays applied (so it keeps protecting its entities) but is not offered again.
            try db.execute(sql: "ALTER TABLE ops ADD COLUMN voided INTEGER NOT NULL DEFAULT 0")
        }
        m.registerMigration("v3") { db in
            // Sleep and recovery per morning, one row per data source so Apple Health and Eight Sleep can coexist.
            try db.execute(sql: """
            CREATE TABLE recovery (
              date TEXT NOT NULL,
              source TEXT NOT NULL,
              sleep_seconds INTEGER,
              sleep_score REAL,
              hrv_ms REAL,
              resting_hr REAL,
              PRIMARY KEY (date, source)
            );
            """)
        }
        m.registerMigration("v4") { db in
            // Sync: every op gets a logical timestamp; each entity remembers the newest write it has seen (last writer wins).
            try db.execute(sql: """
            ALTER TABLE ops ADD COLUMN ts INTEGER;
            ALTER TABLE ops ADD COLUMN seq INTEGER;
            ALTER TABLE ops ADD COLUMN origin_device TEXT;
            ALTER TABLE ops ADD COLUMN origin_id INTEGER;
            ALTER TABLE ops ADD COLUMN local INTEGER NOT NULL DEFAULT 1;
            ALTER TABLE ops ADD COLUMN pushed INTEGER NOT NULL DEFAULT 0;
            UPDATE ops SET ts = created_at, origin_device = device, origin_id = local_id;
            CREATE INDEX ops_seq ON ops(seq);
            CREATE UNIQUE INDEX ops_origin ON ops(origin_device, origin_id);
            CREATE TABLE clocks (entity TEXT PRIMARY KEY, ts INTEGER NOT NULL, device TEXT NOT NULL);
            CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
            """)
            // Entities written before sync existed get the clock of the last op that touched them. Timestamps are made strictly
            // increasing per entity (two old ops in the same millisecond must still have a defined order).
            let decoder = JSONDecoder()
            var lastTs: [String: Int64] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT local_id, payload, created_at, device FROM ops ORDER BY local_id") {
                let keys = (try? decoder.decode(Op.self, from: Data((row["payload"] as String).utf8)))?.entityKeys ?? []
                let ts = max(row["created_at"] as Int64, (keys.compactMap { lastTs[$0] }.max() ?? 0) + 1)
                try db.execute(sql: "UPDATE ops SET ts = ? WHERE local_id = ?", arguments: [ts, row["local_id"] as Int64])
                for key in keys {
                    lastTs[key] = ts
                    try db.execute(sql: "INSERT OR REPLACE INTO clocks (entity, ts, device) VALUES (?, ?, ?)", arguments: [key, ts, row["device"] as String])
                }
            }
        }
        return m
    }
}
