//
//  PromptComposerTests.swift
//  TEST-01：V3 五层 Prompt 拼接
//

import Foundation
import Testing
@testable import vilsay

struct PromptComposerTests {

    // ── §0 基础 ─────────────────────────────────────

    @Test func bareMinimum_noProfile_noContext() {
        let prompt = PromptComposer.systemPrompt(for: nil)
        #expect(prompt.contains("语言整理师"))
        #expect(prompt.contains("P1 自我纠正识别"))
        #expect(!prompt.contains("【场景提示】"))
        #expect(!prompt.contains("【识别质量提示】"))
        #expect(!prompt.contains("【用户专属】"))
    }

    @Test func v2Compat_defaultParams() {
        let p1 = PromptComposer.systemPrompt(for: nil)
        let p2 = PromptComposer.systemPrompt(for: nil, targetAppBundleID: nil, asrConfidence: nil)
        #expect(p1 == p2)
    }

    // ── §A App 上下文 ──────────────────────────────

    @Test func sectionA_mail_formal() {
        let prompt = PromptComposer.systemPrompt(
            for: nil,
            targetAppBundleID: "com.apple.mail"
        )
        // V4：邮件走 OutputMode.email，注入模式规则而非 §A 场景提示
        #expect(prompt.contains("【输出模式：邮件】"))
        #expect(prompt.contains("正式"))
    }

    @Test func sectionA_wechat_casual() {
        let prompt = PromptComposer.systemPrompt(
            for: nil,
            targetAppBundleID: "com.tencent.xinWeChat"
        )
        #expect(prompt.contains("【输出模式：聊天】"))
        #expect(prompt.contains("语气词"))
    }

    @Test func sectionA_unknown_app_noInjection() {
        let prompt = PromptComposer.systemPrompt(
            for: nil,
            targetAppBundleID: "com.apple.Terminal"
        )
        #expect(!prompt.contains("【场景提示】"))
    }

    @Test func sectionA_nil_bundleID_noInjection() {
        let prompt = PromptComposer.systemPrompt(
            for: nil,
            targetAppBundleID: nil
        )
        #expect(!prompt.contains("【场景提示】"))
    }

    // ── §C ASR 置信度 ──────────────────────────────

    @Test func sectionC_lowConfidence_injected() {
        let prompt = PromptComposer.systemPrompt(
            for: nil,
            asrConfidence: 0.25
        )
        #expect(prompt.contains("【识别质量提示】"))
        #expect(prompt.contains("25%"))
        #expect(prompt.contains("同音字纠偏"))
    }

    @Test func sectionC_highConfidence_notInjected() {
        let prompt = PromptComposer.systemPrompt(
            for: nil,
            asrConfidence: 0.85
        )
        #expect(!prompt.contains("【识别质量提示】"))
    }

    @Test func sectionC_exactThreshold_notInjected() {
        let prompt = PromptComposer.systemPrompt(
            for: nil,
            asrConfidence: 0.4
        )
        #expect(!prompt.contains("【识别质量提示】"))
    }

    // ── §1 用户画像 ────────────────────────────────

    @Test func section1_withProfile_injected() {
        let profile = UserProfile(
            habitualWords: [
                .init(word: "就是说", action: "simplify", confidence: 0.8)
            ],
            thinkingStyle: .init(
                expand: "先总后分",
                topicSwitchSignals: ["然后", "另外"],
                closeSignals: ["就这样"],
                confidence: 0.7
            ),
            tone: .init(overall: "直接有主见", sentenceLength: "medium",
                        mixedLang: "zh-en", confidence: 0.6),
            dictionaryItems: [
                .init(type: "term", word: "API", pinyin: nil),
                .init(type: "term", word: "Pipeline", pinyin: nil)
            ]
        )
        let prompt = PromptComposer.systemPrompt(for: profile)
        #expect(prompt.contains("【用户专属】"))
        #expect(prompt.contains("就是说"))
        #expect(prompt.contains("先总后分"))
        #expect(prompt.contains("直接有主见"))
        #expect(prompt.contains("API"))
    }

    @Test func section1_lowConfidence_filtered() {
        let profile = UserProfile(
            habitualWords: [
                .init(word: "啊", action: "remove", confidence: 0.1)
            ],
            thinkingStyle: nil,
            tone: nil,
            dictionaryItems: []
        )
        let prompt = PromptComposer.systemPrompt(for: profile)
        #expect(!prompt.contains("【用户专属】"))
    }

    // ── §1.P 拼音同音纠偏 ─────────────────────────

    @Test func section1P_pinyin_injected() {
        let profile = UserProfile(
            habitualWords: [],
            thinkingStyle: nil,
            tone: nil,
            dictionaryItems: [
                .init(type: "term", word: "事业", pinyin: "shi ye"),
                .init(type: "person", word: "张思远", pinyin: "zhang si yuan")
            ]
        )
        let prompt = PromptComposer.systemPrompt(for: profile)
        #expect(prompt.contains("同音词"))
        #expect(prompt.contains("事业(shi ye)"))
        #expect(prompt.contains("张思远(zhang si yuan)"))
    }

    // ── 五层全部同时 ───────────────────────────────

    @Test func allFiveLayers_simultaneously() {
        let profile = UserProfile(
            habitualWords: [
                .init(word: "就是说", action: "keep", confidence: 0.9)
            ],
            thinkingStyle: nil,
            tone: .init(overall: "直接", sentenceLength: "short",
                        mixedLang: "", confidence: 0.5),
            dictionaryItems: [
                .init(type: "term", word: "事业部", pinyin: "shi ye bu")
            ]
        )
        let prompt = PromptComposer.systemPrompt(
            for: profile,
            targetAppBundleID: "com.apple.mail",
            asrConfidence: 0.2
        )
        #expect(prompt.contains("语言整理师"))
        #expect(prompt.contains("【输出模式：邮件】"))
        #expect(prompt.contains("【识别质量提示】"))
        #expect(prompt.contains("【用户专属】"))
        #expect(prompt.contains("事业部(shi ye bu)"))
        #expect(prompt.contains("P1 自我纠正识别"))

        let r0 = prompt.range(of: "语言整理师")!
        let rA = prompt.range(of: "【输出模式：邮件】")!
        let rC = prompt.range(of: "【识别质量提示】")!
        let r1 = prompt.range(of: "【用户专属】")!
        let r2 = prompt.range(of: "P1 自我纠正识别")!
        #expect(r0.lowerBound < rA.lowerBound)
        #expect(rA.lowerBound < rC.lowerBound)
        #expect(rC.lowerBound < r1.lowerBound)
        #expect(r1.lowerBound < r2.lowerBound)
    }

    @Test func v4_general_matches_v3_persona() {
        #expect(Prompts.personaCore(for: .general) == Prompts.personaCore)
    }

    @Test func v4_general_processing_matches_engine() {
        #expect(Prompts.processingRules(for: .general) == Prompts.processingEngine)
    }
}
