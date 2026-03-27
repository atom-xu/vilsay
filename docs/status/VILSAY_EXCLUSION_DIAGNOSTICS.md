# Vilsay 排除法诊断（环境变量）

在 Xcode：**Product → Scheme → Edit Scheme → Run → Arguments → Environment Variables** 中添加下表变量，**Value 填 `1`（或 `true` / `yes`）**。每次只开 **一两项**，便于定位崩溃/卡死。

启动时控制台会打印：`🧪 诊断排除已启用：…` 或 `未设置任何 VILSAY_EXCLUDE_*`。

| 变量 | 作用 |
|------|------|
| `VILSAY_EXCLUDE_SOUND` | 不播放系统音效（`AudioServicesPlaySystemSound`） |
| `VILSAY_EXCLUDE_HOTKEY_XPC` | 不启动 HotkeyMonitor XPC；`checkHealth` 不会误拉起连接 |
| `VILSAY_EXCLUDE_HOTKEY_HEALTH` | 不跑每 10 秒的 `HotkeyManager.checkHealth` |
| `VILSAY_EXCLUDE_WHISPER` | 不预加载 Whisper；本地转写返回空串 |
| `VILSAY_EXCLUDE_MIC_HAL` 或 **`VILSAY_NO_MIC`** | 不进入真实录音；短名可避免 Scheme 列表里被截断误填 |
| `VILSAY_EXCLUDE_FLOATING_BUTTON` | 不 `showIfNeeded` 悬浮钮 |

## 建议顺序（从快到慢）

1. **`VILSAY_EXCLUDE_MIC_HAL=1`** — 若仍崩：多半不是麦克风/HAL 单一路径。  
2. **`VILSAY_EXCLUDE_WHISPER=1`** — 排除 WhisperKit / CoreML / 下载。  
3. **`VILSAY_EXCLUDE_SOUND=1`** — 排除 AudioToolbox 与录音同机竞争。  
4. **`VILSAY_EXCLUDE_HOTKEY_XPC=1`** — 排除 XPC + 热键子进程（用菜单测主应用）。  
5. **`VILSAY_EXCLUDE_HOTKEY_HEALTH=1`** — 排除周期性 XPC ping。  
6. **`VILSAY_EXCLUDE_FLOATING_BUTTON=1`** — 排除悬浮窗。

实现代码：`vilsay/Core/DiagnosticsExclusion.swift`。

## 「MIC_HAL 没反应」排查

- **Value** 可为 `1`、`true`、`yes`、`on`（不区分大小写）。  
- 启动日志应出现：`VILSAY_EXCLUDE_MIC_HAL 原始值="…" → 生效=true`；若为 `生效=false`，说明值未识别。  
- 开启后**不会开始录音**；长按 Fn 时菜单栏图标 **悬停 (help)** 应出现「诊断：已跳过麦克风/HAL…」。若**仍崩溃**，说明问题**不在**麦克风/HAL 主路径，请改测 `VILSAY_EXCLUDE_WHISPER` 或 `VILSAY_EXCLUDE_HOTKEY_XPC`。
