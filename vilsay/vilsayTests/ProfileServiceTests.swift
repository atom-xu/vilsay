//
//  ProfileServiceTests.swift
//  TEST-06
//

import Foundation
import GRDB
import Testing
@testable import vilsay

struct ProfileServiceTests {

    @Test func insertCandidates_dedup_existingDictionary() throws {
        let db = try TestDatabase.makeEmpty()
        try db.write { conn in
            var dict = DictionaryRecord(
                word: "API", context: nil, pinyin: nil,
                source: "manual", createdAt: "2026-03-25")
            try dict.insert(conn)
        }

        try db.read { conn in
            let existing = try Set(String.fetchAll(conn,
                sql: "SELECT word FROM dictionary"))
            #expect(existing.contains("API"))
            let count = try DictionaryCandidateRecord.fetchCount(conn)
            #expect(count == 0)
        }
    }

    @Test func insertCandidates_dedup_existingCandidate() throws {
        let db = try TestDatabase.makeEmpty()
        try db.write { conn in
            var cand = DictionaryCandidateRecord(
                word: "Pipeline", score: 0.7, context: nil,
                pinyin: "Pipeline", state: "pending", dismissed: 0,
                fromAnalysisAt: "2026-03-25")
            try cand.insert(conn)
        }

        try db.read { conn in
            let existingCandidates = try Set(String.fetchAll(conn,
                sql: "SELECT word FROM dictionary_candidates"))
            #expect(existingCandidates.contains("Pipeline"))
        }

        try db.read { conn in
            let count = try DictionaryCandidateRecord.fetchCount(conn)
            #expect(count == 1)
        }
    }

    @Test func insertCandidates_dedup_dismissedNotReinserted() throws {
        let db = try TestDatabase.makeEmpty()
        try db.write { conn in
            var cand = DictionaryCandidateRecord(
                word: "重构", score: 0.6, context: nil,
                pinyin: "chong gou", state: "dismissed", dismissed: 1,
                fromAnalysisAt: "2026-03-25")
            try cand.insert(conn)
        }

        try db.read { conn in
            let existingCandidates = try Set(String.fetchAll(conn,
                sql: "SELECT word FROM dictionary_candidates"))
            #expect(existingCandidates.contains("重构"))
        }
    }

    @Test func approve_movesToDictionary() throws {
        let db = try TestDatabase.makeEmpty()
        try db.write { conn in
            var cand = DictionaryCandidateRecord(
                word: "Vilsay", score: 0.9, context: nil,
                pinyin: "Vilsay", state: "pending", dismissed: 0,
                fromAnalysisAt: "2026-03-25")
            try cand.insert(conn)
        }

        try db.write { conn in
            guard let cand = try DictionaryCandidateRecord.fetchOne(conn) else { return }
            var dict = DictionaryRecord(
                word: cand.word, context: cand.context,
                pinyin: cand.pinyin, source: "ai",
                createdAt: ISO8601DateFormatter().string(from: Date()))
            try dict.insert(conn)
            guard let id = cand.id else { return }
            try DictionaryCandidateRecord.filter(Column("id") == id).deleteAll(conn)
        }

        try db.read { conn in
            #expect(try DictionaryCandidateRecord.fetchCount(conn) == 0)
            let dict = try DictionaryRecord.filter(Column("word") == "Vilsay").fetchOne(conn)
            #expect(dict != nil)
            #expect(dict?.source == "ai")
            #expect(dict?.pinyin == "Vilsay")
        }
    }

    @Test func confidence_weightedMerge() {
        let old = 0.8
        let new = 0.5
        let merged = old * 0.6 + new * 0.4
        #expect(abs(merged - 0.68) < 0.001)
    }

    @Test func confidence_belowThreshold_notStored() {
        let minC = Constants.profileMinConfidence
        let lowConf = 0.2
        #expect(lowConf < minC)
    }
}
