//
//  AnalyzerTrigger.swift
//  W5-04：满 N 条触发 AI3。
//

import Foundation
import GRDB

actor AnalyzerTrigger {
    static let shared = AnalyzerTrigger()

    /// 上次触发时间，用于冷却防止连续重试
    private var lastFireTime: Date?
    /// 失败后冷却 5 分钟再重试
    private let cooldownAfterFailure: TimeInterval = 300

    func checkAndFire() async {
        // 冷却：上次触发后 5 分钟内不重试（防止分析超时后每条日志都重试）
        if let last = lastFireTime, Date().timeIntervalSince(last) < cooldownAfterFailure {
            return
        }

        guard let pool = try? AppDatabase.shared.dbPool else { return }

        let state: AnalyzerStateRecord?
        do {
            state = try await pool.read { db in
                try AnalyzerStateRecord.filter(Column("id") == 1).fetchOne(db)
            }
        } catch {
            return
        }

        guard let state else { return }

        // 条件 1：新日志数达到阈值
        let diff = state.totalLoggedCount - state.lastTriggerCount
        // 条件 2：已分析位置远落后于实际日志数（修复历史卡死）
        let analysisGap = state.totalLoggedCount - Int(state.lastAnalyzedLogId ?? 0)
        let shouldFire = diff >= Constants.analyzerTriggerThreshold
            || analysisGap >= Constants.analyzerTriggerThreshold * 2

        guard shouldFire else { return }

        lastFireTime = Date()

        Task.detached(priority: .background) {
            await AI3Analyzer.shared.analyze()
        }
    }
}
