# Vilsay · Cursor 开发指引

**仓库内路径：** `docs/CURSOR_DEV_TASKS.md`（根目录另有同名**指针文件**，指向本文）

本文面向 **Cursor / AI 辅助开发**：汇总必读文档、阶段任务入口、代码约定示例、测试与验收要点。详细任务编号与勾选仍以 **`docs/status/VILSAY_DEV_TASKS.md`** 为准。

---

## 1. 必读文档列表

| 优先级 | 文档 | 说明 |
|--------|------|------|
| P0 | [`docs/spec/VILSAY_TECH_ARCH.md`](docs/spec/VILSAY_TECH_ARCH.md) | 技术架构、沙盒/权限、热键、ASR/润色路径 |
| P0 | [`docs/spec/VILSAY_UI_UX.md`](docs/spec/VILSAY_UI_UX.md) | 界面与文案规约 |
| P0 | [`docs/status/VILSAY_DEV_TASKS.md`](docs/status/VILSAY_DEV_TASKS.md) | **主任务书**（Week、W4-Pxx、里程碑） |
| P0 | [`docs/status/WEEKLY_MICRO_ARCH_PROCESS.md`](docs/status/WEEKLY_MICRO_ARCH_PROCESS.md) | 每周开工前微架构门禁 |
| P1 | [`docs/status/PREFLIGHT_AND_TROUBLESHOOTING.md`](docs/status/PREFLIGHT_AND_TROUBLESHOOTING.md) | 本机预检与排障 |
| P1 | [`docs/status/VILSAY_PHASE1_3_NOTES.md`](docs/status/VILSAY_PHASE1_3_NOTES.md) | 环境变量、Paraformer/Whisper 边界 |
| P1 | [`docs/status/API_KEYS_AND_SECRETS.md`](docs/status/API_KEYS_AND_SECRETS.md) | API Key 与安全（勿提交密钥） |
| P2 | [`CLAUDE.md`](CLAUDE.md) | 全仓库文档索引 |
| P2 | [`docs/log/VILSAY_PRD.md`](docs/log/VILSAY_PRD.md) | 产品需求（按需） |

**工程位置：** Xcode 工程 `vilsay/vilsay.xcodeproj`，Scheme `vilsay`，源码 `vilsay/vilsay/`。

---

## 2. 分阶段开发任务（摘要）

| 阶段 | 内容 | 详情 |
|------|------|------|
| Week 1 | 工程、SPM、目录、Entitlements | 任务书 §W1 |
| Week 2 | 菜单栏、悬浮钮、Onboarding、设置/词典/用量 UI | §W2 |
| Week 3 | 热键 `CGEventTap`、`Pipeline`、录音、Whisper/Paraformer、润色、注入、改词 | §W3 |
| Week 4 | 账号、后端、用量、计费；**增补** W4-P01～P05（权限中心、试录、热键自测、分段诊断、错误显性化） | §W4 |
| Week 5 | GRDB、RawLogger、AI3、词典持久化 | §W5 |
| Week 6 | 性能、边界测试、上架材料 | §W6 |

**微架构：** 开工前在 [`docs/status/micro-arch/`](docs/status/micro-arch/) 维护 `WeekN_MICRO_ARCH.md`。

**当前产品约定（热键）：** 能用 **FN / 🌐** 则用，否则 **右 Option**；由 `GlobeKeyHardwareCapabilities` + `AppConfig.hotkeyBindingMode` 自动判定，用户不在设置里切换键位。

---

## 3. 代码示例（约定片段）

### 3.1 主链路入口（勿绕开状态机）

主录音/处理须走 `Pipeline`（`@MainActor`），菜单与热键统一调用：

```swift
// 菜单栏「开始录音」
Task { @MainActor in
    await Pipeline.shared.toggleRecording()
}
```

### 3.2 热键（系统级 HID + 链首优先）

`HotkeyManager` 使用 `CGEventTap` + `headInsertEventTap`；回到前台/唤醒后会 `scheduleReinstallForHeadPriority()` 重插 tap。修改后确认 `AppDelegate` 仍注册相关通知。

### 3.3 配置与密钥

```swift
// 润色/云端能力：环境变量或本机调试 UserDefaults（勿把密钥写进仓库）
AppConfig.hasDashScopeAPIKey
AppConfig.dashscopeAPIKey
```

### 3.4 用户可见错误

优先同步 `AppState.lastPipelineError`、`AppState.polishAttentionMessage`，避免仅 `print` / `Logger`。

### 3.5 Whisper 包内模型（可选）

包内目录：`WhisperModels/<Constants.asrFallbackModel>/`，由 `WhisperModelLocator` 解析。

---

## 4. 测试要求

| 类型 | 要求 |
|------|------|
| 编译 | `xcodebuild -scheme vilsay -configuration Debug build` 通过后再提交流程 |
| 本机功能 | 辅助功能 + 麦克风；无网/有网、本地/云端识别路径至少各通一次（见预检文档） |
| API | DashScope 联调可参考 [`docs/DASHSCOPE_SMOKE_TEST.md`](docs/DASHSCOPE_SMOKE_TEST.md) |
| 回归 | 修改 `HotkeyManager` / `Pipeline` / 权限后：试录音、ESC 取消、菜单「开始录音」兜底 |

**自动化：** 任务书建议 XCTest（可选），不阻塞功能合并。

---

## 5. 验收标准（合并自任务书）

- **Week 2：** 菜单栏可展开、设置 Tab 可切换、悬浮钮可显示与拖动（以任务书 W2 勾选为准）。
- **Week 3：** 热键或菜单可完成「说 → 润色 → 注入」；ESC 取消无输出；Whisper 降级可工作（或包内模型）。
- **里程碑（延迟）：** 松开到出字 &lt; 1.5s（10 次平均）为产品目标，需本机配置 API 后实测。
- **增补 P0（W4-P01～P05）：** 权限分项直达系统设置、试录、热键自测、AI 分段诊断、主链路错误与弱网**对用户可见**（详见任务书原文）。

---

## 6. 与 AI 对话时的推荐前缀

```
请先阅读 `docs/CURSOR_DEV_TASKS.md` 与 `docs/status/VILSAY_DEV_TASKS.md`。
当前进度：Week __，任务 __。
不要扩大范围；改动须可编译；密钥勿入库。
```

---

*文档随 `docs/status/VILSAY_DEV_TASKS.md` 版本演进；冲突时以任务书为准。*
