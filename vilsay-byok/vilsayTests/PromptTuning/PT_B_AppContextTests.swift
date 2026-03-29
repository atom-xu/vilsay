import Foundation
import Testing
@testable import vilsay

@Suite("PT-B: App上下文§A分化")
struct PT_B_AppContextTests {

    @Test("B01 邮件场景正式化")
    func b01() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "王总你好那个合同的事情我们再聊聊吧"
        let output = await PromptTuningHelper.polish(asrText: input, appBundleID: "com.apple.mail")
        PromptTuningHelper.log("B01", input: input, output: output)
        #expect(!output.isEmpty)
        print("[B01-check] 期望正式语体，实际: \(output)")
    }

    @Test("B02 聊天场景保留口语")
    func b02() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "王总你好那个合同的事情我们再聊聊吧"
        let output = await PromptTuningHelper.polish(asrText: input, appBundleID: "com.tencent.xinWeChat")
        PromptTuningHelper.log("B02", input: input, output: output)
        #expect(!output.isEmpty)
        print("[B02-check] 期望口语化，实际: \(output)")
    }

    @Test("B03 无上下文对比")
    func b03() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "王总你好那个合同的事情我们再聊聊吧"
        let output = await PromptTuningHelper.polish(asrText: input)
        PromptTuningHelper.log("B03", input: input, output: output)
        #expect(!output.isEmpty)
        print("[B03-check] 无上下文对比基线: \(output)")
    }

    @Test("B04 笔记场景简洁")
    func b04() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "今天会议要点第一个确认了下周发布时间第二个需要补充测试用例第三个设计稿需要修改"
        let output = await PromptTuningHelper.polish(asrText: input, appBundleID: "com.apple.Notes")
        PromptTuningHelper.log("B04", input: input, output: output)
        #expect(!output.isEmpty)
        print("[B04-check] 笔记场景，期望简洁: \(output)")
    }

    @Test("B05 Word文档正式")
    func b05() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "今天会议要点第一个确认了下周发布时间第二个需要补充测试用例第三个设计稿需要修改"
        let output = await PromptTuningHelper.polish(asrText: input, appBundleID: "com.microsoft.Word")
        PromptTuningHelper.log("B05", input: input, output: output)
        #expect(!output.isEmpty)
        print("[B05-check] 文档场景，期望正式+结构化: \(output)")
    }

    @Test("B06 QQ聊天口语")
    func b06() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "今天会议要点第一个确认了下周发布时间第二个需要补充测试用例第三个设计稿需要修改"
        let output = await PromptTuningHelper.polish(asrText: input, appBundleID: "com.tencent.qq")
        PromptTuningHelper.log("B06", input: input, output: output)
        #expect(!output.isEmpty)
        print("[B06-check] QQ聊天场景: \(output)")
    }

    @Test("B07 Outlook邮件正式")
    func b07() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "嗯关于下周的季度回顾我这边准备了一些数据麻烦大家提前看一下"
        let output = await PromptTuningHelper.polish(asrText: input, appBundleID: "com.microsoft.Outlook")
        PromptTuningHelper.log("B07", input: input, output: output)
        #expect(!output.isEmpty)
    }

    @Test("B08 Foxmail邮件正式")
    func b08() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "嗯关于下周的季度回顾我这边准备了一些数据麻烦大家提前看一下"
        let output = await PromptTuningHelper.polish(asrText: input, appBundleID: "com.tencent.foxmail")
        PromptTuningHelper.log("B08", input: input, output: output)
        #expect(!output.isEmpty)
    }

    @Test("B09 Pages文档")
    func b09() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "这一章主要介绍产品的核心功能包括语音识别文字润色和个性化学习三个方面"
        let output = await PromptTuningHelper.polish(asrText: input, appBundleID: "com.apple.Pages")
        PromptTuningHelper.log("B09", input: input, output: output)
        #expect(!output.isEmpty)
    }

    @Test("B10 Notion结构化表达")
    func b10() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "这一章主要介绍产品的核心功能包括语音识别文字润色和个性化学习三个方面"
        let output = await PromptTuningHelper.polish(asrText: input, appBundleID: "com.notion.id")
        PromptTuningHelper.log("B10", input: input, output: output)
        #expect(!output.isEmpty)
    }

    @Test("B11 iMessage短消息")
    func b11() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "晚上一起吃饭吗你定个地方"
        let output = await PromptTuningHelper.polish(asrText: input, appBundleID: "com.apple.MobileSMS")
        PromptTuningHelper.log("B11", input: input, output: output)
        #expect(!output.isEmpty)
        #expect(output.count <= 40)
    }

    @Test("B12 未知App不注入§A")
    func b12() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "帮我查一下明天北京的天气"
        let output = await PromptTuningHelper.polish(asrText: input, appBundleID: "com.unknown.app")
        PromptTuningHelper.log("B12", input: input, output: output)
        #expect(!output.isEmpty)
    }

    @Test("B13 邮件场景-请假")
    func b13() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "领导你好我下周一到周三请个假家里有点事"
        let output = await PromptTuningHelper.polish(asrText: input, appBundleID: "com.apple.mail")
        PromptTuningHelper.log("B13", input: input, output: output)
        #expect(!output.isEmpty)
    }

    @Test("B14 邮件场景-会议邀请")
    func b14() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "各位同事下周五下午两点在大会议室开产品评审会请大家准时参加"
        let output = await PromptTuningHelper.polish(asrText: input, appBundleID: "com.apple.mail")
        PromptTuningHelper.log("B14", input: input, output: output)
        #expect(!output.isEmpty)
    }

    @Test("B15 邮件场景-催促回复")
    func b15() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "张经理上次发你的报价单看了没有麻烦尽快回复一下"
        let output = await PromptTuningHelper.polish(asrText: input, appBundleID: "com.apple.mail")
        PromptTuningHelper.log("B15", input: input, output: output)
        #expect(!output.isEmpty)
    }
}
