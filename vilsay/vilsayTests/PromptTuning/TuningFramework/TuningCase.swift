//
//  TuningCase.swift
//  vilsay — 调优框架：测试用例定义
//

import Foundation
@testable import vilsay

/// 单条调优测试用例：输入 + 上下文 + 评估维度。
struct TuningCase: Identifiable, Codable {
    let id: String
    let category: String           // e.g. "baseline", "chat", "email", "document", "note", "aiCommand", "edge"
    let description: String        // 人类可读说明

    // ── 输入 ──
    let asrText: String            // 模拟 ASR 转写文本
    let targetBundleID: String?    // 目标应用（nil = general）
    let asrConfidence: Double?     // ASR 置信度（nil = 不注入 §C）

    // ── 用户画像（可选）──
    let profileKey: String?        // "dev" / "biz" / "student" / "med" / "pinyin" / nil

    // ── 评估维度权重（0~1，加总不必为1）──
    let weights: EvalWeights

    // ── 人工参考（可选）：理想输出或关键约束 ──
    let referenceOutput: String?   // 人工写的"金标准"参考（LLM Judge 对比用，非精确匹配）
    let constraints: [String]      // 必须满足的约束描述，e.g. "保留'哈哈'语气词", "不超过30字/bullet"

    struct EvalWeights: Codable {
        var faithfulness: Double = 1.0   // 忠于原意（不丢信息、不加信息）
        var minimalEdit: Double = 1.0    // 最小干预（不过度改写）
        var styleMatch: Double = 1.0     // 符合目标模式风格
        var fluency: Double = 0.5        // 流畅自然
        var formatting: Double = 0.5     // 格式正确（断句、编号、bullet 等）
    }
}

/// 评估结果：每个维度 1~5 分 + 综合评语。
struct TuningResult: Codable {
    let caseID: String
    let promptVariant: String      // 使用的 prompt 版本标识
    let input: String
    let output: String
    let systemPrompt: String

    // ── 各维度得分 1~5 ──
    var faithfulness: Int = 0
    var minimalEdit: Int = 0
    var styleMatch: Int = 0
    var fluency: Int = 0
    var formatting: Int = 0

    // ── LLM Judge 综合评语 ──
    var commentary: String = ""

    // ── 加权总分 ──
    var weightedScore: Double = 0.0

    // ── 元数据 ──
    var durationMs: Int = 0
    var timestamp: String = ""
    var judgeRaw: String = ""      // Judge LLM 原始返回（调试用）
}

/// 批次报告：一组用例的汇总。
struct TuningReport: Codable {
    let variant: String            // prompt 版本
    let timestamp: String
    let results: [TuningResult]

    var averageScore: Double {
        guard !results.isEmpty else { return 0 }
        return results.map(\.weightedScore).reduce(0, +) / Double(results.count)
    }

    var categoryAverages: [String: Double] {
        var groups: [String: [Double]] = [:]
        for r in results {
            let cat = r.caseID.components(separatedBy: "_").first ?? "unknown"
            groups[cat, default: []].append(r.weightedScore)
        }
        return groups.mapValues { $0.reduce(0, +) / Double($0.count) }
    }

    func markdown() -> String {
        var md = "# 调优报告：\(variant)\n"
        md += "时间：\(timestamp)\n\n"
        md += "## 总分：\(String(format: "%.2f", averageScore)) / 5.0\n\n"

        md += "## 分类平均\n"
        for (cat, avg) in categoryAverages.sorted(by: { $0.key < $1.key }) {
            md += "- \(cat): \(String(format: "%.2f", avg))\n"
        }
        md += "\n## 详细结果\n\n"
        md += "| ID | 得分 | 忠实 | 干预 | 风格 | 流畅 | 格式 | 评语 |\n"
        md += "|---|---|---|---|---|---|---|---|\n"
        for r in results {
            md += "| \(r.caseID) | \(String(format: "%.1f", r.weightedScore)) | \(r.faithfulness) | \(r.minimalEdit) | \(r.styleMatch) | \(r.fluency) | \(r.formatting) | \(r.commentary.prefix(60)) |\n"
        }

        // 低分项
        let lowScorers = results.filter { $0.weightedScore < 3.0 }.sorted(by: { $0.weightedScore < $1.weightedScore })
        if !lowScorers.isEmpty {
            md += "\n## 需关注（< 3.0）\n"
            for r in lowScorers {
                md += "- **\(r.caseID)** (\(String(format: "%.1f", r.weightedScore))): \(r.commentary)\n"
            }
        }
        return md
    }
}
