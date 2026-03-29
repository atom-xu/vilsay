//
//  RawLoggerFieldTests.swift
//  TEST-08
//

import GRDB
import Testing
@testable import vilsay

struct RawLoggerFieldTests {

    @Test func allV14Fields_persisted() throws {
        let db = try TestDatabase.makeEmpty()
        try db.write { conn in
            var r = RawLogRecord(
                asrText: "语音",
                polishedText: "润色后",
                durationMs: 300,
                sessionId: "session-1",
                asrProvider: "whisperKit",
                asrConfidence: 0.82,
                targetAppId: "com.apple.mail",
                userFlaggedError: false,
                createdAt: "2026-03-25T10:00:00Z"
            )
            try r.insert(conn)
        }

        try db.read { conn in
            let r = try #require(try RawLogRecord.fetchOne(conn))
            #expect(r.asrProvider == "whisperKit")
            #expect(r.asrConfidence == 0.82)
            #expect(r.targetAppId == "com.apple.mail")
            #expect(r.userFlaggedError == false)
        }
    }

    @Test func nullableFields_allowNil() throws {
        let db = try TestDatabase.makeEmpty()
        try db.write { conn in
            var r = RawLogRecord(
                asrText: "test", polishedText: "test",
                durationMs: nil, sessionId: nil,
                asrProvider: nil, asrConfidence: nil,
                targetAppId: nil, userFlaggedError: false,
                createdAt: "2026-03-25"
            )
            try r.insert(conn)
        }

        try db.read { conn in
            let r = try #require(try RawLogRecord.fetchOne(conn))
            #expect(r.asrProvider == nil)
            #expect(r.asrConfidence == nil)
            #expect(r.targetAppId == nil)
        }
    }

    @Test func dashScope_noConfidence() throws {
        let db = try TestDatabase.makeEmpty()
        try db.write { conn in
            var r = RawLogRecord(
                asrText: "test", polishedText: "test",
                durationMs: 200, sessionId: "s",
                asrProvider: "dashScope",
                asrConfidence: nil,
                targetAppId: "com.apple.Notes",
                userFlaggedError: false,
                createdAt: "2026-03-25"
            )
            try r.insert(conn)
        }

        try db.read { conn in
            let r = try #require(try RawLogRecord.fetchOne(conn))
            #expect(r.asrProvider == "dashScope")
            #expect(r.asrConfidence == nil)
        }
    }

    @Test func defaultFlaggedError_isFalse() throws {
        let db = try TestDatabase.makeEmpty()
        try db.write { conn in
            try conn.execute(sql: """
                INSERT INTO raw_log (asr_text, polished_text, created_at)
                VALUES ('test', 'test', '2026-03-25')
            """)
        }

        try db.read { conn in
            let val = try Int.fetchOne(conn,
                sql: "SELECT user_flagged_error FROM raw_log LIMIT 1")
            #expect(val == 0)
        }
    }
}
