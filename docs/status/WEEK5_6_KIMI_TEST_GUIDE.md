# Week 5+6 + V1.4 · Kimi 测试指南

**版本**: 1.0 | **日期**: 2026-03-25
**测试范围**: AI3 数据链路、V3 Prompt 效果验证、浮层 pill UX、菜单栏、闭环反馈、Review 修复项
**前置阅读**: `docs/spec/VILSAY_TECH_ARCH.md` v1.4、`docs/spec/voice_polish_prompt.md`、`WEEK5_6_CURSOR_TASKS.md`

---

## 一、环境准备

### 1.1 App 环境变量

Xcode Scheme → Edit Scheme → Arguments → Environment Variables:

```
VILSAY_API_BASE = http://127.0.0.1:8000
DASHSCOPE_API_KEY = <你的百炼 Key>
```

### 1.2 重置本地数据（每轮测试前）

```bash
# 删除 App 本地 SQLite，冷启动重建
rm -f ~/Library/Application\ Support/vilsay/vilsay.sqlite

# 或：App 内 设置 → 清除 AI 学习数据（保留手动词典）
```

### 1.3 查看 DB 数据（验证用）

```bash
alias vdb="sqlite3 ~/Library/Application\ Support/vilsay/vilsay.sqlite"

# 常用查询
vdb "SELECT id, asr_text, asr_confidence, target_app_id, user_flagged_error FROM raw_log ORDER BY id DESC LIMIT 5;"
vdb "SELECT * FROM user_profile;"
vdb "SELECT word, pinyin, state FROM dictionary_candidates;"
vdb "SELECT word, pinyin, source FROM dictionary;"
vdb "SELECT * FROM analyzer_state;"
```

### 1.4 查看 Prompt 输出（关键！）

```
Xcode Console 过滤 "[PromptComposer]" 或 "[Pipeline]" 查看润色时发送的完整 System Prompt。
确认 §A / §C / §1 / §1.P 各层是否按预期出现。
```

---

## 二、A 类：V3 Prompt 效果验证（重点）

> **目的**：验证 Prompt V3 五层结构（§0 + §A + §C + §1 + §2）是否真正影响润色质量。
> 每组测试用**同一句 ASR 输入**，对比不同 Prompt 层的输出差异。

---

### T-A01 · §A App 上下文：邮件 vs 聊天语体差异

```
测试方法：用同一句话在两个 App 中分别录音

ASR 模拟输入（说这段话）：
  "嗯就是那个方案呢我觉得还行吧你看着办就好了啊"

场景 1：在 Apple Mail（com.apple.mail）中触发录音
  期望 Prompt 含：【场景提示】用户正在写邮件，注意正式语体
  期望润色结果偏向正式：如 "关于该方案，我认为可行，请酌情处理。"

场景 2：在微信（com.tencent.xinWeChat）中触发录音
  期望 Prompt 含：【场景提示】用户在聊天，保留口语化表达
  期望润色结果保留口语：如 "那个方案我觉得还行，你看着办就好了"

场景 3：在 Terminal（com.apple.Terminal）中触发录音
  期望 Prompt 不含 §A 段（未映射 App 不注入）
  期望润色结果为中性语体

验收：
□ 场景 1 输出明显比场景 2 更正式
□ 场景 2 保留了"觉得""还行""你看着办"等口语
□ 场景 3 无 §A 注入，润色结果居中
□ Console 日志确认三次 Prompt 的 §A 段差异
```

---

### T-A02 · §A App 上下文：文档 vs 笔记

```
ASR 模拟输入：
  "然后第二个问题就是关于那个用户增长的数据嗯我们上个月大概涨了百分之十五"

场景 1：在 Microsoft Word（com.microsoft.Word）中触发
  期望润色偏书面完整：
  "其次，关于用户增长数据，上月同比增长约 15%。"

场景 2：在 Apple Notes（com.apple.Notes）中触发
  期望润色偏简洁笔记体：
  "用户增长：上月涨 15%"

验收：
□ Word 输出有完整句式和正式表达
□ Notes 输出更简短直接
□ 两者都正确去除了填充词"嗯""就是""那个"
```

---

### T-A03 · §C ASR 置信度：低置信 vs 高置信纠偏力度

```
测试方法：需要触发 WhisperKit 本地转写（断网或直接用 Whisper 路径）

场景 1：清晰录音（安静环境，标准语速）
  说："我们下周三开会讨论一下产品路线图"
  期望：asr_confidence 较高（≥ 0.4）
  期望 Prompt 不含 §C（高置信不注入）
  期望润色：最小干预，接近原文

场景 2：模糊录音（远离麦克风、小声说、或有背景噪音）
  说："我们下周三开会讨论一下产品路线图"（故意含糊）
  期望：asr_confidence 较低（< 0.4）
  期望 Prompt 含：【识别质量提示】本次语音识别置信度较低（XX%）...
  期望润色：更积极的同音纠偏

验证方法：
  1. vdb "SELECT asr_confidence FROM raw_log ORDER BY id DESC LIMIT 2;"
     确认两次 confidence 差异
  2. Console 对比两次 Prompt，场景 2 应多出 §C 段
  3. 如果两次 ASR 都正确识别，那 §C 的价值在于"有错时更积极纠正"

验收：
□ 清晰录音 confidence ≥ 0.4，无 §C
□ 模糊录音 confidence < 0.4，有 §C
□ raw_log 两条记录的 asr_confidence 值不同
□ 即使无明显纠错差异，Prompt 层级构造正确即通过
```

---

### T-A04 · §1 用户画像注入：空画像 vs 有画像

```
测试方法：对比积累 20 句前后的润色差异

阶段 1：冷启动（无画像）
  连续说 5 句不同内容：
  ① "嗯就是说我觉得这个 API 的设计有点问题"
  ② "然后然后那个前端组件需要重构一下"
  ③ "对对对就是这样子的然后我们再看看"
  ④ "那个 pipeline 的 timeout 要改成三十秒"
  ⑤ "好的那就这样吧我去写 code review 了"

  记录5次润色结果（复制出来保存）
  Console 确认 Prompt 只有 §0 + §2（无 §1）

阶段 2：积累至 20 句（触发 AI3）
  继续说 15 句（可以重复上述内容或随意说）
  说第 20 句后等待 AI3 分析完成（Console 看 "[AI3Analyzer]" 日志）

  vdb "SELECT key, value FROM user_profile;"
  确认画像非空（应有 habitual_words、thinking_style、tone 等）

阶段 3：有画像后再说相同的话
  重复阶段 1 的 ①~⑤ 句
  记录5次润色结果

对比分析：
  - §1 注入后，口头禅处理是否更符合用户习惯？
    例如：用户总说"就是说"，AI3 可能标记为 keep/simplify
  - 技术术语（API、pipeline、timeout、code review）是否被识别并保留？
  - 语气风格是否更贴近用户真实说话方式？

验收：
□ 阶段 1 Console Prompt 无 §1 / 【用户专属】
□ 阶段 2 后 user_profile 有数据，dictionary_candidates 有候选词
□ 阶段 3 Console Prompt 包含 【用户专属】段
□ 阶段 3 润色结果与阶段 1 有可感知差异（不要求巨大差异，有差异即通过）
□ 技术术语在两个阶段均被正确保留
```

---

### T-A05 · §1.P 拼音同音纠偏效果

```
前置：手动添加几个容易被 ASR 误识别的词到词典

步骤 1：添加词典条目
  设置 → 词典 → 手动添加：
  - "事业"（常被误识别为"试验""世业"）
  - "Vilsay"（英文品牌名）
  - "张思远"（人名，常被误识别为"张思源""长思远"）

步骤 2：确认拼音自动生成
  vdb "SELECT word, pinyin FROM dictionary;"
  期望：
  - 事业 → "shi ye"
  - Vilsay → "Vilsay"（非中文，原样或类似）
  - 张思远 → "zhang si yuan"

步骤 3：说包含这些词的句子
  ① "我觉得这个事业部的方案不错"
  ② "我们用 Vilsay 来处理这个语音"
  ③ "帮我发给张思远"

  检查 Console Prompt 中 §1.P 段：
  期望含类似：
  "以下词汇容易被语音误识别为同音词...事业(shi ye)、张思远(zhang si yuan)"

步骤 4：对比效果
  删除词典中"事业"条目，重新说 ① → 对比两次润色结果
  如果 ASR 把"事业"误识别为"试验"，有 §1.P 时应纠正为"事业"

验收：
□ 词典条目入库后 pinyin 字段非空
□ Prompt §1.P 段包含词典词+拼音
□ 有拼音提示时，同音字纠偏更准确（有差异即通过，不要求 100% 纠正）
□ 无词典时 §1.P 不出现
```

---

### T-A06 · Prompt 完整性：五层同时生效

```
前置：
  - 积累 20 句触发 AI3（user_profile 非空）
  - 词典中有 2~3 个带拼音的词条
  - 在 Apple Mail 中操作

录音内容（故意含糊一点触发低置信度）：
  "嗯那个就是说帮我转发一下那个会议纪要给张思远啊然后顺便问一下那个事业部的进展"

Console 检查完整 Prompt 应包含 5 层：
  ✓ §0 "你是一位语言整理师..."
  ✓ §A "【场景提示】用户正在写邮件，注意正式语体"
  ✓ §C "【识别质量提示】..."（如果低置信度触发）
  ✓ §1 "【用户专属】用户口头禅与保留词：...思维结构：...高频词典：..."
  ✓ §1.P "以下词汇容易被语音误识别为同音词...事业(shi ye)、张思远(zhang si yuan)"
  ✓ §2 "P1 自我纠正识别...P2 填充词...P3 同音字纠偏..."

润色期望：
  - 去除填充词"嗯""那个""就是说""啊"
  - 邮件语体（正式）
  - "张思远""事业部" 正确保留
  - 句式完整

验收：
□ Console 中看到至少 4 层（§C 取决于置信度，可能不触发）
□ 润色结果符合邮件正式语体
□ 人名和术语正确保留
□ 填充词被清理
```

---

## 三、B 类：AI3 数据链路验证

---

### T-B01 · 20 句触发 AI3 分析

```
步骤：
1. 重置数据（rm SQLite 或 App 内清除）
2. 连续说 20 句不同的话（可以是日常对话、工作内容）
3. 观察 Console "[AI3Analyzer]" 或 "[AnalyzerTrigger]" 日志

验证：
  vdb "SELECT total_logged_count, last_trigger_count, last_analyzed_log_id FROM analyzer_state;"
  期望：total=20, last_trigger=20, last_analyzed_log_id=20（或最后一条的 id）

  vdb "SELECT key, substr(value,1,80) FROM user_profile;"
  期望：至少有 habitual_words 或 tone 条目

  vdb "SELECT word, pinyin, state FROM dictionary_candidates;"
  期望：有 AI3 推荐的候选词（可能为空，取决于内容）

验收：
□ 20 句后 AI3 触发（Console 可见分析日志）
□ user_profile 写入（非空）
□ analyzer_state.last_analyzed_log_id 更新
□ Pipeline 延迟无可感知变化（AI3 在后台）
```

---

### T-B02 · 去重验证（FIX-02 修复项）

```
步骤：
1. 说 20 句，AI3 触发，记录 last_analyzed_log_id = X
2. 再说 19 句（不满 20 新增）
3. 确认 AI3 不触发

  vdb "SELECT total_logged_count, last_trigger_count FROM analyzer_state;"
  期望：total=39, last_trigger=20（差值 19 < 20，不触发）

4. 说第 40 句
5. 确认 AI3 再次触发，且只分析 id > X 的记录

  vdb "SELECT last_analyzed_log_id FROM analyzer_state;"
  期望：更新为 40（不是重复分析 1~20）

验收：
□ 第 21~39 句期间不触发 AI3
□ 第 40 句触发 AI3
□ last_analyzed_log_id 从 20 更新到 40（不回退）
```

---

### T-B03 · 候选词去重（FIX-03 修复项）

```
步骤：
1. 说 20 句（内容中重复提到"张思远"或某个专有名词）
2. AI3 触发 → dictionary_candidates 中出现该词
3. 不操作该词（保持 pending 状态）
4. 再说 20 句（同样提到该词）
5. AI3 再次触发

  vdb "SELECT word, count(*) as cnt FROM dictionary_candidates GROUP BY word HAVING cnt > 1;"
  期望：返回空（无重复词条）

验收：
□ 同一词不出现两条 pending 候选
□ dismissed 的词也不会重新出现
```

---

### T-B04 · 候选词生命周期

```
步骤：
1. 积累 20 句触发 AI3
2. 打开词典页 Tab2（智能推荐）
3. 对某个候选词点"加入词典"

  vdb "SELECT word, source FROM dictionary ORDER BY id DESC LIMIT 3;"
  期望：刚才的词出现在 dictionary 表，source="ai"

4. 对另一个候选词点"忽略"

  vdb "SELECT word, state FROM dictionary_candidates WHERE state='dismissed';"
  期望：该词 state="dismissed"

5. 再触发一轮 AI3（继续说 20 句）

  确认：
  - approved 的词不再出现在候选
  - dismissed 的词不再出现在候选

验收：
□ approve → 词进入 dictionary 表 + 从候选消失
□ dismiss → state 变 dismissed + 从 UI 消失
□ 后续 AI3 分析不重新推荐已处理的词
□ 角标数字实时更新
```

---

## 四、C 类：浮层 Pill UX 验证

---

### T-C01 · 录音态 Pill 外观与交互

```
步骤：
1. 触发录音（热键）

期望（录音中）：
□ 显示胶囊/pill 形态（非圆形）
□ 左侧红色闪烁圆点
□ 中间有波形动画（跟随说话声音起伏）
□ 右侧 ✕ 按钮可见

2. 说话时观察波形变化
  □ 说话声大时柱状条高
  □ 安静时柱状条低

3. 点击 ✕ 按钮
  □ 录音立即停止
  □ 无文字输出（与 ESC 等效）
  □ pill 消失
```

---

### T-C02 · 处理态与完成态

```
步骤：
1. 录音 → 松开热键

期望（处理中）：
□ pill 变为"思考中..."（不是"正在识别"或"正在润色"）
□ 有 spinner 动画

期望（完成后）：
□ pill 显示润色文字前 20 字 + "..."
□ 右侧有"⚠ 有误"按钮
□ 默认 2 秒后 pill 消失

2. 再录一句，完成后鼠标移到 pill 上
  □ pill 不消失（悬停延长至 5 秒）
  □ 有足够时间点击"有误"

3. 点击"⚠ 有误"
  □ 按钮变为 ✓ "已记录"
  □ 约 0.5 秒后 pill 消失
  □ vdb 查询最新 raw_log 的 user_flagged_error=1
```

---

### T-C03 · 改词模式 Pill 区分

```
步骤：
1. 在任意 App 中选中一段文字
2. 按热键触发改词模式

期望：
□ pill 显示蓝色指示点（非红色）
□ 显示"听指令..."
□ 有波形和 ✕ 按钮
□ 说"改正式一点" → 完成后文字被替换
```

---

### T-C04 · Pill 位置持久化

```
步骤：
1. 拖动 pill 到屏幕右上角
2. 完全退出 App（Cmd+Q）
3. 重新打开 App
4. 触发录音

期望：
□ pill 出现在上次拖动的位置（右上角）
□ 不是默认底部居中
```

---

## 五、D 类：菜单栏验证

---

### T-D01 · 菜单栏图标状态切换

```
观察菜单栏图标在以下状态的变化：

1. idle（待机）→ 期望：麦克风轮廓（细线）
2. 按热键进入录音 → 期望：实心麦克风
3. 松开热键（处理中）→ 期望：带角标的麦克风（如省略号）
4. 完成 → 回到 idle 图标

□ 深色模式下图标清晰可见
□ 浅色模式下图标清晰可见
```

---

### T-D02 · 录音中菜单项

```
步骤：
1. 触发录音
2. 录音中点击菜单栏图标展开菜单

期望：
□ 菜单顶部有「⏹ 停止录音」和「✕ 取消（不输出）」
□ 两项之间或下方有分割线

3. 点击「⏹ 停止录音」
  □ 正常处理 → 输出润色文字

4. 再次录音 → 展开菜单 → 点击「✕ 取消（不输出）」
  □ 录音取消，无文字输出

5. 非录音状态展开菜单
  □ 顶部为「开始录音」（非停止/取消）
```

---

## 六、E 类：闭环反馈路径端到端

---

### T-E01 · "有误"标记 → AI3 学习

```
步骤：
1. 说 19 句正常录音
2. 第 20 句：说一句容易被误识别的话（如含同音字的专业术语）
3. 完成后在 pill 上点"⚠ 有误"

  vdb "SELECT id, user_flagged_error FROM raw_log ORDER BY id DESC LIMIT 3;"
  期望：最新一条 user_flagged_error=1

4. 第 20 句触发 AI3 分析

  Console 检查 AI3Analyzer 的分析 Prompt 中是否包含：
  "以下记录被用户标记为识别/润色有误..."

验收：
□ 标记的是最新一条 raw_log（不是旧的）
□ AI3 分析时读到了 flagged 记录
□ 闭环路径完整：标记 → 存 DB → AI3 读取 → 纳入分析
```

---

### T-E02 · 并发安全：快速说话后标记（FIX-01 修复项）

```
步骤：
1. 快速连续说两句话（第一句完成后立即开始第二句）
2. 第二句完成后立刻点"⚠ 有误"

  vdb "SELECT id, asr_text, user_flagged_error FROM raw_log ORDER BY id DESC LIMIT 3;"

期望：
□ user_flagged_error=1 标记在最新的那条（第二句），不是第一句
□ 时间戳确认是刚才的记录
```

---

## 七、F 类：Review 修复项回归测试

---

### T-F01 · ASR 超时保护（FIX-04）

```
测试方法：断网测试

1. 断开网络
2. 触发录音 → 说一句话 → 松开
3. 观察：应在合理时间内（< 65s）回到 idle
   不应永远卡在 processing

□ 断网后 ASR 降级到 WhisperKit（或超时失败）
□ 状态最终回到 idle，不永挂
```

---

### T-F02 · 10 次录音回归测试（性能死亡线）

```
操作：正常使用 10 次，记录每次"松开热键 → 文字出现"耗时

方法：Console 搜索 "[Performance]" 日志，读取 ASR / Polish / Inject 各阶段耗时

| 次数 | ASR(ms) | Polish(ms) | Inject(ms) | 总耗时(ms) |
|------|---------|------------|------------|------------|
| 1    |         |            |            |            |
| 2    |         |            |            |            |
| ...  |         |            |            |            |
| 10   |         |            |            |            |
| 平均 |         |            |            |            |

验收：
□ 平均总耗时 < 1500ms（死亡线）
□ 无单次 > 3000ms（异常值）
□ AI3 触发时（第 20 句附近）延迟不突增
```

---

### T-F03 · 清除数据后全链路重建

```
步骤：
1. 先积累 20 句（AI3 触发，有画像）
2. 设置 → 清除 AI 学习数据
3. 确认：
  vdb "SELECT count(*) FROM raw_log;"              → 0
  vdb "SELECT * FROM user_profile;"                → 空
  vdb "SELECT * FROM dictionary_candidates;"       → 空
  vdb "SELECT * FROM analyzer_state;"              → total=0, last_trigger=0, last_analyzed_log_id=NULL
  vdb "SELECT count(*) FROM dictionary;"            → 手动词典保留
4. 重新说 20 句 → AI3 再次触发 → 画像重建

验收：
□ 清除后 raw_log/profile/candidates 全空
□ 手动词典不受影响
□ 重新积累 20 句后 AI3 正常触发
□ 角标归零再重新出现
```

---

## 八、G 类：边界场景补充

---

### T-G01 · raw_log 数据完整性

```
说 3 句话后检查 raw_log：

vdb "SELECT id, substr(asr_text,1,30), asr_provider, asr_confidence, target_app_id FROM raw_log;"

验收：
□ asr_provider 为 "whisperKit" 或 "dashScope"（非 NULL）
□ asr_confidence 有值（WhisperKit 路径）或 NULL（DashScope 路径）
□ target_app_id 为触发时前台 App 的 bundleIdentifier（如 "com.apple.Notes"）
□ user_flagged_error 默认为 0
```

---

### T-G02 · 断网完整流程

```
1. 断开网络
2. 在 Notes 中触发录音 → 说一句 → 松开

期望：
□ 云端 ASR 失败 → 自动降级 WhisperKit
□ 正常出字（可能略慢）
□ raw_log.asr_provider = "whisperKit"
□ target_app_id = "com.apple.Notes"
□ Prompt 含 §A "用户在记笔记，保持简洁"（断网不影响 §A）
```

---

### T-G03 · 隐私政策页

```
1. 设置 → 关于 → 隐私政策
□ Sheet 弹出，WebView 加载或显示内容
□ 无网时显示友好错误提示（非白屏崩溃）
```

---

## 测试结果汇总表

| 类别 | 编号 | 名称 | 结果 | 备注 |
|------|------|------|------|------|
| A-Prompt | T-A01 | §A 邮件 vs 聊天 | □ | |
| A-Prompt | T-A02 | §A 文档 vs 笔记 | □ | |
| A-Prompt | T-A03 | §C 低置信 vs 高置信 | □ | |
| A-Prompt | T-A04 | §1 空画像 vs 有画像 | □ | |
| A-Prompt | T-A05 | §1.P 拼音纠偏 | □ | |
| A-Prompt | T-A06 | 五层同时生效 | □ | |
| B-AI3 | T-B01 | 20 句触发 AI3 | □ | |
| B-AI3 | T-B02 | 去重（FIX-02） | □ | |
| B-AI3 | T-B03 | 候选词去重（FIX-03） | □ | |
| B-AI3 | T-B04 | 候选词生命周期 | □ | |
| C-Pill | T-C01 | 录音态 Pill | □ | |
| C-Pill | T-C02 | 处理态+完成态+有误 | □ | |
| C-Pill | T-C03 | 改词模式蓝色 | □ | |
| C-Pill | T-C04 | 位置持久化 | □ | |
| D-菜单 | T-D01 | 图标状态切换 | □ | |
| D-菜单 | T-D02 | 录音中菜单项 | □ | |
| E-闭环 | T-E01 | 有误→AI3 学习 | □ | |
| E-闭环 | T-E02 | 并发安全（FIX-01） | □ | |
| F-回归 | T-F01 | ASR 超时保护 | □ | |
| F-回归 | T-F02 | 10 次性能测试 | □ | |
| F-回归 | T-F03 | 清除后重建 | □ | |
| G-边界 | T-G01 | raw_log 完整性 | □ | |
| G-边界 | T-G02 | 断网完整流程 | □ | |
| G-边界 | T-G03 | 隐私政策页 | □ | |

---

## 重点关注（给 Kimi 的提示）

1. **A 类是本轮最重要的测试**：V3 Prompt 是否真正改善润色质量。如果 §A 的邮件/聊天语体没有可感知差异，说明 Prompt 设计需要迭代。
2. **对比测试时保存 Console 中的完整 Prompt**：这是判断问题出在"Prompt 构造"还是"LLM 执行"的关键证据。
3. **T-A04 的"可感知差异"标准放宽**：AI3 首次分析画像可能不够准确，只要有差异就通过。画像质量会随使用逐步提升。
4. **如果 §C 始终不触发**：说明 WhisperKit 在测试环境下置信度普遍 ≥ 0.4。这本身是好事（ASR 质量高），只需确认逻辑正确（Console 无 §C 段 = 正确行为）。

---

# 文档结束
