//
//  DatabaseMigrationTests.swift
//  TEST-04
//

import GRDB
import Testing
@testable import vilsay

struct DatabaseMigrationTests {

    @Test func freshDatabase_allTablesExist() throws {
        let db = try TestDatabase.makeEmpty()
        try db.read { conn in
            let tables = try String.fetchAll(conn,
                sql: "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
            #expect(tables.contains("raw_log"))
            #expect(tables.contains("user_profile"))
            #expect(tables.contains("dictionary"))
            #expect(tables.contains("dictionary_candidates"))
            #expect(tables.contains("analyzer_state"))
        }
    }

    @Test func analyzerState_initialRow() throws {
        let db = try TestDatabase.makeEmpty()
        try db.read { conn in
            let state = try AnalyzerStateRecord.fetchOne(conn)
            #expect(state != nil)
            #expect(state?.totalLoggedCount == 0)
            #expect(state?.lastTriggerCount == 0)
            #expect(state?.lastAnalyzedLogId == nil)
        }
    }

    @Test func rawLog_v2Columns() throws {
        let db = try TestDatabase.makeEmpty()
        try db.write { conn in
            var record = RawLogRecord(
                asrText: "测试",
                polishedText: "测试润色",
                durationMs: 100,
                sessionId: "s1",
                asrProvider: "whisperKit",
                asrConfidence: 0.75,
                targetAppId: "com.apple.Notes",
                userFlaggedError: false,
                createdAt: "2026-03-25"
            )
            try record.insert(conn)

            let fetched = try #require(try RawLogRecord.fetchOne(conn))
            #expect(fetched.asrProvider == "whisperKit")
            #expect(fetched.asrConfidence == 0.75)
            #expect(fetched.targetAppId == "com.apple.Notes")
            #expect(fetched.userFlaggedError == false)
            #expect(fetched.outputMode == "general")
        }
    }

    @Test func dictionary_pinyinColumn() throws {
        let db = try TestDatabase.makeEmpty()
        try db.write { conn in
            var record = DictionaryRecord(
                word: "事业",
                context: nil,
                pinyin: "shi ye",
                source: "manual",
                createdAt: "2026-03-25"
            )
            try record.insert(conn)

            let fetched = try #require(try DictionaryRecord.fetchOne(conn))
            #expect(fetched.pinyin == "shi ye")
        }
    }

    @Test func candidates_stateColumn() throws {
        let db = try TestDatabase.makeEmpty()
        try db.write { conn in
            var record = DictionaryCandidateRecord(
                word: "测试词",
                score: 0.8,
                context: nil,
                pinyin: "ce shi ci",
                state: "pending",
                dismissed: 0,
                fromAnalysisAt: "2026-03-25"
            )
            try record.insert(conn)

            let fetched = try #require(try DictionaryCandidateRecord.fetchOne(conn))
            #expect(fetched.state == "pending")
            #expect(fetched.pinyin == "ce shi ci")
        }
    }

    @Test func candidates_stateTransitions() throws {
        let db = try TestDatabase.makeEmpty()
        try db.write { conn in
            var record = DictionaryCandidateRecord(
                word: "张三", score: 0.7, context: nil,
                pinyin: "zhang san", state: "pending", dismissed: 0,
                fromAnalysisAt: "2026-03-25"
            )
            try record.insert(conn)

            try conn.execute(sql: """
                UPDATE dictionary_candidates
                SET state = 'dismissed', dismissed = 1
                WHERE word = '张三'
            """)

            let fetched = try #require(try DictionaryCandidateRecord
                .filter(Column("word") == "张三").fetchOne(conn))
            #expect(fetched.state == "dismissed")
        }
    }

    @Test func analyzerState_lastAnalyzedLogId() throws {
        let db = try TestDatabase.makeEmpty()
        try db.write { conn in
            try conn.execute(sql: """
                UPDATE analyzer_state SET last_analyzed_log_id = 42 WHERE id = 1
            """)

            let state = try #require(try AnalyzerStateRecord.fetchOne(conn))
            #expect(state.lastAnalyzedLogId == 42)
        }
    }

    @Test func clearAIData_resetsAll() throws {
        let db = try TestDatabase.makeEmpty()

        try db.write { conn in
            var log = RawLogRecord(
                asrText: "hi", polishedText: "hi",
                durationMs: 100, sessionId: "s",
                asrProvider: nil, asrConfidence: nil,
                targetAppId: nil, userFlaggedError: false,
                createdAt: "2026-03-25"
            )
            try log.insert(conn)
            try conn.execute(sql: """
                UPDATE analyzer_state
                SET total_logged_count = 5, last_trigger_count = 5,
                    last_analyzed_log_id = 1
                WHERE id = 1
            """)
        }

        try db.write { conn in
            try conn.execute(sql: "DELETE FROM raw_log")
            try conn.execute(sql: "DELETE FROM user_profile")
            try conn.execute(sql: "DELETE FROM dictionary_candidates")
            try conn.execute(sql: """
                UPDATE analyzer_state
                SET total_logged_count = 0, last_trigger_count = 0,
                    last_run_at = NULL, last_analyzed_log_id = NULL
                WHERE id = 1
            """)
        }

        try db.read { conn in
            #expect(try RawLogRecord.fetchCount(conn) == 0)
            #expect(try UserProfileRecord.fetchCount(conn) == 0)
            let state = try #require(try AnalyzerStateRecord.fetchOne(conn))
            #expect(state.totalLoggedCount == 0)
            #expect(state.lastAnalyzedLogId == nil)
        }
    }
}
