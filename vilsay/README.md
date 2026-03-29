# Vilsay

macOS 原生语音润色工具。按住快捷键说话，Vilsay 自动识别语音、润色文字、粘贴到当前应用。

A macOS native voice-to-text polishing tool. Hold a hotkey, speak, and Vilsay automatically transcribes, polishes, and pastes refined text into your current app.

> "这个项目呢就是，然后我们团队上周就是完成了主要的那个功能开发，然后就是这周在做测试，然后大概下周能上线吧。"
>
> **Vilsay** → 项目团队上周完成了主要功能开发，本周正在进行测试，预计下周上线。

## 功能特性 / Features

- **语音 → 文字 → 润色 → 粘贴**，一键完成，无需切换窗口
- **LLM 端到端语音识别**（qwen-audio-asr），中英文混合准确率高
- **本地 Whisper 离线识别**（WhisperKit），无网络时自动降级
- **智能输出模式** — 根据目标应用自动切换风格（聊天 / 邮件 / 文档 / 笔记 / 终端）
- **AI3 用户画像学习** — 基于使用习惯持续优化润色风格
- **BYOK 模式** — 自备 DashScope API Key 即可使用，无需账号

## 下载 / Download

- **[下载 macOS 版本](https://dl.vilhil.cn/Vilsay.dmg)** — 要求 macOS 14 (Sonoma) 及以上
- 官网：[vilsay.com](https://vilsay.com)

## 从源码构建 / Build from Source

```bash
git clone https://github.com/atom-xu/vilsay.git
cd vilsay
open vilsay.xcodeproj
```

1. Xcode 中 **File → Packages → Resolve Package Versions**，等待 SPM 拉取完成
2. 在 Scheme 环境变量或设置页中填入 DashScope API Key
3. **⌘B** 编译，**⌘R** 运行
4. 按住 **Fn / 🌐** 键开始说话，松开自动润色并粘贴

> 首次编译需下载 WhisperKit 等依赖，约 10-30 分钟属正常。

## 架构 / Architecture

```
录音 → ASR 识别 → ITN 标准化 → LLM 润色 → 粘贴到前台应用
              ↓                    ↓
        流式 / 文件识别        AI3 后台画像学习
```

**ASR 优先级链路**：qwen-audio-asr → 后端代理 → Paraformer → WhisperKit 本地

## 项目结构 / Project Structure

```
vilsay/
├── vilsay.xcodeproj
├── vilsay/
│   ├── App/           # AppDelegate, AppState
│   ├── Config/        # AppConfig, Prompts, Constants
│   ├── Core/          # Pipeline, ASR, PromptComposer
│   ├── AI3/           # 用户画像分析
│   ├── Auth/          # 登录、订阅、后端通信
│   ├── DB/            # GRDB 数据库
│   ├── UI/            # SwiftUI 视图
│   ├── Entry/         # 热键、浮层控制器
│   └── Utils/         # 网络监控、Keychain、ITN
├── HotkeyMonitor/     # XPC 热键检测助手
└── vilsayTests/
```

## 依赖 / Dependencies

| 库 | 用途 |
|----|------|
| [WhisperKit](https://github.com/argmaxinc/WhisperKit) | 本地离线语音识别 |
| [GRDB.swift](https://github.com/groue/GRDB.swift) | SQLite 数据库 |
| [LaunchAtLogin](https://github.com/sindresorhus/LaunchAtLogin-modern) | 开机自启 |

## 配置 / Configuration

| 环境变量 | 说明 | 默认值 |
|---------|------|--------|
| `DASHSCOPE_API_KEY` | 阿里云百炼 API Key | — |
| `VILSAY_QWEN_MODEL` | 润色模型 | `qwen-flash` |
| `VILSAY_FILE_ASR_MODEL` | 文件识别模型 | `qwen-audio-asr` |
| `VILSAY_STREAMING_ASR_MODEL` | 流式识别模型 | `paraformer-realtime-v2` |

所有环境变量均可通过设置页 UI 覆盖。

## 许可证 / License

MIT License. See [LICENSE](LICENSE) for details.
