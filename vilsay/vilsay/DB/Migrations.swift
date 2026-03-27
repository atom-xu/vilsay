//
//  Migrations.swift
//

import Foundation
import GRDB

enum Migrations {
    static func registerMigrations(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v1_create_tables") { db in
            try db.create(table: "raw_log", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("asr_text", .text).notNull()
                t.column("polished_text", .text).notNull()
                t.column("duration_ms", .integer)
                t.column("session_id", .text)
                t.column("created_at", .text).notNull()
            }

            try db.create(table: "user_profile", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("key", .text).notNull().unique()
                t.column("value", .text).notNull()
                t.column("confidence", .double).notNull().defaults(to: 0)
                t.column("updated_at", .text).notNull()
            }

            try db.create(table: "dictionary", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("word", .text).notNull().unique()
                t.column("context", .text)
                t.column("source", .text).notNull()
                t.column("created_at", .text).notNull()
            }

            try db.create(table: "dictionary_candidates", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("word", .text).notNull()
                t.column("score", .double).notNull().defaults(to: 0.5)
                t.column("context", .text)
                t.column("dismissed", .integer).notNull().defaults(to: 0)
                t.column("from_analysis_at", .text).notNull()
            }

            try db.create(table: "analyzer_state", ifNotExists: true) { t in
                t.column("id", .integer).primaryKey(onConflict: .replace).defaults(to: 1)
                t.column("total_logged_count", .integer).notNull().defaults(to: 0)
                t.column("last_trigger_count", .integer).notNull().defaults(to: 0)
                t.column("last_run_at", .text)
            }

            try db.execute(sql: """
                INSERT OR IGNORE INTO analyzer_state (id, total_logged_count, last_trigger_count)
                VALUES (1, 0, 0)
            """)
        }

        migrator.registerMigration("v2_add_v14_columns") { db in
            try db.alter(table: "raw_log") { t in
                t.add(column: "asr_provider", .text)
                t.add(column: "asr_confidence", .double)
                t.add(column: "target_app_id", .text)
                t.add(column: "user_flagged_error", .integer).notNull().defaults(to: 0)
            }

            try db.alter(table: "dictionary") { t in
                t.add(column: "pinyin", .text)
            }

            try db.alter(table: "dictionary_candidates") { t in
                t.add(column: "pinyin", .text)
                t.add(column: "state", .text).notNull().defaults(to: "pending")
            }

            try db.execute(sql: """
                UPDATE dictionary_candidates SET state = CASE
                    WHEN dismissed = 1 THEN 'dismissed'
                    ELSE 'pending'
                END
            """)

            try db.alter(table: "analyzer_state") { t in
                t.add(column: "last_analyzed_log_id", .integer)
            }
        }

        migrator.registerMigration("v3_output_mode_raw_log_and_profile") { db in
            try db.alter(table: "raw_log") { t in
                t.add(column: "output_mode", .text).notNull().defaults(to: "general")
            }

            try db.create(table: "user_profile_v3") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("key", .text).notNull()
                t.column("value", .text).notNull()
                t.column("confidence", .double).notNull().defaults(to: 0)
                t.column("updated_at", .text).notNull()
                t.column("output_mode", .text).notNull().defaults(to: "__global__")
                t.uniqueKey(["key", "output_mode"])
            }

            try db.execute(sql: """
                INSERT INTO user_profile_v3 (id, key, value, confidence, updated_at, output_mode)
                SELECT id, key, value, confidence, updated_at, '__global__' FROM user_profile
            """)

            try db.drop(table: "user_profile")
            try db.rename(table: "user_profile_v3", to: "user_profile")
        }
    }
}
