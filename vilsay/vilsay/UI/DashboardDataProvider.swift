//
//  DashboardDataProvider.swift
//  vilsay
//

import Combine
import Foundation
import GRDB
import SwiftUI

/// 聚合仪表盘所需数据。
final class DashboardDataProvider: ObservableObject {
    @Published var todayCount: Int = 0
    @Published var todayDurationMs: Int = 0
    @Published var todayAvgConfidence: Double?

    // 累计统计
    @Published var totalSessions: Int = 0
    @Published var totalDurationMs: Int = 0
    @Published var totalWordCount: Int = 0
    @Published var timeSavedMs: Int = 0
    @Published var avgWordsPerMinute: Double = 0

    // 个性化适应度
    @Published var personalizationScore: Int = 0
    @Published var archetype: SpeechArchetype?

    private let repo = RawLogRepository()
    private var cancellable: AnyCancellable?

    init() {
        // Pipeline 完成后自动刷新
        cancellable = NotificationCenter.default.publisher(for: .init("VilsayPipelineDidComplete"))
            .debounce(for: .seconds(0.5), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                Task { await self?.refresh() }
            }
    }

    @MainActor
    func refresh() async {
        let stats = await repo.todayStats()
        todayCount = stats.count
        todayDurationMs = stats.totalDurationMs
        todayAvgConfidence = stats.avgConfidence

        // 累计统计
        let cumulative = await repo.cumulativeStats()
        totalSessions = cumulative.totalSessions
        totalDurationMs = cumulative.totalDurationMs
        totalWordCount = cumulative.totalWordCount
        timeSavedMs = cumulative.timeSavedMs
        avgWordsPerMinute = cumulative.avgWordsPerMinute

        // 个性化适应度：基于 AI3 画像维度
        personalizationScore = await computePersonalization()
    }

    private func computePersonalization() async -> Int {
        guard let pool = try? AppDatabase.shared.dbPool else { return 0 }
        let result: (Int, SpeechArchetype?) = (try? await pool.read { db -> (Int, SpeechArchetype?) in
            var score = 0
            let keys = try String.fetchAll(db, sql: "SELECT key FROM user_profile WHERE output_mode = '__global__'")
            if keys.contains("habitual_words") { score += 25 }
            if keys.contains("thinking_style") { score += 25 }
            if keys.contains("tone") { score += 25 }
            let dictCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM dictionary") ?? 0
            if dictCount > 0 { score += 15 }
            if keys.contains("correction_gaps") { score += 10 }

            // 读取人格类型
            var arch: SpeechArchetype?
            if let row = try UserProfileRecord
                .filter(Column("key") == "ai3_dimensions" && Column("output_mode") == "__global__")
                .fetchOne(db),
               let jsonData = row.value.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                let dims = StyleDimensions(
                    warmth: obj["warmth"] as? Double ?? 0.5,
                    directness: obj["directness"] as? Double ?? 0.5,
                    confidence: obj["confidence"] as? Double ?? 0,
                    sampleCount: obj["sample_count"] as? Int ?? 0
                )
                arch = dims.archetype
            }
            return (min(100, score), arch)
        }) ?? (0, nil)
        await MainActor.run { archetype = result.1 }
        return result.0
    }
}
