//
//  AI3DeduplicationTests.swift
//  TEST-07
//

import GRDB
import Testing
@testable import vilsay

struct AI3DeduplicationTests {

    @Test func newLogsOnly_firstRun() throws {
        let db = try TestDatabase.makeEmpty()
        try TestDatabase.seedRawLogs(db, count: 20)

        try db.read { conn in
            let state = try #require(try AnalyzerStateRecord.fetchOne(conn))
            let sinceId = state.lastAnalyzedLogId ?? 0

            let newLogs = try RawLogRecord
                .filter(Column("id") > sinceId)
                .order(Column("id").asc)
                .limit(50)
                .fetchAll(conn)

            #expect(newLogs.count == 20)
        }
    }

    @Test func newLogsOnly_afterFirstAnalysis() throws {
        let db = try TestDatabase.makeEmpty()
        try TestDatabase.seedRawLogs(db, count: 20)

        try db.write { conn in
            try conn.execute(sql: """
                UPDATE analyzer_state SET last_analyzed_log_id = 20 WHERE id = 1
            """)
        }

        try db.write { conn in
            for i in 21...30 {
                var r = RawLogRecord(
                    asrText: "新增 \(i)", polishedText: "润色 \(i)",
                    durationMs: 100, sessionId: "s",
                    asrProvider: nil, asrConfidence: nil,
                    targetAppId: nil, userFlaggedError: false,
                    createdAt: "2026-03-25")
                try r.insert(conn)
            }
        }

        try db.read { conn in
            let state = try #require(try AnalyzerStateRecord.fetchOne(conn))
            let sinceId = state.lastAnalyzedLogId ?? 0
            #expect(sinceId == 20)

            let newLogs = try RawLogRecord
                .filter(Column("id") > sinceId)
                .fetchAll(conn)
            #expect(newLogs.count == 10)
            #expect(newLogs.first?.asrText.contains("新增") == true)
        }
    }

    @Test func noNewLogs_skipAnalysis() throws {
        let db = try TestDatabase.makeEmpty()
        try TestDatabase.seedRawLogs(db, count: 20)

        try db.write { conn in
            try conn.execute(sql: """
                UPDATE analyzer_state SET last_analyzed_log_id = 20 WHERE id = 1
            """)
        }

        try db.read { conn in
            let state = try #require(try AnalyzerStateRecord.fetchOne(conn))
            let newLogs = try RawLogRecord
                .filter(Column("id") > (state.lastAnalyzedLogId ?? 0))
                .fetchAll(conn)
            #expect(newLogs.isEmpty)
        }
    }

    @Test func clearData_resetsLogId() throws {
        let db = try TestDatabase.makeEmpty()

        try db.write { conn in
            try conn.execute(sql: """
                UPDATE analyzer_state
                SET last_analyzed_log_id = 50, total_logged_count = 50
                WHERE id = 1
            """)
        }

        try db.write { conn in
            try conn.execute(sql: "DELETE FROM raw_log")
            try conn.execute(sql: """
                UPDATE analyzer_state
                SET total_logged_count = 0, last_trigger_count = 0,
                    last_analyzed_log_id = NULL WHERE id = 1
            """)
        }

        try db.read { conn in
            let state = try #require(try AnalyzerStateRecord.fetchOne(conn))
            #expect(state.lastAnalyzedLogId == nil)
            #expect(state.totalLoggedCount == 0)
        }
    }

    @Test func triggerThreshold_correctDiff() throws {
        let threshold = Constants.analyzerTriggerThreshold
        let db = try TestDatabase.makeEmpty()
        try TestDatabase.seedRawLogs(db, count: threshold - 1)

        try db.write { conn in
            try conn.execute(sql: """
                UPDATE analyzer_state SET total_logged_count = \(threshold - 1) WHERE id = 1
            """)
        }

        try db.read { conn in
            let state = try #require(try AnalyzerStateRecord.fetchOne(conn))
            let diff = state.totalLoggedCount - state.lastTriggerCount
            #expect(diff == threshold - 1)
            #expect(diff < Constants.analyzerTriggerThreshold)
        }

        try db.write { conn in
            var r = RawLogRecord(
                asrText: "第 \(threshold) 句", polishedText: "\(threshold)",
                durationMs: 100, sessionId: "s",
                asrProvider: nil, asrConfidence: nil,
                targetAppId: nil, userFlaggedError: false,
                createdAt: "2026-03-25")
            try r.insert(conn)
            try conn.execute(sql: """
                UPDATE analyzer_state SET total_logged_count = \(threshold) WHERE id = 1
            """)
        }

        try db.read { conn in
            let state = try #require(try AnalyzerStateRecord.fetchOne(conn))
            let diff = state.totalLoggedCount - state.lastTriggerCount
            #expect(diff == threshold)
            #expect(diff >= Constants.analyzerTriggerThreshold)
        }
    }
}
