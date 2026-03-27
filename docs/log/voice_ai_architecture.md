# 语音润色系统 · 三 AI 架构说明
# Voice Polish System · 3-AI Architecture
# 版本：1.1 | 日期：2026-03-22
# 适用产品：Vilsay macOS App（Swift 原生）
# ⚠️ 此文档为架构参考文档，具体实现以 VILSAY_TECH_ARCH.md 为准

---

## 一、三 AI 分工

```
用户说话
    ↓
[AI-1 · ASR 转写]
阿里云 DashScope 流式（主）
WhisperKit 本地（断网降级）
    ↓ 原始文字流
[VAD 断句缓冲 · 800ms]
    ↓ 完整句子
[AI-2 · 润色层]
Qwen 流式润色
System Prompt = §0§2 固定层 + §1 动态层
    ↓ 润色后文字
注入光标位置
    ↓ 异步，不阻塞
[AI-3 · Analyzer · 后台]
分析原始语料，生成用户画像
写入本地 SQLite，注入 §1 区
```

**职责边界（硬性规定）：**
```
AI-1：只管声音变文字，不做任何文字处理
AI-2：只管文字润色，不管数据存储
AI-3：只在后台分析，永远不阻塞 AI-1 和 AI-2
```

---

## 二、AI-3 Analyzer 详细设计

### 2.1 功能定位

| 项目 | 说明 |
|------|------|
| 角色 | 后台观察者，不参与实时对话 |
| 输入 | 原始 ASR 文本（只看原始，不看润色结果）|
| 输出 | 写入本地 SQLite user_profile 表 |
| 触发条件 | raw_log 累积满20条 |
| 运行方式 | Swift async Task，不阻塞主链路 |
| 对比机制 | 每次与上一版 Profile 差异对比，只更新变化字段 |

### 2.2 数据记录结构

每次对话结束后写入 raw_log 表：

```swift
// DB/Schema.swift
struct RawLog: Codable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var rawText: String        // ASR 原始输出（唯一分析来源）
    var polishedText: String   // AI-2 润色结果（仅记录，AI-3 不分析）
    var sceneDetected: String?
    var createdAt: Date
    var analyzed: Bool = false
}
```

**重要约束：AI-3 只读 rawText，永远不读 polishedText。**
原因：防止 LLM 风格污染用户的真实表达习惯。

### 2.3 触发与运行逻辑

```swift
// AI3/AnalyzerTrigger.swift

class AnalyzerTrigger {

    static let threshold = 20  // 对应 Constants.analyzerTriggerThreshold

    func checkAndRun() {
        guard let state = try? db.read({ try AnalyzerState.fetchOne($0) }) else { return }

        let newSessions = state.sessionCount - state.lastAnalyzedSession
        guard newSessions >= Self.threshold else { return }

        // 异步运行，不阻塞调用方
        Task.detached(priority: .background) {
            await AI3Analyzer.shared.run()
        }
    }
}
```

```swift
// AI3/AI3Analyzer.swift

actor AI3Analyzer {
    static let shared = AI3Analyzer()

    func run() async {
        do {
            // 1. 读取最近50条原始记录
            let recentLogs = try db.read { db in
                try RawLog
                    .order(Column("created_at").desc)
                    .limit(50)
                    .fetchAll(db)
            }

            // 2. 读取当前 Profile（用于差异对比）
            let currentProfile = ProfileService.shared.get()

            // 3. 调用 Qwen 分析
            let newProfile = try await callQwenAnalyzer(
                logs: recentLogs,
                currentProfile: currentProfile
            )

            // 4. 差异对比，只更新变化字段
            let mergedProfile = merge(current: currentProfile, new: newProfile)

            // 5. 写回 SQLite
            ProfileService.shared.update(mergedProfile)

            // 6. 推荐词写入候选表
            extractAndSaveCandidates(from: newProfile)

            // 7. 更新触发状态
            updateAnalyzerState()

        } catch {
            // 静默失败，下次触发时重试
            Logger.ai3.error("AI3 分析失败: \(error)")
        }
    }
}
```

### 2.4 AI-3 的 System Prompt

```
你是一个语言行为分析师。

任务：分析用户的语音转文字原始记录，
提炼出这个人独特的说话方式，
用于指导另一个 AI 更准确地整理他的话。

输入材料：
1. 用户最近 N 次对话的原始 ASR 文本
2. 当前已有的风格档案（可能为空）

输出要求：
输出纯 JSON，不要任何解释文字。
每个字段包含 confidence 值（0-1）。
新发现的特征 confidence 初始值为 0.5。
与已有档案相比没有变化的字段原样保留。

输出结构：
{
  "habitual_words": [
    {
      "word": "这样子",
      "action": "keep",
      "confidence": 0.85,
      "frequency": 23
    }
  ],
  "thinking_style": {
    "opening_pattern": "先抛假设再举例",
    "topic_switch_signals": ["那么", "但是呢"],
    "closing_signals": ["你觉得呢", "是不是"],
    "confidence": 0.72
  },
  "tone_profile": {
    "directness": "direct",
    "formality": "mixed",
    "sentence_length": "short",
    "confidence": 0.80
  },
  "dictionary": [
    {
      "type": "project",
      "word": "Agency Web",
      "note": "用户的项目名，勿拆分",
      "confidence": 0.95
    }
  ],
  "analysis_meta": {
    "sessions_analyzed": 20,
    "compared_with_version": "2026-03-20T10:00:00Z",
    "changed_fields": ["habitual_words", "dictionary"],
    "unchanged_fields": ["tone_profile"]
  }
}
```

### 2.5 Profile 进化机制

```
每次 AI-3 运行后执行差异对比：

新出现的特征   → confidence 0.5 加入
持续存在的特征 → confidence +0.05（上限 0.95）
消失的特征     → confidence -0.10，低于 0.3 时自动移除
矛盾的特征     → 两者保留，等待更多数据
```

---

## 三、Prompt 动态注入机制

```swift
// Core/PromptComposer.swift

class PromptComposer {

    func compose(profile: UserProfile?) -> String {
        var prompt = fixedLayer()  // §0 + §2 固定层

        if let profile = profile {
            prompt += buildDynamicLayer(profile)  // §1 动态层
        }
        // profile 为空时只用固定层，行为和没有 AI3 一样

        return prompt
    }

    private func buildDynamicLayer(_ profile: UserProfile) -> String {
        var section = "\n## §1 用户专属区\n"

        // §1.1 口头禅
        if !profile.habitualWords.isEmpty {
            section += "\n### §1.1 口头禅与保留词\n"
            for word in profile.habitualWords where word.confidence >= 0.5 {
                section += "\(word.word) | \(word.action) | 置信度 \(word.confidence)\n"
            }
        }

        // §1.2 思维结构
        if profile.thinkingStyle.confidence >= 0.5 {
            section += "\n### §1.2 思维结构\n"
            section += "展开方式：\(profile.thinkingStyle.openingPattern)\n"
        }

        // §1.3 语气
        if profile.toneProfile.confidence >= 0.5 {
            section += "\n### §1.3 语气风格\n"
            section += "整体语气：\(profile.toneProfile.directness)\n"
        }

        // §1.4 词典
        if !profile.dictionary.isEmpty {
            section += "\n### §1.4 高频词典\n"
            for item in profile.dictionary where item.confidence >= 0.5 {
                section += "\(item.type) | \(item.word) | \(item.note)\n"
            }
        }

        return section
    }
}
```

---

## 四、关键约束（不可违反）

```
1. AI-3 永远不阻塞 AI-2
   Analyzer 在 background Task 运行，失败静默忽略

2. AI-3 只读原始 ASR，不读润色输出
   rawText 是唯一分析来源

3. §1 区为空时系统必须正常工作
   PromptComposer 无 profile 时只输出固定层

4. Profile 只做增量更新，不整体替换
   差异对比后只更新变化字段

5. raw_log 只追加，不修改，不删除
   这是最宝贵的原始语料资产

6. AI-3 的 Qwen 调用用开发者 Key
   不用用户的 Key，用户不可见不可配置
```

---

## 五、与其他文档的关系

```
本文档（voice_ai_architecture.md）
  ↓ 是以下文档的逻辑来源
VILSAY_TECH_ARCH.md · 第五章 AI3 暗线架构
VILSAY_DEV_TASKS.md · Week 5 任务
voice_polish_prompt.md · §1 动态注入区设计

以 VILSAY_TECH_ARCH.md 为实现权威，
本文档是设计推导过程，两者冲突时以 TECH_ARCH 为准。
```

---

## 六、未来扩展方向（现在不做）

```
- AI-3 偏差检测：发现 AI-2 系统性改动倾向，自动补规则
- Profile 版本历史：保留最近5个版本，支持回滚
- 触发频次自适应：活跃用户缩短间隔，低频用户延长
- 用户可查看 Profile：设置页展示学习到的内容（不暴露 AI3 名称）
```

---
# END
# 版本：1.1 | 修改内容：
# - 存储层从黑板改为本地 SQLite
# - 表名统一为 raw_log
# - 伪代码改为 Swift
# - 开发顺序对齐 VILSAY_DEV_TASKS Week 5
# - 新增 PromptComposer 完整实现
