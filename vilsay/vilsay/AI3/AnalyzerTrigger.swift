//
//  AnalyzerTrigger.swift
//  W5-04：满 20 条触发 AI3。
//

import Foundation
import GRDB

actor AnalyzerTrigger {
    static let shared = AnalyzerTrigger()

    func checkAndFire() async {
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
        let diff = state.totalLoggedCount - state.lastTriggerCount
        guard diff >= Constants.analyzerTriggerThreshold else { return }

        do {
            try await pool.write { db in
                try db.execute(sql: """
                    UPDATE analyzer_state
                    SET last_trigger_count = total_logged_count
                    WHERE id = 1
                """)
            }
        } catch {
            return
        }

        Task.detached(priority: .background) {
            await AI3Analyzer.shared.analyze()
        }
    }
}
