# Vilsay · 仓库与文件存放约定

**给开发/协作**：新增或移动文件前请先读本文；与代码模块树以 **`docs/spec/VILSAY_TECH_ARCH.md` §三** 为准，本文侧重 **仓库目录与 Markdown 存放规则**。

---

## 1. 文档（`docs/`）

| 目录 | 用途 | 谁维护 |
|------|------|--------|
| **`docs/spec/`** | 产品/技术**规约**（架构、UI/UX、Prompt 等），改功能前对齐 | 架构 + 开发 |
| **`docs/status/`** | **现状**：任务书、微架构、预检、API 说明、测试记录 | 开发 |
| **`docs/status/micro-arch/`** | 每周 `WeekN_MICRO_ARCH.md`（开工前门禁） | 开发 + 架构 |
| **`docs/log/`** | PRD、Onboarding 等**上游/历史**，以只读查阅为主 | 产品 |
| **`docs/files/`** | 与 `spec/status` 同名文档的**备份副本**（`cp` 同步），**勿**当唯一信源 | 自动/人工 |
| **`docs/design/`** | UI 对比、主题 Token 等设计参考 | 设计 / 开发 |
| **`docs/` 根下** | 专项：`HOTKEY_FIX_SUMMARY` 等、`CURSOR_DEV_TASKS.md`（正文）、`DASHSCOPE_SMOKE_TEST.md` 等；**热键架构见 `docs/spec/HOTKEY_ARCHITECTURE.md`，热键任务见 `docs/status/HOTKEY_FN_COMBO_DETECTION_TASK.md`** | 开发 |
| **`docs/status/`** | 另含：`HOTKEY_FN_COMBO_DETECTION_TASK`、`KIMI_TEST_LOG`、`BACKEND_TEST_REPORT`、`DIAGNOSTIC_LOG`、Week3 风险/修复、`CONFIGURATION_COMPLETE`、`SETUP_API_KEY` 等 | 开发 |

**禁止**：在 **`vilsay/vilsay/`**（Swift 源码树）里放 **`.md` 技术文档**（与编译无关的长文）；说明类 Markdown 一律放在 **`docs/`** 对应子目录。

**入口索引**：仓库根目录 [`CLAUDE.md`](../CLAUDE.md)（全文档导航）。

---

## 2. 代码与资源（`vilsay/vilsay/`）

```
vilsay/vilsay/
├── App/          应用入口、AppState、AppDelegate
├── Entry/        热键、录音、悬浮钮、注入
├── Core/         Pipeline、ASR、润色、VAD 等
├── UI/           SwiftUI 界面
├── Config/       常量、Prompt、AppConfig
├── Utils/        工具
├── Auth/ DB/ AI3/  占位或后续模块
├── Resources/    随包资源（如 WhisperModels 说明）
└── *.swift       根级如 vilsayApp.swift
```

- **Xcode 工程**：`vilsay/vilsay.xcodeproj`，Scheme **`vilsay`**。  
- 若使用 **File System Synchronized** 组，在 `vilsay/vilsay/` 下新增 `.swift` 一般即参与编译；新增资源需在 **Copy Bundle Resources** 中确认。

---

## 3. 仓库根目录（仅少量指针文件）

| 文件 | 说明 |
|------|------|
| [`CLAUDE.md`](../CLAUDE.md) | 文档总索引（必读） |
| [`CURSOR_DEV_TASKS.md`](../CURSOR_DEV_TASKS.md) | **指针**：指向 [`docs/CURSOR_DEV_TASKS.md`](CURSOR_DEV_TASKS.md) 完整正文 |

---

## 4. 与任务书的关系

- 任务拆分与验收：**[`docs/status/VILSAY_DEV_TASKS.md`](status/VILSAY_DEV_TASKS.md)**  
- 每周开工微架构：**[`docs/status/WEEKLY_MICRO_ARCH_PROCESS.md`](status/WEEKLY_MICRO_ARCH_PROCESS.md)**  

---

## 5. 变更记录

| 日期 | 说明 |
|------|------|
| 2026-03-23 | 初版：收拢 `docs/` 与 `vilsay/vilsay/` 分工，热键文档统一在 `docs/` |
| 2026-03-24 | 根目录 `CONFIGURATION_*`、`SETUP_*`、`CURSOR` 正文收拢；`docs/` 下散落的测试/Week3/UI 文档归入 `status/` 或 `design/` |
| 2026-03-24 | **`HOTKEY_ARCHITECTURE` → `docs/spec/`**，**`HOTKEY_FN_COMBO_DETECTION_TASK` → `docs/status/`**（与 `REPO_FILE_LAYOUT` 规约/任务分工一致） |
| 2026-03-25 | 新增 `docs/status/PHASE_PROGRESS_2026_03_25.md`；`VILSAY_PHASE1_3_NOTES` / `HOTKEY_ARCHITECTURE` / `DASHSCOPE_SMOKE_TEST` 同步本阶段热键模式、百炼模型与润色双协议说明 |
| 2026-03-25 | `WEEK4_CURSOR_TASKS.md` 增补任务总览表（客户端 4 + 服务端 6 + `W4-PROD-01`）；`CLAUDE.md` / `docs/CLAUDE.md` 索引更新 |
