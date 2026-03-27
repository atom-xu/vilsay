# Vilsay · 阶段进度汇报

**阶段**：2026-03 中下旬（热键模式、百炼模型/润色链路、测试补强）  
**日期**：2026-03-25  

---

## 一、本阶段交付摘要

| 主题 | 内容 | 状态 |
|------|------|------|
| 主热键触发方式 | `triggerMode`（单击 / 长按）同时约束 **物理 Fn（XPC）** 与 **悬浮球**；两种模式互斥，不再在同一按键上自动混判短按+长按 | 已落地 |
| 百炼模型列表 | 修复 `GET /api/v1/models` 的 JSON 解析（`output.models[].model`）、分页拉全；失败时兜底 `compatible-mode/v1/models` | 已落地 |
| 润色双协议 | DEBUG 直连：无 `/` 的模型走原生 `text-generation`+SSE；含 `/` 或 `VILSAY_POLISH_USE_COMPAT=1` 走 OpenAI 兼容 `chat/completions` | 已落地 |
| AppConfig | Key 与各模型 ID 统一优先级：表单（测试开关开）→ 环境变量 → UserDefaults | 已落地 |
| 润色用量上报 | Pipeline 对 `polishStreaming` / `polishPlain` 首次有效输出上报用量（`PolishUsageOnceGate`） | 已落地 |
| 单元测试 | 新增 `PolishStreamParsing`、`DashScopeModelCatalog` 解析用例；`vilsayTests` 全绿 | 已验收 |
| UI 测试 | `vilsayUITests`（Week2 菜单栏）在无头/当前环境下易失败，**本阶段不作为门禁** | 已知 |

---

## 二、代码与文档索引

| 说明 | 路径 |
|------|------|
| 热键 Fn 边沿、模式分支 | `vilsay/vilsay/Entry/HotkeyManager.swift`、`FnHotkeyDiscrimination.swift` |
| 触发方式状态 | `vilsay/vilsay/App/AppState.swift`（`triggerMode`） |
| 模型列表 / 拆分 | `vilsay/vilsay/Core/DashScopeModelCatalog.swift` |
| 润色请求与解析 | `vilsay/vilsay/Core/PolishService.swift`、`PolishStreamParsing.swift` |
| 运行时配置 | `vilsay/vilsay/Config/AppConfig.swift` |
| 设置页文案 | `vilsay/vilsay/UI/SettingsRootView.swift` |
| 单元测试 | `vilsay/vilsayTests/PolishStreamParsingTests.swift`、`DashScopeModelCatalogTests.swift` 等 |

---

## 三、测试命令（验收）

```bash
cd vilsay
xcodebuild -scheme vilsay -destination 'platform=macOS' test -only-testing:vilsayTests
```

**期望**：`TEST SUCCEEDED`（仅单元测试，不含 UI）。

---

## 四、后续建议（未在本阶段承诺）

- 修复或跳过依赖「Apple 菜单栏」的 `Week2AcceptanceTests`，便于 CI 跑全量 `test`。  
- AI3 分析、账号后端与 Paraformer 本地文件直传等仍按 `VILSAY_DEV_TASKS.md` 排期。

---

# 文档结束
