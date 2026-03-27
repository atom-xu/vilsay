# VILSAY · 第 1～3 阶段交付说明与已知边界

# 版本：1.1 | 日期：2026-03-25

> 与 `VILSAY_DEV_TASKS.md` 任务表配合使用；**前三阶段**指 Week 1（工程初始化）、Week 2（前端界面）、Week 3（主链路后端）。  
> **阶段进度摘要（2026-03）**：见同目录 [`PHASE_PROGRESS_2026_03_25.md`](PHASE_PROGRESS_2026_03_25.md)。

---

## 一、已闭环问题（相对早期模板/配置）

| 问题 | 处理 |
|------|------|
| `vilsay.entitlements` 被清空导致沙盒/麦克风能力缺失 | 已恢复 `com.apple.security.app-sandbox` + `com.apple.security.device.audio-input`（与 `INFOPLIST_KEY_NSMicrophoneUsageDescription` 一致） |
| Xcode 与 Cursor 同改 `project.pbxproj` 冲突 | 约定：改工程文件时先关 Xcode，或冲突后以磁盘为准再合并 |
| `ENABLE_APP_SANDBOX` 与手写 entitlements 叠加导致构建异常 | 当前以 entitlements 为准；`REGISTER_APP_GROUPS` 保持 `NO`（未用 App Group 时） |
| 重复 `@main` / 错误 `createMenus()` | 唯一入口 `vilsayApp.swift`；菜单栏为 `MenuBarExtra` + `MenuBarRootMenu` |
| 跨文件 `private` 导致 Modifier 不可见 | `FloatingTriggerGestureModifier` 为模块内 `struct` |
| `KeyboardShortcuts.initialize()` 不可外部调用 | 已移除调用，依赖 `onKeyDown`/`onKeyUp` 懒注册 |

---

## 二、功能点与代码映射（补充）

| 能力 | 实现位置 |
|------|----------|
| 主热键 Fn / 右 Option（XPC + `HotkeyManager`）、**单击/长按** 模式与 `FnHotkeyDiscrimination` | `Entry/HotkeyManager.swift`、`Entry/FnHotkeyDiscrimination.swift`、`App/AppState.swift`（`triggerMode`） |
| 悬浮球 Push/Toggle（与 `triggerMode` 一致） | `Entry/FloatingTriggerGestureModifier.swift` 等 |
| ESC 取消 | `Pipeline` / 热键相关分支 |
| 主链路编排 | `Core/Pipeline.swift` |
| 麦克风录音 | `Entry/AudioCapture.swift`（16kHz 单声道 `.caf`） |
| 本地 ASR | `Core/WhisperASRFallback.swift`（`openai_whisper-base`） |
| 云端 ASR（Paraformer 文件） | `Core/DashScopeASRClient.swift`（代理 multipart / 公网 URL 联调） |
| 百炼模型列表（设置页「拉取」） | `Core/DashScopeModelCatalog.swift`（`GET /api/v1/models` 分页 + `output.models`；兜底 `compatible-mode/v1/models`） |
| 润色（原生 SSE + OpenAI 兼容流式/非流式） | `Core/PolishService.swift`、`Core/PolishStreamParsing.swift`、`Config/AppConfig.swift`（`polishHTTPURL`、`polishUsesOpenAICompatChatCompletions`） |
| Prompt | `Config/Prompts.swift`、`Core/PromptComposer.swift` |
| 文字注入 | `Entry/TextInjector.swift`（剪贴板 + Cmd+V） |
| 改词（选中文本 + 指令） | `Core/SelectSpeakService.swift` + `Pipeline` 分支 |
| 文本 VAD（800ms 停顿） | `Core/VADBuffer.swift`（**流式 ASR 接入后** feed partial） |
| 网络可达性 | `Utils/NetworkMonitor.swift` |


---

## 三、环境变量（开发联调）

| 变量 | 作用 |
|------|------|
| `DASHSCOPE_API_KEY` | 百炼 / DashScope（Qwen 润色；Paraformer 联调） |
| `VILSAY_QWEN_MODEL` | 可选，默认 `qwen-turbo` |
| `VILSAY_POLISH_USE_COMPAT` | `1`/`true`：DEBUG 直连润色强制走 OpenAI 兼容 `chat/completions`；`0`/`false`：强制原生 `text-generation`（模型 ID 含 `/` 时仍会自动走兼容） |
| `DASHSCOPE_PARAFORMER_FILE_URL` | **公网** 音频 HTTPS URL；设置后且「识别模式」为云端且在线时，走 Paraformer 异步任务（**与当前麦克风生成的本地文件无关**，用于验证 Key 与接口） |
| `vilsay.dashscope_api_key` 等（UserDefaults） | 设置页「在设置中填写云端配置（测试）」开启时与表单同步；关闭后仍可与环境变量组合，**具体优先级**见 `AppConfig` 实现 |

**未配置 ASR 代理且未设公网联调 URL 时**：云端识别模式下本地录音仍走 **Whisper**（符合官方「仅支持 file_urls」限制）；所选 Paraformer 仅在 **代理上传** 路径生效。

**润色**：模型 ID 带 `厂商/模型` 形态（来自兼容列表）时，App 自动走 **compatible-mode**；纯 `qwen-*` 等走原生 `text-generation`。

---

## 四、断句与 VAD（W3-05）

- **当前产品**：一次录音会话的边界 = **松开热键/按钮**（或 Toggle 再次点击结束）。  
- **800ms 文本 VAD**：`VADBuffer` 已就绪，待 **流式 ASR** partial 文本接入时 `feed` 多段；整段 Whisper 结果不必经过 800ms 定时器。

---

## 五、FN / 地球仪热键（`HotkeyBindingMode.fnGlobe`）

- `KeyboardShortcuts` **无法**可靠捕获 FN/Globe（见 `VILSAY_TECH_ARCH` 第十四章）。  
- **当前实现**：嵌入式 XPC `HotkeyMonitor` + 主进程 `HotkeyManager`（需**辅助功能**）。无内置 Globe 键的机器自动使用 **右 Option**，见 `GlobeKeyHardwareCapabilities` / 设置页说明。  
- **触发方式**：设置「单击 / 长按」与 **主热键**、**悬浮球** 一致；详见 [`docs/spec/HOTKEY_ARCHITECTURE.md`](../spec/HOTKEY_ARCHITECTURE.md) 文末「触发方式」节。

---

## 六、自动化测试

- **单元测试**：`xcodebuild test -only-testing:vilsayTests` 为当前门禁；含 `PolishStreamParsingTests`、`DashScopeModelCatalogTests`、`FnHotkeyDiscriminationTests` 等。  
- **UI 测试**：`vilsayUITests`（如 Week2 菜单栏）在无头/部分桌面环境下易失败，与主链路逻辑解耦，**不强制**本阶段 CI 通过。

---

## 七、联调 Paraformer 失败时

- 确认 API Key 为**北京地域**百炼 Key（与官方文档一致）。  
- 任务查询：`DashScopeASRClient` 已先 **POST** 空 body，失败再 **GET**（与官方文档及 curl 兼容）。

---

## 八、Prompt 与 §1 动态层

- **§0 / §2** 仅在 `Config/Prompts.swift` 中维护固定文案。  
- **§1** 对应结构化数据在 `Config/UserProfile.swift`，由 `Core/PromptComposer.swift` **拼成自然语言**后再与固定层合并；**禁止**在 Prompt 字面量里写「§1.1」类占位符。

---

## 九、后续工作（第 4 周起，不在本文件展开）

- 云端 ASR 与本地录音统一：需 **服务端上传** 或 **WebSocket 实时流式** DashScope。  
- 账号、用量、RawLogger、SQLite、AI3 等见 `VILSAY_DEV_TASKS.md` Week 4+。

---

## 十、重置 Onboarding（验收）

```bash
defaults delete <你的BundleID> vilsay.onboarding_done
```

Bundle ID 以 Xcode **Signing & Capabilities** 为准。

---

# 文档结束
