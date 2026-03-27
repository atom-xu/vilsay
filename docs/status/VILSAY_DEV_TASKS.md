# VILSAY · 开发任务书
# 版本：2.3 | 日期：2026-03-22
# ⚠️ 每次开新对话给 Cursor/Kimi，必须附上此文档 + `docs/spec/VILSAY_TECH_ARCH.md`
# ⚠️ 领取或开工任意 Week 前，须先完成「微架构门禁」：[`WEEKLY_MICRO_ARCH_PROCESS.md`](WEEKLY_MICRO_ARCH_PROCESS.md)；本机预检见 [`PREFLIGHT_AND_TROUBLESHOOTING.md`](PREFLIGHT_AND_TROUBLESHOOTING.md)

---

## 一、给 Cursor/Kimi 的初始化指令模板

```
我在开发 Vilsay，一个 macOS 原生语音润色 App。
技术栈：Swift + SwiftUI，最低 macOS 14。

请先读取以下文档：
- docs/spec/VILSAY_TECH_ARCH.md（技术架构、接口定义）
- docs/spec/VILSAY_UI_UX.md（界面规范、文案规范）
- docs/status/VILSAY_DEV_TASKS.md（当前任务）
- docs/status/WEEKLY_MICRO_ARCH_PROCESS.md（每周开工前微架构门禁）

三个 AI：
- AI1：阿里云 DashScope 流式 ASR（主）+ WhisperKit（备）
- AI2：Qwen 流式润色，V2 Prompt 固定层+动态层
- AI3：内置画像分析，异步，用户不可见

悬浮按钮：NSPanel floating，可拖动，支持 Push/Toggle 双模式
改词功能：检测选中文字 → 说指令 → AI 修改
取消机制：录音中按 ESC 取消，不输出

开发原则：先前端后后端，先主链路后 AI3
当前进度：[Week X - Task XX]
当前问题：[具体描述]
```

---

## 二、开发顺序总览

### 2.1 每周任务领取前的微架构门禁（强制）

在**领取**或**开工**某一 Week 的任务之前，**开发**与**架构**须共同完成微架构对齐，并落盘 **`docs/status/micro-arch/WeekN_MICRO_ARCH.md`**（命名与清单见 [`WEEKLY_MICRO_ARCH_PROCESS.md`](WEEKLY_MICRO_ARCH_PROCESS.md)）。内容至少包含：本周范围与模块映射、对外契约、数据流、权限/沙盒、失败降级、可执行验收步骤。

未通过该门禁的，**不得**将本周任务标为「可领取」或「全部完成」；若实现与 `VILSAY_TECH_ARCH.md` 不一致，**先修订文档再合码**（或在该周微架构文档中明确「有意偏离」及原因）。

**Week 1～3 追认**：若当时未写微架构文档，可补一份带「追认」字样的 `WeekN_MICRO_ARCH.md`，便于后续审计。

```
Week 1：项目初始化
Week 2：前端界面全部完成（含占位）
Week 3：主链路后端（AI1+VAD+AI2+注入+改词+取消）
Week 4：账号体系（登录+计费+用量）
Week 5：AI3 数据层 + 分析层
Week 6：联调打磨 + 上架准备
Week 7+：官网 + 后端服务器（可并行）
```

---

## 三、详细任务清单

### WEEK 1 · 项目初始化

**W1-01：创建 Xcode 项目**
```
类型：macOS App
语言：Swift | UI：SwiftUI | 最低：macOS 14.0
完成验证：□ 编译运行 □ 出现默认窗口
```

**W1-02：配置 SPM 依赖**
```
添加：
- WhisperKit（argmaxinc/WhisperKit）
- GRDB.swift（groue/GRDB.swift）
- KeyboardShortcuts（nicklockwood/KeyboardShortcuts）
- LaunchAtLogin（sindresorhus/LaunchAtLogin-modern）
完成验证：□ 所有库下载成功 □ import 无报错
```

**W1-03：建立目录结构**
```
按 VILSAY_TECH_ARCH.md 第三章创建：
App/ Entry/ Core/ AI3/ Auth/ DB/ UI/ Config/ Utils/
完成验证：□ 目录结构正确 □ 编译通过
```

**W1-04：配置权限声明**
```
Info.plist：NSMicrophoneUsageDescription
Entitlements：audio-input、accessibility
完成验证：□ 权限弹窗显示自定义文字
```

---

### WEEK 2 · 前端界面全部完成

> 原则：先获取现有前端截图，在此基础上调整，不从零发明

**W2-01：App 基础结构（菜单栏模式）**
```
- 无 Dock 图标，菜单栏常驻
- 菜单栏图标（待机灰色麦克风）
- 点击展开基础菜单（内容见 UI/UX 5.2）
完成验证：□ 菜单栏有图标 □ 菜单可展开 □ 退出正常
```

**W2-02：悬浮圆形按钮**
```
- NSPanel floating 实现（见 TECH_ARCH 第四章）
- 默认右下角，可拖动
- 五种状态样式（见 UI/UX 3.2）
- 支持 Push/Toggle 双模式切换（先写 UI，逻辑 W3 接）
- Push 模式：按住变红，松开恢复（动画先做，功能 W3 接）
- ESC 取消逻辑占位
完成验证：□ 悬浮按钮可见 □ 可拖动 □ 状态切换动画正常
```

**W2-03：状态指示灯**
```
- AppStatus enum 定义5种状态
- 菜单栏图标随状态变化
- 悬浮按钮随状态变化
完成验证：□ 切换状态，图标和按钮同步变化
```

**W2-04：Onboarding 引导（4步）**
```
Step1 欢迎 → Step2 麦克风 → Step3 Accessibility → Step4 登录
- UserDefaults onboarding_done 控制显示
- Step2 按钮请求麦克风权限
- Step3 按钮打开系统设置
- Step4 显示登录选项（UI，逻辑 W4 接）
完成验证：□ 4步流程正常 □ 完成后不再显示
```

**W2-05：登录/注册页**
```
- 4种登录方式 UI（功能 W4 接）
- 邮箱表单（含邮件验证提示界面）
- 忘记密码界面
完成验证：□ 页面可打开 □ 表单样式正确 □ 按钮有 hover 效果
```

**W2-06：设置页**
```
- 触发方式选择（Push/Toggle）
- 热键设置（KeyboardShortcuts 库）
- 开机自启（LaunchAtLogin 库）
- 识别模式（云端/本地）
- 账号信息占位（邮箱 + 用量 + 套餐）
- 翻译模式：PlaceholderToggle
- 清除本地数据按钮（逻辑 W5 接）
- 版本号、隐私政策链接
完成验证：□ 所有 UI 正确 □ 占位组件灰色不可点
```

**W2-07：词典页**
```
Tab1 我的词典：
- 列表（假数据先用）
- 添加词汇弹窗
- 删除功能

Tab2 智能推荐：
- P0 占位内容
- P1 样式提前做好（条件渲染）
完成验证：□ Tab 切换正常 □ 添加/删除假数据正常
```

**W2-08：用量统计页（P1 UI 先做）**
```
- 本月用量进度条
- 升级按钮（占位）
- 用量折线图（假数据）
完成验证：□ 页面样式正确 □ 假数据展示正常

Week 2 里程碑：
□ 所有界面可打开
□ 截图符合 UI/UX 规范
□ 发截图给架构师确认后进入 Week 3
```

---

### WEEK 3 · 主链路后端

**W3-01：热键注册** ✅（已用 CGEventTap 实现，含 VoiceInk 借鉴的状态保护）
```
- ~~KeyboardShortcuts~~ → 改用 CGEventTap（flagsChanged/keyDown/keyUp）
- 支持右 Option（0x3D）、FN/🌐（0x3F + function 位）
- 借鉴 VoiceInk：MIN_HOLD_DURATION 150ms、POST_STOP_COOLDOWN 300ms、UUID 会话防竞态
- 按下 → 延迟启动 → 通知 Pipeline 开始
- 松开 → 通知 Pipeline 结束
- ESC → 通知 Pipeline 取消
- `GlobeKeyHardwareCapabilities` 检测硬件支持
完成验证：□ 热键在其他 App 内有效 □ ESC 触发取消 □ 快速点击不触发（<150ms）
```

**W3-02：麦克风录音** ✅（整段录音方案，流式待评估）
```
- AVAudioEngine 整段录音 → caf 文件
- ~~流式 PCM~~ → 移至待评估（WebSocket ASR 接入时考虑）
- 权限处理
- 借鉴 VoiceInk：`minAudioDurationForASRSeconds` 0.2s，过短音频过滤
完成验证：□ 录音正常启动 □ 权限被拒时正确处理 □ 短按不产生无效录音
```

**W3-03：阿里云 ASR 接入** ✅（Paraformer REST 异步，WebSocket 流式待评估）
```
- ~~DashScope 实时语音识别 WebSocket~~ → 当前为 Paraformer 异步 REST
- 本地 caf 文件识别 → 返回完整文字
- 流式 ASR（WebSocket）待评估，不在当前 Week 范围内
- Token 认证（服务器端管理，不存客户端）
- 联调文档：`DASHSCOPE_SMOKE_TEST.md`
完成验证：□ 说话返回识别文字 □ curl 联调通过
```

**W3-04：WhisperKit 本地降级** ✅
```
- 加载 whisper-base（`Constants.asrFallbackModel`）
- 默认首次后台下载（需网络；`AppState` 提示准备中）；可选将 CoreML 目录嵌入 Bundle：`WhisperModels/<model>/`，见 `WhisperModelLocator` + `Resources/WhisperModels/README.txt`
- 麦克风主路径：本地 caf → Whisper；与 Paraformer 公网 URL 路径并存
完成验证：□ 无网且已嵌入模型时可识别 □ 或联网首次下载成功后可识别
```

**W3-05：VAD 断句缓冲** ✅（已接入 Pipeline；进阶能力见 W4-01）
```
- **当前**：整段 ASR 结果经 `VADBuffer` 再进入润色；主断句边界与「松开按键」一致（Push/Toggle 行为见 `Pipeline`）
- **W4-01（进阶）**：基于**文本流**的 **800ms** 停顿检测，依赖流式 ASR（WebSocket）接入后启用（任务书 Week 4 第一节）
完成验证：□ 整段链路无重复润色异常 □ 松键后一句一润色行为符合预期
```

**W3-06：V2 Prompt 固定层**
```
- §0 + §2 写入 Prompts.swift（仅固定层，不含 §1 占位符）
- `UserProfile` 结构化字段 + `PromptComposer` 将画像拼成自然语言后再与固定层合并
完成验证：□ nil profile 仅 §0+§2 □ 有 profile 时动态层为自然语言段落（非「§1.1」字面量）
```

**W3-07：Qwen 润色接入**
```
- 阿里云 Qwen API 流式
- 超时 5000ms
- 失败返回原始文字
完成验证：□ 流式输出润色结果 □ 超时不崩溃
```

**W3-08：文字注入** ✅（剪贴板方案，借鉴 VoiceInk）
```
- ~~AXUIElement 注入光标~~ → 改用剪贴板方案（VoiceInk/Typeless 策略）
- `TextInjector`：保存 → 注入 → 还原剪贴板
- 借鉴 VoiceInk：`beginProtectedPasteSession()` + `defer endProtectedPasteSession()`
- 目标应用 PID 捕获（`TargetAppMonitor`）后激活再粘贴
- 测试：微信/Slack/VS Code/Safari/备忘录
- 权限缺失引导
完成验证：□ 5个场景均正常注入 □ 剪贴板内容正确还原
```

**W3-09：取消机制**
```
- 录音中 ESC → 清空缓冲，不输出，不写 log
- 悬浮按钮显示短暂 ✕ 后恢复待机
完成验证：□ 取消后无文字输出 □ 无 raw_log 写入
```

**W3-10：改词功能（SelectSpeak）**
```
- AXUIElement 读取选中文字
- 有选中文字时进入改词模式（蓝色按钮）
- 改词专用 Prompt
- 输出替换选中文字
完成验证：□ 选中文字后按钮变蓝 □ 说「改短一点」正确修改
```

**W3-11：主链路串联（Pipeline）**
```
- 串联 W3-01 到 W3-10
- 状态机驱动菜单栏 + 悬浮按钮
- Push/Toggle 双模式切换

Week 3 里程碑：
□ 按住热键/按钮说话，松开文字出现在微信
□ 选中文字说指令，文字被修改
□ ESC 取消无输出
⚠️ 延迟 < 1.5 秒（10次平均）—— **待本机实测，需配置 DASHSCOPE_API_KEY 后测试**
```

**Week 3 · 缺陷修复与工程增强（已落地，2026-03）**

以下条目为迭代中修复或增强点，**任务书原文未逐条列出**，验收与排障时请一并参考：

| 类别 | 内容 |
|------|------|
| **润色空产出** | `PolishService.polishStreaming`：HTTP 非 2xx、`catch`、SSE 结束且无任何 chunk 时，均 **`polishPlain` 兜底**，避免用户无字可看。 |
| **Whisper 阻塞** | 启动时 `Task.detached` 预加载 WhisperKit；`AppState` 提示「本地模式准备中…」；加载结束清空提示。 |
| **剪贴板** | `TextInjector`：`begin` 保存 `NSPasteboard.general.string(forType: .string)`，整段注入 **`defer` 单次 `end`**，不在每个 chunk 后还原。 |
| **状态 / API** | 无 `DASHSCOPE_API_KEY` 时润色退原文 → `AppStatus.attention` + `polishAttentionMessage`；菜单可查看；`AppConfig.hasDashScopeAPIKey`。 |
| **主链路错误** | `Pipeline` 等路径：`catch` 同步 `lastPipelineError` + `.error`（并带自动恢复策略处保持原逻辑）。 |
| **提示音（沙盒）** | `SoundFeedback` 使用 **`AudioServicesPlaySystemSound`**（如 1104/1103/1105），替代 `NSSound(named:)`。 |
| **热键误触 / 卡 processing** | `Constants`：`minHoldDurationSeconds` 0.15、`postStopCooldownSeconds` 0.3、`maxPushRecordingSeconds` 300、`minAudioDurationForASRSeconds` 0.2；Push 延迟启动 + UUID 会话；短按静默取消；空/过短音频不进 ASR；`process` 兜底避免长期停在 `processing`。 |
| **热键实现升级** | **移除 KeyboardShortcuts**，改用 **`CGEventTap`**（`flagsChanged` / `keyDown` / `keyUp`）：右 Option（0x3D）、FN/🌐（0x3F + function 位 + 75ms 防抖）、自定义占位；`AppConfig` 读 Push/Toggle 与绑定模式。 |
| **Globe 硬件** | `GlobeKeyHardwareCapabilities`：非 MacBook 场景设置页禁用 FN/🌐 选项；启动时若曾选 FN 则回退右 Option。 |
| **目标应用 PID** | `TargetAppMonitor`：`captureTargetApp()` → **`getSelectedText()`** → **`FloatingButtonController.showIfNeeded()`**（先捕 PID、再读选区、再显悬浮钮，减少抢焦点）；注入前 **`activateTargetApp()` + 延迟 50ms** 再粘贴。 |
| **性能日志** | `PerformanceTracker`：单行 `[Performance] ASR: … \| Polish: … \| Inject: …`（Polish 段 wall 时间减去各次 `pasteChunk` 累计近似模型段；Inject 为粘贴累计）。 |
| **悬浮钮显示时机** | `FloatingButtonController` 单例 **`showIfNeeded()`**，首次开始录音时再创建/前置，不再仅依赖启动即显示（与 PID 捕获顺序一致）。 |
| **VAD 接入 Pipeline** | `VADBuffer.acceptFinalTranscript` + `Pipeline.deliverASRThroughVADToPolish`；润色前统一经 `onSentenceComplete`；流式 ASR 后可改为多次 `feed` + `flush`。 |

**下一步优先级（角色分工，2026-03）**

| 顺序 | 内容 | 负责 |
|------|------|------|
| 1 | ~~VAD 接入 Pipeline~~ | ✅ Cursor 已落地 |
| 2 | 文档与任务书、架构说明同步现状（热键/CGEventTap、Paraformer、VAD、剪贴板等） | ✅ `VILSAY_TECH_ARCH` v1.3、`DEV_TASKS` v2.0、预检/微架构流程已落盘 |
| 3 | Week 3 里程碑：**本机 10 次平均延迟 &lt; 1.5s**（微信/备忘录等 + 已配置 API） | 开发者本机实测 |
| 4 | 添加 **XCTest** target、关键路径单测 | 可选，不阻塞进度 |
| 5 | **W4-P01～P05** 设置权限、诊断、错误显性化（见下节） | 与账号任务可并行 |

---

### 增补 P0 · 设置 · 权限与诊断（W4-P01～W4-P05）

> **此前是否已安排？** — **未单独列入**旧版任务书。W2-06「设置页」仅覆盖基础 UI；W6-02「边界测试」是**测试清单**，不是设置内产品功能。下列条目为 **Claude 优化热键/权限** 与「可自助排障」的正式排期，**建议与 Week 4 账号任务并行**（优先完成 P01～P02 可显著降低支持成本）。

**W4-P01：权限中心（设置内分项）** 🔲
```
- 必要权限**逐项**展示（当前 P0：麦克风、辅助功能；后续若接入自动化/输入监控等再扩展）。
- 每项：**状态**（已授权 / 未授权 / 未询问）+ **「打开对应系统设置」** 深链（与 `PermissionManager` 统一封装，避免散落 URL）。
- 未授权时视觉强调；提供「重新检测」或回到设置后自动刷新（`NSApplication.didBecomeActiveNotification` 等）。
- 完成验证：□ 用户无需先弹 Alert 也能直达 Privacy_Microphone / Privacy_Accessibility
```

**W4-P02：麦克风试录（设置内）** 🔲
```
- 独立「试录」：短时录音 → 显示时长（可选峰值电平）→ 可选播放试听 → 删除临时文件。
- **不**经过完整 Pipeline（不测润色），用于确认设备与权限。
- **失败显性化（须在 UI 上有固定区域展示，勿仅打日志）**：麦克风被拒、录音引擎启动失败、文件写入失败、**时长低于** `minAudioDurationForASRSeconds` 时，分别给出**可区分**的说明与「去权限设置」入口（链到 P01）。
- 完成验证：□ 上述异常路径均有用户可见文案；□ 成功路径可回放或看到时长
```

**W4-P03：热键自测（设置内，与 Push/Toggle 无关）** 🔲
```
- 「一键测试热键」：进入监听态后，用户按当前绑定（右 ⌥ / FN·🌐），App 收到事件即显示成功（或失败原因：无辅助功能等）。
- 可选：ESC 检测子项（验证 keyDown 路径）。
- **失败显性化**：Tap 未创建、辅助功能未勾选、绑定模式为 `custom` 尚未实现时，**禁止静默**——须在自测面板显示原因与「打开辅助功能」按钮。
- **热键数量说明（现状与规划）**：
  - **当前实现**：`HotkeyBindingMode` **三选一**（右 Option / FN·🌐 / 自定义占位），**同一时间仅一种**物理绑定生效；**不支持**两套键同时触发不同行为。
  - **多键并存**（例如第二套快捷键、或与 Push/Toggle 无关的独立「中止键」）：需单独评审（路由冲突、无障碍、Carbon/CGEventTap 负载），建议 **Backlog** 单独立项，不在 P03 范围内一次做完。
- 完成验证：□ 与当前 `HotkeyManager` 绑定一致；□ 无权限时明确提示而非静默失败
```

**W4-P04：AI 链路分段显式测试（设置内诊断区）** 🔲
```
- **AI1 本地**：对试录文件或内置短样例调用 `WhisperASRFallback`（或当前本地路径），结果展示在只读文本区 + 耗时。
- **AI1 云端**：对**公网可访问**的样例音频 URL 调用 `DashScopeASRClient`（若未配置 Key 则灰显并说明）；与麦克风主路径差异需在 UI 文案中写清。
- **AI2 润色**：固定一句 ASR 假文调用 `PolishService`（流式或 plain），展示输出 + 耗时；无 Key 时展示预期降级提示。
- **端到端**：可选「与主链路相同」按钮，复用 `Pipeline` 子集或完整流程（需明确是否写入目标 App，建议诊断区仅剪贴板或只读展示）。
- **「成功 / 失败」都要可测**：分段测试不仅要验证**正常返回**，还要覆盖并**显性展示**：API Key 缺失、DashScope HTTP 非 2xx、请求超时、**无网络 / 弱网**（与 `NetworkMonitor` 联动文案）、Whisper 模型未就绪、转写结果为空、音频过短等；每种情况在诊断区有**独立状态行或结果框**，避免与「正常结果」混为一谈。
- 完成验证：□ 各按钮独立可测；□ 识别模式（本地/云端）切换后标签与实测路径一致；□ 上述异常均有用户可读说明（可复制更佳）
```

**W4-P05：主链路错误与弱网显性化（设置 + 全局一致）** 🔲
```
- **目标**：主路径（非仅诊断区）中，录音失败、过短被丢弃、API 不可用、润色失败、目标 App 无法激活等，均转化为**用户看得见**的反馈；与菜单栏已有 `lastPipelineError` / `polishAttentionMessage` **文案与展示位置统一**（设置页可增加「最近一次问题」摘要 + 清除/复制）。
- **网络**：在适当时机提示「当前无网络，云端能力不可用」等（避免与本地 Whisper 路径矛盾）；具体触发点与 `NetworkMonitor` 对齐。
- **与 P02～P04 关系**：诊断区验证异常分支；P05 保证**正式使用**时同等清晰，避免「只有诊断里才看得见」。
- 完成验证：□ 抽样模拟各失败类型，设置或菜单均有明确提示；□ 无仅控制台日志而无 UI 的情况（DEBUG 可额外打日志）
```

**微架构**：领取本组任务前，在 `micro-arch/Week4_MICRO_ARCH.md`（或单独 `Week4P_DIAGNOSTICS.md`）中写明：`SettingsRootView` 新增 Section 结构、是否新建 `DiagnosticsViewModel`、与 `PermissionManager`/`Pipeline` 的调用边界；**错误文案**是否集中 `UserFacingError` 枚举或本地化表。

---

### WEEK 4 · 账号体系

**W4-01：VAD 断句缓冲（从 W3 移至 Week 4）**
```
前置依赖：流式 ASR（WebSocket）接入
- 基于文本流检测 800ms 停顿
- 触发后传给 AI2 润色
- 当前状态：代码存在，待 WebSocket ASR 接入后启用
完成验证：□ 停顿触发，连续说话不误触发
```

**W4-02：后端 API 搭建（基础版）**
```
- 选定技术栈（Node.js 或 Python，参考 TECH_ARCH）
- 搭建基础框架
- 数据库：PostgreSQL 建表（users/sessions/usage）
- 部署到自有服务器
完成验证：□ API 可访问 □ 数据库连接正常
```

**W4-03：邮箱注册/登录**
```
客户端：
- 邮箱+密码表单接入真实 API
- 发送验证邮件提示
- 错误处理（邮箱已注册/密码错误）

服务端：
- POST /auth/register（发验证邮件）
- POST /auth/login（返回 JWT）
- GET /auth/verify-email（验证链接）

完成验证：□ 注册收到验证邮件 □ 登录返回 Token □ App 内状态更新
```

**W4-04：Apple ID 登录**
```
- Sign in with Apple（客户端）
- POST /auth/apple（服务端验证）
完成验证：□ 弹出 Apple 授权界面 □ 登录成功
```

**W4-05：微信登录**
```
- 微信开放平台 OAuth（需申请资质，可能审核周期长）
- 如审核未通过先跳过，其他3种先上
完成验证：□ 微信授权正常 OR □ 标注为待上线
```

**W4-06：Google 登录**
```
- Google OAuth 2.0
- POST /auth/google
完成验证：□ Google 授权正常 □ 登录成功
```

**W4-07：用量统计**
```
客户端：
- 每次润色完成后 POST /usage/record
- 设置页显示实时用量

服务端：
- POST /usage/record（记录一次）
- GET /usage/current（返回本月用量）
- 免费额度限制逻辑

完成验证：□ 用量正确计数 □ 超额提示升级
```

**W4-08：订阅计费（基础版）**
```
- 套餐配置
- 超额拦截（App 内提示）
- 升级按钮跳转（跳转网站或内购，待定）
完成验证：□ 超额时正确提示 □ 免费额度正确

Week 4 里程碑：
□ 4种登录方式均可用（微信可延后）
□ 用量统计准确
□ 超额正确拦截
□ （建议）W4-P01～P05：权限、试录、热键与 AI 分段验证，**含异常分支显性提示**；主链路错误与弱网提示（P05）
```

---

### WEEK 5 · AI3 + 数据层

**W5-01：本地 SQLite 初始化**
```
- GRDB 建库
- 创建所有表（见 TECH_ARCH 第八章）
- 迁移管理
完成验证：□ App 启动自动建库 □ 表结构正确
```

**W5-02：RawLogger 接入**
```
- Pipeline 润色完成后异步写入 raw_log
- 取消时不写入
完成验证：□ 说5句写5条 □ 取消不写入 □ 主链路无延迟影响
```

**W5-03：词典数据库接入**
```
- 词典页从 SQLite 读写（替换假数据）
完成验证：□ 添加词条重启后仍在 □ 删除正确
```

**W5-04：AnalyzerTrigger 计数**
```
- 计数满20触发 AI3
完成验证：□ 说20句触发 □ 再说20句再触发
```

**W5-05：AI3Analyzer**
```
- 读取最近50条 raw_log
- 调用 Qwen 分析（开发者 Key）
- 差异对比更新 profile
- 推荐词写入 candidates
完成验证：□ 人工检查 Profile 质量合理 □ 候选词出现
```

**W5-06：PromptComposer 动态注入**
```
- 有 profile → 注入 §1
- 无 profile → 只用固定层
完成验证：□ 润色质量有可感知提升（第20次 vs 第1次对比）
```

**W5-07：词典推荐 UI 接入**
```
- Tab2 替换占位为真实数据
- 加入/忽略操作接入数据库
- 角标数字实时更新
完成验证：□ 推荐词正确显示 □ 加入后在 Tab1 出现 □ 角标正确
```

**W5-08：清除数据接入**
```
- 清除 raw_log/profile/candidates
- 保留 dictionary
- 重置 analyzer_state
完成验证：□ 清除后数据库对应表为空 □ 手动词典保留

Week 5 里程碑：
□ AI3 完整跑一次，Profile 质量通过人工验证
□ 润色输出有可感知改善
```

---

### WEEK 6 · 打磨 + 上架准备

**W6-01：性能验证（死亡线）**
```
□ 松开热键到文字出现 < 1.5 秒（10次平均）
□ App 内存 < 100MB（待机）
□ 录音时 CPU < 20%
```

**W6-02：边界场景测试**
```
□ 断网完整流程
□ 权限拒绝处理
□ 说空话（纯停顿）
□ 极长句子（> 200字）
□ 纯英文 / 中英混合
□ 在不支持注入的 App（终端等）
□ 快速连续触发
□ Push/Toggle 模式切换
□ 改词后再改词
□ 未登录状态触发
```

**W6-03：App Store 材料**
```
□ App 图标 1024×1024
□ macOS 截图（至少3张）
□ App 名：Vilsay
□ 副标题：说话，比打字更快
□ 描述文案（中文，500字以内）
□ 关键词
□ 隐私政策 URL（有效链接）
□ 年龄分级：4+
□ 类别：效率工具
```

**W6-04：隐私政策页面**
```
内容：见 PRD 第七章数据说明
部署：官网 /privacy
语言：中英双语
```

**W6-05：TestFlight 内测**
```
□ 上传 Build
□ 添加内测用户
□ 内测1周
□ 修复 Bug
□ 提交正式审核
```

---

### WEEK 7+ · 官网（可并行）

**W7-01：Next.js 项目初始化**
```
- 创建 Next.js 项目
- Tailwind CSS 配置
- 部署到服务器
```

**W7-02：首页（Landing）**
```
- Hero + 产品演示 GIF
- 功能亮点4个
- 定价表格（PRD-SUP-001 完成后）
- 下载按钮（App Store 链接）
```

**W7-03：文档页**
```
- 快速开始
- 功能说明
- 常见问题
```

**W7-04：用量面板（需登录）**
```
- 用量折线图（调后端 API）
- 订阅管理
- 账号设置
```

**W7-05：法律页面**
```
- 隐私政策
- 服务条款
- 数据说明（参考 flowkeyboard.com/data-controls.html）
```

---

## 四、任务完成状态

| Task | 名称 | 状态 | 完成日期 |
|------|------|------|---------|
| W1-01 | 创建项目 | ✅ | 2026-03-22 |
| W1-02 | SPM 依赖 | ✅ | 2026-03-22 |
| W1-03 | 目录结构 | ✅ | 2026-03-22 |
| W1-04 | 权限声明 | ✅ | 2026-03-22 |
| W2-01 | 菜单栏结构 | ✅ | 2026-03-22 | Kimi 测试通过 |
| W2-02 | 悬浮按钮 | ✅ | 2026-03-22 | Kimi 测试通过 |
| W2-03 | 状态指示灯 | ✅ | 2026-03-22 | Kimi 测试通过 |
| W2-04 | Onboarding | ✅ | 2026-03-22 | Kimi 测试通过 |
| W2-05 | 登录注册页 | ✅ | 2026-03-22 | Kimi 测试通过 |
| W2-06 | 设置页 | ✅ | 2026-03-22 | Kimi 测试通过 |
| W2-07 | 词典页 | ✅ | 2026-03-22 | Kimi 测试通过 |
| W2-08 | 用量统计页 | ✅ | 2026-03-22 | Kimi 测试通过 |
| W3-01 | 热键注册 | ✅ | 2026-03-22 |
| W3-02 | 麦克风录音 | ✅ | 2026-03-22 |
| W3-03 | 阿里云 ASR | ✅ | 2026-03-22 | Paraformer 异步 REST 已接；本地录音走 Whisper，联调见 `VILSAY_PHASE1_3_NOTES.md` |
| W3-04 | WhisperKit 降级 | ✅ | 2026-03-22 |
| W3-05 | VAD 断句 | ✅ | 2026-03-22 | 当前断句边界=松开按键；800ms 文本 VAD 待流式 ASR |
| W3-06 | V2 Prompt | ✅ | 2026-03-22 |
| W3-07 | Qwen 润色 | ✅ | 2026-03-22 |
| W3-08 | 文字注入 | ✅ | 2026-03-22 |
| W3-09 | 取消机制 | ✅ | 2026-03-22 |
| W3-10 | 改词功能 | ✅ | 2026-03-22 |
| W3-11 | 主链路串联 | ✅ | 2026-03-22 |
| W4-01 | VAD 文本流 800ms（流式 ASR 前置；与正文 WEEK 4 · W4-01 一致） | 🔲 | - |
| W4-02 | 后端 API 搭建 | 🔲 | - |
| W4-03 | 邮箱注册/登录 | 🔲 | - |
| W4-04 | Apple 登录 | 🔲 | - |
| W4-05 | 微信登录 | 🔲 | - |
| W4-06 | Google 登录 | 🔲 | - |
| W4-07 | 用量统计 | 🔲 | - |
| W4-08 | 订阅计费 | 🔲 | - |
| W4-P01 | 设置 · 权限中心（分项深链；增补 P0，可与 W4-02～并行） | 🔲 | - |
| W4-P02 | 设置 · 麦克风试录 | 🔲 | - |
| W4-P03 | 设置 · 热键自测 | 🔲 | - |
| W4-P04 | 设置 · AI1/2 分段诊断（含 API/网络/过短等失败显性） | 🔲 | - |
| W4-P05 | 主链路错误与弱网显性化（与菜单状态统一） | 🔲 | - |
| W5-01 | SQLite 初始化 | 🔲 | - |
| W5-02 | RawLogger | 🔲 | - |
| W5-03 | 词典数据库 | 🔲 | - |
| W5-04 | AnalyzerTrigger | 🔲 | - |
| W5-05 | AI3Analyzer | 🔲 | - |
| W5-06 | PromptComposer | 🔲 | - |
| W5-07 | 词典推荐 UI | 🔲 | - |
| W5-08 | 清除数据 | 🔲 | - |
| W6-01 | 性能验证 | 🔲 | - |
| W6-02 | 边界测试 | 🔲 | - |
| W6-03 | 上架材料 | 🔲 | - |
| W6-04 | 隐私政策 | 🔲 | - |
| W6-05 | TestFlight | 🔲 | - |
| W7-01~05 | 官网 | 🔲 | - |

状态：🔲 未开始 | 🔄 进行中 | ✅ 完成 | ❌ 阻塞

---

## 五、未知风险登记表

> 开发中遇到新问题在此登记，不让问题消失

| # | 发现日期 | 问题描述 | 影响范围 | 处理状态 |
|---|---------|---------|---------|---------|
| R1 | 2026-03-22 | Paraformer REST 仅支持公网 URL，本地 caf 不能直接提交 | 云端 ASR 与麦克风录音统一 | 已说明：日常走 Whisper；后续 WebSocket/OSS 见 `VILSAY_PHASE1_3_NOTES.md` |
| R2 | 2026-03-22 | FN/地球仪键需 CGEventTap | 热键「推荐」模式 | ✅ **已实现**：`HotkeyManager` + CGEventTap；无硬件时设置页禁用 FN/🌐 |
| R3 | 2026-03-22 | Xcode + Cursor 同改 `pbxproj` 易冲突 | 工程文件 | 关 Xcode 再改 或 以磁盘为准 |
| R4 | 2026-03-22 | W3-03 阿里云 ASR 占位实现（返回 nil），需 WebSocket 流式 | 与任务书要求不符 | ✅ **已解决**：REST 异步任务已接，curl 联调文档已提供 |
| R5 | 2026-03-22 | W3-07 Qwen 润色同步调用，需 SSE 真正流式 | 与任务书要求不符 | ✅ **已解决**：SSE 真流式实现，逐 token yield |
| R6 | 2026-03-22 | W3-08 文字注入剪贴板方案，需 AXUIElement 直接注入 | 与任务书要求不符 | ✅ **已解决**：剪贴板保护方案，保存→注入→还原 |
| R7 | 2026-03-22 | Week 3 延迟测试未完成，未测量 10 次平均延迟 | 无法验证里程碑 | ⏳ **待测试**：配置 API Key 后测量 10 次平均延迟 |
| - | - | （新发现可续行）| - | - |

---

## 六、里程碑验收节点

```
Week 2 结束：✅ 所有界面截图符合规范 → 架构师确认
Week 3 结束：⚠️ **风险点已修复，待延迟测试验证** → W3-07真流式✅、W3-08剪贴板保护✅、W3-03ASR✅、延迟测试待配置API Key后测量
Week 4 结束：4种登录可用，用量统计准确
Week 5 结束：AI3 一次完整分析通过人工验证
Week 6 结束：TestFlight 内测通过 → 提交审核
```

---

## 七、变更记录

| 版本 | 日期 | 变更内容 |
|------|------|---------|
| 1.0 | 2026-03-22 | 初始版本 |
| 1.1 | 2026-03-22 | 新增悬浮按钮、改词、取消、账号体系、官网任务 |
| 1.2 | 2026-03-22 | W2-01～W2-03 菜单栏 + 悬浮按钮 + 状态同步（代码在 `vilsay/`） |
| 1.3 | 2026-03-22 | W2-04～W2-08：Onboarding 窗口、`ContentView` Tab（设置/词典/用量）、`LoginView` sheet、`SettingsRootView`、`DictionaryView`、`UsageStatsView` |
| 1.4 | 2026-03-22 | Week 3 主链路：`Pipeline`、`HotkeyManager`、`AudioCapture`、`WhisperASRFallback`、`PolishService`、`TextInjector`、`SelectSpeakService`、`DashScopeASRClient`（占位） |
| 1.5 | 2026-03-22 | 前三阶段收尾：`vilsay.entitlements` 恢复、`DashScopeASRClient` Paraformer 异步任务、设置页说明、新增 `docs/status/VILSAY_PHASE1_3_NOTES.md`、风险表更新 |
| 1.6 | 2026-03-22 | `PromptComposer` + `UserProfile` 结构化、`Prompts` 仅固定层；任务查询 POST/GET；`API_KEYS_AND_SECRETS.md`；`VILSAY_TECH_ARCH` §9 补充 |
| 1.7 | 2026-03-22 | **Week 3 风险点处理计划**：创建 `WEEK3_RISK_RESOLUTION_PLAN.md`；R4-R7 风险登记；明确流式 ASR、流式润色、AX注入、延迟测试需在 Week 3 完成，不推迟到后续版本 |
| 1.8 | 2026-03-22 | **Week 3 风险点修复完成**：W3-07 SSE 真流式 Qwen、W3-08 剪贴板保护、W3-03 Paraformer REST + `DASHSCOPE_SMOKE_TEST.md`；风险 R4-R6 标记已解决，R7 待延迟测试 |
| 1.9 | 2026-03-22 | **Week 3 任务状态更新**：W3-01 标注 CGEventTap 实现、W3-02 标注整段录音、W3-03 标注 WebSocket 待评估、W3-05 移至 W4-01、W3-08 标注剪贴板方案；里程碑标注待实测 |
| 2.0 | 2026-03-22 | **§2.1 微架构门禁**；修正 **W4-01～W4-08** 与正文 WEEK 4 一致；**W3-04/W3-05** 与实现对齐（Whisper 包内路径、VAD 已接入）；**R2** 关闭；索引增加预检与 `docs/spec` 路径；同步 `VILSAY_TECH_ARCH` v1.3 |
| 2.1 | 2026-03-22 | 补 **`micro-arch/Week1～Week3_MICRO_ARCH.md`**（追认版，待确认人签字） |
| 2.2 | 2026-03-22 | **增补 W4-P01～P04**：设置内权限分项深链、试录、热键自测、AI1/2 本地云端分段诊断；里程碑与任务表已列 |
| 2.3 | 2026-03-22 | **W4-P05** 主链路错误/弱网显性化；P02～P04 补充失败分支与文案；P03 写明**单热键绑定**现状与多键 Backlog |

---

## 八、第 1～3 阶段交付与文档索引

- **交付说明、环境变量、已知边界**：[`VILSAY_PHASE1_3_NOTES.md`](VILSAY_PHASE1_3_NOTES.md)（与本文件同级 `docs/status/`）
- **API Key 与安全**：[`API_KEYS_AND_SECRETS.md`](API_KEYS_AND_SECRETS.md)
- **技术架构**：[`docs/spec/VILSAY_TECH_ARCH.md`](../spec/VILSAY_TECH_ARCH.md)
- **每周微架构门禁**：[`WEEKLY_MICRO_ARCH_PROCESS.md`](WEEKLY_MICRO_ARCH_PROCESS.md) · 落盘目录 [`micro-arch/`](micro-arch/) · **Week 1～3 追认**：[Week1](micro-arch/Week1_MICRO_ARCH.md) / [Week2](micro-arch/Week2_MICRO_ARCH.md) / [Week3](micro-arch/Week3_MICRO_ARCH.md)
- **本机预检与排障**：[`PREFLIGHT_AND_TROUBLESHOOTING.md`](PREFLIGHT_AND_TROUBLESHOOTING.md)
- **工程入口与 SPM**：仓库根目录 [`CLAUDE.md`](../../CLAUDE.md)

---
# 文档结束
# 每完成一个 Task 标注 ✅ 和日期
# 遇到阻塞在未知风险表登记
