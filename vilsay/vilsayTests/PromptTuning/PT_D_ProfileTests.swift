import Foundation
import Testing
@testable import vilsay

@Suite("PT-D: 用户画像§1")
struct PT_D_ProfileTests {

    @Test("D01 程序员画像-保留技术词")
    func d01() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "把这个服务部署到K8S集群上然后跑一下CI CD"
        let output = await PromptTuningHelper.polish(asrText: input, profile: PromptTuningHelper.devProfile)
        PromptTuningHelper.log("D01", input: input, output: output)
        #expect(!output.isEmpty)
        let hasTech = output.contains("K8S") || output.contains("Kubernetes") || output.contains("k8s")
        #expect(hasTech)
    }

    @Test("D02 程序员画像-保留口头禅'其实'")
    func d02() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "其实这个bug很简单就是空指针没有判断"
        let output = await PromptTuningHelper.polish(asrText: input, profile: PromptTuningHelper.devProfile)
        PromptTuningHelper.log("D02", input: input, output: output)
        #expect(!output.isEmpty)
        print("[D02-check] 是否保留'其实': \(output)")
    }

    @Test("D03 无画像对比-同一技术输入")
    func d03() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "把这个服务部署到K8S集群上然后跑一下CI CD"
        let output = await PromptTuningHelper.polish(asrText: input)
        PromptTuningHelper.log("D03", input: input, output: output)
        #expect(!output.isEmpty)
        print("[D03-check] 无画像，技术词是否保留: \(output)")
    }

    @Test("D04 商务画像-保留商务用语")
    func d04() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "这个项目我们要赋能一线团队提升颗粒度把OKR对齐一下"
        let output = await PromptTuningHelper.polish(asrText: input, profile: PromptTuningHelper.bizProfile)
        PromptTuningHelper.log("D04", input: input, output: output)
        #expect(!output.isEmpty)
        let hasBiz = output.contains("赋能") || output.contains("OKR") || output.contains("颗粒度")
        #expect(hasBiz)
    }

    @Test("D05 商务画像-正式风格")
    func d05() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "那个关于ROI的事情我觉得我们得找个抓手来推动一下"
        let output = await PromptTuningHelper.polish(asrText: input, profile: PromptTuningHelper.bizProfile)
        PromptTuningHelper.log("D05", input: input, output: output)
        #expect(!output.isEmpty)
        #expect(output.contains("ROI"))
    }

    @Test("D06 商务画像+邮件上下文")
    func d06() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "各位下午好关于Q2的OKR我这边整理了一份初稿麻烦大家看看给点反馈"
        let output = await PromptTuningHelper.polish(
            asrText: input,
            profile: PromptTuningHelper.bizProfile,
            appBundleID: "com.apple.mail"
        )
        PromptTuningHelper.log("D06", input: input, output: output)
        #expect(!output.isEmpty)
        #expect(output.contains("OKR") || output.contains("Q2"))
    }

    @Test("D07 学生画像-保留口语化")
    func d07() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "然后就是说这道题我不太会你能给我讲讲吗"
        let output = await PromptTuningHelper.polish(asrText: input, profile: PromptTuningHelper.studentProfile)
        PromptTuningHelper.log("D07", input: input, output: output)
        #expect(!output.isEmpty)
        print("[D07-check] 学生画像，是否保留口语感: \(output)")
    }

    @Test("D08 学生画像-聊天场景")
    func d08() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "今天的作业太多了我要写到半夜"
        let output = await PromptTuningHelper.polish(
            asrText: input,
            profile: PromptTuningHelper.studentProfile,
            appBundleID: "com.tencent.xinWeChat"
        )
        PromptTuningHelper.log("D08", input: input, output: output)
        #expect(!output.isEmpty)
    }

    @Test("D09 无画像对比-同一学生输入")
    func d09() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "然后就是说这道题我不太会你能给我讲讲吗"
        let output = await PromptTuningHelper.polish(asrText: input)
        PromptTuningHelper.log("D09", input: input, output: output)
        #expect(!output.isEmpty)
        print("[D09-check] 无画像对比: \(output)")
    }

    @Test("D10 医学画像-术语保留")
    func d10() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "患者主诉头痛三天既往史有高血压建议做个CT看看"
        let output = await PromptTuningHelper.polish(asrText: input, profile: PromptTuningHelper.medProfile)
        PromptTuningHelper.log("D10", input: input, output: output)
        #expect(!output.isEmpty)
        let hasMed = output.contains("主诉") || output.contains("既往史") || output.contains("CT")
        #expect(hasMed)
    }

    @Test("D11 医学画像-药物名称")
    func d11() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "开了阿莫西林和布洛芬让患者回去观察三天"
        let output = await PromptTuningHelper.polish(asrText: input, profile: PromptTuningHelper.medProfile)
        PromptTuningHelper.log("D11", input: input, output: output)
        #expect(!output.isEmpty)
        #expect(output.contains("阿莫西林") || output.contains("布洛芬"))
    }

    @Test("D12 医学画像-严谨风格")
    func d12() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "嗯那个核磁共振的结果出来了没有什么大问题就是有点轻微的炎症"
        let output = await PromptTuningHelper.polish(asrText: input, profile: PromptTuningHelper.medProfile)
        PromptTuningHelper.log("D12", input: input, output: output)
        #expect(!output.isEmpty)
        #expect(output.contains("核磁共振") || output.contains("MRI"))
    }

    @Test("D13 有画像-thinking style影响")
    func d13() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "我觉得首先我们要确认需求然后再做技术方案最后安排排期"
        let output = await PromptTuningHelper.polish(asrText: input, profile: PromptTuningHelper.devProfile)
        PromptTuningHelper.log("D13", input: input, output: output)
        #expect(!output.isEmpty)
    }

    @Test("D14 低置信度画像-habitualWord不保留")
    func d14() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let lowProfile = UserProfile(
            habitualWords: [
                HabitualWord(word: "YOLO", action: "保留", confidence: 0.1),
            ]
        )
        let input = "今天YOLO一下去吃好的"
        let output = await PromptTuningHelper.polish(asrText: input, profile: lowProfile)
        PromptTuningHelper.log("D14", input: input, output: output)
        #expect(!output.isEmpty)
        print("[D14-check] 低置信度词是否被过滤: \(output)")
    }

    @Test("D15 空画像等同无画像")
    func d15() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "明天下午开会讨论项目进度"
        let withEmpty = await PromptTuningHelper.polish(asrText: input, profile: PromptTuningHelper.emptyProfile)
        let withNil = await PromptTuningHelper.polish(asrText: input, profile: nil)
        PromptTuningHelper.log("D15-empty", input: input, output: withEmpty)
        PromptTuningHelper.log("D15-nil", input: input, output: withNil)
        #expect(!withEmpty.isEmpty)
        #expect(!withNil.isEmpty)
    }
}
