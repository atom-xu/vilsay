//
//  ErrorFeedbackTests.swift
//  TEST-05
//

import GRDB
import Testing
@testable import vilsay

struct ErrorFeedbackTests {

    @Test func flagLatest_marksNewestRow() throws {
        let db = try TestDatabase.makeEmpty()
        try TestDatabase.seedRawLogs(db, count: 3)

        try db.write { conn in
            try conn.execute(sql: """
                UPDATE raw_log SET user_flagged_error = 1
                WHERE id = (SELECT MAX(id) FROM raw_log)
            """)
        }

        try db.read { conn in
            let all = try RawLogRecord.order(Column("id")).fetchAll(conn)
            #expect(all[0].userFlaggedError == false)
            #expect(all[1].userFlaggedError == false)
            #expect(all[2].userFlaggedError == true)
        }
    }

    @Test func flagLatest_emptyTable_noError() throws {
        let db = try TestDatabase.makeEmpty()
        try db.write { conn in
            try conn.execute(sql: """
                UPDATE raw_log SET user_flagged_error = 1
                WHERE id = (SELECT MAX(id) FROM raw_log)
            """)
        }
    }

    @Test func flagLatest_idempotent() throws {
        let db = try TestDatabase.makeEmpty()
        try TestDatabase.seedRawLogs(db, count: 1)

        for _ in 0..<2 {
            try db.write { conn in
                try conn.execute(sql: """
                    UPDATE raw_log SET user_flagged_error = 1
                    WHERE id = (SELECT MAX(id) FROM raw_log)
                """)
            }
        }

        try db.read { conn in
            let log = try #require(try RawLogRecord.fetchOne(conn))
            #expect(log.userFlaggedError == true)
        }
    }

    @Test func getFlaggedErrors_returnsOnlyFlagged() throws {
        let db = try TestDatabase.makeEmpty()
        try TestDatabase.seedRawLogs(db, count: 5)

        try db.write { conn in
            try conn.execute(sql: "UPDATE raw_log SET user_flagged_error = 1 WHERE id IN (3, 5)")
        }

        try db.read { conn in
            let flagged = try RawLogRecord
                .filter(Column("user_flagged_error") == true)
                .fetchAll(conn)
            #expect(flagged.count == 2)
            let ids = flagged.compactMap(\.id)
            #expect(ids.contains(3))
            #expect(ids.contains(5))
        }
    }
}
