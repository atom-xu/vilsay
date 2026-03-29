//
//  Database.swift
//  AppDatabase 单例（W5-01 / W5-08）。
//

import Foundation
import GRDB
import os.log

final class AppDatabase {
    static let shared = AppDatabase()

    private static let log = Logger(subsystem: "com.vilsay.app", category: "AppDatabase")

    private(set) var dbPool: DatabasePool!

    private init() {}

    func setup() throws {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base.appendingPathComponent("vilsay", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("vilsay.sqlite")

        var config = Configuration()
        config.foreignKeysEnabled = true
        dbPool = try DatabasePool(path: url.path, configuration: config)

        var migrator = DatabaseMigrator()
        Migrations.registerMigrations(&migrator)
        try migrator.migrate(dbPool)
        Self.log.info("SQLite 就绪: \(url.path)")
    }

    /// 清除 AI 学习数据；**保留** `dictionary` 手动词条。
    func clearAIData() throws {
        try dbPool.write { db in
            try db.execute(sql: "DELETE FROM raw_log")
            try db.execute(sql: "DELETE FROM user_profile")
            try db.execute(sql: "DELETE FROM dictionary_candidates")
            try db.execute(sql: """
                UPDATE analyzer_state
                SET total_logged_count = 0, last_trigger_count = 0, last_run_at = NULL,
                    last_analyzed_log_id = NULL
                WHERE id = 1
            """)
        }
    }
}
