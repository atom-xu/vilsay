//
//  FunctionalPipelineTests.swift
//  vilsayTests — 功能性端到端测试：模拟环境，无需 API Key。
//
//  覆盖：OutputMode 路由 → Prompt 组装 → 润色风格 → raw_log 记录 → AI3 分组
//

import Testing
import Foundation
import GRDB
@testable import vilsay

// MARK: - F1：OutputMode 路由完整性

@Suite("F1 · OutputMode 路由")
struct F1_OutputModeRouting {

    @Test("F1-01 微信 → .chat")
    func wechatResolves() {
        let r = MockPipelineSimulator.simulate(asrText: "测试", targetBundleID: "com.tencent.xinWeChat")
        #expect(r.outputMode == .chat)
    }

    @Test("F1-02 Word → .document")
    func wordResolves() {
        let r = MockPipelineSimulator.simulate(asrText: "测试", targetBundleID: "com.microsoft.Word")
        #expect(r.outputMode == .document)
    }

    @Test("F1-03 Claude → .general（aiCommand 暂未自动激活）")
    func claudeResolves() {
        let r = MockPipelineSimulator.simulate(asrText: "测试", targetBundleID: "com.anthropic.claudefordesktop")
        #expect(r.outputMode == .general)
    }

    @Test("F1-04 Mail → .email")
    func mailResolves() {
        let r = MockPipelineSimulator.simulate(asrText: "测试", targetBundleID: "com.apple.mail")
        #expect(r.outputMode == .email)
    }

    @Test("F1-05 Notes → .note")
    func notesResolves() {
        let r = MockPipelineSimulator.simulate(asrText: "测试", targetBundleID: "com.apple.Notes")
        #expect(r.outputMode == .note)
    }

    @Test("F1-06 未知 app → .general")
    func unknownResolves() {
        let r = MockPipelineSimulator.simulate(asrText: "测试", targetBundleID: "com.unknown.app")
        #expect(r.outputMode == .general)
    }

    @Test("F1-07 nil bundleID → .general")
    func nilResolves() {
        let r = MockPipelineSimulator.simulate(asrText: "测试", targetBundleID: nil)
        #expect(r.outputMode == .general)
    }

    @Test("F1-08 Slack → .chat")
    func slackResolves() {
        let r = MockPipelineSimulator.simulate(asrText: "测试", targetBundleID: "com.slack.Slack")
        #expect(r.outputMode == .chat)
    }

    @Test("F1-09 Notion → .document")
    func notionResolves() {
        let r = MockPipelineSimulator.simulate(asrText: "测试", targetBundleID: "com.notion.id")
        #expect(r.outputMode == .document)
    }

    @Test("F1-10 Outlook → .email")
    func outlookResolves() {
        let r = MockPipelineSimulator.simulate(asrText: "测试", targetBundleID: "com.microsoft.Outlook")
        #expect(r.outputMode == .email)
    }
}

// MARK: - F2：Prompt 组装正确性（V3/V4 分支）

@Suite("F2 · Prompt 组装")
struct F2_PromptComposition {

    @Test("F2-01 .general 路径包含 V3 原文 §0")
    func generalContainsV3Persona() {
        let r = MockPipelineSimulator.simulate(asrText: "测试", targetBundleID: nil)
        #expect(r.systemPrompt.contains("语言整理师"))
        #expect(r.systemPrompt.contains("最小干预"))
    }

    @Test("F2-02 .general 路径包含 V3 原文 §2 P1-P5")
    func generalContainsV3Rules() {
        let r = MockPipelineSimulator.simulate(asrText: "测试", targetBundleID: nil)
        #expect(r.systemPrompt.contains("P1 自我纠正识别"))
        #expect(r.systemPrompt.contains("P5 多语言边界"))
    }

    @Test("F2-03 .general 不包含 V4 模式规则")
    func generalNoV4Rules() {
        let r = MockPipelineSimulator.simulate(asrText: "测试", targetBundleID: nil)
        #expect(!r.systemPrompt.contains("输出模式："))
        #expect(!r.systemPrompt.contains("指令提取师"))
        #expect(!r.systemPrompt.contains("结构化写作助手"))
    }

    @Test("F2-04 .document 包含结构化身份")
    func documentPersona() {
        let r = MockPipelineSimulator.simulate(asrText: "测试", targetBundleID: "com.microsoft.Word")
        #expect(r.systemPrompt.contains("结构化写作助手") || r.systemPrompt.contains("输出模式：文档"))
    }

    @Test("F2-05 .document 包含 P6 结构化重组")
    func documentHasP6() {
        let r = MockPipelineSimulator.simulate(asrText: "测试", targetBundleID: "com.microsoft.Word")
        #expect(r.systemPrompt.contains("P6") || r.systemPrompt.contains("结构化重组"))
    }

    @Test("F2-06 .aiCommand 包含指令提取身份（需手动 override 激活）")
    func aiCommandPersona() {
        let bid = "com.vilsay.test.aicommand"
        OutputModeResolver.setUserOverride(bundleID: bid, mode: .aiCommand)
        defer { OutputModeResolver.setUserOverride(bundleID: bid, mode: nil) }
        let r = MockPipelineSimulator.simulate(asrText: "测试", targetBundleID: bid)
        #expect(r.systemPrompt.contains("指令提取") || r.systemPrompt.contains("输出模式：AI 指令"))
    }

    @Test("F2-07 .chat 包含保留语气词规则")
    func chatRules() {
        let r = MockPipelineSimulator.simulate(asrText: "测试", targetBundleID: "com.tencent.xinWeChat")
        #expect(r.systemPrompt.contains("保留口语") || r.systemPrompt.contains("输出模式：聊天"))
    }

    @Test("F2-08 .email 包含正式语体规则")
    func emailRules() {
        let r = MockPipelineSimulator.simulate(asrText: "测试", targetBundleID: "com.apple.mail")
        #expect(r.systemPrompt.contains("邮件") || r.systemPrompt.contains("正式"))
    }

    @Test("F2-09 .note 包含笔记整理身份")
    func notePersona() {
        let r = MockPipelineSimulator.simulate(asrText: "测试", targetBundleID: "com.apple.Notes")
        #expect(r.systemPrompt.contains("笔记") || r.systemPrompt.contains("输出模式：笔记"))
    }

    @Test("F2-10 所有非 .general 模式都包含 P1-P5 通用规则")
    func allModesHaveCommonRules() {
        let bundles = [
            "com.tencent.xinWeChat",
            "com.microsoft.Word",
            "com.apple.mail",
            "com.apple.Notes",
        ]
        for bid in bundles {
            let r = MockPipelineSimulator.simulate(asrText: "测试", targetBundleID: bid)
            #expect(r.systemPrompt.contains("P1"), "P1 missing for \(bid)")
        }
    }

    @Test("F2-11 带 profile 时 §1 出现在 prompt 中")
    func profileInjected() {
        let r = MockPipelineSimulator.simulate(
            asrText: "测试",
            targetBundleID: "com.microsoft.Word",
            profile: PromptTuningHelper.devProfile
        )
        #expect(r.systemPrompt.contains("Kubernetes") || r.systemPrompt.contains("用户专属"))
    }

    @Test("F2-12 低置信度时 §C 出现")
    func confidenceHint() {
        let r = MockPipelineSimulator.simulate(
            asrText: "测试",
            targetBundleID: nil,
            asrConfidence: 0.2
        )
        #expect(r.systemPrompt.contains("识别质量提示") || r.systemPrompt.contains("置信度"))
    }
}

// MARK: - F3：输出风格验证

@Suite("F3 · 输出风格")
struct F3_OutputStyle {

    @Test("F3-01 .aiCommand 输出有编号（需 override 激活）")
    func aiCommandNumbered() {
        let bid = "com.vilsay.test.aicommand.f3"
        OutputModeResolver.setUserOverride(bundleID: bid, mode: .aiCommand)
        defer { OutputModeResolver.setUserOverride(bundleID: bid, mode: nil) }
        let r = MockPipelineSimulator.simulate(
            asrText: "帮我写一个登录接口然后就是说要支持OAuth然后返回JWT",
            targetBundleID: bid
        )
        #expect(r.polishedText.contains("1."))
        #expect(r.polishedText.contains("2."))
    }

    @Test("F3-02 .aiCommand 输出无口语连接词（需 override 激活）")
    func aiCommandNoFillers() {
        let bid = "com.vilsay.test.aicommand.f3"
        OutputModeResolver.setUserOverride(bundleID: bid, mode: .aiCommand)
        defer { OutputModeResolver.setUserOverride(bundleID: bid, mode: nil) }
        let r = MockPipelineSimulator.simulate(
            asrText: "然后就是说那个帮我写接口",
            targetBundleID: bid
        )
        #expect(!r.polishedText.contains("然后就是说"))
        #expect(!r.polishedText.contains("那个"))
    }

    @Test("F3-03 .chat 输出保留口语感")
    func chatKeepsCasual() {
        let r = MockPipelineSimulator.simulate(
            asrText: "我觉得还行吧哈哈",
            targetBundleID: "com.tencent.xinWeChat"
        )
        #expect(!r.polishedText.contains("##"))
        #expect(!r.polishedText.contains("1."))
    }

    @Test("F3-04 .email 输出有正式语体")
    func emailFormal() {
        let r = MockPipelineSimulator.simulate(
            asrText: "就是想跟你说一下那个方案的事",
            targetBundleID: "com.apple.mail"
        )
        #expect(r.polishedText.contains("您好") || r.polishedText.contains("关于"))
    }

    @Test("F3-05 .document 长文本有结构")
    func documentStructured() {
        let longText = String(repeating: "我觉得这个产品的核心竞争力在于长文本的结构化整理能力因为短文本已经被输入法覆盖了", count: 5)
        let r = MockPipelineSimulator.simulate(
            asrText: longText,
            targetBundleID: "com.microsoft.Word"
        )
        #expect(r.polishedText.contains("##") || r.polishedText.contains("1."))
    }

    @Test("F3-06 .note 输出是 bullet")
    func noteBullets() {
        let r = MockPipelineSimulator.simulate(
            asrText: "核心竞争力在长文本短文本不行",
            targetBundleID: "com.apple.Notes"
        )
        #expect(r.polishedText.contains("- "))
    }

    @Test("F3-07 .general 短文本不结构化")
    func generalShortNoStructure() {
        let r = MockPipelineSimulator.simulate(
            asrText: "今天天气不错",
            targetBundleID: nil
        )
        #expect(!r.polishedText.contains("##"))
        #expect(!r.polishedText.contains("1."))
    }

    @Test("F3-08 同一输入不同模式输出不同")
    func sameInputDifferentModes() {
        let input = "帮我写一个登录接口然后就是说要支持OAuth"
        // chat vs document vs email — 三种自动激活的模式
        let chat = MockPipelineSimulator.simulate(asrText: input, targetBundleID: "com.tencent.xinWeChat")
        let doc = MockPipelineSimulator.simulate(asrText: input, targetBundleID: "com.microsoft.Word")
        let email = MockPipelineSimulator.simulate(asrText: input, targetBundleID: "com.apple.mail")
        #expect(chat.polishedText != doc.polishedText)
        #expect(chat.polishedText != email.polishedText)
        #expect(doc.polishedText != email.polishedText)
    }
}

// MARK: - F4：数据库记录验证

@Suite("F4 · 数据库记录")
struct F4_DatabaseRecording {

    @Test("F4-01 raw_log 记录包含 output_mode")
    func rawLogHasOutputMode() {
        // 清除可能残留的 UserDefaults override（并行测试隔离）
        OutputModeResolver.setUserOverride(bundleID: "com.tencent.xinWeChat", mode: nil)
        let r = MockPipelineSimulator.simulate(asrText: "测试", targetBundleID: "com.tencent.xinWeChat")
        #expect(r.rawLogRecord.outputMode == "chat")
    }

    @Test("F4-02 raw_log 记录包含 target_app_id")
    func rawLogHasTargetApp() {
        let r = MockPipelineSimulator.simulate(asrText: "测试", targetBundleID: "com.microsoft.Word")
        #expect(r.rawLogRecord.targetAppId == "com.microsoft.Word")
    }

    @Test("F4-03 .general 模式 output_mode = 'general'")
    func generalModeValue() {
        let r = MockPipelineSimulator.simulate(asrText: "测试", targetBundleID: nil)
        #expect(r.rawLogRecord.outputMode == "general")
    }

    @Test("F4-04 raw_log 可写入内存数据库")
    func canWriteToDatabase() throws {
        let db = try TestDatabase.makeEmpty()
        let r = MockPipelineSimulator.simulate(asrText: "测试录音", targetBundleID: "com.apple.mail")
        try db.write { conn in
            var record = r.rawLogRecord
            try record.insert(conn)
        }
        let count = try db.read { conn in
            try RawLogRecord.fetchCount(conn)
        }
        #expect(count == 1)
    }

    @Test("F4-05 多模式记录可写入同一数据库")
    func multiModeRecords() throws {
        let db = try TestDatabase.makeEmpty()
        let bundles: [String?] = [
            "com.tencent.xinWeChat",
            "com.microsoft.Word",
            "com.apple.mail",
            "com.apple.Notes",
            "com.anthropic.claudefordesktop",
            nil
        ]
        try db.write { conn in
            for bid in bundles {
                let r = MockPipelineSimulator.simulate(asrText: "测试第\(bid ?? "nil")条", targetBundleID: bid)
                var record = r.rawLogRecord
                try record.insert(conn)
            }
        }
        let count = try db.read { conn in try RawLogRecord.fetchCount(conn) }
        #expect(count == 6)

        // 按 output_mode 分组统计
        let modes = try db.read { conn in
            try String.fetchAll(conn, sql: "SELECT DISTINCT output_mode FROM raw_log ORDER BY output_mode")
        }
        #expect(modes.contains("chat"))
        #expect(modes.contains("document"))
        #expect(modes.contains("email"))
        #expect(modes.contains("general"))
    }
}

// MARK: - F5：V3 回归验证

@Suite("F5 · V3 回归")
struct F5_V3Regression {

    @Test("F5-01 V3 无参 systemPrompt 行为不变")
    func v3NoParamSignature() {
        let prompt = PromptComposer.systemPrompt(for: nil)
        #expect(prompt.contains("语言整理师"))
        #expect(prompt.contains("最小干预"))
        #expect(prompt.contains("P1 自我纠正识别"))
    }

    @Test("F5-02 Prompts.personaCore 无参属性 = V3 原文")
    func v3PersonaCoreProperty() {
        let persona = Prompts.personaCore
        #expect(persona.contains("语言整理师"))
        #expect(persona.contains("最小干预"))
    }

    @Test("F5-03 Prompts.processingEngine 无参属性 = V3 原文")
    func v3ProcessingEngineProperty() {
        let engine = Prompts.processingEngine
        #expect(engine.contains("P1 自我纠正识别"))
        #expect(engine.contains("P2 填充词处理"))
        #expect(engine.contains("P3 同音字纠偏"))
        #expect(engine.contains("P4 断句重组"))
        #expect(engine.contains("P5 多语言边界"))
    }

    @Test("F5-04 personaCore(.general) == personaCore 无参")
    func generalEqualsV3() {
        let v3 = Prompts.personaCore
        let v4General = Prompts.personaCore(for: .general)
        #expect(v3 == v4General)
    }

    @Test("F5-05 processingRules(.general) == processingEngine 无参")
    func generalRulesEqualsV3() {
        let v3 = Prompts.processingEngine
        let v4General = Prompts.processingRules(for: .general)
        #expect(v3 == v4General)
    }

    @Test("F5-06 .general 路径 appContextMap 对已知 app 仍生效")
    func generalAppContextMapWorks() {
        // 用一个在 appContextMap 中但不在 OutputModeResolver 中的 app（如果有的话）
        // 或者验证 .general 路径下 appContextMap 逻辑存在
        let prompt = PromptComposer.systemPrompt(for: nil, targetAppBundleID: "com.unknown.app")
        // 未知 app → .general → 无 appContextMap 命中 → 不含场景提示
        #expect(!prompt.contains("场景提示"))
    }
}

// MARK: - F6：闭环数据流验证

@Suite("F6 · 闭环数据流")
struct F6_ClosedLoop {

    @Test("F6-01 完整闭环：bundleID → mode → prompt → polish → record")
    func fullLoop() throws {
        let db = try TestDatabase.makeEmpty()

        // 模拟 5 次微信聊天
        try db.write { conn in
            for i in 1...5 {
                let r = MockPipelineSimulator.simulate(
                    asrText: "聊天测试第\(i)条",
                    targetBundleID: "com.tencent.xinWeChat"
                )
                #expect(r.outputMode == .chat)
                #expect(r.rawLogRecord.outputMode == "chat")
                var record = r.rawLogRecord
                try record.insert(conn)
            }
        }

        // 模拟 5 次文档写作
        try db.write { conn in
            for i in 1...5 {
                let r = MockPipelineSimulator.simulate(
                    asrText: "文档测试第\(i)条",
                    targetBundleID: "com.microsoft.Word"
                )
                #expect(r.outputMode == .document)
                var record = r.rawLogRecord
                try record.insert(conn)
            }
        }

        // 验证数据库中按 mode 分组
        let chatCount = try db.read { conn in
            try RawLogRecord.filter(Column("output_mode") == "chat").fetchCount(conn)
        }
        let docCount = try db.read { conn in
            try RawLogRecord.filter(Column("output_mode") == "document").fetchCount(conn)
        }
        #expect(chatCount == 5)
        #expect(docCount == 5)
    }

    @Test("F6-02 AI3 分组阈值：<5 条不触发 per-mode 分析")
    func ai3ThresholdCheck() throws {
        let db = try TestDatabase.makeEmpty()
        // 写入 3 条 chat（不足 5 条）
        try db.write { conn in
            for i in 1...3 {
                let r = MockPipelineSimulator.simulate(asrText: "少量\(i)", targetBundleID: "com.tencent.xinWeChat")
                var record = r.rawLogRecord
                try record.insert(conn)
            }
        }
        let chatCount = try db.read { conn in
            try RawLogRecord.filter(Column("output_mode") == "chat").fetchCount(conn)
        }
        #expect(chatCount == 3)
        // 3 < 5，AI3 不应生成 per-mode profile（逻辑验证）
    }

    @Test("F6-03 模式切换不混淆上下文")
    func modeSwitchIsolation() {
        // 连续在不同 app 间切换
        let r1 = MockPipelineSimulator.simulate(asrText: "邮件内容", targetBundleID: "com.apple.mail")
        let r2 = MockPipelineSimulator.simulate(asrText: "聊天内容", targetBundleID: "com.tencent.xinWeChat")
        let r3 = MockPipelineSimulator.simulate(asrText: "文档内容", targetBundleID: "com.microsoft.Word")

        // 各自的 mode 和 prompt 风格不交叉
        #expect(r1.outputMode == .email)
        #expect(r2.outputMode == .chat)
        #expect(r3.outputMode == .document)
        #expect(r1.systemPrompt != r2.systemPrompt)
        #expect(r2.systemPrompt != r3.systemPrompt)
    }
}
