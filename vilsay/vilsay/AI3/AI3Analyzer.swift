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
                // 分析成功后同时更新 last_trigger_count + last_analyzed_log_id，
                // 避免触发器因提前更新 trigger_count 而在分析失败时卡死。
                if let maxId = maxAnalyzedId {
                    try db.execute(
                        sql: """
                        UPDATE analyzer_state
                        SET last_run_at = ?,
                            last_analyzed_log_id = ?,
                            last_trigger_count = total_logged_count
                        WHERE id = 1
                        """,
                        arguments: [now, maxId]
                    )
                } else {
                    try db.execute(
                        sql: """
                        UPDATE analyzer_state
                        SET last_run_at = ?,
                            last_trigger_count = total_logged_count
                        WHERE id = 1
                        """,
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
        guard !rows.isEmpty else {
            throw NSError(domain: "AI3Analyzer", code: 1, userInfo: [NSLocalizedDescriptionKey: "空行"])
        }

        // 读取 AI3 已有的认知画像和词典，在本次分析中累积更新
        var existingPortrait = ""
        var existingDictWords: [String] = []
        if let pool = try? AppDatabase.shared.dbPool {
            existingPortrait = (try? await pool.read { db in
                try UserProfileRecord
                    .filter(Column("key") == "ai3_portrait" && Column("output_mode") == profileOutputMode)
                    .fetchOne(db)?.value
            }) ?? ""
            existingDictWords = (try? await pool.read { db in
                try String.fetchAll(db, sql: "SELECT word FROM dictionary UNION SELECT word FROM dictionary_candidates")
            }) ?? []
        }

        var system = """
        你是用户的专属语言分析师。你的任务是通过分析用户的语音记录，逐步深入理解这个人——他的身份、职业、说话风格、思维方式、常提到的人和事。

        你有两个输出任务：

        【任务一：认知画像（portrait）】
        用自然语言写一段关于这个用户的认知画像（200-400字）。这段文字将直接告诉润色 AI「你在为谁服务」。
        画像应包含你能推断出的：
        - 职业/身份（如：程序员、产品经理、学生）
        - 工作领域和常涉及的话题
        - 经常提到的人名、项目名、工具名
        - 说话风格特征（直接/委婉、严谨/随意、中英混用程度）
        - 思维习惯（先说结论还是先铺垫、是否爱举例、话题切换方式）
        - 你观察到的任何其他有助于润色的个人特征

        ⚠️ 重要：画像要写得像是「你对这个人的理解」，而不是一份技术分析报告。
        ⚠️ 只写你有证据支撑的内容，不要猜测或编造。
        ⚠️ 每次分析都在上一次画像基础上更新，不要从头重写，而是修正、补充、加深理解。

        【任务二：结构化分析（JSON）】
        用 JSON 格式返回语言特征和润色质量诊断：
        {
          "style_dimensions": {"warmth": 0.0, "directness": 0.0},
          "habitual_words": [{"word": "...", "action": "keep|simplify|remove", "confidence": 0.0}],
          "thinking_style": {"expand": "...", "topic_switch_signals": ["..."], "close_signals": ["..."], "confidence": 0.0},
          "tone": {"overall": "...", "sentence_length": "short|medium|long", "mixed_lang": "...", "confidence": 0.0},
          "dictionary_candidates": [{"word": "...", "context": "...", "score": 0.0}],
          "correction_gaps": [{"asr_fragment": "...", "polished_fragment": "...", "expected": "...", "gap_type": "missed_typo|missed_pinyin|over_delete|under_delete|wrong_correction", "confidence": 0.0}]
        }

        style_dimensions 说明（基于 Social Style Model, Merrill & Reid）：
        - warmth（表达温度）：0.0 = 完全理性克制（数据驱动、少情感词、客观陈述），1.0 = 完全感性丰富（情感词多、感叹、共情表达、故事性）
        - directness（沟通节奏）：0.0 = 详尽铺垫（先背景再结论、多条件从句、层层展开），1.0 = 精炼直接（先说结论、短句、指令式、省略铺垫）
        请根据本次语音记录中用户的实际表达给出 0~1 之间的观测值。

        dictionary_candidates 要求（宁缺毋滥）：
        - 仅推荐用户实际使用的正确词汇（专有名词、技术术语、品牌名），不含口头禅
        - ASR 原文中的错误拼写绝对不能作为候选词，应放入 correction_gaps
        - word 必须是正确拼写，context 用中文说明语境

        correction_gaps：找出润色遗漏的错误或不当修改。

        【输出格式】
        先输出画像，再输出 JSON，用分隔符隔开：
        ---PORTRAIT---
        （你的认知画像文字）
        ---JSON---
        （JSON 对象）
        """

        // 注入已有画像，让 AI3 在此基础上累积更新
        if !existingPortrait.isEmpty {
            system += "\n\n【你之前对这个用户的认知画像】\n\(existingPortrait)\n请在此基础上更新，保留仍然正确的内容，修正不准确的部分，补充新发现。"
        }

        let pairedLines = rows.enumerated().map { i, row in
            "\(i + 1). ASR：\(row.asrText)\n   润色：\(row.polishedText)"
        }.joined(separator: "\n")
        var user = """
        以下是最近 \(rows.count) 条语音记录（ASR 原文 + 润色结果）：
        \(pairedLines)
        """
        if !existingDictWords.isEmpty {
            user += "\n\n用户词典已有以下词汇（不要重复推荐）：\(existingDictWords.joined(separator: "、"))"
        }
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
        req.timeoutInterval = 60.0  // AI3 分析需要模型输出复杂 JSON，需要足够的超时

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = req.timeoutInterval
        config.timeoutIntervalForResource = req.timeoutInterval * 2
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

        // 解析双段输出：---PORTRAIT--- 和 ---JSON---
        let (portrait, jsonText) = Self.splitPortraitAndJSON(from: text)

        // 保存认知画像
        if let portrait = portrait, !portrait.isEmpty {
            let portraitPool = try? AppDatabase.shared.dbPool
            try? await portraitPool?.write { db in
                try db.execute(
                    sql: """
                    INSERT INTO user_profile (key, value, confidence, updated_at, output_mode)
                    VALUES ('ai3_portrait', ?, 1.0, ?, ?)
                    ON CONFLICT (key, output_mode) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at
                    """,
                    arguments: [portrait, ISO8601DateFormatter().string(from: Date()), profileOutputMode]
                )
            }
            Self.log.info("AI3Analyzer：认知画像已更新（\(portrait.count)字）")
        }

        guard let json = Self.extractJSONObject(from: jsonText ?? text) else {
            let head = String(text.prefix(800))
            Self.log.error("AI3Analyzer：无法解析模型返回的 JSON，正文前 800 字：\(head, privacy: .public)")
            throw NSError(domain: "AI3Analyzer", code: 4, userInfo: nil)
        }
        try await ProfileService.mergeAnalysisJSON(json, outputMode: profileOutputMode)

        // 落库 correction_gaps（润色质量诊断），供后续 Prompt 调优参考
        if let gaps = json["correction_gaps"] as? [[String: Any]], !gaps.isEmpty {
            if let gapsData = try? JSONSerialization.data(withJSONObject: gaps),
               let gapsStr = String(data: gapsData, encoding: .utf8) {
                let gapsPool = try? AppDatabase.shared.dbPool
                try? await gapsPool?.write { db in
                    try db.execute(
                        sql: """
                        INSERT INTO user_profile (key, value, confidence, updated_at, output_mode)
                        VALUES ('correction_gaps', ?, 1.0, ?, ?)
                        ON CONFLICT (key, output_mode) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at
                        """,
                        arguments: [gapsStr, ISO8601DateFormatter().string(from: Date()), profileOutputMode]
                    )
                }
                Self.log.info("AI3Analyzer：发现 \(gaps.count) 个润色纠偏漏洞")
            }
        }
    }

    /// 拆分 ---PORTRAIT--- 和 ---JSON--- 双段输出。
    private static func splitPortraitAndJSON(from text: String) -> (portrait: String?, jsonText: String?) {
        let portraitMarker = "---PORTRAIT---"
        let jsonMarker = "---JSON---"

        // 尝试按分隔符拆分
        if let portraitRange = text.range(of: portraitMarker),
           let jsonRange = text.range(of: jsonMarker) {
            let portrait = String(text[portraitRange.upperBound..<jsonRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let jsonPart = String(text[jsonRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (portrait.isEmpty ? nil : portrait, jsonPart.isEmpty ? nil : jsonPart)
        }

        // 没有分隔符：尝试在 JSON 之前的文本作为 portrait
        if let jsonStart = text.firstIndex(of: "{") {
            let before = String(text[text.startIndex..<jsonStart])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let portrait = before.count >= 20 ? before : nil  // 至少 20 字才算画像
            return (portrait, String(text[jsonStart...]))
        }

        return (nil, nil)
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
