//
//  RawLogger.swift
//  W5-02 / V14-05：异步写入 raw_log。
//

import Foundation
import GRDB

enum RawLogger {
    /// 异步写入 raw_log，并通知 `AnalyzerTrigger`。须在 `Task.detached(.background)` 中调用。
    static func logAsync(
        asr: String,
        polished: String,
        durationMs: Int,
        sessionId: String,
        asrProvider: String? = nil,
        asrConfidence: Double? = nil,
        targetAppBundleID: String? = nil,
        outputMode: String = "general"
    ) {
        Task.detached(priority: .background) {
            let trimmedASR = asr.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedPolished = polished.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedASR.isEmpty else { return }
            guard let pool = try? AppDatabase.shared.dbPool else { return }

            do {
                try await pool.write { db in
                    var record = RawLogRecord(
                        asrText: trimmedASR,
                        polishedText: trimmedPolished,
                        durationMs: durationMs,
                        sessionId: sessionId,
                        asrProvider: asrProvider,
                        asrConfidence: asrConfidence,
                        targetAppId: targetAppBundleID,
                        userFlaggedError: false,
                        createdAt: ISO8601DateFormatter().string(from: Date()),
                        outputMode: outputMode
                    )
                    try record.insert(db)
                    try db.execute(sql: """
                        UPDATE analyzer_state
                        SET total_logged_count = total_logged_count + 1
                        WHERE id = 1
                    """)
                }
                await AnalyzerTrigger.shared.checkAndFire()
                print("[RawLogger] 记录成功: asr=\(trimmedASR.prefix(30))…")
            } catch {
                // 静默失败
            }
        }
    }
}
