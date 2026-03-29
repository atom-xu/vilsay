//
//  TestDatabase.swift
//  vilsayTests — 内存 GRDB（v1+v2 迁移）
//

import Foundation
import GRDB
@testable import vilsay

/// 创建一个内存 GRDB `DatabaseQueue`，跑完 v1+v2 迁移，可直接用于测试。
/// 每次调用返回全新的空数据库。
enum TestDatabase {
    static func makeEmpty() throws -> DatabaseQueue {
        let db = try DatabaseQueue(configuration: .init())
        var migrator = DatabaseMigrator()
        Migrations.registerMigrations(&migrator)
        try migrator.migrate(db)
        return db
    }

    /// 插入 N 条 raw_log 测试数据
    static func seedRawLogs(
        _ db: DatabaseQueue,
        count: Int,
        asrPrefix: String = "测试语音"
    ) throws {
        try db.write { conn in
            for i in 1...count {
                var record = RawLogRecord(
                    asrText: "\(asrPrefix) 第\(i)句",
                    polishedText: "润色后 第\(i)句",
                    durationMs: 500,
                    sessionId: UUID().uuidString,
                    asrProvider: "whisperKit",
                    asrConfidence: 0.75,
                    targetAppId: "com.apple.Notes",
                    userFlaggedError: false,
                    createdAt: ISO8601DateFormatter().string(from: Date())
                )
                try record.insert(conn)
            }
            try conn.execute(sql: """
                UPDATE analyzer_state
                SET total_logged_count = \(count)
                WHERE id = 1
            """)
        }
    }
}
