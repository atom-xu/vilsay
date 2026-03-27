//
//  TuningEvaluator.swift
//  vilsay — 调优框架：LLM-as-Judge 评估引擎
//
//  核心原则：用 LLM 理解语义来评分，不做关键词匹配。
//  评估模型可以是 Qwen 自身（自评）或外部模型（交叉评）。
//

import Foundation
@testable import vilsay

enum TuningEvaluator {

    // MARK: - Judge Prompt（核心：让 LLM 理解质量维度，而非关键词匹配）

    /// 构造 Judge 的 system prompt。
    private static func judgeSystemPrompt() -> String {
        """
        你是一位语音转写润色质量评估专家。你的任务是评估"润色结果"相对于"原始输入"的质量。

        评估维度（每项 1~5 分）：
        1. faithfulness（忠于原意）：润色后是否完整保留了原文的全部信息和意图？是否添加了原文没有的内容？
           - 5分：信息零丢失零添加
           - 3分：有轻微信息损失或添加但不影响理解
           - 1分：严重丢失关键信息或添加了大量原文没有的内容
        2. minimalEdit（最小干预）：修改幅度是否恰当？是否只做了必要的修改？
           - 5分：只修改了确实需要修改的地方（错别字、断句、填充词）
           - 3分：有些不必要的改写但整体可接受
           - 1分：大幅改写，面目全非
        3. styleMatch（风格匹配）：输出风格是否符合目标场景？
           - 5分：完美匹配目标风格（如聊天保留口语、邮件正式得体）
           - 3分：风格基本正确但有偏差
           - 1分：风格完全不匹配（如聊天场景输出了正式书面语）
        4. fluency（流畅自然）：读起来是否通顺自然？
           - 5分：非常自然流畅
           - 3分：基本通顺但有生硬处
           - 1分：读起来不通顺或机器感强
        5. formatting（格式正确）：标点、分段、编号等格式是否正确？
           - 5分：格式完美适配场景
           - 3分：格式基本正确
           - 1分：格式混乱或不适配场景

        你必须严格按以下 JSON 格式返回，不要添加任何其他文字：
        {"faithfulness":N,"minimalEdit":N,"styleMatch":N,"fluency":N,"formatting":N,"commentary":"一句话评语"}

        其中 N 是 1~5 的整数。commentary 用中文，不超过 100 字。
        """
    }

    /// 构造 Judge 的 user message。
    private static func judgeUserMessage(
        input: String,
        output: String,
        mode: OutputMode,
        constraints: [String],
        referenceOutput: String?
    ) -> String {
        var msg = """
        【原始输入】
        \(input)

        【润色结果】
        \(output)

        【目标场景】\(mode.title)
        """

        if !constraints.isEmpty {
            msg += "\n\n【质量约束（必须满足）】\n"
            for (i, c) in constraints.enumerated() {
                msg += "\(i + 1). \(c)\n"
            }
        }

        if let ref = referenceOutput {
            msg += "\n\n【参考输出（仅供对比，不要求完全一致）】\n\(ref)"
        }

        msg += "\n\n请评估润色结果的质量，严格按 JSON 格式返回。"
        return msg
    }

    // MARK: - 评估执行

    /// 对单条结果执行 LLM Judge 评估。
    static func evaluate(
        tuningCase: TuningCase,
        input: String,
        output: String,
        systemPrompt: String,
        mode: OutputMode
    ) async -> TuningResult {
        let start = DispatchTime.now()

        let judgeSystem = judgeSystemPrompt()
        let judgeUser = judgeUserMessage(
            input: input,
            output: output,
            mode: mode,
            constraints: tuningCase.constraints,
            referenceOutput: tuningCase.referenceOutput
        )

        // 调用同一个 PolishService（复用 API Key），但用 Judge prompt
        let judgeResponse = await PolishService.polishPlain(system: judgeSystem, user: judgeUser)

        let elapsed = Int((DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000)

        var result = TuningResult(
            caseID: tuningCase.id,
            promptVariant: "v4_current",
            input: input,
            output: output,
            systemPrompt: systemPrompt,
            durationMs: elapsed,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            judgeRaw: judgeResponse
        )

        // 解析 JSON 评分
        parseJudgeResponse(judgeResponse, into: &result)

        // 加权计算总分
        let w = tuningCase.weights
        let totalWeight = w.faithfulness + w.minimalEdit + w.styleMatch + w.fluency + w.formatting
        guard totalWeight > 0 else {
            result.weightedScore = 0
            return result
        }
        result.weightedScore = (
            Double(result.faithfulness) * w.faithfulness +
            Double(result.minimalEdit) * w.minimalEdit +
            Double(result.styleMatch) * w.styleMatch +
            Double(result.fluency) * w.fluency +
            Double(result.formatting) * w.formatting
        ) / totalWeight

        return result
    }

    /// 解析 Judge LLM 返回的 JSON。容错：即使格式不标准也尽量提取。
    private static func parseJudgeResponse(_ raw: String, into result: inout TuningResult) {
        // 尝试直接 JSON 解析
        let cleaned = raw
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // 找到第一个 { 和最后一个 }
        guard let start = cleaned.firstIndex(of: "{"),
              let end = cleaned.lastIndex(of: "}") else {
            result.commentary = "Judge 返回格式异常: \(raw.prefix(100))"
            // 给默认中间分
            result.faithfulness = 3; result.minimalEdit = 3
            result.styleMatch = 3; result.fluency = 3; result.formatting = 3
            return
        }

        let jsonStr = String(cleaned[start...end])
        guard let data = jsonStr.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            result.commentary = "Judge JSON 解析失败: \(jsonStr.prefix(100))"
            result.faithfulness = 3; result.minimalEdit = 3
            result.styleMatch = 3; result.fluency = 3; result.formatting = 3
            return
        }

        func score(_ key: String) -> Int {
            if let v = dict[key] as? Int { return max(1, min(5, v)) }
            if let v = dict[key] as? Double { return max(1, min(5, Int(v))) }
            return 3
        }

        result.faithfulness = score("faithfulness")
        result.minimalEdit = score("minimalEdit")
        result.styleMatch = score("styleMatch")
        result.fluency = score("fluency")
        result.formatting = score("formatting")
        result.commentary = dict["commentary"] as? String ?? ""
    }
}
