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

    }
}
