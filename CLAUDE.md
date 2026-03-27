# Vilsay · 文档索引

**说明：** 正文均在 `docs/` 下对应分类目录中；本文件仅作路径指针，不包含规约正文。

**文件存放规则（给全体开发）：** 请先读 **[`docs/REPO_FILE_LAYOUT.md`](docs/REPO_FILE_LAYOUT.md)**（仓库目录、`docs/` 与源码树分工、禁止在 `vilsay/vilsay/` 堆 Markdown 长文）。代码模块树细节见 **`docs/spec/VILSAY_TECH_ARCH.md`** 第三章。

| Cursor 完整指引 | [docs/CURSOR_DEV_TASKS.md](docs/CURSOR_DEV_TASKS.md)（根目录 `CURSOR_DEV_TASKS.md` 为指针） |

---

## `docs/spec/` · 规约（开发须遵守）

| 文件 |
|------|
| [docs/spec/VILSAY_ARCHITECTURE.md](docs/spec/VILSAY_ARCHITECTURE.md) |
| [docs/spec/VILSAY_TECH_ARCH.md](docs/spec/VILSAY_TECH_ARCH.md) |
| [docs/spec/VILSAY_UI_UX.md](docs/spec/VILSAY_UI_UX.md) |
| [docs/spec/voice_polish_prompt.md](docs/spec/voice_polish_prompt.md) |
| [docs/spec/HOTKEY_ARCHITECTURE.md](docs/spec/HOTKEY_ARCHITECTURE.md) · 热键专项架构（与总架构互补） |

## `docs/` 根目录 · 专项补充

| 文件 |
|------|
| [docs/VILSAY_TECH_SPEC_SUPPLEMENT.md](docs/VILSAY_TECH_SPEC_SUPPLEMENT.md) · 技术规范补充（目标架构与**附录 A：当前实现对照**） |

---

## `docs/status/` · 现状（任务与测试）

| 文件 |
|------|
| [docs/status/VILSAY_DEV_TASKS.md](docs/status/VILSAY_DEV_TASKS.md) |
| [docs/status/WEEKLY_MICRO_ARCH_PROCESS.md](docs/status/WEEKLY_MICRO_ARCH_PROCESS.md) · **每周开工前**开发与架构对齐（微架构门禁） |
| [docs/status/micro-arch/](docs/status/micro-arch/) · `WeekN_MICRO_ARCH.md` 落盘 |
| [docs/status/PREFLIGHT_AND_TROUBLESHOOTING.md](docs/status/PREFLIGHT_AND_TROUBLESHOOTING.md) · 本机预检与排障 |
| [docs/status/VILSAY_PHASE1_3_NOTES.md](docs/status/VILSAY_PHASE1_3_NOTES.md) · 第 1～3 阶段交付、环境变量、已知边界 |
| [docs/status/PHASE_PROGRESS_2026_03_25.md](docs/status/PHASE_PROGRESS_2026_03_25.md) · 阶段进度（热键模式、百炼/润色、测试） |
| [docs/status/WEEK4_CURSOR_TASKS.md](docs/status/WEEK4_CURSOR_TASKS.md) · **Week 4 Cursor 任务书**：**10** 个可执行任务（**客户端 4** + **服务端 6**）+ **生产上线清单**（`W4-PROD-01`） |
| [docs/status/WEEK5_6_CURSOR_TASKS.md](docs/status/WEEK5_6_CURSOR_TASKS.md) · **Week 5+6 Cursor 任务书**：W5（AI3+DB，8任务）+ W6（打磨+上架，5任务）+ Week7（Onboarding+官网） |
| [docs/status/WEEK4_KIMI_TEST_GUIDE.md](docs/status/WEEK4_KIMI_TEST_GUIDE.md) · **Week 4 Kimi 测试指南**（A～G 类，含里程碑验收清单）|
| [docs/status/WEEK5_6_KIMI_TEST_GUIDE.md](docs/status/WEEK5_6_KIMI_TEST_GUIDE.md) · **Week 5+6 Kimi 测试指南**（V3 Prompt 效果验证 + AI3 数据链路 + 浮层 Pill + 闭环反馈 + Review 修复回归，24 项测试）|
| [docs/status/WEEK5_6_AUTO_TEST_TASKS.md](docs/status/WEEK5_6_AUTO_TEST_TASKS.md) · **Week 5+6 自动化测试任务书**：8 套测试（50 用例），Swift Testing + 内存 GRDB，`xcodebuild test` 全自动执行 |
| [docs/status/WEEK7_CURSOR_TASKS.md](docs/status/WEEK7_CURSOR_TASKS.md) · **Week 7 Cursor 任务书**：W7-A（Onboarding 完整实现，10 任务）+ W7-B（产品官网 Next.js，8 任务） |
| [docs/status/WEEK6_7_IMPLEMENTATION_AND_REMAINING.md](docs/status/WEEK6_7_IMPLEMENTATION_AND_REMAINING.md) · **Week 6～7 实现汇总与未完成项**（与附录 A 同步） |
| [docs/status/PROMPT_TUNING_100_TESTS.md](docs/status/PROMPT_TUNING_100_TESTS.md) · **Prompt 调优 100 测试**：8 类 100 用例，真实 Qwen API 调用，验证 V3 五层 Prompt 效果 |
| [docs/status/FIX_CORE_PIPELINE.md](docs/status/FIX_CORE_PIPELINE.md) · **核心链路修复**：FIX-P01~P06，API Key 加载 + 润色/AI3 失败可见化 + 设置页 Key 输入 + AI3 手动触发 |
| [docs/status/ACCURACY_ENHANCEMENT_TASKS.md](docs/status/ACCURACY_ENHANCEMENT_TASKS.md) · **准确率增强**：ACC-P0~P2，Per-App 上下文缓冲 + ASR 错误映射 + AI3 分应用分析 + 用户反馈闭环（11 任务） |
| [docs/status/PROMPT_V4_OUTPUT_MODE_TASKS.md](docs/status/PROMPT_V4_OUTPUT_MODE_TASKS.md) · **Prompt V4 OutputMode 架构**：PM-01~PM-11，按目标应用切换输出模式（AI指令/聊天/邮件/文档/笔记），闭环学习 |
| [docs/status/PROMPT_TUNING_FRAMEWORK.md](docs/status/PROMPT_TUNING_FRAMEWORK.md) · **Prompt 调优框架**：LLM-as-Judge 评估引擎，33 用例，5 维评分，A/B 对比，多方协作调优 |
| [docs/status/W4_01_STREAMING_ASR_CURSOR_TASKS.md](docs/status/W4_01_STREAMING_ASR_CURSOR_TASKS.md) · **W4-01 WebSocket 流式 ASR**（AudioCapture 重写 + StreamingClient + Pipeline 路由）|
| [docs/status/API_KEYS_AND_SECRETS.md](docs/status/API_KEYS_AND_SECRETS.md) · API Key 与安全（勿入库） |
| [docs/status/HOTKEY_FN_COMBO_DETECTION_TASK.md](docs/status/HOTKEY_FN_COMBO_DETECTION_TASK.md) · 热键 Fn 组合键与自检任务 |
| [docs/status/KIMI_TEST_GUIDE.md](docs/status/KIMI_TEST_GUIDE.md) |
| [docs/status/KIMI_TEST_LOG.md](docs/status/KIMI_TEST_LOG.md) |
| [docs/status/BACKEND_TEST_REPORT.md](docs/status/BACKEND_TEST_REPORT.md) |
| [docs/status/DIAGNOSTIC_LOG.md](docs/status/DIAGNOSTIC_LOG.md) |
| [docs/status/CONFIGURATION_COMPLETE.md](docs/status/CONFIGURATION_COMPLETE.md) |
| [docs/status/SETUP_API_KEY.md](docs/status/SETUP_API_KEY.md) |

---

## `docs/design/` · UI 设计参考

| 文件 | 说明 |
|------|------|
| [docs/design/UI_DESIGN_COMPARISON.md](docs/design/UI_DESIGN_COMPARISON.md) | Vilsay vs Sugar Theme 详细对比 |
| [docs/design/UI_SUGAR_THEME_QUICK_REF.md](docs/design/UI_SUGAR_THEME_QUICK_REF.md) | Sugar Theme Token 快速参考 |

---

## `docs/status/` · 风险与计划（节选）

| 文件 | 说明 |
|------|------|
| [docs/status/WEEK3_RISK_RESOLUTION_PLAN.md](docs/status/WEEK3_RISK_RESOLUTION_PLAN.md) | Week 3 风险点处理计划（分析） |
| [docs/status/WEEK3_FIX_INSTRUCTIONS.md](docs/status/WEEK3_FIX_INSTRUCTIONS.md) | Week 3 修复指令（给 Cursor） |

## `docs/` · 联调测试

| 文件 | 说明 |
|------|------|
| [docs/DASHSCOPE_SMOKE_TEST.md](docs/DASHSCOPE_SMOKE_TEST.md) | DashScope API curl 联调文档 |

## `docs/` · 热键专项（补充材料，根目录）

| 文件 | 说明 |
|------|------|
| [docs/HOTKEY_FIX_SUMMARY.md](docs/HOTKEY_FIX_SUMMARY.md) | 热键修复摘要 |
| [docs/HOTKEY_RELEASE_DEBUG_REPORT.md](docs/HOTKEY_RELEASE_DEBUG_REPORT.md) | 发布/调试排障 |
| [docs/PERMISSIONS_OPTIMIZATION_REPORT.md](docs/PERMISSIONS_OPTIMIZATION_REPORT.md) | 权限相关说明 |

> 架构规约见 **`docs/spec/HOTKEY_ARCHITECTURE.md`**，开发任务见 **`docs/status/HOTKEY_FN_COMBO_DETECTION_TASK.md`**（已列入上表 `spec` / `status`）。

---

## `docs/log/` · 历史 / 上游（按需查阅）

| 文件 |
|------|
| [docs/log/VILSAY_PRD.md](docs/log/VILSAY_PRD.md) |
| [docs/log/VILSAY_ONBOARDING.md](docs/log/VILSAY_ONBOARDING.md) |
| [docs/log/voice_ai_architecture.md](docs/log/voice_ai_architecture.md) |

---

## `docs/CLAUDE.md` · Cursor 开发初始化（原文）

| 文件 |
|------|
| [docs/CLAUDE.md](docs/CLAUDE.md) |

---

## `docs/files/` · 你提供的源副本（可保留作备份）

与 `docs/spec|status|log/` 中同名文件内容一致（由 `cp` 同步）。

---

## macOS 工程（Xcode）

| 说明 | 路径 |
|------|------|
| Xcode 工程 | `vilsay/vilsay.xcodeproj` |
| 源码与资源 | `vilsay/vilsay/` |
| Scheme | `vilsay` |

首次打开请在 Xcode 中 **File → Packages → Resolve Package Versions**，待 SPM 拉取完成后 **⌘B** 编译。

### Xcode 长时间转圈是否正常？

- **Updating WhisperKit / Indexing**：WhisperKit 依赖多，**首次解析与索引 10～30 分钟** 都常见，只要 Activity 里仍在下载/编译即非卡死。  
- **不要重复点 Build**：会提示 “A build action is already running”，等当前任务结束或 **`⌘ + .`** 取消后再试。  
- 首次成功后建议在 Xcode 中 **File → Packages → Resolve**，然后将生成的 **`Package.resolved`**（在 `vilsay.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/`）**提交到 Git**，他人打开工程可少拉依赖。  
- 菜单栏图标旁 **「调试（验收用）」** 仅用于切换状态/角标，正式发版前可移除或隐藏。

### 应用入口与菜单（避免重复 `@main`）

- **唯一 `@main`**：`vilsay/vilsay/vilsayApp.swift`。本 target **不得**再出现第二个带 `@main` 的文件（例如 Xcode 默认模板里的 **`App.swift`**）。若你本地存在 **`App.swift`** 且编译报「duplicate main」或调用了不存在的 **`AppState.shared.createMenus()`**：**删除该 `App.swift` 全文**即可。  
- 菜单栏不是 `NSMenu` + `createMenus()`，而是由 **`MenuBarExtra`** + **`UI/MenuBarRootMenu.swift`** 构建；`AppState` **没有** 也不应添加 `createMenus()`。  
- 需要 NSApplication 生命周期时只用 **`App/AppDelegate.swift`**（已通过 `@NSApplicationDelegateAdaptor` 接入）。

### SPM 依赖说明（非多余）

`WhisperKit`、`GRDB`、`KeyboardShortcuts`、`LaunchAtLogin` 均在规约与任务书中有对应 Week（见 `vilsay/Config/DependenciesSmoke.swift` 顶部注释）。**W3 之前**可仅在 `DependenciesSmoke.noop()` 中保持链接，**不要**为「减负」随意移除，否则后续任务要重新接 SPM。

---

**项目：** Vilsay · macOS 原生语音润色 App · Swift / SwiftUI / macOS 14+
