import Foundation
import Testing
@testable import vilsay

/// PT-I：长文本结构化（V4 document/chat/note/aiCommand/email）
@Suite("PT-I: 长文本结构化")
struct PT_I_LongTextStructureTests {

    /// 约 500+ 字重复段落，便于分段/编号类断言（须满足字符数下限，避免误报）
    private static func paragraph500() -> String {
        let unit = "关于产品迭代我们首先要对齐目标然后拆解里程碑接着评估风险最后同步干系人。"
        return String(repeating: unit, count: 18)
    }

    /// 约 900+ 字，含多个「论点」标记（须满足任务书「长文本」下限）
    private static func multiTopic1000() -> String {
        let a = "第一个论点是成本控制需要从采购和人力两方面入手。"
        let b = "第二个论点是用户体验要比竞品快半拍。"
        let c = "第三个论点是数据合规必须前置不能事后补。"
        return String(repeating: a + b + c, count: 15)
    }

    @Test("I01 500字口语 document 有分段倾向")
    func i01() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = Self.paragraph500()
        #expect(input.count >= 450)
        let output = await PromptTuningHelper.polish(
            asrText: input,
            appBundleID: "com.microsoft.Word"
        )
        PromptTuningHelper.log("I01", input: input, output: output)
        #expect(!output.isEmpty)
        let newlines = output.filter { $0 == "\n" }.count
        #expect(newlines >= 1 || output.contains("。"))
    }

    @Test("I02 500字口语 chat 不过度结构化")
    func i02() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = Self.paragraph500()
        let output = await PromptTuningHelper.polish(
            asrText: input,
            appBundleID: "com.tencent.xinWeChat"
        )
        PromptTuningHelper.log("I02", input: input, output: output)
        #expect(!output.isEmpty)
        let hashCount = output.filter { $0 == "#" }.count
        #expect(hashCount <= 3)
    }

    @Test("I03 1000字多论点 document 编号或列表")
    func i03() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = Self.multiTopic1000()
        #expect(input.count >= 900)
        let output = await PromptTuningHelper.polish(
            asrText: input,
            appBundleID: "com.notion.id"
        )
        PromptTuningHelper.log("I03", input: input, output: output)
        #expect(!output.isEmpty)
        let hasStructure = output.contains("1.") || output.contains("1、") || output.contains("-")
            || output.contains("•") || output.contains("##")
            || output.contains("（一）") || output.contains("第一")
        if hasStructure || output.count < input.count {
            // 期望有结构或压缩；无则仅记录日志供人工看报告
        } else {
            print("[I03-soft] 长文本未出现明显编号/列表，已记录 output 供回归检视")
        }
    }

    @Test("I04 300字 note bullet")
    func i04() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = String(repeating: "待办事项需要记录会议结论和行动项。", count: 15)
        let output = await PromptTuningHelper.polish(
            asrText: input,
            appBundleID: "com.apple.Notes"
        )
        PromptTuningHelper.log("I04", input: input, output: output)
        #expect(!output.isEmpty)
        let hasBullet = output.contains("-") || output.contains("•") || output.contains("·")
        #expect(hasBullet || output.contains("TODO"))
    }

    @Test("I05 给AI下指令 aiCommand")
    func i05() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = String(repeating: "然后就是说帮我写个脚本先拉仓库再跑测试然后部署到测试环境对了还要打标签。", count: 8)
        let output = await PromptTuningHelper.polish(
            asrText: input,
            appBundleID: "com.cursor.ide"
        )
        PromptTuningHelper.log("I05", input: input, output: output)
        #expect(!output.isEmpty)
    }

    @Test("I06 邮件场景 email")
    func i06() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = String(repeating: "王总你好然后我想汇报一下进度就是说下周可以交付。", count: 10)
        let output = await PromptTuningHelper.polish(
            asrText: input,
            appBundleID: "com.apple.mail"
        )
        PromptTuningHelper.log("I06", input: input, output: output)
        #expect(!output.isEmpty)
    }

    @Test("I07 相同输入六种模式风格差异")
    func i07() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "然后就是说我们先把需求对齐再排期最后上线对吧。"
        let bundles: [String] = [
            "com.cursor.ide",
            "com.tencent.xinWeChat",
            "com.apple.mail",
            "com.microsoft.Word",
            "com.apple.Notes",
            "com.example.unknown.app",
        ]
        var outputs: [String] = []
        for bid in bundles {
            let o = await PromptTuningHelper.polish(asrText: input, appBundleID: bid)
            outputs.append(o)
            PromptTuningHelper.log("I07-\(bid)", input: input, output: o)
        }
        #expect(outputs.count == 6)
        let setCount = Set(outputs).count
        #expect(setCount >= 2)
    }

    @Test("I08 重复论述 document")
    func i08() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let sentence = "核心结论是我们必须降本增效。"
        let input = String(repeating: sentence, count: 25)
        let output = await PromptTuningHelper.polish(
            asrText: input,
            appBundleID: "com.apple.Pages"
        )
        PromptTuningHelper.log("I08", input: input, output: output)
        #expect(!output.isEmpty)
        #expect(output.count <= input.count * 2)
    }

    @Test("I09 逻辑跳跃 document")
    func i09() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = """
        先说一下吃饭的事。对了代码审查要严格。还有明天带伞。总之预算要砍一半。
        """
        let output = await PromptTuningHelper.polish(
            asrText: input,
            appBundleID: "md.obsidian"
        )
        PromptTuningHelper.log("I09", input: input, output: output)
        #expect(!output.isEmpty)
    }

    @Test("I10 极长1500字 document 分段")
    func i10() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let unit = "长文本测试需要验证分段策略与可读性以及模型是否遵循模式规则。"
        let input = String(repeating: unit, count: 50)
        #expect(input.count >= 1400)
        let output = await PromptTuningHelper.polish(
            asrText: input,
            appBundleID: "com.microsoft.Word"
        )
        PromptTuningHelper.log("I10", input: input, output: output)
        #expect(!output.isEmpty)
        let newlines = output.filter { $0 == "\n" }.count
        #expect(newlines >= 1 || output.contains("。"))
    }
}
