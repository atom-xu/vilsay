import Foundation
import Testing
@testable import vilsay

/// PT-J：模式切换与 V3（.general）回归
@Suite("PT-J: 模式切换与 general 回归")
struct PT_J_ModeSwitchingTests {

    @Test("J01 chat 与 email 切换")
    func j01() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "然后就是说麻烦你帮我跟客户约个下周三的时间谢谢。"
        let chatOut = await PromptTuningHelper.polish(
            asrText: input,
            appBundleID: "com.tencent.xinWeChat"
        )
        let emailOut = await PromptTuningHelper.polish(
            asrText: input,
            appBundleID: "com.microsoft.Outlook"
        )
        PromptTuningHelper.log("J01-chat", input: input, output: chatOut)
        PromptTuningHelper.log("J01-email", input: input, output: emailOut)
        #expect(!chatOut.isEmpty && !emailOut.isEmpty)
        #expect(chatOut != emailOut || chatOut.count != emailOut.count)
    }

    @Test("J02 未知 bundle general 短文本")
    func j02() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "好的收到"
        let output = await PromptTuningHelper.polish(
            asrText: input,
            appBundleID: "com.unknown.app.vilsay"
        )
        PromptTuningHelper.log("J02", input: input, output: output)
        #expect(!output.isEmpty)
        #expect(output.count <= 32)
    }

    @Test("J03 未知 bundle general 长文本")
    func j03() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = String(repeating: "我们需要在下周前完成联调和验收。", count: 20)
        let output = await PromptTuningHelper.polish(
            asrText: input,
            appBundleID: "com.nonexistent.bundle"
        )
        PromptTuningHelper.log("J03", input: input, output: output)
        #expect(!output.isEmpty)
    }

    @Test("J04 aiCommand 减少连接词倾向")
    func j04() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "然后就是说那个你先拉分支然后跑一下单测然后发版"
        let output = await PromptTuningHelper.polish(
            asrText: input,
            appBundleID: "com.openai.chat"
        )
        PromptTuningHelper.log("J04", input: input, output: output)
        #expect(!output.isEmpty)
        let thenCount = output.components(separatedBy: "然后").count - 1
        #expect(thenCount <= 2)
    }

    @Test("J05 chat 保留口语连接词倾向")
    func j05() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "然后就是说哈哈我今天其实挺开心的"
        let output = await PromptTuningHelper.polish(
            asrText: input,
            appBundleID: "com.apple.MobileSMS"
        )
        PromptTuningHelper.log("J05", input: input, output: output)
        #expect(!output.isEmpty)
    }
}
