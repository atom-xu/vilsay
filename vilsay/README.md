# Vilsay

macOS native voice-to-text polishing tool. Hold a hotkey, speak, and Vilsay automatically transcribes, polishes, and pastes refined text into your current app.

> "这个项目呢就是，然后我们团队上周就是完成了主要的那个功能开发，然后就是这周在做测试，然后大概下周能上线吧。"
>
> **Vilsay** → 项目团队上周完成了主要功能开发，本周正在进行测试，预计下周上线。

## Features

- **Voice → Text → Polish → Paste** in one step, no window switching
- **LLM-powered ASR** (qwen-audio-asr) with high accuracy for Chinese-English mixed speech
- **Local Whisper fallback** (WhisperKit) for offline use
- **Smart output modes** — auto-adapts style based on the target app (chat / email / document / note / terminal)
- **AI3 user profiling** — learns your speaking style and improves over time
- **BYOK mode** — bring your own DashScope API Key, no account required

## Download

- **[Download for macOS](https://dl.vilhil.cn/Vilsay.dmg)** — requires macOS 14 (Sonoma)+
- Website: [vilsay.com](https://vilsay.com)

## Build from Source

```bash
git clone https://github.com/atom-xu/vilsay.git
cd vilsay
open vilsay.xcodeproj
```

1. In Xcode: **File → Packages → Resolve Package Versions**, wait for SPM to finish
2. Set your DashScope API Key in Scheme environment variables or the Settings page
3. **⌘B** to build, **⌘R** to run
4. Hold **Fn / 🌐** to speak, release to polish and paste

> First build downloads WhisperKit and other dependencies, which may take 10-30 minutes.

## Architecture

```
Recording → ASR → ITN → LLM Polish → Paste to frontmost app
              ↓              ↓
        Stream / File    AI3 profiling
        recognition      (learns every N uses)
```

**ASR priority chain**: qwen-audio-asr → backend proxy → Paraformer → WhisperKit local

## Project Structure

```
vilsay/
├── vilsay.xcodeproj
├── vilsay/
│   ├── App/           # AppDelegate, AppState
│   ├── Config/        # AppConfig, Prompts, Constants
│   ├── Core/          # Pipeline, ASR clients, PromptComposer
│   ├── AI3/           # User profiling, ProfileService
│   ├── Auth/          # Login, subscription, backend client
│   ├── DB/            # GRDB schema, migrations
│   ├── UI/            # SwiftUI views
│   ├── Entry/         # Hotkey, overlay controller
│   └── Utils/         # Network monitor, Keychain, ITN
├── HotkeyMonitor/     # XPC helper for hotkey detection
└── vilsayTests/
```

## Dependencies

| Library | Purpose |
|---------|---------|
| [WhisperKit](https://github.com/argmaxinc/WhisperKit) | Local offline speech recognition |
| [GRDB.swift](https://github.com/groue/GRDB.swift) | SQLite database |
| [LaunchAtLogin](https://github.com/sindresorhus/LaunchAtLogin-modern) | Launch at login |

## Configuration

| Environment Variable | Description | Default |
|---------------------|-------------|---------|
| `DASHSCOPE_API_KEY` | Alibaba DashScope API Key | — |
| `VILSAY_QWEN_MODEL` | Polish model | `qwen-flash` |
| `VILSAY_FILE_ASR_MODEL` | File ASR model | `qwen-audio-asr` |
| `VILSAY_STREAMING_ASR_MODEL` | Streaming ASR model | `paraformer-realtime-v2` |

All environment variables can be overridden via the Settings UI (stored in UserDefaults).

## License

MIT License. See [LICENSE](LICENSE) for details.
