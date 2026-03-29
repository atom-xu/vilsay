import Foundation
import Testing
@testable import vilsay

@Suite("PT-C: ASR置信度§C")
struct PT_C_ConfidenceTests {

    @Test("C01 高置信度-同音字")
    func c01() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "我们需要全面部属这个方案"
        let output = await PromptTuningHelper.polish(asrText: input, asrConfidence: 0.85)
        PromptTuningHelper.log("C01", input: input, output: output)
        #expect(!output.isEmpty)
        print("[C01-check] 高置信度(0.85)，是否纠偏'部属→部署': \(output)")
    }

    @Test("C02 低置信度-同音字增强纠偏")
    func c02() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "我们需要全面部属这个方案"
        let output = await PromptTuningHelper.polish(asrText: input, asrConfidence: 0.25)
        PromptTuningHelper.log("C02", input: input, output: output)
        #expect(!output.isEmpty)
        print("[C02-check] 低置信度(0.25)，应更积极纠偏'部属→部署': \(output)")
    }

    @Test("C03 低置信度-多同音错误")
    func c03() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "这个季度的应收已经超标了需要及时处里"
        let output = await PromptTuningHelper.polish(asrText: input, asrConfidence: 0.20)
        PromptTuningHelper.log("C03", input: input, output: output)
        #expect(!output.isEmpty)
        print("[C03-check] 低置信度，多同音: \(output)")
    }

    @Test("C04 高置信度-同一输入")
    func c04() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "这个季度的应收已经超标了需要及时处里"
        let output = await PromptTuningHelper.polish(asrText: input, asrConfidence: 0.90)
        PromptTuningHelper.log("C04", input: input, output: output)
        #expect(!output.isEmpty)
        print("[C04-check] 高置信度，同输入: \(output)")
    }

    @Test("C05 置信度=0.4不触发§C")
    func c05() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "这个工做很重要"
        let output = await PromptTuningHelper.polish(asrText: input, asrConfidence: 0.4)
        PromptTuningHelper.log("C05", input: input, output: output)
        #expect(!output.isEmpty)
        print("[C05-check] 阈值边界0.4: \(output)")
    }

    @Test("C06 置信度=0.39触发§C")
    func c06() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "这个工做很重要"
        let output = await PromptTuningHelper.polish(asrText: input, asrConfidence: 0.39)
        PromptTuningHelper.log("C06", input: input, output: output)
        #expect(!output.isEmpty)
        print("[C06-check] 阈值下方0.39: \(output)")
    }

    @Test("C07 极低置信度0.1")
    func c07() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "挥发性有鸡化和勿的咽酒"
        let output = await PromptTuningHelper.polish(asrText: input, asrConfidence: 0.10)
        PromptTuningHelper.log("C07", input: input, output: output)
        #expect(!output.isEmpty)
        print("[C07-check] 极低置信度，极差输入: \(output)")
    }

    @Test("C08 nil置信度不注入§C")
    func c08() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "他的工做态度很认真"
        let output = await PromptTuningHelper.polish(asrText: input, asrConfidence: nil)
        PromptTuningHelper.log("C08", input: input, output: output)
        #expect(!output.isEmpty)
    }

    @Test("C09 低置信度但输入正确-不过度纠偏")
    func c09() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "今天天气真好我们去公园走走吧"
        let output = await PromptTuningHelper.polish(asrText: input, asrConfidence: 0.20)
        PromptTuningHelper.log("C09", input: input, output: output)
        #expect(!output.isEmpty)
        #expect(output.contains("公园"))
    }

    @Test("C10 低置信度+邮件上下文")
    func c10() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "关于那个和同的事情我们在确认一下"
        let output = await PromptTuningHelper.polish(
            asrText: input,
            appBundleID: "com.apple.mail",
            asrConfidence: 0.30
        )
        PromptTuningHelper.log("C10", input: input, output: output)
        #expect(!output.isEmpty)
        print("[C10-check] 低置信度+邮件: \(output)")
    }
}
