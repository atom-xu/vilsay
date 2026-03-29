//
//  TuningRunner.swift
//  vilsay — 调优框架：批量执行引擎
//
//  用法：
//    1. 选择用例集（全量 / 按类别 / 按 ID 列表）
//    2. 可选：传入 prompt 变体（A/B 对比）
//    3. 执行 → 生成 TuningReport
//    4. 输出 Markdown 或 JSON 供多方审阅
//

import Foundation
@testable import vilsay

enum TuningRunner {

    /// 执行一批调优用例，返回报告。
    ///
    /// - Parameters:
    ///   - cases: 要执行的用例
    ///   - variant: 当前 prompt 版本标识（如 "v4.0", "v4.1-chat-tweak"）
    ///   - promptOverride: 可选的 system prompt 覆盖（用于 A/B 测试）；nil 则用当前 PromptComposer
    ///   - concurrency: 并发数（避免 API 限流）
    static func run(
        cases: [TuningCase],
        variant: String = "v4_current",
        promptOverride: ((TuningCase, OutputMode) -> String)? = nil,
        concurrency: Int = 3
    ) async -> TuningReport {
        var results: [TuningResult] = []

        // 串行 / 限流执行（Qwen API 限流较严，不宜过高并发）
        for batch in cases.chunked(into: concurrency) {
            await withTaskGroup(of: TuningResult.self) { group in
                for tc in batch {
                    group.addTask {
                        await executeSingle(tc, variant: variant, promptOverride: promptOverride)
                    }
                }
                for await result in group {
                    results.append(result)
                }
            }
        }

        // 按 caseID 排序
        results.sort { $0.caseID < $1.caseID }

        return TuningReport(
            variant: variant,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            results: results
        )
    }

    /// 执行单条用例：compose prompt → polish → judge。
    private static func executeSingle(
        _ tc: TuningCase,
        variant: String,
        promptOverride: ((TuningCase, OutputMode) -> String)?
    ) async -> TuningResult {
        let profile = resolveProfile(tc.profileKey)
        let mode = OutputModeResolver.resolve(bundleID: tc.targetBundleID)

        let systemPrompt: String
        if let override = promptOverride {
            systemPrompt = override(tc, mode)
        } else {
            systemPrompt = PromptComposer.systemPrompt(
                for: profile,
                targetAppBundleID: tc.targetBundleID,
                asrConfidence: tc.asrConfidence
            )
        }

        let userMsg = Prompts.polishUserMessage(asrText: tc.asrText)
        let polished = await PolishService.polishPlain(system: systemPrompt, user: userMsg)

        var result = await TuningEvaluator.evaluate(
            tuningCase: tc,
            input: tc.asrText,
            output: polished,
            systemPrompt: systemPrompt,
            mode: mode
        )
        result = TuningResult(
            caseID: tc.id,
            promptVariant: variant,
            input: tc.asrText,
            output: polished,
            systemPrompt: systemPrompt,
            faithfulness: result.faithfulness,
            minimalEdit: result.minimalEdit,
            styleMatch: result.styleMatch,
            fluency: result.fluency,
            formatting: result.formatting,
            commentary: result.commentary,
            weightedScore: result.weightedScore,
            durationMs: result.durationMs,
            timestamp: result.timestamp,
            judgeRaw: result.judgeRaw
        )
        return result
    }

    /// 从预置画像 key 映射到 UserProfile。
    private static func resolveProfile(_ key: String?) -> UserProfile? {
        guard let key else { return nil }
        switch key {
        case "dev": return PromptTuningHelper.devProfile
        case "biz": return PromptTuningHelper.bizProfile
        case "student": return PromptTuningHelper.studentProfile
        case "med": return PromptTuningHelper.medProfile
        case "pinyin": return PromptTuningHelper.pinyinHeavyProfile
        case "empty": return PromptTuningHelper.emptyProfile
        default: return nil
        }
    }

    // MARK: - A/B 对比

    /// 对同一组用例跑两个 prompt 变体，生成对比报告。
    static func abCompare(
        cases: [TuningCase],
        variantA: String,
        promptA: ((TuningCase, OutputMode) -> String)? = nil,
        variantB: String,
        promptB: @escaping (TuningCase, OutputMode) -> String,
        concurrency: Int = 2
    ) async -> String {
        let reportA = await run(cases: cases, variant: variantA, promptOverride: promptA, concurrency: concurrency)
        let reportB = await run(cases: cases, variant: variantB, promptOverride: promptB, concurrency: concurrency)

        var md = "# A/B 对比报告\n\n"
        md += "| 变体 | 平均分 | 用例数 |\n|---|---|---|\n"
        md += "| \(variantA) | \(String(format: "%.2f", reportA.averageScore)) | \(reportA.results.count) |\n"
        md += "| \(variantB) | \(String(format: "%.2f", reportB.averageScore)) | \(reportB.results.count) |\n\n"

        md += "## 分类对比\n\n"
        md += "| 类别 | \(variantA) | \(variantB) | Δ |\n|---|---|---|---|\n"
        let allCats = Set(reportA.categoryAverages.keys).union(reportB.categoryAverages.keys).sorted()
        for cat in allCats {
            let a = reportA.categoryAverages[cat] ?? 0
            let b = reportB.categoryAverages[cat] ?? 0
            let delta = b - a
            let sign = delta >= 0 ? "+" : ""
            md += "| \(cat) | \(String(format: "%.2f", a)) | \(String(format: "%.2f", b)) | \(sign)\(String(format: "%.2f", delta)) |\n"
        }

        md += "\n## 逐条对比（仅差异 > 0.5 的用例）\n\n"
        let dictB = Dictionary(uniqueKeysWithValues: reportB.results.map { ($0.caseID, $0) })
        for rA in reportA.results {
            guard let rB = dictB[rA.caseID] else { continue }
            let diff = rB.weightedScore - rA.weightedScore
            guard abs(diff) > 0.5 else { continue }
            let arrow = diff > 0 ? "↑" : "↓"
            md += "### \(rA.caseID) \(arrow) \(String(format: "%+.1f", diff))\n"
            md += "- A (\(String(format: "%.1f", rA.weightedScore))): \(rA.commentary)\n"
            md += "- B (\(String(format: "%.1f", rB.weightedScore))): \(rB.commentary)\n\n"
        }

        return md
    }

    // MARK: - 输出

    /// 将报告写入文件（Markdown + JSON）。
    static func saveReport(_ report: TuningReport, to directory: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)

        let ts = report.timestamp.replacingOccurrences(of: ":", with: "-")
        let baseName = "\(report.variant)_\(ts)"

        // Markdown
        let mdURL = directory.appendingPathComponent("\(baseName).md")
        try report.markdown().write(to: mdURL, atomically: true, encoding: .utf8)

        // JSON（机器可读）
        let jsonURL = directory.appendingPathComponent("\(baseName).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(report)
        try jsonData.write(to: jsonURL)
    }
}

// MARK: - Array chunking helper

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        let step = Swift.max(1, size)
        return stride(from: 0, to: count, by: step).map {
            Array(self[$0 ..< Swift.min($0 + step, count)])
        }
    }
}
