//
//  FullSuiteOnlyTest.swift
//  单独运行全量评估，避免与其他测试争抢 QPM 配额
//

import Foundation
import Testing
@testable import vilsay

@Suite("全量评估（独立）")
struct FullSuiteOnlyTest {

    @Test("67 用例全量评估 + 报告生成")
    func fullSuite67() async throws {
        let key = PromptTuningHelper.apiKey
        guard key != nil else { return }

        let report = await TuningRunner.run(
            cases: TuningCaseRegistry.allCases,
            variant: "v4.2_layered",
            concurrency: 1
        )

        // 构建结果文本
        var log = "━━━ \(report.variant) ━━━\n"
        log += "用例数: \(report.results.count)\n"
        log += "平均分: \(String(format: "%.2f", report.averageScore)) / 5.0\n\n"

        let cats = Dictionary(grouping: report.results, by: { String($0.caseID.prefix(while: { $0 != "_" })) })
        for (cat, items) in cats.sorted(by: { $0.key < $1.key }) {
            let avg = items.map(\.weightedScore).reduce(0, +) / Double(items.count)
            log += "  [\(cat)] \(String(format: "%.2f", avg)) (\(items.count)条)\n"
        }
        log += "\n"

        for r in report.results {
            log += "\(r.caseID)|\(String(format: "%.1f", r.weightedScore))|\(r.faithfulness)|\(r.minimalEdit)|\(r.styleMatch)|\(r.fluency)|\(r.formatting)|\(r.commentary.prefix(60))\n"
        }

        let lowScores = report.results.filter { $0.weightedScore < 3.5 }
        if !lowScores.isEmpty {
            log += "\n⚠️ LOW:\n"
            for r in lowScores {
                log += "  \(r.caseID): \(String(format: "%.1f", r.weightedScore)) | \(r.commentary)\n"
            }
        }

        // 尝试多个路径写入
        let paths = [
            FileManager.default.temporaryDirectory.appendingPathComponent("vilsay_full67.txt").path,
            NSTemporaryDirectory() + "vilsay_full67.txt",
            NSHomeDirectory() + "/vilsay_full67.txt",
            "/tmp/vilsay_full67.txt",
            "/Users/atom/Desktop/Vilsay/tuning_output.txt",
        ]
        var writtenTo = "NONE"
        for p in paths {
            do {
                try log.write(toFile: p, atomically: true, encoding: .utf8)
                writtenTo = p
                break
            } catch {
                continue
            }
        }

        // 也尝试写 JSON
        let jsonResults = report.results.map { r -> [String: Any] in
            ["caseID": r.caseID, "weightedScore": r.weightedScore,
             "faithfulness": r.faithfulness, "minimalEdit": r.minimalEdit,
             "styleMatch": r.styleMatch, "fluency": r.fluency,
             "formatting": r.formatting, "commentary": r.commentary,
             "input": r.input, "output": r.output]
        }
        let jsonObj: [String: Any] = [
            "variant": report.variant, "averageScore": report.averageScore,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "results": jsonResults, "writtenTo": writtenTo
        ]
        if let data = try? JSONSerialization.data(withJSONObject: jsonObj, options: [.prettyPrinted]) {
            let jsonPaths = paths.map { $0.replacingOccurrences(of: ".txt", with: ".json") }
            for p in jsonPaths {
                if let _ = try? data.write(to: URL(fileURLWithPath: p)) { break }
            }
        }

        // 用 #expect 的消息携带关键信息
        #expect(report.results.count >= 60,
            "count=\(report.results.count) avg=\(String(format: "%.2f", report.averageScore)) writeTo=\(writtenTo)")
        #expect(report.averageScore >= 2.5,
            "avg=\(String(format: "%.2f", report.averageScore)) low=\(lowScores.map { "\($0.caseID):\(String(format: "%.1f", $0.weightedScore))" }.joined(separator: ","))")

        // 尝试写到报告目录
        let reportDir = URL(fileURLWithPath: "/Users/atom/Desktop/VilsayTuningReports")
        try? FileManager.default.createDirectory(at: reportDir, withIntermediateDirectories: true)
        try? TuningRunner.saveReport(report, to: reportDir)
    }
}
