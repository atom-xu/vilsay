//
//  TuningIntegrationTests.swift
//  vilsay — 调优框架集成测试
//
//  运行方式：
//    DASHSCOPE_API_KEY=sk-xxx xcodebuild test \
//      -project vilsay.xcodeproj -scheme vilsay \
//      -only-testing "vilsayTests/TuningIntegrationTests" \
//      DASHSCOPE_API_KEY=sk-xxx 2>&1 | xcbeautify
//
//  报告输出：~/Desktop/VilsayTuningReports/
//

import Foundation
import Testing
@testable import vilsay

@Suite("调优框架集成测试")
struct TuningIntegrationTests {

    /// 快速验证：跑 3 条基线用例，确认框架链路通畅。
    @Test("smoke: 框架链路验证")
    func smokeTest() async {
        guard PromptTuningHelper.apiKey != nil else { return }

        let cases = Array(TuningCaseRegistry.baseline.prefix(3))
        let report = await TuningRunner.run(cases: cases, variant: "smoke", concurrency: 1)

        #expect(report.results.count == 3)
        var log = ""
        for r in report.results {
            let line = "[\(r.caseID)] score=\(String(format: "%.1f", r.weightedScore)) 忠=\(r.faithfulness) 干=\(r.minimalEdit) 风=\(r.styleMatch) 畅=\(r.fluency) 格=\(r.formatting) | \(r.commentary)"
            print(line)
            log += line + "\n"
            log += "  输入: \(r.input.prefix(60))\n"
            log += "  输出: \(r.output.prefix(80))\n\n"
            #expect(r.weightedScore > 0, "评分不应为0: \(r.caseID)")
            #expect(!r.output.isEmpty, "输出不应为空: \(r.caseID)")
        }
        let summary = "[smoke] 平均分: \(String(format: "%.2f", report.averageScore))"
        print(summary)
        log += summary + "\n"
        try? log.write(toFile: "/tmp/vilsay_smoke_result.txt", atomically: true, encoding: .utf8)
    }

    /// 按 category 分别跑，输出分类报告。
    @Test("full: baseline 用例全量评估")
    func baselineFullTest() async {
        guard PromptTuningHelper.apiKey != nil else { return }

        let report = await TuningRunner.run(
            cases: TuningCaseRegistry.baseline,
            variant: "v4_baseline",
            concurrency: 2
        )
        printReport(report)
        #expect(report.averageScore >= 2.5, "基线平均分不应低于 2.5")
    }

    @Test("full: chat 用例全量评估")
    func chatFullTest() async {
        guard PromptTuningHelper.apiKey != nil else { return }

        let report = await TuningRunner.run(
            cases: TuningCaseRegistry.chat,
            variant: "v4_chat",
            concurrency: 2
        )
        printReport(report)
        #expect(report.averageScore >= 2.5, "聊天模式平均分不应低于 2.5")
    }

    @Test("full: email 用例全量评估")
    func emailFullTest() async {
        guard PromptTuningHelper.apiKey != nil else { return }

        let report = await TuningRunner.run(
            cases: TuningCaseRegistry.email,
            variant: "v4_email",
            concurrency: 2
        )
        printReport(report)
        #expect(report.averageScore >= 2.5)
    }

    @Test("full: document 用例全量评估")
    func documentFullTest() async {
        guard PromptTuningHelper.apiKey != nil else { return }

        let report = await TuningRunner.run(
            cases: TuningCaseRegistry.document,
            variant: "v4_document",
            concurrency: 2
        )
        printReport(report)
        #expect(report.averageScore >= 2.5)
    }

    @Test("full: note 用例全量评估")
    func noteFullTest() async {
        guard PromptTuningHelper.apiKey != nil else { return }

        let report = await TuningRunner.run(
            cases: TuningCaseRegistry.note,
            variant: "v4_note",
            concurrency: 2
        )
        printReport(report)
        #expect(report.averageScore >= 2.5)
    }

    @Test("full: edge 用例评估")
    func edgeFullTest() async {
        guard PromptTuningHelper.apiKey != nil else { return }

        let report = await TuningRunner.run(
            cases: TuningCaseRegistry.edge,
            variant: "v4_edge",
            concurrency: 1  // 边界用例串行，避免并发异常
        )
        printReport(report)
    }

    @Test("full: longText 核心竞争力场景")
    func longTextFullTest() async {
        guard PromptTuningHelper.apiKey != nil else { return }

        let report = await TuningRunner.run(
            cases: TuningCaseRegistry.longText,
            variant: "v4_longText",
            concurrency: 1  // 长文本API耗时长，串行
        )
        printReport(report)
        #expect(report.averageScore >= 2.5, "长文本平均分不应低于 2.5（核心竞争力）")
    }

    @Test("full: profile 联动评估")
    func profileFullTest() async {
        guard PromptTuningHelper.apiKey != nil else { return }

        let report = await TuningRunner.run(
            cases: TuningCaseRegistry.profile,
            variant: "v4_profile",
            concurrency: 1
        )
        printReport(report)
        #expect(report.averageScore >= 2.5)
    }

    /// 全量：所有用例一次性跑完，生成完整报告文件。
    @Test("全量评估 + 报告生成")
    func fullSuiteWithReport() async throws {
        guard PromptTuningHelper.apiKey != nil else { return }

        let report = await TuningRunner.run(
            cases: TuningCaseRegistry.allCases,
            variant: "v4_full_67",
            concurrency: 1
        )

        printReport(report)

        let desktopDir = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Desktop/VilsayTuningReports")
        let fallbackDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VilsayTuningReports", isDirectory: true)
        do {
            try TuningRunner.saveReport(report, to: desktopDir)
            print("[全量] 报告已保存至: \(desktopDir.path)")
        } catch {
            try TuningRunner.saveReport(report, to: fallbackDir)
            print("[全量] 桌面目录写入失败，已改为临时目录: \(fallbackDir.path) — \(error.localizedDescription)")
        }
    }

    // MARK: - A/B 对比示例

    /// 演示如何做 A/B 对比：当前 prompt vs 修改后的 prompt。
    @Test("A/B 对比示例：chat 模式微调")
    func abCompareChatExample() async {
        guard PromptTuningHelper.apiKey != nil else { return }

        // 变体 B：尝试在 chat 模式加强"保留语气词"指令
        let tweakedChatPrompt: (TuningCase, OutputMode) -> String = { tc, mode in
            if mode == .chat {
                // 在原始 prompt 基础上追加一条规则
                let base = PromptComposer.systemPrompt(
                    for: nil,
                    targetAppBundleID: tc.targetBundleID,
                    asrConfidence: tc.asrConfidence
                )
                return base + "\n\n【追加规则】语气词（哈哈、嗯嗯、唉、对对对）必须100%保留，不得删除或替换。"
            }
            return PromptComposer.systemPrompt(
                for: nil,
                targetAppBundleID: tc.targetBundleID,
                asrConfidence: tc.asrConfidence
            )
        }

        let md = await TuningRunner.abCompare(
            cases: TuningCaseRegistry.chat,
            variantA: "v4_chat_current",
            promptA: nil,
            variantB: "v4_chat_tweaked",
            promptB: tweakedChatPrompt,
            concurrency: 1
        )

        print(md)
    }

    // MARK: - Helpers

    private func printReport(_ report: TuningReport) {
        var log = "━━━ \(report.variant) ━━━\n"
        log += "平均分: \(String(format: "%.2f", report.averageScore)) / 5.0\n"
        for r in report.results {
            let bar = String(repeating: "█", count: Int(r.weightedScore))
            let line = "  \(r.caseID.padding(toLength: 15, withPad: " ", startingAt: 0)) \(bar) \(String(format: "%.1f", r.weightedScore)) 忠=\(r.faithfulness) 干=\(r.minimalEdit) 风=\(r.styleMatch) 畅=\(r.fluency) 格=\(r.formatting) | \(r.commentary.prefix(60))"
            log += line + "\n"
            log += "    输入: \(r.input.prefix(60))\n"
            log += "    输出: \(r.output.prefix(80))\n"
        }
        log += "━━━━━━━━━━━━━━━\n"
        print(log)
        // 追加写到文件
        let path = "/tmp/vilsay_tuning_\(report.variant).txt"
        try? log.write(toFile: path, atomically: true, encoding: .utf8)
    }
}
