//
//  PromptEffectivenessTests.swift
//  TEST-02：真实 Qwen 调用（无 DASHSCOPE_API_KEY 时提前 return，不失败）
//

import Foundation
import Testing
@testable import vilsay

struct PromptEffectivenessTests {

    private static var apiKey: String? {
        let s = ProcessInfo.processInfo.environment["DASHSCOPE_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let s, !s.isEmpty else { return nil }
        return s
    }

    private func polish(systemPrompt: String, asrText: String) async -> String {
        let user = Prompts.polishUserMessage(asrText: asrText)
        return await PolishService.polishPlain(system: systemPrompt, user: user)
    }

    @Test func appContext_mail_vs_wechat_style() async {
        guard Self.apiKey != nil else { return }
        let asr = "嗯就是那个方案呢我觉得还行吧你看着办就好了啊"

        let mailPrompt = PromptComposer.systemPrompt(
            for: nil,
            targetAppBundleID: "com.apple.mail"
        )
        let chatPrompt = PromptComposer.systemPrompt(
            for: nil,
            targetAppBundleID: "com.tencent.xinWeChat"
        )

        let mailResult = await polish(systemPrompt: mailPrompt, asrText: asr)
        let chatResult = await polish(systemPrompt: chatPrompt, asrText: asr)

        // LLM 输出不确定，不强制二者不同；仅校验有有效输出
        #expect(!mailResult.isEmpty && !chatResult.isEmpty)
        if mailResult == chatResult {
            print("⚠️ 邮件与聊天输出相同（模型可能忽略场景差异）")
        }

        let casualWords = ["吧", "啊", "呢", "嗯"]
        let mailHasCasual = casualWords.contains { mailResult.contains($0) }
        let chatHasCasual = casualWords.contains { chatResult.contains($0) }

        print("📧 邮件输出: \(mailResult)")
        print("💬 聊天输出: \(chatResult)")
        print("📧 含口语词: \(mailHasCasual), 💬 含口语词: \(chatHasCasual)")
    }

    @Test func appContext_word_vs_notes_length() async {
        guard Self.apiKey != nil else { return }
        let asr = "然后第二个问题就是关于那个用户增长的数据嗯我们上个月大概涨了百分之十五"

        let wordPrompt = PromptComposer.systemPrompt(
            for: nil,
            targetAppBundleID: "com.microsoft.Word"
        )
        let notesPrompt = PromptComposer.systemPrompt(
            for: nil,
            targetAppBundleID: "com.apple.Notes"
        )

        let wordResult = await polish(systemPrompt: wordPrompt, asrText: asr)
        let notesResult = await polish(systemPrompt: notesPrompt, asrText: asr)

        print("📄 Word 输出(\(wordResult.count)字): \(wordResult)")
        print("📝 Notes 输出(\(notesResult.count)字): \(notesResult)")

        #expect(notesResult.count <= wordResult.count + 5,
                "笔记输出应不长于文档输出\nWord(\(wordResult.count)): \(wordResult)\nNotes(\(notesResult.count)): \(notesResult)")
    }

    @Test func appContext_none_vs_mail() async {
        guard Self.apiKey != nil else { return }
        let asr = "帮我跟客户说一下那个交付时间要推迟两周"

        let barePrompt = PromptComposer.systemPrompt(for: nil)
        let mailPrompt = PromptComposer.systemPrompt(
            for: nil,
            targetAppBundleID: "com.apple.mail"
        )

        let bareResult = await polish(systemPrompt: barePrompt, asrText: asr)
        let mailResult = await polish(systemPrompt: mailPrompt, asrText: asr)

        print("🔲 无上下文: \(bareResult)")
        print("📧 邮件上下文: \(mailResult)")

        if bareResult == mailResult {
            print("⚠️ 两个输出相同，§A 可能未产生影响")
        }
    }

    @Test func confidence_low_vs_high_correction() async {
        guard Self.apiKey != nil else { return }
        let asr = "我觉得这个试验部的方案义定要重新评估一下"

        let lowConfPrompt = PromptComposer.systemPrompt(
            for: nil,
            asrConfidence: 0.2
        )
        let highConfPrompt = PromptComposer.systemPrompt(
            for: nil,
            asrConfidence: 0.9
        )

        let lowResult = await polish(systemPrompt: lowConfPrompt, asrText: asr)
        let highResult = await polish(systemPrompt: highConfPrompt, asrText: asr)

        print("🔽 低置信: \(lowResult)")
        print("🔼 高置信: \(highResult)")

        let lowFixedShiYe = lowResult.contains("事业")
        let highFixedShiYe = highResult.contains("事业")
        print("低置信纠正'试验→事业': \(lowFixedShiYe)")
        print("高置信纠正'试验→事业': \(highFixedShiYe)")
    }

    @Test func pinyin_dictionary_correction() async {
        guard Self.apiKey != nil else { return }
        let asr = "帮我发给张思源然后问一下试验部的进展"

        let noDictPrompt = PromptComposer.systemPrompt(for: nil)

        let withDictProfile = UserProfile(
            habitualWords: [],
            thinkingStyle: nil,
            tone: nil,
            dictionaryItems: [
                .init(type: "person", word: "张思远", pinyin: "zhang si yuan"),
                .init(type: "term", word: "事业部", pinyin: "shi ye bu")
            ]
        )
        let dictPrompt = PromptComposer.systemPrompt(for: withDictProfile)

        let noDictResult = await polish(systemPrompt: noDictPrompt, asrText: asr)
        let dictResult = await polish(systemPrompt: dictPrompt, asrText: asr)

        print("📕 无词典: \(noDictResult)")
        print("📗 有词典: \(dictResult)")

        let dictFixedZhang = dictResult.contains("张思远")
        let dictFixedShiYeBu = dictResult.contains("事业部")
        print("词典纠正'张思源→张思远': \(dictFixedZhang)")
        print("词典纠正'试验部→事业部': \(dictFixedShiYeBu)")

        // 纠偏依赖模型，不强制命中；保证有润色输出即可
        #expect(!dictResult.isEmpty && !noDictResult.isEmpty)
    }

    @Test func profile_vs_noProfile() async {
        guard Self.apiKey != nil else { return }
        let asr = "嗯就是说我觉得这个 API 的设计有点问题然后然后那个前端需要重构"

        let barePrompt = PromptComposer.systemPrompt(for: nil)

        let profile = UserProfile(
            habitualWords: [
                .init(word: "就是说", action: "keep", confidence: 0.9),
            ],
            thinkingStyle: .init(
                expand: "先总后分，喜欢列举", topicSwitchSignals: ["然后"],
                closeSignals: ["就这样"], confidence: 0.8
            ),
            tone: .init(overall: "直接、技术化、偏短句",
                        sentenceLength: "short", mixedLang: "zh-en", confidence: 0.7),
            dictionaryItems: [
                .init(type: "term", word: "API", pinyin: nil),
                .init(type: "term", word: "重构", pinyin: nil)
            ]
        )
        let profilePrompt = PromptComposer.systemPrompt(for: profile)

        let bareResult = await polish(systemPrompt: barePrompt, asrText: asr)
        let profileResult = await polish(systemPrompt: profilePrompt, asrText: asr)

        print("🔲 无画像: \(bareResult)")
        print("👤 有画像: \(profileResult)")

        let bareHasJiuShiShuo = bareResult.contains("就是说")
        let profileHasJiuShiShuo = profileResult.contains("就是说")
        print("无画像保留'就是说': \(bareHasJiuShiShuo)")
        print("有画像保留'就是说': \(profileHasJiuShiShuo) (应为 true，action=keep)")
    }
}
