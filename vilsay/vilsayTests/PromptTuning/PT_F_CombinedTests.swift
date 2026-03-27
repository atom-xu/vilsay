import Foundation
import Testing
@testable import vilsay

@Suite("PT-F: 组合场景")
struct PT_F_CombinedTests {

    @Test("F01 全层激活-程序员邮件低置信度")
    func f01() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "王总你好关于多克部属的事情我想跟你在确认一下方案"
        let output = await PromptTuningHelper.polish(
            asrText: input,
            profile: PromptTuningHelper.devProfile,
            appBundleID: "com.apple.mail",
            asrConfidence: 0.25
        )
        PromptTuningHelper.log("F01", input: input, output: output)
        #expect(!output.isEmpty)
        print("[F01-full] \(output)")
    }

    @Test("F02 全层-医学笔记低置信度")
    func f02() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "患者男性45岁主述头疼三天既往史有高血压开了不落芬和啊默西林"
        let output = await PromptTuningHelper.polish(
            asrText: input,
            profile: PromptTuningHelper.medProfile,
            appBundleID: "com.apple.Notes",
            asrConfidence: 0.30
        )
        PromptTuningHelper.log("F02", input: input, output: output)
        #expect(!output.isEmpty)
        print("[F02-full] \(output)")
    }

    @Test("F03 全层-商务文档正常置信度")
    func f03() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "Q2的OKR我觉得我们需要找到新的抓手来提升ROI同时赋能一线团队"
        let output = await PromptTuningHelper.polish(
            asrText: input,
            profile: PromptTuningHelper.bizProfile,
            appBundleID: "com.microsoft.Word",
            asrConfidence: 0.80
        )
        PromptTuningHelper.log("F03", input: input, output: output)
        #expect(!output.isEmpty)
        #expect(output.contains("OKR") || output.contains("ROI"))
    }

    @Test("F04 学生聊天场景")
    func f04() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "然后就是说今天的作业我没写完老师会不会骂我"
        let output = await PromptTuningHelper.polish(
            asrText: input,
            profile: PromptTuningHelper.studentProfile,
            appBundleID: "com.tencent.xinWeChat"
        )
        PromptTuningHelper.log("F04", input: input, output: output)
        #expect(!output.isEmpty)
    }

    @Test("F05 程序员Notion笔记")
    func f05() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "今天的技术方案讨论结果第一我们用库伯内提斯第二前端重构用React第三后端切Go"
        let output = await PromptTuningHelper.polish(
            asrText: input,
            profile: PromptTuningHelper.devProfile,
            appBundleID: "com.notion.id"
        )
        PromptTuningHelper.log("F05", input: input, output: output)
        #expect(!output.isEmpty)
    }

    @Test("F06 画像+上下文无拼音")
    func f06() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let noPinyinProfile = UserProfile(
            habitualWords: [HabitualWord(word: "嗯", action: "保留", confidence: 0.5)],
            tone: ToneProfile(overall: "轻松", sentenceLength: "短", mixedLang: "无", confidence: 0.6),
            dictionaryItems: [DictionaryItem(type: "用语", word: "测试")]
        )
        let input = "嗯今天做了个测试结果还行"
        let output = await PromptTuningHelper.polish(
            asrText: input,
            profile: noPinyinProfile,
            appBundleID: "com.tencent.xinWeChat"
        )
        PromptTuningHelper.log("F06", input: input, output: output)
        #expect(!output.isEmpty)
    }

    @Test("F07 超长输入全层激活")
    func f07() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = """
        好的我来汇报一下本周的工作进展首先在前端方面我们完成了首页重构优化了加载速度从三秒降到了一点五秒\
        然后在后端方面我们把数据库从MySQL迁移到了PostgreSQL性能提升了大概百分之四十\
        另外我们还修复了十二个bug其中三个是线上紧急的包括用户登录失败和支付回调丢失的问题\
        最后关于下周计划我们要开始做V2版本的需求评审预计周三之前要把技术方案写完
        """
        let output = await PromptTuningHelper.polish(
            asrText: input,
            profile: PromptTuningHelper.devProfile,
            appBundleID: "com.microsoft.Word",
            asrConfidence: 0.70
        )
        PromptTuningHelper.log("F07", input: input, output: output)
        #expect(!output.isEmpty)
        #expect(output.count >= 80)
    }

    @Test("F08 话题切换信号")
    func f08() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "首先说一下预算的事情我们还有五万块另外关于人员招聘HR那边说下周可以面试了"
        let output = await PromptTuningHelper.polish(
            asrText: input,
            profile: PromptTuningHelper.devProfile
        )
        PromptTuningHelper.log("F08", input: input, output: output)
        #expect(!output.isEmpty)
    }

    @Test("F09 医生写邮件")
    func f09() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "张主任您好关于那个患者的CT结果我这边看了一下建议做个核磁共振进一步确认"
        let output = await PromptTuningHelper.polish(
            asrText: input,
            profile: PromptTuningHelper.medProfile,
            appBundleID: "com.apple.mail"
        )
        PromptTuningHelper.log("F09", input: input, output: output)
        #expect(!output.isEmpty)
        #expect(output.contains("CT") || output.contains("核磁共振"))
    }

    @Test("F10 拼音纠偏+聊天场景")
    func f10() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "你用过百练没有感觉统一千问还行"
        let output = await PromptTuningHelper.polish(
            asrText: input,
            profile: PromptTuningHelper.pinyinHeavyProfile,
            appBundleID: "com.tencent.xinWeChat"
        )
        PromptTuningHelper.log("F10", input: input, output: output)
        #expect(!output.isEmpty)
        print("[F10-check] 聊天场景下拼音纠偏: \(output)")
    }

    @Test("F11 完美输入-不过度修改")
    func f11() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "今天下午三点在会议室开会，请大家准时参加。"
        let output = await PromptTuningHelper.polish(
            asrText: input,
            profile: PromptTuningHelper.bizProfile,
            appBundleID: "com.apple.mail",
            asrConfidence: 0.90
        )
        PromptTuningHelper.log("F11", input: input, output: output)
        #expect(!output.isEmpty)
        #expect(output.contains("会议室") && output.contains("准时"))
    }

    @Test("F12 口语方言+画像")
    func f12() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "哎呀这个事情搞得我头大你说咋整嘛"
        let output = await PromptTuningHelper.polish(
            asrText: input,
            profile: PromptTuningHelper.studentProfile,
            appBundleID: "com.tencent.xinWeChat"
        )
        PromptTuningHelper.log("F12", input: input, output: output)
        #expect(!output.isEmpty)
    }

    @Test("F13 数字密集商务报告")
    func f13() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "Q2的GMV是一千二百万比Q1增长了百分之十五ROI达到了三点二我们的目标是四"
        let output = await PromptTuningHelper.polish(
            asrText: input,
            profile: PromptTuningHelper.bizProfile,
            appBundleID: "com.microsoft.Word"
        )
        PromptTuningHelper.log("F13", input: input, output: output)
        #expect(!output.isEmpty)
        #expect(output.contains("ROI") || output.contains("GMV"))
    }

    @Test("F14 模糊输入-推断标注")
    func f14() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "那个什么来着就是上次说的那个"
        let output = await PromptTuningHelper.polish(
            asrText: input,
            profile: PromptTuningHelper.devProfile
        )
        PromptTuningHelper.log("F14", input: input, output: output)
        #expect(!output.isEmpty)
        print("[F14-check] 是否有推断标注: \(output)")
    }

    @Test("F15 全部nil最小配置")
    func f15() async {
        guard PromptTuningHelper.apiKey != nil else { return }
        let input = "帮我写个邮件给老板说明天请假"
        let output = await PromptTuningHelper.polish(
            asrText: input,
            profile: nil,
            appBundleID: nil,
            asrConfidence: nil
        )
        PromptTuningHelper.log("F15", input: input, output: output)
        #expect(!output.isEmpty)
    }
}
