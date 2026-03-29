//
//  RawLogger.swift
//  W5-02 / V14-05：异步写入 raw_log。
//

import Foundation
import GRDB
import os.log

enum RawLogger {
    private static let log = Logger(subsystem: "com.vilsay.app", category: "RawLogger")
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

            var insertedId: Int64?
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
                    insertedId = record.id
                    try db.execute(sql: """
                        UPDATE analyzer_state
                        SET total_logged_count = total_logged_count + 1
                        WHERE id = 1
                    """)
                }
                await AnalyzerTrigger.shared.checkAndFire()
                log.debug("记录成功: asr=\(trimmedASR.prefix(30))…")
            } catch {
                // 静默失败
            }

            // L3 后台 Review：不影响主流程，静默对比润色质量
            if let rowId = insertedId, !trimmedPolished.isEmpty {
                await Self.backgroundReview(
                    rowId: rowId,
                    asrText: trimmedASR,
                    polishedText: trimmedPolished
                )
            }
        }
    }

    /// 后台调用 LLM review，结果写回 raw_log.review_text / review_ms。
    private static func backgroundReview(rowId: Int64, asrText: String, polishedText: String) async {
        log.info("📝 Review 开始 (row \(rowId), \(asrText.count)字)")
        let start = CFAbsoluteTimeGetCurrent()
        let reviewed = await PolishService.polishPlain(
            system: Prompts.reviewSystemPrompt,
            user: Prompts.reviewUserMessage(asrText: asrText, polishedText: polishedText)
        )
        let ms = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
        let trimmed = reviewed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            log.warning("⚠️ Review 返回空结果（\(ms)ms），跳过写入")
            return
        }

        guard let pool = try? AppDatabase.shared.dbPool else { return }
        do {
            try await pool.write { db in
                try db.execute(
                    sql: "UPDATE raw_log SET review_text = ?, review_ms = ? WHERE id = ?",
                    arguments: [trimmed, ms, rowId]
                )
            }
            let changed = trimmed != polishedText
            log.info("📝 Review 完成: \(ms)ms, \(changed ? "有修正" : "无变化") (row \(rowId))")
        } catch {
            log.error("📝 Review 写入失败: \(error.localizedDescription)")
        }
    }
}
