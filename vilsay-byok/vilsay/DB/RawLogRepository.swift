//
//  RawLogRepository.swift
//  vilsay
//

import Combine
import Foundation
import GRDB
import SwiftUI

/// 历史记录 / 仪表盘数据源（查询 `raw_log` 表）。
final class RawLogRepository: ObservableObject {
    @Published var records: [RawLogRecord] = []

    // MARK: - 分页查询

    func fetchRecent(limit: Int = 50, offset: Int = 0) {
        Task { await _fetchRecent(limit: limit, offset: offset) }
    }

    private func _fetchRecent(limit: Int, offset: Int) async {
        guard let pool = try? AppDatabase.shared.dbPool else { return }
        let items = (try? await pool.read { db in
            try RawLogRecord
                .order(Column("created_at").desc)
                .limit(limit, offset: offset)
                .fetchAll(db)
        }) ?? []
        await MainActor.run { self.records = items }
    }

    // MARK: - 带筛选的查询

    func fetchFiltered(
        search: String = "",
        dateRange: HistoryDateFilter = .all,
        flaggedOnly: Bool = false,
        limit: Int = 100
    ) {
        Task { await _fetchFiltered(search: search, dateRange: dateRange, flaggedOnly: flaggedOnly, limit: limit) }
    }

    private func _fetchFiltered(search: String, dateRange: HistoryDateFilter, flaggedOnly: Bool, limit: Int) async {
        guard let pool = try? AppDatabase.shared.dbPool else { return }
        let items = (try? await pool.read { db -> [RawLogRecord] in
            var request = RawLogRecord.all()

            if !search.isEmpty {
                let pattern = "%\(search)%"
                request = request.filter(
                    Column("asr_text").like(pattern) || Column("polished_text").like(pattern)
                )
            }

            if let threshold = dateRange.isoThreshold {
                request = request.filter(Column("created_at") >= threshold)
            }

            if flaggedOnly {
                request = request.filter(Column("user_flagged_error") == true)
            }

            return try request
                .order(Column("created_at").desc)
                .limit(limit)
                .fetchAll(db)
        }) ?? []
        await MainActor.run { self.records = items }
    }

    // MARK: - 今日统计

    struct TodayStats {
        var count: Int = 0
        var totalDurationMs: Int = 0
        var avgConfidence: Double?
    }

    func todayStats() async -> TodayStats {
        guard let pool = try? AppDatabase.shared.dbPool else { return TodayStats() }
        let threshold = Self.todayMidnightISO()
        return (try? await pool.read { db -> TodayStats in
            let rows = try RawLogRecord
                .filter(Column("created_at") >= threshold)
                .fetchAll(db)
            let count = rows.count
            let totalMs = rows.compactMap(\.durationMs).reduce(0, +)
            let confidences = rows.compactMap(\.asrConfidence)
            let avg = confidences.isEmpty ? nil : confidences.reduce(0, +) / Double(confidences.count)
            return TodayStats(count: count, totalDurationMs: totalMs, avgConfidence: avg)
        }) ?? TodayStats()
    }

    // MARK: - 最近 7 天每日次数

    struct DailyCount: Identifiable {
        let date: String   // "yyyy-MM-dd"
        let count: Int
        var id: String { date }
    }

    func weeklyDailyCounts() async -> [DailyCount] {
        guard let pool = try? AppDatabase.shared.dbPool else { return [] }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let weekAgo = cal.date(byAdding: .day, value: -6, to: today) else { return [] }
        let threshold = ISO8601DateFormatter().string(from: weekAgo)

        let dbCounts: [DailyCount] = (try? await pool.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT substr(created_at, 1, 10) AS d, COUNT(*) AS c
                FROM raw_log
                WHERE created_at >= ?
                GROUP BY d
                ORDER BY d
                """, arguments: [threshold])
            return rows.map { DailyCount(date: $0["d"], count: $0["c"]) }
        }) ?? []

        // 填充空天
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        var map: [String: Int] = [:]
        for dc in dbCounts { map[dc.date] = dc.count }
        var result: [DailyCount] = []
        for i in 0..<7 {
            let d = cal.date(byAdding: .day, value: i, to: today.addingTimeInterval(-6 * 86400))!
            let key = fmt.string(from: d)
            result.append(DailyCount(date: key, count: map[key] ?? 0))
        }
        return result
    }

    // MARK: - 累计统计（仪表盘用）

    struct CumulativeStats {
        var totalSessions: Int = 0
        var totalDurationMs: Int = 0
        var totalWordCount: Int = 0
        var timeSavedMs: Int = 0        // 估算：口述比打字快 3 倍
        var avgWordsPerMinute: Double = 0
    }

    func cumulativeStats() async -> CumulativeStats {
        guard let pool = try? AppDatabase.shared.dbPool else { return CumulativeStats() }
        return (try? await pool.read { db -> CumulativeStats in
            let rows = try RawLogRecord.fetchAll(db)
            let totalSessions = rows.count
            let totalMs = rows.compactMap(\.durationMs).reduce(0, +)

            // 字数：取润色文本或 ASR 文本的字符数
            let totalWords = rows.reduce(0) { sum, r in
                let text = r.polishedText.isEmpty ? r.asrText : r.polishedText
                return sum + text.count
            }

            // 节省时间估算：打字速度约 40 字/分钟，口述后的文本如果手打需要的时间 - 实际口述时间
            let typingTimeMs = totalWords > 0 ? Int(Double(totalWords) / 40.0 * 60_000) : 0
            let saved = max(0, typingTimeMs - totalMs)

            // 平均口述速度（字/分钟）
            let totalMinutes = Double(totalMs) / 60_000.0
            let wpm = totalMinutes > 0 ? Double(totalWords) / totalMinutes : 0

            return CumulativeStats(
                totalSessions: totalSessions,
                totalDurationMs: totalMs,
                totalWordCount: totalWords,
                timeSavedMs: saved,
                avgWordsPerMinute: wpm
            )
        }) ?? CumulativeStats()
    }

    // MARK: - 标记错误

    func toggleFlaggedError(id: Int64) {
        Task {
            guard let pool = try? AppDatabase.shared.dbPool else { return }
            try? await pool.write { db in
                if var record = try RawLogRecord.fetchOne(db, key: id) {
                    record.userFlaggedError.toggle()
                    try record.update(db)
                }
            }
        }
    }

    // MARK: - 工具

    private static func todayMidnightISO() -> String {
        let cal = Calendar.current
        let midnight = cal.startOfDay(for: Date())
        return ISO8601DateFormatter().string(from: midnight)
    }
}

// MARK: - 日期筛选

enum HistoryDateFilter: String, CaseIterable, Identifiable {
    case today = "今天"
    case thisWeek = "本周"
    case thisMonth = "本月"
    case all = "全部"

    var id: String { rawValue }

    var isoThreshold: String? {
        let cal = Calendar.current
        let now = Date()
        let date: Date?
        switch self {
        case .today:     date = cal.startOfDay(for: now)
        case .thisWeek:  date = cal.date(byAdding: .day, value: -7, to: now)
        case .thisMonth: date = cal.date(byAdding: .month, value: -1, to: now)
        case .all:       return nil
        }
        guard let d = date else { return nil }
        return ISO8601DateFormatter().string(from: d)
    }
}
