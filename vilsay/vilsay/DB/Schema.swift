//
//  Schema.swift
//  GRDB Record 定义（W5-01 / V14-01）。
//

import Foundation
import GRDB

struct RawLogRecord: Codable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var asrText: String
    var polishedText: String
    var durationMs: Int?
    var sessionId: String?
    var asrProvider: String?
    var asrConfidence: Double?
    var targetAppId: String?
    var userFlaggedError: Bool
    var createdAt: String
    /// PM-07：`OutputMode.rawValue`，默认 `general`。
    var outputMode: String

    static let databaseTableName = "raw_log"

    enum CodingKeys: String, CodingKey {
        case id
        case asrText = "asr_text"
        case polishedText = "polished_text"
        case durationMs = "duration_ms"
        case sessionId = "session_id"
        case asrProvider = "asr_provider"
        case asrConfidence = "asr_confidence"
        case targetAppId = "target_app_id"
        case userFlaggedError = "user_flagged_error"
        case createdAt = "created_at"
        case outputMode = "output_mode"
    }

    init(
        id: Int64? = nil,
        asrText: String,
        polishedText: String,
        durationMs: Int? = nil,
        sessionId: String? = nil,
        asrProvider: String? = nil,
        asrConfidence: Double? = nil,
        targetAppId: String? = nil,
        userFlaggedError: Bool = false,
        createdAt: String,
        outputMode: String = "general"
    ) {
        self.id = id
        self.asrText = asrText
        self.polishedText = polishedText
        self.durationMs = durationMs
        self.sessionId = sessionId
        self.asrProvider = asrProvider
        self.asrConfidence = asrConfidence
        self.targetAppId = targetAppId
        self.userFlaggedError = userFlaggedError
        self.createdAt = createdAt
        self.outputMode = outputMode
    }
}

struct UserProfileRecord: Codable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var key: String
    var value: String
    var confidence: Double
    var updatedAt: String
    /// PM-09：`__global__` 或 `OutputMode.rawValue`。
    var outputMode: String

    static let databaseTableName = "user_profile"

    enum CodingKeys: String, CodingKey {
        case id, key, value, confidence
        case updatedAt = "updated_at"
        case outputMode = "output_mode"
    }

    init(
        id: Int64? = nil,
        key: String,
        value: String,
        confidence: Double,
        updatedAt: String,
        outputMode: String = "__global__"
    ) {
        self.id = id
        self.key = key
        self.value = value
        self.confidence = confidence
        self.updatedAt = updatedAt
        self.outputMode = outputMode
    }
}

struct DictionaryRecord: Codable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var word: String
    var context: String?
    var pinyin: String?
    var source: String
    var createdAt: String

    static let databaseTableName = "dictionary"

    enum CodingKeys: String, CodingKey {
        case id, word, context, pinyin, source
        case createdAt = "created_at"
    }
}

struct DictionaryCandidateRecord: Codable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var word: String
    var score: Double
    var context: String?
    var pinyin: String?
    /// `pending` / `approved` / `dismissed`（V14）；`dismissed` 列保留兼容旧逻辑。
    var state: String
    var dismissed: Int
    var fromAnalysisAt: String

    static let databaseTableName = "dictionary_candidates"

    enum CodingKeys: String, CodingKey {
        case id, word, score, context, pinyin, state, dismissed
        case fromAnalysisAt = "from_analysis_at"
    }

    init(
        id: Int64? = nil,
        word: String,
        score: Double,
        context: String?,
        pinyin: String? = nil,
        state: String = "pending",
        dismissed: Int = 0,
        fromAnalysisAt: String
    ) {
        self.id = id
        self.word = word
        self.score = score
        self.context = context
        self.pinyin = pinyin
        self.state = state
        self.dismissed = dismissed
        self.fromAnalysisAt = fromAnalysisAt
    }
}

struct AnalyzerStateRecord: Codable, FetchableRecord, PersistableRecord {
    var id: Int64
    var totalLoggedCount: Int
    var lastTriggerCount: Int
    var lastAnalyzedLogId: Int64?
    var lastRunAt: String?

    static let databaseTableName = "analyzer_state"

    enum CodingKeys: String, CodingKey {
        case id
        case totalLoggedCount = "total_logged_count"
        case lastTriggerCount = "last_trigger_count"
        case lastAnalyzedLogId = "last_analyzed_log_id"
        case lastRunAt = "last_run_at"
    }
}
