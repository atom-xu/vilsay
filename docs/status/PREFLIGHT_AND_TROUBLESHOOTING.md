# Vilsay · 本机预检与排障

**版本：** 1.0 | **日期：** 2026-03-22  
**读者：** 开发者、测试、首次运行用户

---

## 1. 首次运行前预检（建议按顺序）

| 检查项 | 说明 |
|--------|------|
| **macOS 14+** | 与 WhisperKit / 工程部署目标一致。 |
| **麦克风** | 系统设置 → 隐私与安全性 → 麦克风 → 勾选 Vilsay。首次录音会触发系统授权。 |
| **辅助功能** | **系统设置 → 隐私与安全性 → 辅助功能** → 勾选 **Vilsay**。全局热键（右 Option / FN·🌐）、`CGEventTap`、录音中 **ESC 取消**均依赖此项；未勾选时菜单栏可能出现橙色提示，请用 **「开始录音」** 验证主链路。 |
| **网络（可选）** | 沙盒已启用 `com.apple.security.network.client`：WhisperKit **首次在线下载**模型、DashScope API 调用需要网络。若需完全离线 Whisper，将 CoreML 模型目录嵌入 Bundle，见 `vilsay/Resources/WhisperModels/README.txt`。 |
| **API Key（云端润色/部分 ASR）** | 若使用 DashScope 能力，需按 `API_KEYS_AND_SECRETS.md` / `VILSAY_PHASE1_3_NOTES.md` 配置环境或构建配置。 |

---

## 2. 症状对照

| 现象 | 常见原因 | 建议 |
|------|----------|------|
| 能启动但**热键无反应**、**无法 ESC 结束** | 辅助功能未授权或 `CGEventTap` 创建失败 | 打开辅助功能设置勾选 Vilsay；使用菜单 **「开始录音」** 切换录音。 |
| **无提示音** | 未进入录音态；或设置关闭提示音；或系统静音 | 确认 `AppState.soundFeedbackEnabled`；先确认菜单录音能进入「录音中」再听音效。 |
| **不转写 / 无文字** | Whisper 未加载成功；麦克风无有效音频；API Key 缺失导致链路提前失败 | 看菜单 **「上次错误详情…」**；控制台查 Whisper 加载日志；确认麦克风权限与最短录音时长（过短可能被过滤）。 |
| Whisper **下载失败** | 无网络、沙盒网络曾被关闭、Hub 不可达 | 检查网络；或将模型嵌入 App（`WhisperModels/openai_whisper-base`）。 |

---

## 3. 与架构文档的关系

- 权限与模块职责以 **`docs/spec/VILSAY_TECH_ARCH.md`** 为准。
- 每周实现细节以 **`docs/status/micro-arch/WeekN_MICRO_ARCH.md`**（微架构门禁）为准。
