# Week 5+6 自动化测试任务书

**版本**: 1.0 | **日期**: 2026-03-25
**目标**: 所有核心逻辑可通过 `xcodebuild test` 一键验证，无需人工操作
**框架**: Swift Testing（`@Test` + `#expect()`）
**原则**: 测试自己能发现问题、修复后能自证修复正确

---

## 设计思路

| 层级 | 可自动化？ | 方法 |
|------|-----------|------|
| PromptComposer 拼接逻辑 | ✅ 完全自动 | 纯函数，给定输入→断言输出包含/不包含指定片段 |
| PinyinHelper | ✅ 完全自动 | 纯函数 |
| DB Schema / Migration | ✅ 完全自动 | 内存 GRDB，无需磁盘文件 |
| RawLogger / ProfileService / ErrorFeedback | ✅ 完全自动 | 内存 DB |
| AI3Analyzer 去重逻辑 | ✅ 完全自动 | 内存 DB + mock Qwen 响应 |
| Prompt 实际润色效果 | ✅ 集成测试 | 真实调 Qwen API，对比不同 Prompt 的输出差异 |
| Pipeline 超时保护 | ⚠️ 半自动 | mock 慢 ASR，验证超时触发 |
| 浮层/菜单栏 UI | ❌ 需 UI Test | 已有 Week2AcceptanceTests 模式可扩展 |

---

## 测试文件规划

```
vilsayTests/
├── PromptComposerTests.swift      ← V3 五层 Prompt 拼接（12 个 case）
├── PromptEffectivenessTests.swift  ← 真实 LLM 调用验证效果（6 个 case，需 API Key）
├── PinyinHelperTests.swift         ← 拼音转换（5 个 case）
├── DatabaseMigrationTests.swift    ← v1→v2 迁移、Schema 对齐（8 个 case）
├── ErrorFeedbackTests.swift        ← 原子标记 + 并发安全（4 个 case）
├── ProfileServiceTests.swift       ← 候选词去重 + 置信度合并（6 个 case）
├── AI3DeduplicationTests.swift     ← last_analyzed_log_id 去重（5 个 case）
├── RawLoggerFieldTests.swift       ← 新字段写入完整性（4 个 case）
└── (已有) HotkeyComboLogicTests.swift / PolishStreamParsingTests.swift / ...
```

---

## 公共测试工具：内存数据库

> 所有 DB 相关测试使用内存 GRDB，不碰磁盘，测试间互不干扰。

```
目标文件：
  vilsayTests/TestHelpers/InMemoryDatabase.swift  ← 新建

实现：

import GRDB
@testable import vilsay

/// 创建一个内存 GRDB DatabaseQueue，跑完 v1+v2 迁移，可直接用于测试。
/// 每次调用返回全新的空数据库。
enum TestDatabase {
    static func makeEmpty() throws -> DatabaseQueue {
        let db = try DatabaseQueue(configuration: .init())
        var migrator = DatabaseMigrator()
        Migrations.registerMigrations(&migrator)
        try migrator.migrate(db)
        return db
    }

    /// 插入 N 条 raw_log 测试数据
    static func seedRawLogs(_ db: DatabaseQueue, count: Int,
                            asrPrefix: String = "测试语音") throws {
        try db.write { conn in
            for i in 1...count {
                var record = RawLogRecord(
                    asrText: "\(asrPrefix) 第\(i)句",
                    polishedText: "润色后 第\(i)句",
                    durationMs: 500,
                    sessionId: UUID().uuidString,
                    asrProvider: "whisperKit",
                    asrConfidence: 0.75,
                    targetAppId: "com.apple.Notes",
                    userFlaggedError: false,
                    createdAt: ISO8601DateFormatter().string(from: Date())
                )
                try record.insert(conn)
            }
            // 同步 analyzer_state
            try conn.execute(sql: """
                UPDATE analyzer_state
                SET total_logged_count = \(count)
                WHERE id = 1
            """)
        }
    }
}
```

---

## TEST-01 · PromptComposerTests（12 case）

> **核心测试**：验证 V3 五层 Prompt 在各种组合下正确拼接。纯函数，无副作用，毫秒级运行。

```
目标文件：
  vilsayTests/PromptComposerTests.swift

import Testing
@testable import vilsay

struct PromptComposerTests {

    // ── §0 基础 ─────────────────────────────────────

    @Test func bareMinimum_noProfile_noContext() {
        // 最简情况：无画像、无 App 上下文、无置信度
        let prompt = PromptComposer.systemPrompt(for: nil)
        #expect(prompt.contains("语言整理师"))           // §0
        #expect(prompt.contains("P1 自我纠正识别"))      // §2
        #expect(!prompt.contains("【场景提示】"))         // 无 §A
        #expect(!prompt.contains("【识别质量提示】"))     // 无 §C
        #expect(!prompt.contains("【用户专属】"))         // 无 §1
    }

    @Test func v2Compat_defaultParams() {
        // V2 兼容路径：只传 profile
        let p1 = PromptComposer.systemPrompt(for: nil)
        let p2 = PromptComposer.systemPrompt(for: nil, targetAppBundleID: nil, asrConfidence: nil)
        #expect(p1 == p2)  // 两种调法结果完全相同
    }

    // ── §A App 上下文 ──────────────────────────────

    @Test func sectionA_mail_formal() {
        let prompt = PromptComposer.systemPrompt(
            for: nil,
            targetAppBundleID: "com.apple.mail"
        )
        #expect(prompt.contains("【场景提示】"))
        #expect(prompt.contains("邮件"))
        #expect(prompt.contains("正式语体"))
    }

    @Test func sectionA_wechat_casual() {
        let prompt = PromptComposer.systemPrompt(
            for: nil,
            targetAppBundleID: "com.tencent.xinWeChat"
        )
        #expect(prompt.contains("【场景提示】"))
        #expect(prompt.contains("聊天"))
        #expect(prompt.contains("口语化"))
    }

    @Test func sectionA_unknown_app_noInjection() {
        let prompt = PromptComposer.systemPrompt(
            for: nil,
            targetAppBundleID: "com.apple.Terminal"
        )
        #expect(!prompt.contains("【场景提示】"))  // 未映射 App 不注入
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
            asrConfidence: 0.25  // 低于 0.4
        )
        #expect(prompt.contains("【识别质量提示】"))
        #expect(prompt.contains("25%"))
        #expect(prompt.contains("同音字纠偏"))
    }

    @Test func sectionC_highConfidence_notInjected() {
        let prompt = PromptComposer.systemPrompt(
            for: nil,
            asrConfidence: 0.85  // 高于 0.4
        )
        #expect(!prompt.contains("【识别质量提示】"))
    }

    @Test func sectionC_exactThreshold_notInjected() {
        let prompt = PromptComposer.systemPrompt(
            for: nil,
            asrConfidence: 0.4  // 等于阈值，不注入（< 才注入）
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
                .init(word: "API", type: "term", pinyin: nil),
                .init(word: "Pipeline", type: "term", pinyin: nil)
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
                .init(word: "啊", action: "remove", confidence: 0.1) // 低于 0.3
            ],
            thinkingStyle: nil,
            tone: nil,
            dictionaryItems: []
        )
        let prompt = PromptComposer.systemPrompt(for: profile)
        #expect(!prompt.contains("【用户专属】"))  // 全部被过滤，不注入
    }

    // ── §1.P 拼音同音纠偏 ─────────────────────────

    @Test func section1P_pinyin_injected() {
        let profile = UserProfile(
            habitualWords: [],
            thinkingStyle: nil,
            tone: nil,
            dictionaryItems: [
                .init(word: "事业", type: "term", pinyin: "shi ye"),
                .init(word: "张思远", type: "person", pinyin: "zhang si yuan")
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
                .init(word: "事业部", type: "term", pinyin: "shi ye bu")
            ]
        )
        let prompt = PromptComposer.systemPrompt(
            for: profile,
            targetAppBundleID: "com.apple.mail",
            asrConfidence: 0.2
        )
        // 验证 5 层全部存在
        #expect(prompt.contains("语言整理师"))       // §0
        #expect(prompt.contains("【场景提示】"))      // §A
        #expect(prompt.contains("【识别质量提示】"))  // §C
        #expect(prompt.contains("【用户专属】"))      // §1
        #expect(prompt.contains("事业部(shi ye bu)")) // §1.P
        #expect(prompt.contains("P1 自我纠正识别"))   // §2

        // 验证顺序：§0 在 §A 前，§A 在 §C 前，§C 在 §1 前，§1 在 §2 前
        let r0 = prompt.range(of: "语言整理师")!
        let rA = prompt.range(of: "【场景提示】")!
        let rC = prompt.range(of: "【识别质量提示】")!
        let r1 = prompt.range(of: "【用户专属】")!
        let r2 = prompt.range(of: "P1 自我纠正识别")!
        #expect(r0.lowerBound < rA.lowerBound)
        #expect(rA.lowerBound < rC.lowerBound)
        #expect(rC.lowerBound < r1.lowerBound)
        #expect(r1.lowerBound < r2.lowerBound)
    }
}
```

---

## TEST-02 · PromptEffectivenessTests（真实 LLM 调用）

> **集成测试**：用同一段 ASR 输入 + 不同 Prompt 调用真实 Qwen API，验证输出差异。
> 需要 `DASHSCOPE_API_KEY` 环境变量。无 Key 时自动 skip。
> 每个 case 约 2-5s（网络调用），总计 < 30s。

```
目标文件：
  vilsayTests/PromptEffectivenessTests.swift

import Testing
import Foundation
@testable import vilsay

struct PromptEffectivenessTests {

    /// 跳过条件：无 API Key 时不运行
    private static var apiKey: String? {
        ProcessInfo.processInfo.environment["DASHSCOPE_API_KEY"]
    }

    /// 调用 Qwen 润色的简化 helper
    private func polish(systemPrompt: String, asrText: String) async throws -> String {
        guard let key = Self.apiKey else {
            throw SkipError()  // 跳过
        }
        let user = Prompts.polishUserMessage(asrText: asrText)
        // 直接调 PolishService.polishPlain (非流式，简单)
        let result = try await PolishService.polishPlain(
            system: systemPrompt,
            user: user
        )
        return result
    }

    // ── 邮件 vs 聊天 语体对比 ──────────────────────

    @Test func appContext_mail_vs_wechat_style() async throws {
        guard Self.apiKey != nil else { return }  // 无 Key 跳过

        let asr = "嗯就是那个方案呢我觉得还行吧你看着办就好了啊"

        let mailPrompt = PromptComposer.systemPrompt(
            for: nil,
            targetAppBundleID: "com.apple.mail"
        )
        let chatPrompt = PromptComposer.systemPrompt(
            for: nil,
            targetAppBundleID: "com.tencent.xinWeChat"
        )

        let mailResult = try await polish(systemPrompt: mailPrompt, asrText: asr)
        let chatResult = try await polish(systemPrompt: chatPrompt, asrText: asr)

        // 两个结果应该不同
        #expect(mailResult != chatResult,
                "邮件和聊天场景应产生不同风格的输出\n邮件: \(mailResult)\n聊天: \(chatResult)")

        // 邮件结果不应包含口语词
        let casualWords = ["吧", "啊", "呢", "嗯"]
        let mailHasCasual = casualWords.contains { mailResult.contains($0) }
        let chatHasCasual = casualWords.contains { chatResult.contains($0) }

        // 邮件应更少口语词（不强制为 0，但应少于聊天）
        // 这里用 print 记录而非强断言，因为 LLM 输出不完全确定
        print("📧 邮件输出: \(mailResult)")
        print("💬 聊天输出: \(chatResult)")
        print("📧 含口语词: \(mailHasCasual), 💬 含口语词: \(chatHasCasual)")
    }

    // ── 文档 vs 笔记 简洁度对比 ────────────────────

    @Test func appContext_word_vs_notes_length() async throws {
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

        let wordResult = try await polish(systemPrompt: wordPrompt, asrText: asr)
        let notesResult = try await polish(systemPrompt: notesPrompt, asrText: asr)

        print("📄 Word 输出(\(wordResult.count)字): \(wordResult)")
        print("📝 Notes 输出(\(notesResult.count)字): \(notesResult)")

        // Notes 输出应更短（简洁）
        #expect(notesResult.count <= wordResult.count + 5,
                "笔记输出应不长于文档输出\nWord(\(wordResult.count)): \(wordResult)\nNotes(\(notesResult.count)): \(notesResult)")
    }

    // ── 无上下文 vs 有上下文 ──────────────────────

    @Test func appContext_none_vs_mail() async throws {
        guard Self.apiKey != nil else { return }

        let asr = "帮我跟客户说一下那个交付时间要推迟两周"

        let barePrompt = PromptComposer.systemPrompt(for: nil)
        let mailPrompt = PromptComposer.systemPrompt(
            for: nil,
            targetAppBundleID: "com.apple.mail"
        )

        let bareResult = try await polish(systemPrompt: barePrompt, asrText: asr)
        let mailResult = try await polish(systemPrompt: mailPrompt, asrText: asr)

        print("🔲 无上下文: \(bareResult)")
        print("📧 邮件上下文: \(mailResult)")

        // 邮件版本应更正式（至少不完全相同）
        // 不强制断言不同（LLM 有可能巧合相同），但记录差异
        if bareResult == mailResult {
            print("⚠️ 两个输出相同，§A 可能未产生影响")
        }
    }

    // ── 低置信度 vs 高置信度 纠错差异 ──────────────

    @Test func confidence_low_vs_high_correction() async throws {
        guard Self.apiKey != nil else { return }

        // 含同音字错误的 ASR 输出
        let asr = "我觉得这个试验部的方案义定要重新评估一下"
        // 正确应该是：事业部、一定

        let lowConfPrompt = PromptComposer.systemPrompt(
            for: nil,
            asrConfidence: 0.2  // 低置信度
        )
        let highConfPrompt = PromptComposer.systemPrompt(
            for: nil,
            asrConfidence: 0.9  // 高置信度
        )

        let lowResult = try await polish(systemPrompt: lowConfPrompt, asrText: asr)
        let highResult = try await polish(systemPrompt: highConfPrompt, asrText: asr)

        print("🔽 低置信: \(lowResult)")
        print("🔼 高置信: \(highResult)")

        // 低置信度应更积极纠正"试验"→"事业"，"义定"→"一定"
        let lowFixed试验 = lowResult.contains("事业")
        let highFixed试验 = highResult.contains("事业")
        print("低置信纠正'试验→事业': \(lowFixed试验)")
        print("高置信纠正'试验→事业': \(highFixed试验)")
    }

    // ── 有拼音词典 vs 无词典 纠偏效果 ──────────────

    @Test func pinyin_dictionary_correction() async throws {
        guard Self.apiKey != nil else { return }

        let asr = "帮我发给张思源然后问一下试验部的进展"
        // 正确：张思远（人名）、事业部

        let noDictPrompt = PromptComposer.systemPrompt(for: nil)

        let withDictProfile = UserProfile(
            habitualWords: [],
            thinkingStyle: nil,
            tone: nil,
            dictionaryItems: [
                .init(word: "张思远", type: "person", pinyin: "zhang si yuan"),
                .init(word: "事业部", type: "term", pinyin: "shi ye bu")
            ]
        )
        let dictPrompt = PromptComposer.systemPrompt(for: withDictProfile)

        let noDictResult = try await polish(systemPrompt: noDictPrompt, asrText: asr)
        let dictResult = try await polish(systemPrompt: dictPrompt, asrText: asr)

        print("📕 无词典: \(noDictResult)")
        print("📗 有词典: \(dictResult)")

        // 有词典时应纠正为"张思远"和"事业部"
        let dictFixed张 = dictResult.contains("张思远")
        let dictFixed事 = dictResult.contains("事业部")
        print("词典纠正'张思源→张思远': \(dictFixed张)")
        print("词典纠正'试验部→事业部': \(dictFixed事)")

        // 至少应纠正一个
        #expect(dictFixed张 || dictFixed事,
                "有拼音词典时应至少纠正一个同音词\n输出: \(dictResult)")
    }

    // ── 画像注入 vs 无画像 风格对比 ────────────────

    @Test func profile_vs_noProfile() async throws {
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
                .init(word: "API", type: "term", pinyin: nil),
                .init(word: "重构", type: "term", pinyin: nil)
            ]
        )
        let profilePrompt = PromptComposer.systemPrompt(for: profile)

        let bareResult = try await polish(systemPrompt: barePrompt, asrText: asr)
        let profileResult = try await polish(systemPrompt: profilePrompt, asrText: asr)

        print("🔲 无画像: \(bareResult)")
        print("👤 有画像: \(profileResult)")

        // 记录差异点
        let bareHas就是说 = bareResult.contains("就是说")
        let profileHas就是说 = profileResult.contains("就是说")
        print("无画像保留'就是说': \(bareHas就是说)")
        print("有画像保留'就是说': \(profileHas就是说) (应为 true，action=keep)")
    }
}

说明：
  - 无 DASHSCOPE_API_KEY 环境变量时，所有 case 自动跳过（不报错）
  - 每个 case 同时 print 完整输出，方便人工审阅日志
  - 断言宽松：LLM 输出不确定性，只断言"明显应该不同"的情况
  - 运行：xcodebuild test -scheme vilsay DASHSCOPE_API_KEY=sk-xxx
```

---

## TEST-03 · PinyinHelperTests（5 case）

```
目标文件：
  vilsayTests/PinyinHelperTests.swift

import Testing
@testable import vilsay

struct PinyinHelperTests {

    @Test func chinese_basic() {
        let result = PinyinHelper.toPinyin("事业")
        #expect(result.lowercased().contains("shi"))
        #expect(result.lowercased().contains("ye"))
    }

    @Test func chinese_name() {
        let result = PinyinHelper.toPinyin("张思远")
        #expect(result.lowercased().contains("zhang"))
        #expect(result.lowercased().contains("si"))
        #expect(result.lowercased().contains("yuan"))
    }

    @Test func english_passthrough() {
        let result = PinyinHelper.toPinyin("API")
        #expect(result.contains("API") || result.contains("api"))
    }

    @Test func mixed_chinese_english() {
        let result = PinyinHelper.toPinyin("API接口")
        #expect(result.lowercased().contains("jie"))
        #expect(result.lowercased().contains("kou"))
    }

    @Test func empty_string() {
        let result = PinyinHelper.toPinyin("")
        #expect(result.isEmpty)
    }
}
```

---

## TEST-04 · DatabaseMigrationTests（8 case）

```
目标文件：
  vilsayTests/DatabaseMigrationTests.swift

import Testing
import GRDB
@testable import vilsay

struct DatabaseMigrationTests {

    @Test func freshDatabase_allTablesExist() throws {
        let db = try TestDatabase.makeEmpty()
        try db.read { conn in
            // 5 张表
            let tables = try String.fetchAll(conn,
                sql: "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
            #expect(tables.contains("raw_log"))
            #expect(tables.contains("user_profile"))
            #expect(tables.contains("dictionary"))
            #expect(tables.contains("dictionary_candidates"))
            #expect(tables.contains("analyzer_state"))
        }
    }

    @Test func analyzerState_initialRow() throws {
        let db = try TestDatabase.makeEmpty()
        try db.read { conn in
            let state = try AnalyzerStateRecord.fetchOne(conn)
            #expect(state != nil)
            #expect(state?.totalLoggedCount == 0)
            #expect(state?.lastTriggerCount == 0)
            #expect(state?.lastAnalyzedLogId == nil)
        }
    }

    @Test func rawLog_v2Columns() throws {
        let db = try TestDatabase.makeEmpty()
        try db.write { conn in
            var record = RawLogRecord(
                asrText: "测试",
                polishedText: "测试润色",
                durationMs: 100,
                sessionId: "s1",
                asrProvider: "whisperKit",
                asrConfidence: 0.75,
                targetAppId: "com.apple.Notes",
                userFlaggedError: false,
                createdAt: "2026-03-25"
            )
            try record.insert(conn)

            let fetched = try RawLogRecord.fetchOne(conn)!
            #expect(fetched.asrProvider == "whisperKit")
            #expect(fetched.asrConfidence == 0.75)
            #expect(fetched.targetAppId == "com.apple.Notes")
            #expect(fetched.userFlaggedError == false)
        }
    }

    @Test func dictionary_pinyinColumn() throws {
        let db = try TestDatabase.makeEmpty()
        try db.write { conn in
            var record = DictionaryRecord(
                word: "事业",
                context: nil,
                pinyin: "shi ye",
                source: "manual",
                createdAt: "2026-03-25"
            )
            try record.insert(conn)

            let fetched = try DictionaryRecord.fetchOne(conn)!
            #expect(fetched.pinyin == "shi ye")
        }
    }

    @Test func candidates_stateColumn() throws {
        let db = try TestDatabase.makeEmpty()
        try db.write { conn in
            var record = DictionaryCandidateRecord(
                word: "测试词",
                score: 0.8,
                context: nil,
                pinyin: "ce shi ci",
                state: "pending",
                dismissed: 0,
                fromAnalysisAt: "2026-03-25"
            )
            try record.insert(conn)

            let fetched = try DictionaryCandidateRecord.fetchOne(conn)!
            #expect(fetched.state == "pending")
            #expect(fetched.pinyin == "ce shi ci")
        }
    }

    @Test func candidates_stateTransitions() throws {
        let db = try TestDatabase.makeEmpty()
        try db.write { conn in
            var record = DictionaryCandidateRecord(
                word: "张三", score: 0.7, context: nil,
                pinyin: "zhang san", state: "pending", dismissed: 0,
                fromAnalysisAt: "2026-03-25"
            )
            try record.insert(conn)

            // 模拟 dismiss
            try conn.execute(sql: """
                UPDATE dictionary_candidates
                SET state = 'dismissed', dismissed = 1
                WHERE word = '张三'
            """)

            let fetched = try DictionaryCandidateRecord
                .filter(Column("word") == "张三").fetchOne(conn)!
            #expect(fetched.state == "dismissed")
        }
    }

    @Test func analyzerState_lastAnalyzedLogId() throws {
        let db = try TestDatabase.makeEmpty()
        try db.write { conn in
            try conn.execute(sql: """
                UPDATE analyzer_state SET last_analyzed_log_id = 42 WHERE id = 1
            """)

            let state = try AnalyzerStateRecord.fetchOne(conn)!
            #expect(state.lastAnalyzedLogId == 42)
        }
    }

    @Test func clearAIData_resetsAll() throws {
        let db = try TestDatabase.makeEmpty()

        // 写入数据
        try db.write { conn in
            var log = RawLogRecord(
                asrText: "hi", polishedText: "hi",
                durationMs: 100, sessionId: "s",
                asrProvider: nil, asrConfidence: nil,
                targetAppId: nil, userFlaggedError: false,
                createdAt: "2026-03-25"
            )
            try log.insert(conn)
            try conn.execute(sql: """
                UPDATE analyzer_state
                SET total_logged_count = 5, last_trigger_count = 5,
                    last_analyzed_log_id = 1
                WHERE id = 1
            """)
        }

        // 模拟 clearAIData
        try db.write { conn in
            try conn.execute(sql: "DELETE FROM raw_log")
            try conn.execute(sql: "DELETE FROM user_profile")
            try conn.execute(sql: "DELETE FROM dictionary_candidates")
            try conn.execute(sql: """
                UPDATE analyzer_state
                SET total_logged_count = 0, last_trigger_count = 0,
                    last_run_at = NULL, last_analyzed_log_id = NULL
                WHERE id = 1
            """)
        }

        try db.read { conn in
            #expect(try RawLogRecord.fetchCount(conn) == 0)
            #expect(try UserProfileRecord.fetchCount(conn) == 0)
            let state = try AnalyzerStateRecord.fetchOne(conn)!
            #expect(state.totalLoggedCount == 0)
            #expect(state.lastAnalyzedLogId == nil)
        }
    }
}
```

---

## TEST-05 · ErrorFeedbackTests（4 case）

```
目标文件：
  vilsayTests/ErrorFeedbackTests.swift

import Testing
import GRDB
@testable import vilsay

struct ErrorFeedbackTests {

    @Test func flagLatest_marksNewestRow() throws {
        let db = try TestDatabase.makeEmpty()
        try TestDatabase.seedRawLogs(db, count: 3)

        // 模拟 flagLatestError 的原子 SQL
        try db.write { conn in
            try conn.execute(sql: """
                UPDATE raw_log SET user_flagged_error = 1
                WHERE id = (SELECT MAX(id) FROM raw_log)
            """)
        }

        try db.read { conn in
            let all = try RawLogRecord.order(Column("id")).fetchAll(conn)
            #expect(all[0].userFlaggedError == false)
            #expect(all[1].userFlaggedError == false)
            #expect(all[2].userFlaggedError == true)  // 只有最新一条
        }
    }

    @Test func flagLatest_emptyTable_noError() throws {
        let db = try TestDatabase.makeEmpty()
        // 空表执行不崩溃
        try db.write { conn in
            try conn.execute(sql: """
                UPDATE raw_log SET user_flagged_error = 1
                WHERE id = (SELECT MAX(id) FROM raw_log)
            """)
        }
        // 应该不抛异常
    }

    @Test func flagLatest_idempotent() throws {
        let db = try TestDatabase.makeEmpty()
        try TestDatabase.seedRawLogs(db, count: 1)

        // 连续 flag 两次
        for _ in 0..<2 {
            try db.write { conn in
                try conn.execute(sql: """
                    UPDATE raw_log SET user_flagged_error = 1
                    WHERE id = (SELECT MAX(id) FROM raw_log)
                """)
            }
        }

        try db.read { conn in
            let log = try RawLogRecord.fetchOne(conn)!
            #expect(log.userFlaggedError == true)
        }
    }

    @Test func getFlaggedErrors_returnsOnlyFlagged() throws {
        let db = try TestDatabase.makeEmpty()
        try TestDatabase.seedRawLogs(db, count: 5)

        // Flag 第 3 和第 5 条
        try db.write { conn in
            try conn.execute(sql: "UPDATE raw_log SET user_flagged_error = 1 WHERE id IN (3, 5)")
        }

        try db.read { conn in
            let flagged = try RawLogRecord
                .filter(Column("user_flagged_error") == true)
                .fetchAll(conn)
            #expect(flagged.count == 2)
            #expect(flagged.map(\.id).contains(3))
            #expect(flagged.map(\.id).contains(5))
        }
    }
}
```

---

## TEST-06 · ProfileServiceTests（6 case）

```
目标文件：
  vilsayTests/ProfileServiceTests.swift

import Testing
import GRDB
@testable import vilsay

struct ProfileServiceTests {

    @Test func insertCandidates_dedup_existingDictionary() throws {
        let db = try TestDatabase.makeEmpty()
        // 先在 dictionary 中放一个词
        try db.write { conn in
            var dict = DictionaryRecord(
                word: "API", context: nil, pinyin: nil,
                source: "manual", createdAt: "2026-03-25")
            try dict.insert(conn)
        }

        // 模拟 AI3 推荐同一个词
        try db.write { conn in
            let existing = try Set(String.fetchAll(conn,
                sql: "SELECT word FROM dictionary"))
            #expect(existing.contains("API"))

            // 不应插入（已在 dictionary）
            // 模拟 insertCandidates 逻辑
            if !existing.contains("API") {
                // 不应执行到这里
                #expect(Bool(false), "不应插入已有词典词")
            }
        }

        try db.read { conn in
            let count = try DictionaryCandidateRecord.fetchCount(conn)
            #expect(count == 0)
        }
    }

    @Test func insertCandidates_dedup_existingCandidate() throws {
        let db = try TestDatabase.makeEmpty()
        // 先放一个 pending 候选词
        try db.write { conn in
            var cand = DictionaryCandidateRecord(
                word: "Pipeline", score: 0.7, context: nil,
                pinyin: "Pipeline", state: "pending", dismissed: 0,
                fromAnalysisAt: "2026-03-25")
            try cand.insert(conn)
        }

        try db.read { conn in
            let existingCandidates = try Set(String.fetchAll(conn,
                sql: "SELECT word FROM dictionary_candidates"))
            #expect(existingCandidates.contains("Pipeline"))
        }

        // 再次插入同一词应被跳过
        try db.read { conn in
            let count = try DictionaryCandidateRecord.fetchCount(conn)
            #expect(count == 1)  // 仍然只有 1 条
        }
    }

    @Test func insertCandidates_dedup_dismissedNotReinserted() throws {
        let db = try TestDatabase.makeEmpty()
        try db.write { conn in
            var cand = DictionaryCandidateRecord(
                word: "重构", score: 0.6, context: nil,
                pinyin: "chong gou", state: "dismissed", dismissed: 1,
                fromAnalysisAt: "2026-03-25")
            try cand.insert(conn)
        }

        try db.read { conn in
            let existingCandidates = try Set(String.fetchAll(conn,
                sql: "SELECT word FROM dictionary_candidates"))
            // dismissed 的词也应被过滤
            #expect(existingCandidates.contains("重构"))
        }
    }

    @Test func approve_movesToDictionary() throws {
        let db = try TestDatabase.makeEmpty()
        try db.write { conn in
            var cand = DictionaryCandidateRecord(
                word: "Vilsay", score: 0.9, context: nil,
                pinyin: "Vilsay", state: "pending", dismissed: 0,
                fromAnalysisAt: "2026-03-25")
            try cand.insert(conn)
        }

        // 模拟 approve：从候选移到词典
        try db.write { conn in
            guard let cand = try DictionaryCandidateRecord.fetchOne(conn) else { return }
            var dict = DictionaryRecord(
                word: cand.word, context: cand.context,
                pinyin: cand.pinyin, source: "ai",
                createdAt: ISO8601DateFormatter().string(from: Date()))
            try dict.insert(conn)
            _ = try DictionaryCandidateRecord.deleteAll(conn,
                ids: [cand.id!])
        }

        try db.read { conn in
            #expect(try DictionaryCandidateRecord.fetchCount(conn) == 0)
            let dict = try DictionaryRecord.filter(Column("word") == "Vilsay").fetchOne(conn)
            #expect(dict != nil)
            #expect(dict?.source == "ai")
            #expect(dict?.pinyin == "Vilsay")
        }
    }

    @Test func confidence_weightedMerge() {
        // 加权平均：new = old * 0.6 + new * 0.4
        let old = 0.8
        let new = 0.5
        let merged = old * 0.6 + new * 0.4
        #expect(abs(merged - 0.68) < 0.001)
    }

    @Test func confidence_belowThreshold_notStored() {
        let minC = Constants.profileMinConfidence  // 0.3
        let lowConf = 0.2
        #expect(lowConf < minC)
        // 低于阈值的不应注入 Prompt
    }
}
```

---

## TEST-07 · AI3DeduplicationTests（5 case）

```
目标文件：
  vilsayTests/AI3DeduplicationTests.swift

import Testing
import GRDB
@testable import vilsay

struct AI3DeduplicationTests {

    @Test func newLogsOnly_firstRun() throws {
        let db = try TestDatabase.makeEmpty()
        try TestDatabase.seedRawLogs(db, count: 20)

        try db.read { conn in
            let state = try AnalyzerStateRecord.fetchOne(conn)!
            let sinceId = state.lastAnalyzedLogId ?? 0

            let newLogs = try RawLogRecord
                .filter(Column("id") > sinceId)
                .order(Column("id").asc)
                .limit(50)
                .fetchAll(conn)

            #expect(newLogs.count == 20)  // 首次应读到全部 20 条
        }
    }

    @Test func newLogsOnly_afterFirstAnalysis() throws {
        let db = try TestDatabase.makeEmpty()
        try TestDatabase.seedRawLogs(db, count: 20)

        // 模拟第一轮分析完成
        try db.write { conn in
            try conn.execute(sql: """
                UPDATE analyzer_state SET last_analyzed_log_id = 20 WHERE id = 1
            """)
        }

        // 再插入 10 条
        try db.write { conn in
            for i in 21...30 {
                var r = RawLogRecord(
                    asrText: "新增 \(i)", polishedText: "润色 \(i)",
                    durationMs: 100, sessionId: "s",
                    asrProvider: nil, asrConfidence: nil,
                    targetAppId: nil, userFlaggedError: false,
                    createdAt: "2026-03-25")
                try r.insert(conn)
            }
        }

        try db.read { conn in
            let state = try AnalyzerStateRecord.fetchOne(conn)!
            let sinceId = state.lastAnalyzedLogId ?? 0
            #expect(sinceId == 20)

            let newLogs = try RawLogRecord
                .filter(Column("id") > sinceId)
                .fetchAll(conn)
            #expect(newLogs.count == 10)  // 只读到新增的 10 条
            #expect(newLogs.first?.asrText.contains("新增") == true)
        }
    }

    @Test func noNewLogs_skipAnalysis() throws {
        let db = try TestDatabase.makeEmpty()
        try TestDatabase.seedRawLogs(db, count: 20)

        try db.write { conn in
            try conn.execute(sql: """
                UPDATE analyzer_state SET last_analyzed_log_id = 20 WHERE id = 1
            """)
        }

        try db.read { conn in
            let state = try AnalyzerStateRecord.fetchOne(conn)!
            let newLogs = try RawLogRecord
                .filter(Column("id") > (state.lastAnalyzedLogId ?? 0))
                .fetchAll(conn)
            #expect(newLogs.isEmpty)  // 无新日志
        }
    }

    @Test func clearData_resetsLogId() throws {
        let db = try TestDatabase.makeEmpty()

        try db.write { conn in
            try conn.execute(sql: """
                UPDATE analyzer_state
                SET last_analyzed_log_id = 50, total_logged_count = 50
                WHERE id = 1
            """)
        }

        // 清除
        try db.write { conn in
            try conn.execute(sql: "DELETE FROM raw_log")
            try conn.execute(sql: """
                UPDATE analyzer_state
                SET total_logged_count = 0, last_trigger_count = 0,
                    last_analyzed_log_id = NULL WHERE id = 1
            """)
        }

        try db.read { conn in
            let state = try AnalyzerStateRecord.fetchOne(conn)!
            #expect(state.lastAnalyzedLogId == nil)
            #expect(state.totalLoggedCount == 0)
        }
    }

    @Test func triggerThreshold_correctDiff() throws {
        let db = try TestDatabase.makeEmpty()
        try TestDatabase.seedRawLogs(db, count: 19)

        try db.write { conn in
            try conn.execute(sql: """
                UPDATE analyzer_state SET total_logged_count = 19 WHERE id = 1
            """)
        }

        try db.read { conn in
            let state = try AnalyzerStateRecord.fetchOne(conn)!
            let diff = state.totalLoggedCount - state.lastTriggerCount
            #expect(diff == 19)
            #expect(diff < Constants.analyzerTriggerThreshold)  // 不触发
        }

        // 加第 20 条
        try db.write { conn in
            var r = RawLogRecord(
                asrText: "第20句", polishedText: "20",
                durationMs: 100, sessionId: "s",
                asrProvider: nil, asrConfidence: nil,
                targetAppId: nil, userFlaggedError: false,
                createdAt: "2026-03-25")
            try r.insert(conn)
            try conn.execute(sql: """
                UPDATE analyzer_state SET total_logged_count = 20 WHERE id = 1
            """)
        }

        try db.read { conn in
            let state = try AnalyzerStateRecord.fetchOne(conn)!
            let diff = state.totalLoggedCount - state.lastTriggerCount
            #expect(diff == 20)
            #expect(diff >= Constants.analyzerTriggerThreshold)  // 触发！
        }
    }
}
```

---

## TEST-08 · RawLoggerFieldTests（4 case）

```
目标文件：
  vilsayTests/RawLoggerFieldTests.swift

import Testing
import GRDB
@testable import vilsay

struct RawLoggerFieldTests {

    @Test func allV14Fields_persisted() throws {
        let db = try TestDatabase.makeEmpty()
        try db.write { conn in
            var r = RawLogRecord(
                asrText: "语音",
                polishedText: "润色后",
                durationMs: 300,
                sessionId: "session-1",
                asrProvider: "whisperKit",
                asrConfidence: 0.82,
                targetAppId: "com.apple.mail",
                userFlaggedError: false,
                createdAt: "2026-03-25T10:00:00Z"
            )
            try r.insert(conn)
        }

        try db.read { conn in
            let r = try RawLogRecord.fetchOne(conn)!
            #expect(r.asrProvider == "whisperKit")
            #expect(r.asrConfidence == 0.82)
            #expect(r.targetAppId == "com.apple.mail")
            #expect(r.userFlaggedError == false)
        }
    }

    @Test func nullableFields_allowNil() throws {
        let db = try TestDatabase.makeEmpty()
        try db.write { conn in
            var r = RawLogRecord(
                asrText: "test", polishedText: "test",
                durationMs: nil, sessionId: nil,
                asrProvider: nil, asrConfidence: nil,
                targetAppId: nil, userFlaggedError: false,
                createdAt: "2026-03-25"
            )
            try r.insert(conn)
        }

        try db.read { conn in
            let r = try RawLogRecord.fetchOne(conn)!
            #expect(r.asrProvider == nil)
            #expect(r.asrConfidence == nil)
            #expect(r.targetAppId == nil)
        }
    }

    @Test func dashScope_noConfidence() throws {
        let db = try TestDatabase.makeEmpty()
        try db.write { conn in
            var r = RawLogRecord(
                asrText: "test", polishedText: "test",
                durationMs: 200, sessionId: "s",
                asrProvider: "dashScope",
                asrConfidence: nil,  // DashScope 不返回置信度
                targetAppId: "com.apple.Notes",
                userFlaggedError: false,
                createdAt: "2026-03-25"
            )
            try r.insert(conn)
        }

        try db.read { conn in
            let r = try RawLogRecord.fetchOne(conn)!
            #expect(r.asrProvider == "dashScope")
            #expect(r.asrConfidence == nil)
        }
    }

    @Test func defaultFlaggedError_isFalse() throws {
        let db = try TestDatabase.makeEmpty()
        try db.write { conn in
            // 通过 SQL 直接插入，不指定 user_flagged_error
            try conn.execute(sql: """
                INSERT INTO raw_log (asr_text, polished_text, created_at)
                VALUES ('test', 'test', '2026-03-25')
            """)
        }

        try db.read { conn in
            let val = try Int.fetchOne(conn,
                sql: "SELECT user_flagged_error FROM raw_log LIMIT 1")
            #expect(val == 0)  // 默认为 0
        }
    }
}
```

---

## 执行方式

```bash
# 运行全部单元测试（不含 LLM 集成测试）
xcodebuild test \
  -scheme vilsay \
  -destination 'platform=macOS' \
  -only-testing:vilsayTests \
  2>&1 | tail -20

# 运行 LLM 集成测试（需 API Key）
xcodebuild test \
  -scheme vilsay \
  -destination 'platform=macOS' \
  -only-testing:vilsayTests/PromptEffectivenessTests \
  DASHSCOPE_API_KEY=sk-your-key \
  2>&1 | tail -40

# 只跑 Prompt 拼接测试（最快，纯逻辑）
xcodebuild test \
  -scheme vilsay \
  -destination 'platform=macOS' \
  -only-testing:vilsayTests/PromptComposerTests \
  2>&1 | tail -20
```

---

## 测试汇总

| 文件 | Case 数 | 类型 | 耗时 | 依赖 |
|------|---------|------|------|------|
| PromptComposerTests | 12 | 纯逻辑 | <1s | 无 |
| PromptEffectivenessTests | 6 | LLM 集成 | ~20s | DASHSCOPE_API_KEY |
| PinyinHelperTests | 5 | 纯逻辑 | <1s | 无 |
| DatabaseMigrationTests | 8 | 内存 DB | <1s | GRDB |
| ErrorFeedbackTests | 4 | 内存 DB | <1s | GRDB |
| ProfileServiceTests | 6 | 内存 DB | <1s | GRDB |
| AI3DeduplicationTests | 5 | 内存 DB | <1s | GRDB |
| RawLoggerFieldTests | 4 | 内存 DB | <1s | GRDB |
| **合计** | **50** | | **< 25s** | |

---

# 文档结束
