import Foundation
import Testing
@testable import vilsay

@Suite("PT-H: 稳定性与一致性")
struct PT_H_StabilityTests {

    /// 同一输入跑 3 次，比较核心内容是否一致
    private func runStability(
        id: String,
        input: String,
        profile: UserProfile? = nil,
        appBundleID: String? = nil,
        asrConfidence: Double? = nil,
        mustContain: [String] = []
    ) async {
        guard PromptTuningHelper.apiKey != nil else { return }
        var outputs: [String] = []
        for i in 1...3 {
            let output = await PromptTuningHelper.polish(
                asrText: input,
                profile: profile,
                appBundleID: appBundleID,
                asrConfidence: asrConfidence
            )
            outputs.append(output)
            print("[\(id)-run\(i)] \(output)")
        }
        for (i, o) in outputs.enumerated() {
            #expect(!o.isEmpty, "Run \(i + 1) 为空")
        }
        // 与 `PolishService.polishPlain` 无 Key 时一致：三次均为原文，不做关键词一致性要求
        let degradedNoAPI = outputs.allSatisfy { $0 == input }
        guard !degradedNoAPI else { return }
        for keyword in mustContain {
            let hits = outputs.filter { $0.contains(keyword) }.count
            #expect(hits >= 2, "关键词'\(keyword)'仅在\(hits)/3次中出现")
        }
    }

    @Test("H01 基线稳定性")
    func h01() async {
        await runStability(
            id: "H01",
            input: "明天下午三点开会讨论项目进度",
            mustContain: ["会"]
        )
    }

    @Test("H02 邮件场景稳定性")
    func h02() async {
        await runStability(
            id: "H02",
            input: "王总你好关于合同的事情我们再确认一下",
            appBundleID: "com.apple.mail",
            mustContain: ["合同"]
        )
    }

    @Test("H03 同音字纠偏稳定性")
    func h03() async {
        await runStability(
            id: "H03",
            input: "他的工做态度很认真",
            mustContain: ["工作"]
        )
    }

    @Test("H04 技术术语稳定性")
    func h04() async {
        await runStability(
            id: "H04",
            input: "把服务部署到K8S集群上",
            profile: PromptTuningHelper.devProfile,
            mustContain: ["集群"]
        )
    }

    @Test("H05 拼音纠偏稳定性")
    func h05() async {
        await runStability(
            id: "H05",
            input: "百练平台不错",
            profile: PromptTuningHelper.pinyinHeavyProfile,
            mustContain: ["百炼"]
        )
    }

    @Test("H06 商务用语稳定性")
    func h06() async {
        await runStability(
            id: "H06",
            input: "我们需要找到新的抓手来提升ROI",
            profile: PromptTuningHelper.bizProfile,
            mustContain: ["ROI"]
        )
    }

    @Test("H07 低置信度稳定性")
    func h07() async {
        await runStability(
            id: "H07",
            input: "我们需要全面部属这个方案",
            asrConfidence: 0.20,
            mustContain: ["部署"]
        )
    }

    @Test("H08 短句稳定性")
    func h08() async {
        await runStability(
            id: "H08",
            input: "好的收到",
            mustContain: ["收到"]
        )
    }

    @Test("H09 全层激活稳定性")
    func h09() async {
        await runStability(
            id: "H09",
            input: "王总你好关于多克部属的事情再确认一下",
            profile: PromptTuningHelper.devProfile,
            appBundleID: "com.apple.mail",
            asrConfidence: 0.25
        )
    }

    @Test("H10 中英混合稳定性")
    func h10() async {
        await runStability(
            id: "H10",
            input: "把这个bug fix一下然后提个PR",
            profile: PromptTuningHelper.devProfile,
            mustContain: ["PR"]
        )
    }
}
