import Foundation
import Testing
@testable import vilsay

@Suite("PT-E: 拼音纠偏§1.P")
struct PT_E_PinyinTests {

    @Test("E01 百炼→百练纠偏")
    func e01() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "我们用的是阿里的百练平台"
        let output = await PromptTuningHelper.polish(
            asrText: input,
            profile: PromptTuningHelper.pinyinHeavyProfile
        )
        PromptTuningHelper.log("E01", input: input, output: output)
        #expect(!output.isEmpty)
        print("[E01-check] 是否纠偏为'百炼': \(output)")
    }

    @Test("E02 威尔赛→Vilsay纠偏")
    func e02() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "威尔赛这个产品还不错"
        let output = await PromptTuningHelper.polish(
            asrText: input,
            profile: PromptTuningHelper.pinyinHeavyProfile
        )
        PromptTuningHelper.log("E02", input: input, output: output)
        #expect(!output.isEmpty)
        print("[E02-check] 是否纠偏为'Vilsay': \(output)")
    }

    @Test("E03 统一千问→通义千问纠偏")
    func e03() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "统一千问是阿里的大模型"
        let output = await PromptTuningHelper.polish(
            asrText: input,
            profile: PromptTuningHelper.pinyinHeavyProfile
        )
        PromptTuningHelper.log("E03", input: input, output: output)
        #expect(!output.isEmpty)
        print("[E03-check] 是否纠偏为'通义千问': \(output)")
    }

    @Test("E04 阿莫西林-同音错误")
    func e04() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "给患者开了啊默西林三天的量"
        let output = await PromptTuningHelper.polish(
            asrText: input,
            profile: PromptTuningHelper.medProfile
        )
        PromptTuningHelper.log("E04", input: input, output: output)
        #expect(!output.isEmpty)
        print("[E04-check] 是否纠偏为'阿莫西林': \(output)")
    }

    @Test("E05 布洛芬-同音错误")
    func e05() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "不落芬一天三次饭后服用"
        let output = await PromptTuningHelper.polish(
            asrText: input,
            profile: PromptTuningHelper.medProfile
        )
        PromptTuningHelper.log("E05", input: input, output: output)
        #expect(!output.isEmpty)
        print("[E05-check] 是否纠偏为'布洛芬': \(output)")
    }

    @Test("E06 CT-同音")
    func e06() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "先做个西提检查看看情况"
        let output = await PromptTuningHelper.polish(
            asrText: input,
            profile: PromptTuningHelper.medProfile
        )
        PromptTuningHelper.log("E06", input: input, output: output)
        #expect(!output.isEmpty)
        print("[E06-check] 是否纠偏为'CT': \(output)")
    }

    @Test("E07 Docker-同音多克")
    func e07() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "把这个服务打包成多克镜像"
        let output = await PromptTuningHelper.polish(
            asrText: input,
            profile: PromptTuningHelper.devProfile
        )
        PromptTuningHelper.log("E07", input: input, output: output)
        #expect(!output.isEmpty)
        print("[E07-check] 是否纠偏为'Docker': \(output)")
    }

    @Test("E08 Kubernetes-同音")
    func e08() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "库伯内提斯集群需要扩容"
        let output = await PromptTuningHelper.polish(
            asrText: input,
            profile: PromptTuningHelper.devProfile
        )
        PromptTuningHelper.log("E08", input: input, output: output)
        #expect(!output.isEmpty)
        print("[E08-check] 是否纠偏为'Kubernetes': \(output)")
    }

    @Test("E09 CI/CD-同音")
    func e09() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "思艾思地流水线挂了赶紧看看"
        let output = await PromptTuningHelper.polish(
            asrText: input,
            profile: PromptTuningHelper.devProfile
        )
        PromptTuningHelper.log("E09", input: input, output: output)
        #expect(!output.isEmpty)
        print("[E09-check] 是否纠偏为'CI/CD': \(output)")
    }

    @Test("E10 无拼音画像-同一输入")
    func e10() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "库伯内提斯集群需要扩容"
        let output = await PromptTuningHelper.polish(asrText: input)
        PromptTuningHelper.log("E10", input: input, output: output)
        #expect(!output.isEmpty)
        print("[E10-check] 无拼音画像，对比E08: \(output)")
    }

    @Test("E11 拼音+低置信度双重增强")
    func e11() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "百练平台上的统一千问不好用"
        let output = await PromptTuningHelper.polish(
            asrText: input,
            profile: PromptTuningHelper.pinyinHeavyProfile,
            asrConfidence: 0.20
        )
        PromptTuningHelper.log("E11", input: input, output: output)
        #expect(!output.isEmpty)
        print("[E11-check] 双重增强: \(output)")
    }

    @Test("E12 权益vs全域近音区分")
    func e12() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "用户的全域保护是我们的首要任务"
        let output = await PromptTuningHelper.polish(
            asrText: input,
            profile: PromptTuningHelper.pinyinHeavyProfile
        )
        PromptTuningHelper.log("E12", input: input, output: output)
        #expect(!output.isEmpty)
        print("[E12-check] 是否纠偏'全域→权益': \(output)")
    }

    @Test("E13 正确使用不误纠")
    func e13() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "百炼平台的通义千问表现很好"
        let output = await PromptTuningHelper.polish(
            asrText: input,
            profile: PromptTuningHelper.pinyinHeavyProfile
        )
        PromptTuningHelper.log("E13", input: input, output: output)
        #expect(!output.isEmpty)
        #expect(output.contains("百炼"))
        #expect(output.contains("通义千问"))
    }

    @Test("E14 人名同音纠偏")
    func e14() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "卫则西事件对医疗行业影响很大"
        let output = await PromptTuningHelper.polish(
            asrText: input,
            profile: PromptTuningHelper.pinyinHeavyProfile
        )
        PromptTuningHelper.log("E14", input: input, output: output)
        #expect(!output.isEmpty)
        print("[E14-check] 是否纠偏为'魏则西': \(output)")
    }

    @Test("E15 大量拼音词不报错")
    func e15() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        var items: [DictionaryItem] = []
        for i in 0..<60 {
            items.append(DictionaryItem(type: "用语", word: "测试词\(i)", pinyin: "ce shi ci \(i)"))
        }
        let bigProfile = UserProfile(dictionaryItems: items)
        let input = "这是一个普通的测试句子"
        let output = await PromptTuningHelper.polish(asrText: input, profile: bigProfile)
        PromptTuningHelper.log("E15", input: input, output: output)
        #expect(!output.isEmpty)
    }
}
