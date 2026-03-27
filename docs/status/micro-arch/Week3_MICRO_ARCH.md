# Week 3 · 微架构说明（追认版）

| 项 | 内容 |
|----|------|
| **状态** | 追认 |
| **日期** | 2026-03-22 |
| **对应任务** | W3-01～W3-11 |
| **中枢** | `Core/Pipeline.swift`（`@MainActor` 单例） |

---

## 1. 范围与模块映射

| 任务 | 模块 | 说明 |
|------|------|------|
| W3-01 热键 | `Entry/HotkeyManager.swift` | `CGEventTap`：`flagsChanged`（右 Option、FN/🌐）、`keyDown`（ESC=53）；**需辅助功能**。Tap 失败时 `AppState.hotkeyAccessibilityRequired = true`，并尝试 `NSEvent` ESC 兜底；`HotkeyBindingMode.custom` 时不触发录音仅占位。 |
| W3-02 录音 | `Entry/AudioCapture.swift` | `AVAudioEngine` → 临时 `.caf`；与 `Constants.minAudioDurationForASRSeconds`（0.2s）配合过滤过短音频。 |
| W3-03 云端 ASR | `Core/DashScopeASRClient.swift` | Paraformer **异步 REST**（需公网可访问 URL 的任务路径）；与麦克风直录 **不**直接等价（本地文件主走 Whisper）。 |
| W3-04 本地 ASR | `Core/WhisperASRFallback.swift`、`WhisperModelLocator.swift` | `WhisperKit`：`preload()` 于启动 `Task.detached`；支持包内 `WhisperModels/<asrFallbackModel>/`。 |
| W3-05 VAD | `Core/VADBuffer.swift` | 整段 ASR 结果经 `acceptFinalTranscript` → `onSentenceComplete` → 润色；**800ms 文本流式 VAD** 留待流式 ASR（Week 4 任务书 W4-01）。 |
| W3-06 Prompt | `Config/Prompts.swift`、`UserProfile.swift`、`PromptComposer.swift` | 固定层 §0/§2；画像转自然语言，**不**在 `Prompts` 中写死「§1」字面量。 |
| W3-07 润色 | `Core/PolishService.swift` | Qwen **SSE** 流式；无 Key / 失败时 `polishPlain` 或兜底；超时见 `Constants.polishTimeoutMs`。 |
| W3-08 注入 | `Entry/TextInjector.swift` | 剪贴板保护会话：`beginProtectedPasteSession` → 分块 `pasteChunk` → `end`；非 AX 逐字注入。 |
| W3-09 取消 | `Pipeline.cancel()` + 热键 ESC | 取消不写 raw_log（Week 5 前亦无 DB）；`showCancelFlash` 提示。 |
| W3-10 改词 | `Core/SelectSpeakService.swift`（选区逻辑）、Pipeline 内 `capturedSelection` + `Prompts.buildEditPrompt` | 与 `TargetAppMonitor` 配合。 |
| W3-11 串联 | `Pipeline` | 状态机驱动 `AppState.status`；与 `SoundFeedback`、`PerformanceTracker` 协作。 |

**卫星模块**：`Entry/TargetAppMonitor.swift`（目标 App PID + 选中文本）、`Utils/SoundFeedback.swift`、`Utils/NetworkMonitor.swift`、`Utils/PerformanceTracker.swift`、`Core/GlobeKeyHardwareCapabilities.swift`。

---

## 2. 对外契约（主链路）

### 2.1 入口（均在主线程语义下由 `Pipeline` 协调）

| 入口 | 行为 |
|------|------|
| `startRecording()` | 冷却、`processing` 拦截 → 捕 PID/选区 → `FloatingButtonController.showIfNeeded()` → `AppStatus.recording` 或 `editMode` → `audio.start()` → 提示音 |
| `stopRecording()` | 停录 → 过短则静默返回 → 否则 `process(fileURL:)` |
| `toggleRecording()` | 会话中则 stop，否则 start |
| `onHotkeyPushDown` / `onHotkeyPushUp` | 仅 `triggerMode == .push`；**延迟 `minHoldDurationSeconds`（0.15s）** 后才真正 `beginRecordingSession`；上抬时尚未开始则取消待定任务并进入冷却 |
| `onHotkeyToggle` | Toggle 模式单次边沿触发 `toggleRecording` |
| `cancel()` | 清会话、删临时文件、`idle`、取消闪动 |

### 2.2 ASR 选择逻辑（`process` 内）

1. 时长 &lt; `minAudioDurationForASRSeconds` → 直接返回，保持 UI 可恢复 idle。
2. `recognitionMode == .cloud` 且 `NetworkMonitor.isConnected` 且 `DashScopeASRClient.transcribeFileIfAvailable` 返回非空 → 用云端；**否则** `WhisperASRFallback.transcribe`。
3. 本地模式且 Whisper 仍在加载：可设 `localWhisperStatusHint`。

### 2.3 润色与注入

- `deliverASRThroughVADToPolish` → `runPolishInjectAfterVAD`：`activateTargetApp()` → 延迟 50ms → 保护会话内流式 `pasteChunk`（批量约 `polishStreamingPasteMinBatchCharacters`）。
- 无 DashScope Key：润色链仍可能走兜底，最终 `AppStatus.attention` + `polishAttentionMessage`。

---

## 3. 数据流（简图）

```
热键/菜单/悬浮钮
    → Pipeline（录音启停、取消）
    → AudioCapture → caf
    → ASR（DashScope 可选 / Whisper 默认）
    → VADBuffer.acceptFinalTranscript
    → PolishService（SSE）
    → TextInjector（剪贴板）
    → SoundFeedback / AppState / PerformanceTracker
```

---

## 4. 权限与沙盒

| 能力 | 说明 |
|------|------|
| 麦克风 | 录音前系统弹窗；拒绝则 `start` 失败 → `lastPipelineError` + 短暂 `.error` |
| 辅助功能 | **无 entitlement**；未授权时 CGEventTap 可能为 nil → 热键与 ESC 失效，**菜单「开始录音」仍可用** |
| 网络 | Whisper 首次下载、DashScope API 需要；离线可依赖 Bundle 内 Whisper 目录 |
| 剪贴板 | 沙盒内通用粘贴板；注入依赖目标 App 可编辑 |

---

## 5. 失败与降级

| 场景 | 行为 |
|------|------|
| Whisper 加载失败 | `WhisperASRFallback` 记错误；`localWhisperReady` false；转写 `throw` → Pipeline `catch` → `lastPipelineError` + `.error` → 约 1.5s 回 `idle` |
| 云端 ASR 不可用 | 回退 Whisper（若本地可用） |
| 润色无 SSE 输出 | `polishPlain` 或空兜底；无 Key 时 attention 提示 |
| 目标 App 激活失败 | `lastPipelineError` 文案提示，不粘贴 |
| 短按 / 冷却 | Push 未达最短时间不开始录音；`postStopCooldownSeconds` 内忽略新开始 |

**常量（摘录）**：`minHoldDurationSeconds` 0.15、`postStopCooldownSeconds` 0.3、`maxPushRecordingSeconds` 300、`minAudioDurationForASRSeconds` 0.2、`polishTimeoutMs` 5000、`vadPauseMs` 800（为后续流式预留）。

---

## 6. 与规约 / 任务书关系

- **W3-03**：任务书「流式 ASR」当前实现为 **Paraformer REST**；与 PRD 差异已在 `VILSAY_DEV_TASKS`、`VILSAY_PHASE1_3_NOTES` 说明。
- **W3-05**：**已接入 Pipeline**；**800ms 文本 VAD** 依赖流式 ASR，归 **W4-01**。
- **热键**：全链路 **CGEventTap**，与早期「KeyboardShortcuts」任务书条目不一致处以 `VILSAY_TECH_ARCH` v1.3 为准。

---

## 7. 验收步骤（本机）

**前置**：`DASHSCOPE_API_KEY` 按仓库文档配置（测润色/云端 ASR）；辅助功能勾选 Vilsay；麦克风允许。

1. **菜单栏「开始录音」**：说话 ≥0.2s → 停止 → 目标 App 出现润色后文字（或无 Key 时出现 attention 与原文兜底粘贴行为，以当前实现为准）。
2. **右 Option（Push）**：按住 ≥0.15s 后松手 → 同上；短按 &lt;0.15s → 不应产生有效转写。
3. **ESC**：录音中按 ESC → 无文字注入，状态回待机，短暂取消提示。
4. **断网或仅本地模式**：Whisper 已就绪时仍能出字（若模型已下载或已嵌入 Bundle）。
5. **关闭辅助功能**：热键失效时菜单仍有橙色说明（若 `hotkeyAccessibilityRequired`）；仍可用菜单开始/结束录音验证 ASR+润色。

---

## 8. 已知未闭合项（任务书已登记）

- Week 3 里程碑 **延迟 &lt; 1.5s（10 次平均）**：需 DEBUG 统计或人工秒表，见 `Pipeline` 内 `#if DEBUG` 埋点。
- **raw_log**：取消不写；持久化 Logger 属 Week 5。

---

## 9. 确认

- [x] 架构已审阅  
- [x] 开发已确认与实现一致  

**确认人 / 日期：** Kimi / 2026-03-23
