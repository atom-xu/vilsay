# Vilsay

macOS 原生语音润色工具。按住快捷键说话，Vilsay 自动识别语音、润色文字、粘贴到当前应用。

> "这个项目呢就是，然后我们团队上周就是完成了主要的那个功能开发，然后就是这周在做测试，然后大概下周能上线吧。"
>
> **Vilsay** → 项目团队上周完成了主要功能开发，本周正在进行测试，预计下周上线。

## 核心能力

- **语音 → 文字 → 润色 → 粘贴**，一键完成，无需切换窗口
- **LLM 端到端语音识别**（qwen-audio-asr），中英文混合准确率高
- **本地 Whisper 离线识别**（WhisperKit），无网络时自动降级
- **五层 Prompt 架构**，按目标应用自动切换输出风格（聊天/邮件/文档/笔记/AI 指令）
- **AI3 用户画像学习**，基于 Social Style Model 持续优化润色风格
- **L3 Review 二次校验**，后台自动审校，不阻塞主链路
- **BYOK 模式**，自备 API Key 即可使用，无需后端账号

## 系统要求

- macOS 14.0+
- Apple Silicon（WhisperKit 本地模型）或 Intel Mac（仅云端模式）

## 快速开始

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

## 架构概览

```
录音 → ASR 识别 → ITN 标准化 → LLM 润色 → 粘贴到前台应用
              ↓                    ↓
        流式 / 文件识别       AI3 后台画像学习
        (paraformer / qwen-audio)  (每 N 次触发分析)
```

**ASR 优先级链路**：qwen-audio-asr → 代理服务 → Paraformer 文件识别 → WhisperKit 本地

**润色 Prompt 分层**：
| 层 | 内容 |
|----|------|
| §0 | 身份内核 — 语言整理师，简洁优先，忠于意图 |
| §A | 场景提示 — 按目标应用自动注入（邮件/聊天/终端…） |
| §C | 置信度分级 — 低置信度时积极纠偏 |
| §P | 认知画像 — AI3 学习生成的用户理解 |
| §1 | 用户专属 — 口头禅、思维结构、词典、风格偏好 |
| §2 | 处理引擎 — 场景识别 + 纠偏引擎 P1-P5 |

**输出模式（V4）**：
| 模式 | 触发 | 特点 |
|------|------|------|
| general | 默认 | 去噪 + 书面化精炼 |
| chat | 微信/iMessage | 保留口语感，最小干预 |
| email | Mail/Outlook | 书面语体，分段编号 |
| document | Word/Pages | 结构化，Markdown 格式 |
| note | Notes/Notion | 提炼要点，bullet 输出 |
| aiCommand | Terminal/Cursor | 提取指令，编号输出 |

## 项目结构

```
vilsay/
├── vilsay.xcodeproj
├── vilsay/
│   ├── App/           # AppDelegate, AppState
│   ├── Config/        # AppConfig, Prompts, Constants
│   ├── Core/          # Pipeline, ASR clients, PromptComposer
│   ├── AI3/           # 用户画像分析器, ProfileService
│   ├── DB/            # GRDB Schema, Migrations
│   ├── UI/            # SwiftUI 视图 (Dashboard, Settings, Profile, History)
│   ├── Entry/         # 热键, 浮层控制器
│   └── Utils/         # 网络监控, Keychain, ITN
├── docs/              # 架构规约, 任务书, 测试指南
└── website/           # Next.js 产品官网
```

## 依赖

| 库 | 用途 |
|----|------|
| [WhisperKit](https://github.com/argmaxinc/WhisperKit) | 本地离线语音识别 |
| [GRDB.swift](https://github.com/groue/GRDB.swift) | SQLite 数据库 |
| [LaunchAtLogin](https://github.com/sindresorhus/LaunchAtLogin-modern) | 开机自启 |

## 配置

| 环境变量 | 说明 | 默认值 |
|---------|------|--------|
| `DASHSCOPE_API_KEY` | 阿里云百炼 API Key | — |
| `VILSAY_QWEN_MODEL` | 润色模型 | `qwen-flash` |
| `VILSAY_FILE_ASR_MODEL` | 文件识别模型 | `qwen-audio-asr` |
| `VILSAY_STREAMING_ASR_MODEL` | 流式识别模型 | `paraformer-realtime-v2` |
| `VILSAY_REVIEW_MODEL` | Review 审校模型 | `qwen-plus` |
| `VILSAY_ANALYZER_MODEL` | AI3 分析模型 | `qwen-plus` |
| `VILSAY_POLISH_REVIEW` | 启用 L3 Review | `0` |

所有环境变量均可通过设置页 UI 覆盖（存 UserDefaults），优先级：环境变量 > UserDefaults。

## Build Configurations

| 配置 | 说明 |
|------|------|
| Debug | 开发调试，AI3 每 5 次触发 |
| Release | 正式版，AI3 每 20 次触发 |
| BYOK | 自备 Key 专版，无内购，无后端账号依赖 |

## License

Copyright 2026 Vilsay. All rights reserved.
