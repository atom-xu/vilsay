//
//  ProfileService.swift
//  W5-05 / W5-06：画像与候选词读写。
//

import Foundation
import GRDB
import os.log

enum ProfileService {
    private static let log = Logger(subsystem: "com.vilsay.app", category: "ProfileService")

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        return f
    }()

    /// 从 DB 组装 `UserProfile`（V3：仅 `__global__`）。
    static func getProfile() -> UserProfile? {
        getProfile(for: .general)
    }

    /// per-mode 优先，全局 `__global__` 兜底（与 `OutputMode` 对齐）。
    static func getProfile(for mode: OutputMode) -> UserProfile? {
        guard let pool = try? AppDatabase.shared.dbPool else { return nil }
        do {
            return try pool.read { db in
                if mode != .general {
                    if let p = try Self.assembleProfile(db: db, outputMode: mode.rawValue), !p.isEmpty {
                        return p
                    }
                }
                return try Self.assembleProfile(db: db, outputMode: "__global__")
            }
        } catch {
            Self.log.error("getProfile 失败: \(error.localizedDescription)")
            return nil
        }
    }

    private static func assembleProfile(db: Database, outputMode: String) throws -> UserProfile? {
        var profile = UserProfile()
        if let row = try UserProfileRecord
            .filter(Column("key") == "habitual_words" && Column("output_mode") == outputMode)
            .fetchOne(db) {
            if row.confidence >= Constants.profileMinConfidence,
               let data = row.value.data(using: .utf8),
               let arr = try? JSONDecoder().decode([HabitualWordDTO].self, from: data) {
                profile.habitualWords = arr.map {
                    HabitualWord(
                        word: $0.word,
                        action: $0.action ?? "keep",
                        confidence: $0.confidence ?? 0
                    )
                }
            }
        }

        if let row = try UserProfileRecord
            .filter(Column("key") == "thinking_style" && Column("output_mode") == outputMode)
            .fetchOne(db) {
            if row.confidence >= Constants.profileMinConfidence,
               let data = row.value.data(using: .utf8) {
                let dec = JSONDecoder()
                dec.keyDecodingStrategy = .convertFromSnakeCase
                if let ts = try? dec.decode(ThinkingStyleDTO.self, from: data) {
                    profile.thinkingStyle = ThinkingStyle(
                        expand: ts.expand ?? "",
                        topicSwitchSignals: ts.topicSwitchSignals ?? [],
                        closeSignals: ts.closeSignals ?? [],
                        confidence: row.confidence
                    )
                }
            }
        }

        if let row = try UserProfileRecord
            .filter(Column("key") == "tone" && Column("output_mode") == outputMode)
            .fetchOne(db) {
            if row.confidence >= Constants.profileMinConfidence,
               let data = row.value.data(using: .utf8) {
                let dec = JSONDecoder()
                dec.keyDecodingStrategy = .convertFromSnakeCase
                if let t = try? dec.decode(ToneDTO.self, from: data) {
                    profile.tone = ToneProfile(
                        overall: t.overall ?? "",
                        sentenceLength: t.sentenceLength ?? "medium",
                        mixedLang: t.mixedLang ?? "",
                        confidence: row.confidence
                    )
                }
            }
        }

        let dictRows = try DictionaryRecord.order(Column("created_at").desc).fetchAll(db)
        profile.dictionaryItems = dictRows.prefix(Constants.profileMaxDictItems).map { row in
            DictionaryItem(type: row.source == "ai" ? "AI" : "用语", word: row.word, pinyin: row.pinyin)
        }

        return profile.isEmpty ? nil : profile
    }

    struct DictionaryCandidate: Identifiable, Equatable, Sendable {
        var id: Int64
        var word: String
        var score: Double
        var context: String?
    }

    static func getCandidates() -> [DictionaryCandidate] {
        guard let pool = try? AppDatabase.shared.dbPool else { return [] }
        do {
            return try pool.read { db in
                try Self.fetchPendingCandidates(db: db)
            }
        } catch {
            return []
        }
    }

    /// FIX-07：异步读，避免在 AI3 后台任务中阻塞线程池。
    static func getCandidatesAsync() async -> [DictionaryCandidate] {
        guard let pool = try? AppDatabase.shared.dbPool else { return [] }
        return (try? await pool.read { db in
            try Self.fetchPendingCandidates(db: db)
        }) ?? []
    }

    private static func fetchPendingCandidates(db: Database) throws -> [DictionaryCandidate] {
        let rows = try DictionaryCandidateRecord
            .filter(Column("state") == "pending")
            .order(Column("score").desc)
            .fetchAll(db)
        return rows.compactMap { r -> DictionaryCandidate? in
            guard let id = r.id else { return nil }
            return DictionaryCandidate(id: id, word: r.word, score: r.score, context: r.context)
        }
    }

    static func approveCandidate(id: Int64) async {
        guard let pool = try? AppDatabase.shared.dbPool else { return }
        do {
            try await pool.write { db in
                guard let row = try DictionaryCandidateRecord.fetchOne(db, key: id) else { return }
                var entry = DictionaryRecord(
                    word: row.word,
                    context: row.context,
                    pinyin: row.pinyin ?? PinyinHelper.toPinyin(row.word),
                    source: "ai",
                    createdAt: Self.isoFormatter.string(from: Date())
                )
                try entry.insert(db)
                _ = try DictionaryCandidateRecord.filter(Column("id") == id).deleteAll(db)
            }
        } catch {
            Self.log.error("approveCandidate: \(error.localizedDescription)")
        }
    }

    static func dismissCandidate(id: Int64) async {
        guard let pool = try? AppDatabase.shared.dbPool else { return }
        do {
            try await pool.write { db in
                try db.execute(
                    sql: """
                    UPDATE dictionary_candidates
                    SET dismissed = 1, state = 'dismissed'
                    WHERE id = ?
                    """,
                    arguments: [id]
                )
            }
        } catch {
            Self.log.error("dismissCandidate: \(error.localizedDescription)")
        }
    }

    /// AI3 分析结果落库（W5-05）。`outputMode` 为 `user_profile` 作用域（`__global__` 或 `OutputMode.rawValue`）。
    static func mergeAnalysisJSON(_ data: [String: Any], outputMode: String = "__global__") async throws {
        guard let pool = try? AppDatabase.shared.dbPool else { return }
        let now = Self.isoFormatter.string(from: Date())

        try await pool.write { db in
            if let dims = data["style_dimensions"] as? [String: Any] {
                try mergeStyleDimensions(dims, db: db, now: now, outputMode: outputMode)
            }
            if let hw = data["habitual_words"] as? [[String: Any]] {
                try mergeHabitualWords(hw, db: db, now: now, outputMode: outputMode)
            }
            if let ts = data["thinking_style"] as? [String: Any] {
                try mergeThinkingStyle(ts, db: db, now: now, outputMode: outputMode)
            }
            if let tone = data["tone"] as? [String: Any] {
                try mergeTone(tone, db: db, now: now, outputMode: outputMode)
            }
            if let cands = data["dictionary_candidates"] as? [[String: Any]] {
                try insertCandidates(cands, db: db, now: now)
            }
        }
    }

    /// 口头禅累积合并：新词加入，旧词用 EWMA 衰减置信度，低于阈值才淘汰。
    private static func mergeHabitualWords(_ arr: [[String: Any]], db: Database, now: String, outputMode: String) throws {
        // 读取已有口头禅
        var existing: [[String: Any]] = []
        if let row = try UserProfileRecord
            .filter(Column("key") == "habitual_words" && Column("output_mode") == outputMode)
            .fetchOne(db),
           let data = row.value.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            existing = parsed
        }

        // 按 word 索引已有词
        var wordMap: [String: [String: Any]] = [:]
        for item in existing {
            if let w = item["word"] as? String {
                wordMap[w] = item
            }
        }

        // 合并新数据：已有词 EWMA 更新置信度，新词直接加入
        let alpha = 0.3
        for newItem in arr {
            guard let w = newItem["word"] as? String else { continue }
            let newConf = newItem["confidence"] as? Double ?? 0.5
            let newAction = newItem["action"] as? String ?? "keep"
            if var old = wordMap[w] {
                let oldConf = old["confidence"] as? Double ?? 0.5
                old["confidence"] = alpha * newConf + (1 - alpha) * oldConf
                old["action"] = newAction  // 取最新的 action 判断
                wordMap[w] = old
            } else {
                wordMap[w] = newItem
            }
        }

        // 衰减未在本轮出现的旧词（置信度 × 0.95，自然淘汰）
        let newWords = Set(arr.compactMap { $0["word"] as? String })
        for (w, var item) in wordMap where !newWords.contains(w) {
            let conf = item["confidence"] as? Double ?? 0.5
            item["confidence"] = conf * 0.95
            wordMap[w] = item
        }

        // 过滤低置信度词，排序输出
        let merged = wordMap.values
            .filter { ($0["confidence"] as? Double ?? 0) >= Constants.profileMinConfidence }
            .sorted { ($0["confidence"] as? Double ?? 0) > ($1["confidence"] as? Double ?? 0) }
        let avgConf = merged.compactMap { $0["confidence"] as? Double }.reduce(0, +) / Double(max(1, merged.count))

        let jsonData = try JSONSerialization.data(withJSONObject: merged)
        guard let jsonStr = String(data: jsonData, encoding: .utf8) else { return }
        try mergeProfileKey("habitual_words", value: jsonStr, newConf: avgConf, db: db, now: now, outputMode: outputMode)
    }

    /// 双轴维度 EWMA 累积（代码层计算，不依赖 AI 做数学）。
    private static func mergeStyleDimensions(_ obj: [String: Any], db: Database, now: String, outputMode: String) throws {
        let newWarmth = obj["warmth"] as? Double ?? 0.5
        let newDirectness = obj["directness"] as? Double ?? 0.5
        let alpha = 0.3

        // 读取已有维度
        var storedWarmth = newWarmth
        var storedDirectness = newDirectness
        var storedConfidence = 0.5
        var sampleCount = 0

        if let row = try UserProfileRecord
            .filter(Column("key") == "ai3_dimensions" && Column("output_mode") == outputMode)
            .fetchOne(db),
           let data = row.value.data(using: .utf8),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let oldW = existing["warmth"] as? Double ?? 0.5
            let oldD = existing["directness"] as? Double ?? 0.5
            sampleCount = existing["sample_count"] as? Int ?? 0
            storedConfidence = existing["confidence"] as? Double ?? 0.5
            // EWMA
            storedWarmth = alpha * newWarmth + (1 - alpha) * oldW
            storedDirectness = alpha * newDirectness + (1 - alpha) * oldD
        }

        sampleCount += 1
        // 置信度随样本数渐进 1.0：min(1.0, 0.3 + 0.7 × (n / (n + 10)))
        storedConfidence = min(1.0, 0.3 + 0.7 * (Double(sampleCount) / Double(sampleCount + 10)))

        let merged: [String: Any] = [
            "warmth": storedWarmth,
            "directness": storedDirectness,
            "confidence": storedConfidence,
            "sample_count": sampleCount,
        ]
        let jsonData = try JSONSerialization.data(withJSONObject: merged)
        guard let jsonStr = String(data: jsonData, encoding: .utf8) else { return }
        try mergeProfileKey("ai3_dimensions", value: jsonStr, newConf: storedConfidence, db: db, now: now, outputMode: outputMode)
    }

    private static func mergeThinkingStyle(_ obj: [String: Any], db: Database, now: String, outputMode: String) throws {
        let jsonData = try JSONSerialization.data(withJSONObject: obj)
        guard let jsonStr = String(data: jsonData, encoding: .utf8) else { return }
        let conf = obj["confidence"] as? Double ?? 0
        try mergeProfileKey("thinking_style", value: jsonStr, newConf: conf, db: db, now: now, outputMode: outputMode)
    }

    private static func mergeTone(_ obj: [String: Any], db: Database, now: String, outputMode: String) throws {
        let jsonData = try JSONSerialization.data(withJSONObject: obj)
        guard let jsonStr = String(data: jsonData, encoding: .utf8) else { return }
        let conf = obj["confidence"] as? Double ?? 0
        try mergeProfileKey("tone", value: jsonStr, newConf: conf, db: db, now: now, outputMode: outputMode)
    }

    private static func mergeProfileKey(
        _ key: String,
        value: String,
        newConf: Double,
        db: Database,
        now: String,
        outputMode: String
    ) throws {
        if let existing = try UserProfileRecord
            .filter(Column("key") == key && Column("output_mode") == outputMode)
            .fetchOne(db) {
            let merged = existing.confidence * 0.6 + newConf * 0.4
            if merged < Constants.profileMinConfidence {
                try UserProfileRecord.filter(Column("key") == key && Column("output_mode") == outputMode).deleteAll(db)
                return
            }
            try db.execute(
                sql: """
                UPDATE user_profile SET value = ?, confidence = ?, updated_at = ?
                WHERE key = ? AND output_mode = ?
                """,
                arguments: [value, merged, now, key, outputMode]
            )
        } else {
            guard newConf >= Constants.profileMinConfidence else { return }
            var rec = UserProfileRecord(
                key: key,
                value: value,
                confidence: newConf,
                updatedAt: now,
                outputMode: outputMode
            )
            try rec.insert(db)
        }
    }

    private static func insertCandidates(_ arr: [[String: Any]], db: Database, now: String) throws {
        // 大小写不敏感去重：词典、候选表、本批次
        let existingWords = try Set<String>(String.fetchAll(db, sql: "SELECT LOWER(word) FROM dictionary"))
        let existingCandidateWords = try Set<String>(String.fetchAll(db, sql: "SELECT LOWER(word) FROM dictionary_candidates"))
        var insertedInBatch = Set<String>()

        // ASR 噪声过滤：读取近期 raw_log，如果候选词只出现在 ASR 原文
        // 而从未出现在润色结果中，说明 AI2 每次都把它改掉了——是 ASR 错误，不是真实词汇
        let recentPolished = try String.fetchAll(db, sql: "SELECT polished_text FROM raw_log ORDER BY id DESC LIMIT 100")
        let polishedCorpus = recentPolished.joined(separator: " ")

        for c in arr {
            guard let word = c["word"] as? String, !word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let w = word.trimmingCharacters(in: .whitespacesAndNewlines)
            let wLower = w.lowercased()
            let score = c["score"] as? Double ?? 0.5
            guard score >= 0.5 else { continue }
            // 单字词过滤：单个汉字/字母大概率是 ASR 碎片，不作为候选
            if w.count <= 1 { continue }
            if existingWords.contains(wLower) { continue }
            if existingCandidateWords.contains(wLower) { continue }
            if insertedInBatch.contains(wLower) { continue }
            // ASR 噪声过滤：词从未出现在润色结果中 → AI2 认为它是错的 → 跳过
            if !polishedCorpus.localizedCaseInsensitiveContains(w) {
                Self.log.debug("候选词被过滤（未出现在润色结果中）：\(w)")
                continue
            }
            let ctx = c["context"] as? String
            var rec = DictionaryCandidateRecord(
                word: w,
                score: score,
                context: ctx,
                pinyin: PinyinHelper.toPinyin(w),
                state: "pending",
                dismissed: 0,
                fromAnalysisAt: now
            )
            try rec.insert(db)
            insertedInBatch.insert(wLower)
        }
    }

    private struct HabitualWordDTO: Codable {
        var word: String
        var action: String?
        var confidence: Double?
    }

    private struct ThinkingStyleDTO: Codable {
        var expand: String?
        var topicSwitchSignals: [String]?
        var closeSignals: [String]?
    }

    private struct ToneDTO: Codable {
        var overall: String?
        var sentenceLength: String?
        var mixedLang: String?
    }
}
