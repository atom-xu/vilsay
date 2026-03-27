//
//  AI3Analyzer.swift
//  W5-05：读 raw_log → Qwen → 写 profile / candidates。
//

import Foundation
import GRDB
import os.log

final class AI3Analyzer {
    static let shared = AI3Analyzer()

    private static let log = Logger(subsystem: "com.vilsay.app", category: "AI3Analyzer")

    private init() {}

    func analyze() async {
        #if DEBUG
        Self.log.info("AI3Analyzer：开始分析（DEBUG）")
        #endif

        guard let pool = try? AppDatabase.shared.dbPool else {
            Self.log.error("AI3Analyzer：数据库不可用，跳过")
            return
        }

        guard let apiKey = AppConfig.dashscopeAPIKey, !apiKey.isEmpty else {
            Self.log.error("AI3Analyzer：无 DASHSCOPE API Key，跳过分析")
            return
        }

        let rowsForPrompt: [RawLogRecord]
        do {
            rowsForPrompt = try await pool.read { db in
                let lastId = try AnalyzerStateRecord.fetchOne(db)?.lastAnalyzedLogId
                if let last = lastId, last > 0 {
                    let rows = try RawLogRecord
                        .filter(Column("id") > last)
                        .order(Column("id").asc)
                        .limit(Constants.analyzerRecentSessions)
                        .fetchAll(db)
                    return rows
                }
                let recent = try RawLogRecord
                    .order(Column("id").desc)
                    .limit(Constants.analyzerRecentSessions)
                    .fetchAll(db)
                return recent.reversed()
            }
        } catch {
            Self.log.error("AI3Analyzer：读 raw_log 失败 \(error.localizedDescription)")
            return
        }

        guard !rowsForPrompt.isEmpty else {
            Self.log.info("AI3Analyzer：无可用 raw_log 行，跳过")
            return
        }

        let flagged = await ErrorFeedbackService.getFlaggedErrors()

        // 全局画像（V3 行为）
        do {
            try await Self.analyzeAndMerge(
                rows: rowsForPrompt,
                profileOutputMode: "__global__",
                flagged: flagged,
                apiKey: apiKey
            )
        } catch {
            Self.log.error("AI3Analyzer：全局分析失败 \(error.localizedDescription)")
            return
        }

        // 按 output_mode 分组（非 general 且 ≥5 条）
        let grouped = Dictionary(grouping: rowsForPrompt, by: \.outputMode)
        for (modeRaw, logs) in grouped where modeRaw != "general" && logs.count >= 5 {
            do {
                try await Self.analyzeAndMerge(
                    rows: logs,
                    profileOutputMode: modeRaw,
                    flagged: flagged,
                    apiKey: apiKey
                )
                Self.log.info("AI3Analyzer：已写入 \(modeRaw) 分组画像（\(logs.count) 条）")
            } catch {
                Self.log.error("AI3Analyzer：分组 \(modeRaw) 分析失败 \(error.localizedDescription)")
            }
        }

        let now = ISO8601DateFormatter().string(from: Date())
        let maxAnalyzedId = rowsForPrompt.compactMap(\.id).max()
        do {
            try await pool.write { db in
                if let maxId = maxAnalyzedId {
                    try db.execute(
                        sql: """
                        UPDATE analyzer_state
                        SET last_run_at = ?, last_analyzed_log_id = ?
                        WHERE id = 1
                        """,
                        arguments: [now, maxId]
                    )
                } else {
                    try db.execute(
                        sql: "UPDATE analyzer_state SET last_run_at = ? WHERE id = 1",
                        arguments: [now]
                    )
                }
            }
        } catch {
            Self.log.error("AI3Analyzer：更新 analyzer_state 失败 \(error.localizedDescription)")
        }

        let pending = await ProfileService.getCandidatesAsync().count
        let analyzedCount = rowsForPrompt.count
        await MainActor.run {
            AppState.shared.candidatesCount = pending
            AppState.shared.dictionaryBadgeCount = pending
            AppState.shared.ai3LastAnalysisResult = "已分析 \(analyzedCount) 条会话"
            AppState.shared.ai3LastAnalysisDate = Date()
        }
        Self.log.info("AI3Analyzer：分析完成，\(analyzedCount) 条 raw_log，候选词 \(pending) 个")
    }

    /// 单次 LLM 调用 + 落库（`profileOutputMode` 为 `user_profile.output_mode`）。
    private static func analyzeAndMerge(
        rows: [RawLogRecord],
        profileOutputMode: String,
        flagged: [RawLogRecord],
        apiKey: String
    ) async throws {
        let asrLines = rows.map(\.asrText)
        guard !asrLines.isEmpty else {
            throw NSError(domain: "AI3Analyzer", code: 1, userInfo: [NSLocalizedDescriptionKey: "空行"])
        }

        let system = """
        你是一个语言习惯分析助手。分析以下用户的语音转写记录，提取用户的语言特征。
        用 JSON 格式返回，包含以下字段：
        {
          "habitual_words": [{"word": "...", "action": "keep|simplify|remove", "confidence": 0.0}],
          "thinking_style": {"expand": "...", "topic_switch_signals": ["..."], "close_signals": ["..."], "confidence": 0.0},
          "tone": {"overall": "...", "sentence_length": "short|medium|long", "mixed_lang": "...", "confidence": 0.0},
          "dictionary_candidates": [{"word": "...", "context": "...", "score": 0.0}]
        }
        所有字段均可为空数组或 null，不得编造。
        vocabulary 候选词仅提取名词、专有名词、缩写，不含口头禅。
        """

        let numbered = asrLines.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        var user = """
        以下是最近 \(asrLines.count) 条语音记录（仅原始转写，非润色结果）：
        \(numbered)
        """
        if !flagged.isEmpty {
            let fb = flagged.prefix(12).enumerated().map { i, row in
                "\(i + 1). ASR：\(row.asrText) ｜ 润色：\(row.polishedText)"
            }.joined(separator: "\n")
            user += "\n\n以下记录被用户标记为识别/润色有误，请特别关注这些错误模式：\n\(fb)"
        }

        let body: [String: Any] = [
            "model": AppConfig.dashscopeAnalyzerModel,
            "input": [
                "messages": [
                    ["role": "system", "content": system],
                    ["role": "user", "content": user],
                ],
            ],
            "parameters": ["result_format": "message"],
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            Self.log.error("AI3Analyzer：请求 JSON 序列化失败")
            throw NSError(domain: "AI3Analyzer", code: 2, userInfo: nil)
        }

        var req = URLRequest(url: AppConfig.qwenPolishEndpoint)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = httpBody
        req.timeoutInterval = Double(Constants.polishTimeoutMs) / 1000.0 * 2

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = req.timeoutInterval
        let session = URLSession(configuration: config)

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            Self.log.error("AI3Analyzer：API 返回 HTTP \(code)")
            throw NSError(domain: "AI3Analyzer", code: code, userInfo: nil)
        }
        _ = http
        guard let text = PolishStreamParsing.nativeNonStreamQwenContent(from: data) else {
            Self.log.error("AI3Analyzer：无法解析模型输出正文")
            throw NSError(domain: "AI3Analyzer", code: 3, userInfo: nil)
        }
        guard let json = Self.extractJSONObject(from: text) else {
            let head = String(text.prefix(800))
            Self.log.error("AI3Analyzer：无法解析模型返回的 JSON，正文前 800 字：\(head, privacy: .public)")
            throw NSError(domain: "AI3Analyzer", code: 4, userInfo: nil)
        }
        try await ProfileService.mergeAnalysisJSON(json, outputMode: profileOutputMode)
    }

    /// 从模型输出中截取 JSON 对象（可带 ```json 围栏）。
    private static func extractJSONObject(from text: String) -> [String: Any]? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            if let start = s.firstIndex(of: "{") {
                s = String(s[start...])
            }
            if let end = s.lastIndex(of: "}") {
                s = String(s[...end])
            }
        }
        guard let data = s.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return obj
    }
}
