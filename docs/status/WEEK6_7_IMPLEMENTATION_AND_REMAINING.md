# Week 6～7 · 实现汇总与未完成项

**日期**：2026-03-26  
**作用**：对照 `WEEK5_6_CURSOR_TASKS.md`、`WEEK7_CURSOR_TASKS.md` 与当前仓库，便于评审与排期。  
**技术对照**：`docs/VILSAY_TECH_SPEC_SUPPLEMENT.md` 附录 A（已同步刷新）。

---

## 一、已在客户端落地的 Week 6 / 7 条目

| 任务 | 说明 |
|------|------|
| **W6-01** | 悬浮胶囊：波形、取消、处理中 Spinner、「思考中…」、完成预览、**「有误」→ ErrorFeedback、改词模式蓝条「听指令…」**（`FloatingButtonView` / `FloatingButtonController`） |
| **W6-02** | 菜单栏多状态图标、`MenuBarRootMenu` **停止录音 / 取消**（原已具备，持续迭代） |
| **W6-03（可观测）** | `PerformanceTracker.logPipeline` 输出 **Total ms**，超过 `Constants.maxTotalLatencyMs`（1500）时 **Logger warning**，便于本机对照死亡线 |
| **W6-04（自动化子集）** | `vilsayTests/W6BoundaryTests.swift`：用量请求体 snake_case、Onboarding 续步、浮层预览常量、延迟预算 |
| **W6-06** | App 内 **隐私政策**（`SettingsRootView` → `PrivacyPolicyView` sheet） |
| **W6（上架辅助）** | `Info.plist`：`ITSAppUsesNonExemptEncryption`（按实际加密使用情况核对） |
| **W7-A01～A03/A05～A07/A09～A10** | 引导 **断点续传**（`OnboardingResume`）、权限轮询 UI、`AppDelegate` **restoreSession + didBecomeActive 权限重检**、Timer 清理、**`OnboardingTests`** |
| **W7-A04** | 登录步 **跳过登录**；OAuth 按钮接 `OAuthSignInCoordinator`；邮箱 `LoginView` sheet |
| **W7-B（骨架）** | `website/`：Next.js App Router、首页/文档/定价/隐私/条款、`DownloadMacButton` 全站 **`/#download`** |

---

## 二、仍以人工 / 流程为主的项

| 任务 | 说明 |
|------|------|
| **W6-03** | **实测**：不同机型上 ASR+润色+注入是否在 1500ms 目标内；以 Console `Performance` 日志为准 |
| **W6-04** | 多语言、Whisper 降级、弱网等 **真机场景**；文档化已知问题 |
| **W6-05** | App Store **截图、描述、关键词** |
| **W6-07** | **TestFlight / 商店提交**、出口合规问卷与 **Info.plist 加密声明**一致 |
| **W7-B** | 域名部署、`npm run build` CI、**真实 demo.gif / og-image**、Mac App Store **最终 URL** |
| **vilsayUITests** | 菜单栏依赖环境：不作为默认 CI 门禁（见 `PHASE_PROGRESS_2026_03_25.md`） |

---

## 三、规约级中长期项（非本周必完）

- **自建润色代理**（密钥不驻客户端）
- **统一 `AppError` + 服务端错误 JSON 契约**（`VILSAY_TECH_SPEC_SUPPLEMENT` 第五、六章）
- **流式 ASR + VAD** 与第一章目标态完全对齐
- **OAuth / 邮件** 生产级配置与回归清单

详见 **`docs/VILSAY_TECH_SPEC_SUPPLEMENT.md` 附录 A**。

---

## 四、推荐验收命令

```bash
# 单元 / 边界 / Onboarding（不含 UI、不含真实 DashScope 长套件）
cd vilsay
xcodebuild -scheme vilsay -destination 'platform=macOS' \
  test -only-testing:vilsayTests/W6BoundaryTests \
  -only-testing:vilsayTests/OnboardingTests
```

```bash
# 官网（需本机 Node）
cd website && npm install && npm run build
```

**调优全量报告**（需 `DASHSCOPE_API_KEY`）：`TuningIntegrationTests/fullSuiteWithReport` 优先写 `Desktop/VilsayTuningReports`；**失败时自动落到系统临时目录**（避免沙盒/权限导致整包测试红）。

---

## 五、相关文档索引

| 文档 | 用途 |
|------|------|
| [WEEK5_6_CURSOR_TASKS.md](WEEK5_6_CURSOR_TASKS.md) | W5+W6 任务原文 |
| [WEEK7_CURSOR_TASKS.md](WEEK7_CURSOR_TASKS.md) | W7 Onboarding + 官网任务原文 |
| [PHASE_PROGRESS_2026_03_25.md](PHASE_PROGRESS_2026_03_25.md) | 阶段进度与单测门禁说明 |
| [VILSAY_EXCLUSION_DIAGNOSTICS.md](VILSAY_EXCLUSION_DIAGNOSTICS.md) | 崩溃二分环境变量 |
| [VILSAY_TECH_SPEC_SUPPLEMENT.md](../VILSAY_TECH_SPEC_SUPPLEMENT.md) | 规约补充 + **附录 A** |

---

# 文档结束
