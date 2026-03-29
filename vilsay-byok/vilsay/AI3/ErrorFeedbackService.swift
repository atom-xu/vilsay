//
//  ErrorFeedbackService.swift
//  V14-06：用户标记「有误」闭环。
//

import Foundation
import GRDB
import os.log

enum ErrorFeedbackService {
    private static let log = Logger(subsystem: "com.vilsay.app", category: "ErrorFeedback")

    /// 将最新一条 `raw_log` 标记为用户已反馈有误。
    static func flagLatestError() {
        Task.detached(priority: .userInitiated) {
            guard let pool = try? AppDatabase.shared.dbPool else { return }
            do {
                try await pool.write { db in
                    // FIX-01：单条原子 UPDATE，避免 fetch 与 update 之间插入新行导致误标。
                    try db.execute(sql: """
                        UPDATE raw_log SET user_flagged_error = 1
                        WHERE id = (SELECT MAX(id) FROM raw_log)
                    """)
                }
            } catch {
                Self.log.error("flagLatestError: \(error.localizedDescription)")
            }
        }
    }

    /// 供 AI3 分析：用户标记为有误的记录。
    static func getFlaggedErrors() async -> [RawLogRecord] {
        guard let pool = try? AppDatabase.shared.dbPool else { return [] }
        return (try? await pool.read { db in
            try RawLogRecord
                .filter(Column("user_flagged_error") == true)
                .order(Column("id").desc)
                .limit(50)
                .fetchAll(db)
        }) ?? []
    }
}
