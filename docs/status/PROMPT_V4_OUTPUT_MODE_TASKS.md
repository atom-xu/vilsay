# Prompt V4 · OutputMode 驱动的闭环处理架构 · Cursor 开发计划书

> 版本：2.0 | 2026-03-26
> 核心变化：在 V3 基础上**增量追加** OutputMode 层——现有代码一行不删，新功能只加不改
> 产品定位：核心竞争力在 **1-3 分钟长文本的结构化整理**，短文本纠错是基础能力

---

## ⚠️ 增量原则（所有任务必须遵守）

```
1. 现有 Prompts.swift 中的 section0、section2 原文保留，不修改、不删除
2. 现有 PromptComposer.swift 中的 appContextMap 保留，不删除
3. 现有 systemPrompt(for:) 无参签名保留，行为不变
4. OutputMode.general 的 §0/§A/§2 输出 = V3 现有完整输出，一字不改
5. 所有新增方法使用新签名（带 OutputMode 参数），不覆盖旧方法
6. 新增文件放在对应目录，不重命名/移动现有文件
```

**验证方式**：升级完成后，不传 OutputMode 的调用路径必须产生与升级前完全相同的 Prompt 输出。

---

## 一、设计概要

在 V3 五层 Prompt（§0 + §A + §C + §1 + §2）基础上，新增 **OutputMode 路由层**：

```
V3（保留，作为 .general 默认路径）：
  §0 固定身份 → §A appContextMap 一句话提示 → §C → §1 → §2 固定 P1-P5

V4（新增，当 OutputMode ≠ .general 时激活）：
  §0 模式身份 → §A 模式规则集 → §C → §1 → §2 P1-P5 + 模式专属 P6-P10
```

**关键**：V3 路径完整保留。V4 只在 OutputMode 非 `.general` 时才走新路径。

---

## 二、OutputMode 定义

```swift
/// 输出模式：由目标应用决定。.general 即 V3 原有行为。
enum OutputMode: String, Codable {
    case aiCommand   // AI 对话工具：Claude, ChatGPT, Cursor
    case chat        // 即时通讯：微信, iMessage, QQ, Slack
    case email       // 邮件：Mail, Outlook, Foxmail
    case document    // 文档：Word, Pages, Notion
    case note        // 笔记：Notes, Bear, Obsidian
    case general     // 未识别 app / V3 默认行为（不改变任何现有逻辑）
}
```

---

## 三、Cursor 任务清单（11 任务）

### PM-01 · 新建 OutputMode 枚举 + Resolver

**新建文件**：`Config/OutputMode.swift`

```swift
enum OutputMode: String, Codable {
    case aiCommand, chat, email, document, note, general
}

enum OutputModeResolver {
    private static let modeMap: [String: OutputMode] = [
        // AI 对话
        "com.anthropic.claudefordesktop": .aiCommand,
        "com.openai.chat":               .aiCommand,
        "com.cursor.ide":                .aiCommand,
        "dev.continue.continue":         .aiCommand,
        // 聊天
        "com.tencent.xinWeChat":  .chat,
        "com.apple.MobileSMS":    .chat,
        "com.tencent.qq":         .chat,
        "com.slack.Slack":        .chat,
        "com.electron.lark":      .chat,
        "com.alibaba.DingTalkMac": .chat,
        "ru.keepcoder.Telegram":  .chat,
        // 邮件
        "com.apple.mail":         .email,
        "com.tencent.foxmail":    .email,
        "com.microsoft.Outlook":  .email,
        // 文档
        "com.microsoft.Word":     .document,
        "com.apple.Pages":        .document,
        "com.notion.id":          .document,
        "md.obsidian":            .document,
        // 笔记
        "com.apple.Notes":        .note,
        "net.shinyfrog.bear":     .note,
    ]

    static func resolve(bundleID: String?) -> OutputMode {
        guard let id = bundleID else { return .general }
        return modeMap[id] ?? .general
    }
}
```

**注意**：这是纯新增文件，不修改任何现有文件。

**验收**：
- [ ] 6 种模式全部可识别
- [ ] 未匹配 bundleID 返回 `.general`
- [ ] 单元测试覆盖所有已知 bundleID

---

### PM-02 · Prompts.swift：新增 `personaCore(for:)` 方法

**修改文件**：`Config/Prompts.swift`

**增量规则**：
- **保留** `private static let section0 = ...` 原文不动
- **保留** `static var personaCore: String { section0 }` 不动
- **新增** `static func personaCore(for mode: OutputMode) -> String` 方法

```swift
// ===== 以下为新增代码，不修改上方任何现有代码 =====

/// V4：按 OutputMode 返回 §0 身份定义。.general 返回 V3 原文。
static func personaCore(for mode: OutputMode) -> String {
    switch mode {
    case .general:
        return section0  // ← 直接复用 V3 原文，一字不改
    case .aiCommand:
        return """
        你是一位指令提取师。用户在向 AI 工具下达指令。
        任务：从口语中提取核心指令，编号输出，删除一切冗余。
        原则：精准 > 完整 > 简洁。不需要寒暄和过渡。
        """
    case .chat:
        return """
        你是一位语言整理师，处理 ASR 产生的原始文字。
        任务：最小干预——只修错别字和断句，保留口语风格和语气词。
        原则：自然 > 准确 > 简洁。用户在聊天，不要让输出像书面语。
        """
    case .email:
        return """
        你是一位语言整理师，处理 ASR 产生的原始文字。
        任务：将口语整理为正式邮件语体，适当分段，加过渡句。
        原则：得体 > 完整 > 简洁。保持专业但不过度正式。
        """
    case .document:
        return """
        你是一位结构化写作助手，处理 ASR 产生的原始文字。
        任务：理解说话人意图，将口语重组为结构化文本——分段、编号、逻辑排列。
        原则：结构 > 完整 > 准确。长文本必须分段，多论点必须编号。
        """
    case .note:
        return """
        你是一位笔记整理师，处理 ASR 产生的原始文字。
        任务：提炼要点，bullet 输出，去除冗余。
        原则：简洁 > 完整 > 结构。每条 bullet 一个要点。
        """
    }
}
```

**验收**：
- [ ] `Prompts.personaCore`（无参，V3）仍返回原文
- [ ] `Prompts.personaCore(for: .general)` 返回与无参版完全相同的字符串
- [ ] `Prompts.personaCore(for: .document)` 包含"结构化写作"
- [ ] 现有所有调用 `Prompts.personaCore` 的地方编译通过、行为不变

---

### PM-03 · Prompts.swift：新增 `modeRules(for:)` 方法

**修改文件**：`Config/Prompts.swift`

**增量规则**：纯新增方法，不修改任何现有代码。

```swift
/// V4：按 OutputMode 返回 §A 模式规则集。.general 不注入额外规则（由 appContextMap 兜底）。
static func modeRules(for mode: OutputMode) -> String? {
    switch mode {
    case .general:
        return nil  // ← .general 不注入模式规则，保持 V3 行为（appContextMap 仍生效）
    case .aiCommand:
        return """
        【输出模式：AI 指令】
        R1 删除所有口语连接词（"然后"、"就是说"、"那个"、"对吧"）
        R2 提取核心指令，编号输出（1. 2. 3. 或 a. b. c.）
        R3 多个独立要求用换行分隔，不要合并成一段
        R4 技术术语保持原样，不做同义替换
        R5 不需要开头寒暄（"你好"、"帮我"）和结尾总结
        R6 如果用户在描述需求而非下指令，提炼为要求列表
        """
    case .chat:
        return """
        【输出模式：聊天】
        R1 保留口语化表达和语气词（"哈哈"、"嗯"、"对对对"）
        R2 不要结构化，保持自然对话语感
        R3 只做最小必要的纠错（错别字、明显断句错误）
        R4 不要把短句合并成长句
        R5 不要添加书面化的过渡词
        R6 保留表达情绪和态度的词语
        """
    case .email:
        return """
        【输出模式：邮件】
        R1 开头加适当称呼（如果原文有暗示收件人）
        R2 口语连接词替换为正式过渡（"然后"→"此外"、"就是说"→"具体而言"）
        R3 超过 3 个要点时使用编号
        R4 结尾加适当收束（如果原文有结束意图）
        R5 语气正式但不生硬，不要使用"鄙人"、"敬启"等过度正式用语
        R6 段落之间用空行分隔
        """
    case .document:
        return """
        【输出模式：文档】
        R1 识别多个论点或主题，每个论点独立分段
        R2 每段开头用一句话概括该段核心主张
        R3 可使用 Markdown 格式：## 标题、- bullet、1. 编号
        R4 按论述逻辑重排段落顺序（而非说话时间顺序）
        R5 去除重复论述——同一观点说了多次只保留最完整的一次
        R6 口语连接词替换为书面逻辑连接（"然后"→"其次"、"反正就是"→删除）
        R7 超过 500 字的输出必须分段，每段不超过 200 字
        """
    case .note:
        return """
        【输出模式：笔记】
        R1 提炼要点，每条用 - 开头
        R2 每条 bullet 一个要点，不超过 30 字
        R3 删除所有冗余和重复
        R4 保留关键数据和结论，删除论证过程
        R5 如果有明确的行动项，用 TODO: 标记
        """
    }
}
```

**验收**：
- [ ] `.general` 返回 `nil`（不注入，保持 V3 原有 appContextMap 行为）
- [ ] `.aiCommand` 包含"删除连接词"、"编号输出"
- [ ] `.chat` 包含"保留语气词"、"不要结构化"
- [ ] 现有代码编译不受影响

---

### PM-04 · Prompts.swift：新增 `processingRules(for:)` 方法

**修改文件**：`Config/Prompts.swift`

**增量规则**：
- **保留** `private static let section2 = ...` 原文不动（P1-P5）
- **保留** `static var processingEngine: String { section2 }` 不动
- **新增** `static func processingRules(for mode: OutputMode) -> String` 方法

```swift
/// V4：§2 处理规则 = 通用层 P1-P5（V3 原文） + 模式专属层 P6-P10。
/// .general 只返回 P1-P5（= V3 原文）。
static func processingRules(for mode: OutputMode) -> String {
    var rules = section2  // ← 始终以 V3 原文 P1-P5 为基础

    // 按模式追加专属规则
    switch mode {
    case .general:
        break  // 不追加，保持 V3 原样
    case .document:
        rules += """
        \nP6 结构化重组：识别多个论点并分段，可用编号或 bullet
        P7 逻辑排列：按论述逻辑重排，而非说话时间顺序，去除重复论述
        P8 要点提炼：每段开头用一句话概括核心主张
        """
    case .note:
        rules += """
        \nP6 结构化重组：提炼要点为 bullet 列表
        P8 要点提炼：每条 bullet 一个核心要点
        """
    case .email:
        rules += """
        \nP7 逻辑排列：按论述逻辑重排段落
        P9 语气转换：口语 → 书面正式语体，保留得体度
        """
    case .aiCommand:
        rules += """
        \nP6 结构化重组：提取指令编号输出
        P10 指令提取：从口语描述中提取可执行指令
        """
    case .chat:
        break  // 聊天模式不追加结构化规则，只用 P1-P5 纠错
    }

    return rules
}
```

**验收**：
- [ ] `Prompts.processingEngine`（无参，V3）仍返回 P1-P5 原文
- [ ] `Prompts.processingRules(for: .general)` 返回与 `processingEngine` 完全相同的字符串
- [ ] `Prompts.processingRules(for: .document)` 包含 P1-P5 + P6 + P7 + P8
- [ ] 现有调用 `Prompts.processingEngine` 的地方编译通过、行为不变

---

### PM-05 · PromptComposer：新增 V4 路径，保留 V3 路径

**修改文件**：`Core/PromptComposer.swift`

**增量规则**：
- **保留** 现有 `systemPrompt(for:targetAppBundleID:asrConfidence:)` 方法体
- **保留** `appContextMap` 字典不删除
- 在现有方法内部，增加 OutputMode 分支：**仅当 mode ≠ .general 时**走 V4 路径

```swift
/// V3→V4 升级：在现有方法内增加 mode 路由。
static func systemPrompt(
    for profile: UserProfile?,
    targetAppBundleID: String? = nil,
    asrConfidence: Double? = nil
) -> String {
    let mode = OutputModeResolver.resolve(bundleID: targetAppBundleID)

    // ===== V4 路径：mode ≠ .general 时使用模式专属 Prompt =====
    if mode != .general {
        var sections: [String] = []
        sections.append(Prompts.personaCore(for: mode))           // §0 模式身份

        if let rules = Prompts.modeRules(for: mode) {             // §A 模式规则集
            sections.append(rules)
        }

        // §C 低置信度提示（复用现有逻辑，不改）
        if let conf = asrConfidence,
           conf < Constants.asrLowConfidenceThreshold {
            let pct = Int(conf * 100)
            sections.append(
                "【识别质量提示】本次语音识别置信度较低（\(pct)%），" +
                    "请特别注意同音字纠偏，对不通顺的词组优先尝试同音替换。"
            )
        }

        // §1 用户画像（复用现有 profile 拼接逻辑，不改）
        if let p = profile, !p.isEmpty {
            // ... 与下方 V3 路径中 §1 拼接逻辑完全相同 ...
            // （建议提取为 private 方法复用，但不修改原有输出）
        }

        sections.append(Prompts.processingRules(for: mode))       // §2 通用+模式专属
        return sections.joined(separator: "\n\n---\n\n")
    }

    // ===== V3 路径：.general，以下为现有代码，一字不改 =====
    var sections: [String] = []
    sections.append(Prompts.personaCore)
    // ... 现有全部代码原样保留 ...
}
```

**重构建议**：§1（profile 拼接）和 §C（低置信度）的逻辑在两条路径中相同，建议提取为 `private static func buildProfileSection(...)` 和 `private static func buildConfidenceHint(...)`，但**输出内容不变**。

**验收**：
- [ ] 未知 bundleID → `.general` → 输出与升级前**逐字相同**
- [ ] 微信 bundleID → V3 时走 appContextMap → V4 时走 `.chat` 模式规则（功能增强，不丢失）
- [ ] `systemPrompt(for: profile)` 无参调用 → `.general` → V3 行为不变
- [ ] **回归测试**：用 V3 的 PT_A~PT_H 测试跑一遍，全部 PASS

---

### PM-06 · Pipeline 传递 OutputMode

**修改文件**：`Core/Pipeline.swift`

**增量改动**（约 2 行）：

```swift
// 在调用 PromptComposer 之前，计算 mode（新增 1 行）
let outputMode = OutputModeResolver.resolve(
    bundleID: TargetAppMonitor.shared.capturedBundleIdentifier
)

// PromptComposer 调用不变（已有 targetAppBundleID 参数，内部会自动路由）
// 无需修改调用签名

// 在 RawLogger.logAsync 调用处，追加 outputMode 参数（新增 1 个参数）
RawLogger.logAsync(
    ...,  // 现有参数全部保留
    outputMode: outputMode.rawValue  // 新增
)
```

**验收**：
- [ ] 现有 Pipeline 流程不受影响
- [ ] `RawLogger.logAsync` 正确接收 `outputMode`

---

### PM-07 · raw_log 新增 output_mode 字段

**修改文件**：`DB/Schema.swift` + `DB/Migrations.swift`

**增量改动**：
- `RawLogRecord` 新增 `outputMode: String` 属性（默认值 `"general"`）
- 新增 Migration：`ALTER TABLE raw_log ADD COLUMN output_mode TEXT NOT NULL DEFAULT 'general'`

**注意**：现有字段全部保留，旧数据自动获得 `"general"` 默认值。

**验收**：
- [ ] 旧数据 output_mode = "general"
- [ ] 新记录正确存储 mode
- [ ] 现有 RawLogRecord 的读写不受影响

---

### PM-08 · AI3Analyzer 按 OutputMode 分组分析

**修改文件**：`AI3/AI3Analyzer.swift`

**增量规则**：
- **保留**现有的全量分析逻辑作为全局 profile 生成（`__global__`）
- **新增**按 `output_mode` 分组的分析路径

```swift
// 现有逻辑保留：生成全局 profile（V3 行为不变）
let allLogs = try RawLogRecord.filter(Column("id") > lastId).fetchAll(db)
let globalProfile = try await analyzeGroup(allLogs)  // 现有逻辑
saveProfile(globalProfile, mode: "__global__")

// ===== 新增：按 output_mode 分组，生成 per-mode profile =====
let grouped = Dictionary(grouping: allLogs) { $0.outputMode }
for (modeRaw, logs) in grouped where modeRaw != "general" {
    guard logs.count >= 5 else { continue }  // 数据不足时不生成 per-mode profile
    let modeProfile = try await analyzeGroup(logs)
    saveProfile(modeProfile, mode: modeRaw)
}
```

**验收**：
- [ ] 全局 profile 仍然正常生成（V3 行为不变）
- [ ] per-mode profile 仅在该 mode 数据 ≥ 5 条时才生成
- [ ] chat 组的分析不影响 document 组

---

### PM-09 · user_profile 支持 per-mode 存储

**修改文件**：`DB/Schema.swift` + `Config/UserProfile.swift`

**增量改动**：
- `user_profile` 表新增 `output_mode TEXT NOT NULL DEFAULT '__global__'`
- 查询逻辑：**优先** per-mode profile → **fallback** 到 `__global__` → **fallback** 到空 profile

```swift
/// 查询 profile：per-mode 优先，全局兜底。
static func loadProfile(for mode: OutputMode) -> UserProfile? {
    // 1. 先查 per-mode
    if mode != .general,
       let modeProfile = try? fetchProfile(outputMode: mode.rawValue) {
        return modeProfile
    }
    // 2. fallback 到全局（= V3 现有行为）
    return try? fetchProfile(outputMode: "__global__")
}
```

**验收**：
- [ ] 无 per-mode profile 时返回全局 profile（V3 行为不变）
- [ ] 有 per-mode profile 时优先使用
- [ ] 现有 `UserProfile` 读写不受影响

---

### PM-10 · 100 测试补充长文本 + 多模式用例

**新建文件**：`vilsayTests/PromptTuning/PT_I_LongTextStructure.swift`、`PT_J_ModeSwitching.swift`

**增量规则**：现有 PT_A~PT_H 不修改，新增 PT_I + PT_J。

**PT_I（10 题）：长文本结构化**
- I-01：500 字口语 → document 模式 → 验证输出有分段
- I-02：500 字口语 → chat 模式 → 验证输出**无**结构化（保持口语）
- I-03：1000 字多论点 → document 模式 → 验证编号/bullet
- I-04：300 字 → note 模式 → 验证 bullet 输出
- I-05：给 AI 下指令 300 字 → aiCommand 模式 → 验证编号、无连接词
- I-06：邮件场景 200 字 → email 模式 → 验证正式语体
- I-07：相同 500 字输入 → 分别用 6 种模式 → 输出风格明显不同
- I-08：长文本有重复论述 → document 模式 → 验证去重
- I-09：长文本有逻辑跳跃 → document 模式 → 验证逻辑重排
- I-10：极长 1500 字 → document 模式 → 验证强制分段

**PT_J（5 题）：模式切换 + V3 回归**
- J-01：同一用户 chat → email 切换 → 风格正确切换
- J-02：未知 bundleID → `.general` → 短文本最小干预（**= V3 行为**）
- J-03：未知 bundleID → `.general` → 长文本行为（**= V3 行为**）
- J-04：aiCommand 模式 → 输出不含口语连接词
- J-05：chat 模式 → 输出保留口语连接词

**验收**：
- [ ] PT_I + PT_J 共 15 题全部 PASS
- [ ] **PT_A~PT_H 原有 100 题仍全部 PASS**（回归验证）
- [ ] 每题记录 latency_ms

---

### PM-11 · OutputMode 设置页（可选，后置）

**修改文件**：`UI/SettingsRootView.swift`

**增量改动**：在现有设置页**末尾新增**一个 Section "应用输出模式"：
- 列出已识别的应用及其自动 OutputMode
- 用户可手动覆盖（如某 app 从 `.general` 改为 `.document`）
- 覆盖存入 UserDefaults，`OutputModeResolver` 增加 UserDefaults 优先查询

**验收**：
- [ ] 不改动设置页现有功能
- [ ] 新 Section 在现有 Section 之后
- [ ] 用户覆盖后立即生效

---

## 四、执行顺序

```
第一步：PM-01（新建 OutputMode.swift，纯新增，零风险）
         ↓
第二步：PM-02 + PM-03 + PM-04（Prompts.swift 新增 3 个方法，可并行，不改现有代码）
         ↓
第三步：PM-05（PromptComposer 加 V4 路径，V3 路径原样保留）
         ↓
  回归验证点 ✅：跑 PT_A~PT_H，必须全部 PASS（V3 未被破坏）
         ↓
第四步：PM-06 + PM-07（Pipeline + DB，可并行，追加字段和参数）
         ↓
第五步：PM-08 + PM-09（AI3 分组 + per-mode profile，可并行）
         ↓
第六步：PM-10（新增测试 PT_I + PT_J + 回归 PT_A~PT_H）
         ↓
第七步：PM-11（设置页，可后置到下个迭代）
```

**关键卡点**：第三步完成后必须做回归验证。如果 PT_A~PT_H 有任何 FAIL，说明 V3 路径被破坏，必须先修复再继续。

---

## 五、与现有文档/代码的关系

| 现有内容 | V4 升级后状态 |
|---------|-------------|
| `Prompts.section0`（V3 §0 原文） | **保留不动**，`.general` 直接引用 |
| `Prompts.section2`（V3 §2 P1-P5） | **保留不动**，所有模式共享 P1-P5 |
| `PromptComposer.appContextMap` | **保留不动**，`.general` 路径仍使用 |
| `systemPrompt(for:)` 无参签名 | **保留不动**，行为 = V3 |
| `raw_log` 现有字段 | **全部保留**，新增 `output_mode` 列 |
| `user_profile` 现有结构 | **全部保留**，新增 `output_mode` 列 |
| `ACCURACY_ENHANCEMENT_TASKS.md` | 互补，ACC-P0 上下文缓冲可加 mode 维度 |
| `PROMPT_TUNING_100_TESTS.md` PT_A~PT_H | **不修改**，作为 V3 回归测试 |
| `FIX_CORE_PIPELINE.md` FIX-P01~P06 | 前置依赖，先保证链路能跑 |

---

## 六、闭环数据流

```
① TargetAppMonitor.capturedBundleIdentifier（已有，不改）
     ↓
② OutputModeResolver.resolve() → OutputMode（新增）
     ↓
③ PromptComposer：
   mode == .general → V3 原有路径（§0 + appContextMap + §C + §1 + §2 P1-P5）
   mode != .general → V4 新路径（§0(mode) + modeRules + §C + §1 + §2 P1-P5+Px）
     ↓
④ AI2 处理 → 输出（不改）
     ↓
⑤ raw_log 记录 output_mode（新增字段）
     ↓
⑥ AI3 分组分析：全局 profile（V3 不变）+ per-mode profile（新增）
     ↓
⑦ 下次 ③ 时，per-mode profile 优先，fallback 全局
```
