# 准确率增强架构 · Cursor 任务书

> 版本：1.0 | 2026-03-26
> 目标：在现有 V3 五层 Prompt 基础上，通过上下文缓冲 + 错误映射 + AI3 分应用分析三层提升润色准确率
> 约束：**延迟增量 ≤ 50ms**（P95），**应用间上下文严格隔离**

---

## 设计原则

1. **延迟可控**：上下文注入 token 预算硬限 200 tokens，超出截断最早条目
2. **应用隔离**：`TargetAppMonitor.capturedBundleIdentifier` 已存入 `raw_log.target_app_id`，所有上下文按 bundleID 分桶
3. **渐进增强**：P0 → P1 → P2 分阶段交付，每阶段独立可测试

---

## 现有基础设施

| 组件 | 状态 | 说明 |
|------|------|------|
| `raw_log.target_app_id` | ✅ 已有 | 每条记录存目标 app bundleID |
| `PromptComposer` §A | ✅ 已有 | 10 个硬编码 app 场景提示 |
| `TargetAppMonitor` | ✅ 已有 | 录音前捕获 bundleID |
| AI3 per-app 分析 | ❌ 缺失 | 当前混合所有 app 一起分析 |
| 上下文缓冲 | ❌ 缺失 | 无历史润色结果传递 |
| 错误映射表 | ❌ 缺失 | 无 ASR 错误→正确词映射 |

---

## ACC-P0 · Per-App 上下文缓冲（4 任务）

### ACC-P0-01 · RecentContextBuffer 数据结构

**文件**：`Core/RecentContextBuffer.swift`（新建）

```swift
/// 按目标应用维护最近润色结果，供 PromptComposer 注入上下文。
@MainActor
final class RecentContextBuffer {
    static let shared = RecentContextBuffer()

    /// 每个 app 最多保留条数
    private let maxPerApp = 3
    /// 注入 prompt 时的 token 硬限（按字符数估算，1 中文字 ≈ 2 tokens）
    private let maxTokenBudget = 200

    /// bundleID → [(polishedText, timestamp)]
    private var buffer: [String: [(text: String, date: Date)]] = [:]

    /// 录音结束后调用：存入当前 app 的润色结果
    func append(polishedText: String, forApp bundleID: String?) {
        guard let id = bundleID, !polishedText.isEmpty else { return }
        var list = buffer[id] ?? []
        list.append((text: polishedText, date: Date()))
        if list.count > maxPerApp { list.removeFirst() }
        buffer[id] = list
    }

    /// 取当前 app 的最近上下文（截断至 token 预算内）
    func recentContext(forApp bundleID: String?) -> String? {
        guard let id = bundleID, let list = buffer[id], !list.isEmpty else { return nil }
        var result = ""
        var estimatedTokens = 0
        for entry in list.reversed() {
            let entryTokens = entry.text.count  // 粗估：1字≈1token（中文偏保守）
            if estimatedTokens + entryTokens > maxTokenBudget { break }
            result = "- \(entry.text)\n" + result
            estimatedTokens += entryTokens
        }
        return result.isEmpty ? nil : result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 清除指定 app 的缓冲（可选）
    func clear(forApp bundleID: String?) {
        guard let id = bundleID else { return }
        buffer[id] = nil
    }
}
```

**验收**：
- [ ] 单元测试：append 3 条后 buffer 仅保留 3 条
- [ ] 单元测试：不同 bundleID 互不干扰
- [ ] 单元测试：超 token 预算时截断最早条目

---

### ACC-P0-02 · PromptComposer 注入 §A.ctx 上下文段

**文件**：`Core/PromptComposer.swift`

**改动**：在 §A（场景提示）之后追加 §A.ctx（最近上下文），格式：

```
§A.ctx 你在该应用中的近期润色结果（仅供参考，帮助你理解当前话题和用词偏好）：
- 第一条润色结果
- 第二条润色结果
```

**代码**：
```swift
// 在 buildSystemPrompt 中，§A 段之后追加：
if let ctx = RecentContextBuffer.shared.recentContext(forApp: targetAppBundleID) {
    sections.append("§A.ctx 你在该应用中的近期润色结果（仅供参考）：\n\(ctx)")
}
```

**验收**：
- [ ] 有上下文时 §A.ctx 出现在 system prompt 中
- [ ] 无上下文时不插入任何内容
- [ ] 不同 app 的上下文不混用

---

### ACC-P0-03 · Pipeline 写入上下文缓冲

**文件**：`Core/Pipeline.swift`

**改动**：在润色完成、注入粘贴板之后，调用：
```swift
RecentContextBuffer.shared.append(
    polishedText: polishedResult,
    forApp: TargetAppMonitor.shared.capturedBundleIdentifier
)
```

**位置**：在 `RawLogger.logAsync(...)` 调用附近（约 line 850）。

**验收**：
- [ ] 润色成功后 buffer 有值
- [ ] 润色失败（降级为原文）时不写入 buffer

---

### ACC-P0-04 · 延迟基准测试

**文件**：`vilsayTests/PromptTuning/PromptTuningHelper.swift`（修改）

**改动**：在现有 100 测试框架中加入计时断言和对比组。

```swift
/// 在 callPolishAPI 中记录延迟
let start = CFAbsoluteTimeGetCurrent()
// ... API 调用 ...
let latencyMs = (CFAbsoluteTimeGetCurrent() - start) * 1000

/// 断言
#expect(latencyMs < 800, "P95 延迟超过 800ms: \(latencyMs)ms")
```

新增对比测试组（加在 PT_F 组合测试中）：
- F-16：相同输入，无上下文 vs 有上下文（3 条历史），记录延迟差
- F-17：相同输入，200 token 上下文 vs 无上下文，延迟差 < 50ms

**验收**：
- [ ] 每个测试输出 `latency_ms`
- [ ] 有上下文 vs 无上下文延迟差 < 50ms（P95）
- [ ] 无测试因延迟超限 FAIL（800ms 硬限）

---

## ACC-P1 · ASR 错误映射 + AI3 Per-App 分析（5 任务）

### ACC-P1-01 · asr_error_map 数据表

**文件**：`DB/Schema.swift` + `DB/Migrations.swift`

新增 `asr_error_map` 表：

```sql
CREATE TABLE asr_error_map (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    asr_wrong TEXT NOT NULL,        -- ASR 错误词（如"百练"）
    correct_word TEXT NOT NULL,     -- 正确词（如"百炼"）
    source TEXT NOT NULL DEFAULT 'ai3',  -- 来源：ai3 / user_feedback
    hit_count INTEGER NOT NULL DEFAULT 1,
    confidence REAL NOT NULL DEFAULT 0.5,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE UNIQUE INDEX idx_error_map_pair ON asr_error_map(asr_wrong, correct_word);
```

**验收**：
- [ ] Migration v3 创建表成功
- [ ] GRDB Record 类型 `ASRErrorMapRecord` 可 CRUD
- [ ] 重复插入同对时 `hit_count += 1`（UPSERT）

---

### ACC-P1-02 · AI3Analyzer per-app 分组分析

**文件**：`AI3/AI3Analyzer.swift`

**改动**：
```swift
// 现有：读取所有新 raw_log
let newLogs = try RawLogRecord.filter(Column("id") > lastId).fetchAll(db)

// 改为：按 target_app_id 分组
let grouped = Dictionary(grouping: newLogs) { $0.targetAppId ?? "__global__" }
for (appId, logs) in grouped {
    let analysis = try await analyzeGroup(logs, appId: appId)
    // 存储 per-app profile 片段
}
```

**注意**：`ToneProfile` / `ThinkingStyle` 按 app 独立存储。全局 profile 仍保留作 fallback。

**验收**：
- [ ] 邮件 app 的 log 不影响聊天 app 的 profile
- [ ] 未识别 bundleID 的 log 归入 `__global__`
- [ ] 全局 profile 仍可作为 fallback

---

### ACC-P1-03 · AI3 纠偏分析：提取 ASR 错误模式

**文件**：`AI3/AI3Analyzer.swift`

**改动**：在现有 profile 分析 prompt 中追加指令段：

```
另外，请对比每条记录的 asr_text 和 polished_text，提取 ASR 反复出现的错误模式。
输出格式：
error_patterns: [
  {"wrong": "百练", "correct": "百炼", "count": 3},
  {"wrong": "哎斯二", "correct": "ASR", "count": 2}
]
```

解析 AI3 返回的 `error_patterns` 后写入 `asr_error_map` 表。

**验收**：
- [ ] AI3 分析后 `asr_error_map` 有新增条目
- [ ] 错误映射来源标记为 `ai3`
- [ ] 重复错误 `hit_count` 累加

---

### ACC-P1-04 · PromptComposer 注入 §1.E 错误映射段

**文件**：`Core/PromptComposer.swift`

**改动**：新增 §1.E 段，从 `asr_error_map` 读取高置信度映射：

```swift
// 读取 confidence > 0.6 且 hit_count >= 2 的映射（最多 20 条）
let maps = try ASRErrorMapRecord
    .filter(Column("confidence") > 0.6 && Column("hit_count") >= 2)
    .order(Column("hit_count").desc)
    .limit(20)
    .fetchAll(db)

if !maps.isEmpty {
    let mapStr = maps.map { "\($0.asrWrong)→\($0.correctWord)" }.joined(separator: "、")
    sections.append("§1.E 已知 ASR 错误映射（遇到左侧词请替换为右侧）：\(mapStr)")
}
```

**Token 预算**：§1.E 上限 100 tokens（≈50 个映射对），超出截断低 hit_count 的。

**验收**：
- [ ] 有映射时 §1.E 出现在 prompt 中
- [ ] 无映射时不插入
- [ ] 低置信度映射不注入（防止错误纠正）

---

### ACC-P1-05 · Per-App Profile 选择逻辑

**文件**：`Core/PromptComposer.swift`

**改动**：`systemPrompt(for:targetAppBundleID:...)` 中，profile 选择逻辑改为：

```
1. 查 per-app profile（bundleID 精确匹配）
2. 无则 fallback 到 __global__ profile
3. 无全局 profile 则用默认空 profile
```

**验收**：
- [ ] 邮件 app 使用邮件 profile，聊天 app 使用聊天 profile
- [ ] 无 per-app profile 时平滑 fallback 到全局
- [ ] 新 app 首次使用时不报错

---

## ACC-P2 · 用户反馈闭环（2 任务）

### ACC-P2-01 · 浮层 Pill "有误" 按钮

**文件**：`UI/FloatingPillView.swift`

**改动**：润色完成后的浮层增加小按钮 "有误"（或 ✕ 图标），点击后：
1. 弹出对比面板：左侧原文（ASR）/ 右侧润色结果
2. 用户可编辑右侧为正确文本
3. 提交后：
   - 将 `raw_log.user_flagged_error = 1`
   - 调用 diff 提取错误对 → 写入 `asr_error_map`（source = `user_feedback`）
   - 替换粘贴板为用户修正文本

**验收**：
- [ ] "有误"按钮可见且不影响正常浮层交互
- [ ] 用户修正后 `asr_error_map` 有新条目
- [ ] 修正文本写入粘贴板

---

### ACC-P2-02 · Diff 提取：ASR原文 vs 用户修正

**文件**：`Core/DiffExtractor.swift`（新建）

```swift
struct ErrorPair {
    let wrong: String   // ASR 原文片段
    let correct: String // 用户修正片段
}

/// 对比 ASR 原文和用户修正文本，提取差异词对。
/// 使用简单的逐词对比（中文按字符，英文按空格分词）。
static func extract(asrText: String, correctedText: String) -> [ErrorPair]
```

**验收**：
- [ ] "百练模型" vs "百炼模型" → `[("百练", "百炼")]`
- [ ] 多处差异全部提取
- [ ] 相同文本返回空数组

---

## 延迟预算总表

| 注入段 | 估算 tokens | TTFT 增量 |
|--------|------------|----------|
| §A.ctx（上下文缓冲） | ≤ 200 | ≤ 20ms |
| §1.E（错误映射） | ≤ 100 | ≤ 10ms |
| Per-app profile（§1 略增） | ≤ 50 | ≤ 5ms |
| **合计** | **≤ 350** | **≤ 35ms** |

> Qwen-turbo 8K window，当前基线 ~300 tokens，增至 ~650 tokens，TTFT 增量在可接受范围。

---

## 执行顺序

```
ACC-P0-01 → P0-02 → P0-03 → P0-04（上下文缓冲，可独立交付测试）
    ↓
ACC-P1-01 → P1-03 → P1-04（错误映射表 + AI3 提取 + prompt 注入）
ACC-P1-02 → P1-05（per-app profile，可与上面并行）
    ↓
ACC-P2-01 → P2-02（用户反馈，最后做）
```

---

## 与 100 测试的关系

在 `PROMPT_TUNING_100_TESTS.md` 的 PT_F 组中追加：
- **F-16**：有 3 条上下文 vs 无上下文，输出质量对比
- **F-17**：有 3 条上下文 vs 无上下文，延迟差 < 50ms
- **F-18**：有 10 条错误映射 §1.E vs 无映射，"百练"→"百炼" 修正率

现有 PT_B 组（App 上下文 §A）天然覆盖 per-app 场景。
