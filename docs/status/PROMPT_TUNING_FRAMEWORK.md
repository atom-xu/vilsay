# Prompt 调优框架 — 设计文档

> 版本：v1.0 | 2026-03-26

## 核心理念

**LLM-as-Judge**：用 LLM 自身理解语义来评估输出质量，而非关键词匹配。

- 关键词匹配的问题：`contains("周三")` 只验证表面，无法判断语义完整性、风格适配、干预程度
- LLM Judge 的优势：理解"忠于原意"、"最小干预"、"风格匹配"等模糊概念，给出 1~5 分评估 + 评语
- 防止"变傻"：调优过程不往 prompt 里堆关键词规则，而是通过 LLM Judge 反馈来迭代 prompt 的表述方式

## 架构

```
┌─────────────────┐
│ TuningCaseRegistry │  ← 用例库（多方可贡献）
│  35+ 预置用例      │
└────────┬────────┘
         ▼
┌─────────────────┐
│  TuningRunner    │  ← 批量执行引擎
│  串行/并发控制     │
└────────┬────────┘
         │
    ┌────┴────┐
    ▼         ▼
┌────────┐ ┌───────────┐
│PolishService│ │TuningEvaluator│
│（被测系统）│ │（LLM Judge）  │
└────────┘ └───────────┘
         │
         ▼
┌─────────────────┐
│ TuningReport     │  ← Markdown + JSON 报告
│  分数/评语/对比    │
└─────────────────┘
```

## 评估维度（5 项，1~5 分）

| 维度 | 说明 | 关键问题 |
|------|------|---------|
| **faithfulness** | 忠于原意 | 信息有无丢失或添加？ |
| **minimalEdit** | 最小干预 | 修改幅度是否恰当？ |
| **styleMatch** | 风格匹配 | 输出风格是否符合目标场景？ |
| **fluency** | 流畅自然 | 读起来通不通顺？ |
| **formatting** | 格式正确 | 标点/分段/编号是否正确？ |

每条用例可自定义各维度权重。例如：
- chat 模式：`minimalEdit` 和 `styleMatch` 权重调高（口语保留最重要）
- document 模式：`formatting` 权重调高（结构化是核心价值）
- 短文本：`minimalEdit` 权重调高（不能过度改写）

## 用例库（TuningCaseRegistry）

| 类别 | 数量 | 重点验证 |
|------|------|---------|
| baseline | 5 | V3 回归：填充词、自我纠正、断句、短输入 |
| chat | 5 | 最小干预、语气词保留、口语风格 |
| email | 3 | 正式语体、分条、称呼礼貌 |
| document | 3 | 分段、逻辑重排、去重 |
| note | 3 | Bullet 格式、要点提炼、TODO 标记 |
| aiCommand | 3 | 指令提取 vs 正常对话区分 |
| edge | 5 | 纯英文、极短、低置信度、prompt 注入 |
| longText | 3 | 500字+ 核心竞争力场景 |
| profile | 3 | 画像 + 模式联动（dev/med/biz）|
| **合计** | **33** | |

### 新增用例规范

```swift
TuningCase(
    id: "chat_06",                    // {category}_{序号}
    category: "chat",
    description: "人类可读说明",
    asrText: "模拟 ASR 转写",
    targetBundleID: "com.xxx",        // nil = general
    asrConfidence: nil,               // < 0.4 触发 §C
    profileKey: "dev",                // nil / dev / biz / student / med / pinyin
    weights: chatWeights,
    referenceOutput: "可选金标准",      // LLM Judge 对比用
    constraints: ["约束1", "约束2"]    // 必须满足的语义约束
)
```

## 多方协作流程

```
产品经理 ──→ 提供真实场景 ASR 文本 + 期望约束
              ↓
测试人员 ──→ 编写 TuningCase，加入 Registry
              ↓
开发者   ──→ 修改 Prompts.swift，跑 TuningRunner
              ↓
         ──→ 查看报告：平均分是否提升？低分项是否改善？
              ↓
         ──→ A/B 对比：新 prompt vs 旧 prompt
              ↓
         ──→ 确认无回归后合入
```

### 角色分工

| 角色 | 负责 | 修改文件 |
|------|------|---------|
| 产品/运营 | 提供真实 ASR 样本和预期 | 不接触代码 |
| 测试 | 编写 TuningCase | `TuningCaseRegistry.swift` |
| 开发 | 调整 prompt | `Prompts.swift` |
| 架构 | 评估维度/权重调整 | `TuningCase.swift`、`TuningEvaluator.swift` |

## 运行方式

### 快速验证（3 条，~30s）

```bash
DASHSCOPE_API_KEY=sk-xxx xcodebuild test \
  -project vilsay/vilsay.xcodeproj -scheme vilsay \
  -only-testing "vilsayTests/TuningIntegrationTests/smokeTest" \
  DASHSCOPE_API_KEY=sk-xxx 2>&1 | xcbeautify
```

### 按类别跑

```bash
# 只跑 chat 类
-only-testing "vilsayTests/TuningIntegrationTests/chatFullTest"

# 只跑长文本（核心竞争力）
-only-testing "vilsayTests/TuningIntegrationTests/longTextFullTest"
```

### 全量 + 生成报告

```bash
-only-testing "vilsayTests/TuningIntegrationTests/fullSuiteWithReport"
# 报告输出至 ~/Desktop/VilsayTuningReports/
```

### A/B 对比

```bash
-only-testing "vilsayTests/TuningIntegrationTests/abCompareChatExample"
```

## 报告格式

### Markdown（人类阅读）

```
# 调优报告：v4_full
平均分：3.85 / 5.0

## 分类平均
- baseline: 4.10
- chat: 3.60
- document: 3.90
...

## 需关注（< 3.0）
- **ai_02** (2.4): aiCommand 模式对正常提问过度提取为编号列表
```

### JSON（机器分析）

完整数据包括每条用例的 5 维分数、LLM Judge 原始返回、system prompt 快照、耗时等，可用于趋势追踪。

## 调优迭代示例

假设发现 chat 模式 `minimalEdit` 得分偏低（模型过度改写口语）：

1. **定位**：查看报告中 chat 类低分项的 `commentary`
2. **假设**：chat 的 `modeRules` 中"只做最小必要的纠错"表述不够强
3. **修改**：在 `Prompts.swift` 的 `.chat` modeRules 中加强表述
4. **验证**：
   ```swift
   // A/B 对比
   let tweaked: (TuningCase, OutputMode) -> String = { tc, mode in
       var prompt = PromptComposer.systemPrompt(...)
       if mode == .chat {
           prompt += "\n【强调】绝对禁止改写用户原有的口语表达..."
       }
       return prompt
   }
   let md = await TuningRunner.abCompare(
       cases: TuningCaseRegistry.chat,
       variantA: "v4_current", promptA: nil,
       variantB: "v4_chat_v2", promptB: tweaked
   )
   ```
5. **确认**：chat `minimalEdit` 提升且其他维度未退步 → 合入

## 文件清单

```
vilsayTests/PromptTuning/TuningFramework/
├── TuningCase.swift              # 数据模型
├── TuningEvaluator.swift         # LLM-as-Judge 引擎
├── TuningRunner.swift            # 批量执行 + 报告
├── TuningCaseRegistry.swift      # 用例库（多方贡献入口）
├── TuningTestSetup.swift         # 环境配置
└── TuningIntegrationTests.swift  # 测试入口
```

## 与现有 PT_A~J 测试的关系

| 维度 | PT_A~J（100 测试） | TuningFramework（33 用例） |
|------|-------------------|--------------------------|
| 目的 | 功能验证（pass/fail） | 质量评估（1~5 分） |
| 评估方式 | 关键词 #expect | LLM-as-Judge |
| 产出 | 测试结果 ✅/❌ | 分数报告 + 评语 |
| 适用场景 | CI 门禁 | Prompt 迭代调优 |
| 共存 | 保留 | 新增 |

两者互补：PT_A~J 保障基本功能不回归，TuningFramework 驱动质量持续提升。
