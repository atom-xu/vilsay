# VILSAY · 技术架构文档
# Tech Architecture Document
# 版本：1.3 | 日期：2026-03-22
# 上游文档：VILSAY_PRD.md
# 关联：每周微架构门禁见 `docs/status/WEEKLY_MICRO_ARCH_PROCESS.md`；预检排障见 `docs/status/PREFLIGHT_AND_TROUBLESHOOTING.md`；**热键专项架构**见同目录 **`HOTKEY_ARCHITECTURE.md`**

---

## 一、技术选型总表

### 1.1 客户端（macOS App）

| 层级 | 技术 | License | 选择原因 |
|------|------|---------|---------|
| 语言 | Swift 5.9+ | - | 原生性能、iOS 复用 |
| UI 框架 | SwiftUI | - | Apple 官方、现代声明式 |
| 最低系统 | macOS 14 Sonoma | - | WhisperKit 要求 |
| 本地 ASR | WhisperKit | MIT ✅ | Apple 官方推荐、可商用 |
| 云端 ASR | 阿里云 DashScope | - | 中文最准、国内合规 |
| LLM 润色 | 阿里云 Qwen | - | 国内合规、和 ASR 同账号 |
| AI3 分析 | 阿里云 Qwen | - | 内置，用开发者 Key |
| 本地数据库 | GRDB.swift | MIT ✅ | Swift 最佳 SQLite 库 |
| 全局热键（Phase 1～3） | **CGEventTap** | Apple | **右 Option（0x3D）、FN/🌐（0x3F + function 位）**；需**辅助功能**；与 `HotkeyManager` 绑定；**已移除**早期任务书中的 KeyboardShortcuts 依赖 |
| 开机自启 | LaunchAtLogin | MIT ✅ | macOS 标准方案 |
| 依赖管理 | Swift Package Manager | - | Xcode 原生，无需 CocoaPods |

### 1.2 后端服务器

| 层级 | 技术 | 说明 |
|------|------|------|
| 语言/框架 | TBD（建议 Node.js/Fastify 或 Python/FastAPI）| 待决定 |
| 数据库 | PostgreSQL | 用户账号、用量记录 |
| 缓存 | Redis | 会话 Token、限流 |
| 部署 | 自有服务器 | 已有服务器 |
| 认证 | JWT + OAuth2 | Apple/微信/Google/邮箱 |

> 后端技术栈建议：如果团队有 JS 基础选 Node.js（和前端生态统一）；
> 如果有 Python 基础选 FastAPI（开发速度快）。

### 1.3 产品官网

| 层级 | 技术 | 说明 |
|------|------|------|
| 框架 | Next.js | SEO 友好，适合产品官网 |
| 样式 | Tailwind CSS | 快速开发 |
| 部署 | 自有服务器 / Vercel | 均可 |
| 域名 | 已购买 | - |

### 1.4 License 合规确认

| 库 | License | 商用 |
|----|---------|------|
| WhisperKit | MIT | ✅ |
| GRDB.swift | MIT | ✅ |
| LaunchAtLogin | MIT | ✅ |
| ~~KeyboardShortcuts~~ | MIT | Phase 1～3 **未使用**（热键已统一为 CGEventTap） |
| VoiceInk Swift | GPLv3 | ❌ 只参考思路，不复制代码 |

---

## 二、整体架构图

```
┌───────────────────────────────────────────────────────┐
│                    用户层                              │
│    悬浮圆形按钮（可拖动）  +  菜单栏图标               │
└───────────────────────────────────────────────────────┘
                          ↓ 热键 / 按钮事件
┌───────────────────────────────────────────────────────┐
│                  Entry Layer 接入层                    │
│  HotkeyManager       FloatingButton      TextInjector │
│  CGEventTap（需辅助功能） NSPanel floating  剪贴板粘贴注入 │
└───────────────────────────────────────────────────────┘
              ↓ 音频流                    ↑ 润色文字
┌───────────────────────────────────────────────────────┐
│              Core Pipeline 主链路（同步）               │
│                                                       │
│  AudioCapture → ASR → VADBuffer → PolishService       │
│  AVAudioEngine  Paraformer REST 异步 / 整段转写后经   │
│                WhisperKit（本地 caf）  VAD 再润色 Qwen SSE │
│                可选包内模型目录 WhisperModels/         │
│                                                       │
│  SelectSpeakService（改词模式）                        │
│  检测选中文字 → 特殊 Prompt → 替换原文                 │
└───────────────────────────────────────────────────────┘
              ↓ 异步 Task，不阻塞主链路
┌───────────────────────────────────────────────────────┐
│                AI3 暗线（完全异步）                    │
│  RawLogger → AnalyzerTrigger → AI3Analyzer            │
│  写入raw_log  计数满20条触发    Qwen分析画像           │
│                                ↓                     │
│                           ProfileService              │
│                           写入user_profile            │
│                           推荐词写入candidates         │
└───────────────────────────────────────────────────────┘
              ↓                         ↑ 账号/用量
┌─────────────────┐         ┌───────────────────────────┐
│   Data Layer    │         │      Backend Server       │
│   本地 SQLite   │         │   账号 / 计费 / 用量统计   │
│   raw_log       │         │   PostgreSQL + Redis       │
│   user_profile  │         │   REST API / JWT           │
│   dictionary    │         │                           │
│   candidates    │         │      产品官网              │
│   analyzer_state│         │   Next.js + 用量查看       │
└─────────────────┘         └───────────────────────────┘
```

---

## 三、目录结构（工程实际：`vilsay/vilsay/`）

```
vilsay/
├── vilsay.xcodeproj
│
├── vilsay/                          # macOS Target 源码根
│   ├── vilsayApp.swift
│   ├── App/
│   │   ├── AppDelegate.swift
│   │   ├── AppState.swift
│   │   └── …
│   ├── Entry/
│   │   ├── HotkeyManager.swift      # CGEventTap 全局热键 + ESC
│   │   ├── FloatingButtonController.swift / FloatingButtonView.swift
│   │   ├── AudioCapture.swift
│   │   └── TextInjector.swift       # 剪贴板保护 + 粘贴（非 AX 逐字注入）
│   │
│   ├── Core/
│   │   ├── Pipeline.swift
│   │   ├── VADBuffer.swift          # 整段 ASR 后经此再润色；800ms 文本 VAD 待流式 ASR
│   │   ├── DashScopeASRClient.swift # Paraformer 异步 REST（公网 URL 任务）
│   │   ├── WhisperASRFallback.swift # WhisperKit 本地转写
│   │   ├── WhisperModelLocator.swift # 可选包内 CoreML 目录
│   │   ├── PolishService.swift
│   │   ├── SelectSpeakService.swift
│   │   └── PromptComposer.swift
│   │
│   ├── AI3/
│   │   ├── RawLogger.swift
│   │   ├── AnalyzerTrigger.swift
│   │   ├── AI3Analyzer.swift
│   │   └── ProfileService.swift
│   │
│   ├── Auth/
│   │   ├── AuthService.swift        # 登录/注册逻辑
│   │   ├── AppleAuthProvider.swift  # Sign in with Apple
│   │   ├── WeChatAuthProvider.swift # 微信登录
│   │   ├── GoogleAuthProvider.swift # Google 登录
│   │   └── EmailAuthProvider.swift  # 邮箱+密码
│   │
│   ├── DB/
│   │   ├── Database.swift
│   │   ├── Schema.swift
│   │   └── Migrations/
│   │
│   ├── UI/
│   │   ├── FloatingButtonView.swift # 悬浮按钮 SwiftUI 视图
│   │   ├── MenuBarView.swift
│   │   ├── SettingsView.swift
│   │   ├── DictionaryView.swift
│   │   ├── OnboardingView.swift
│   │   ├── LoginView.swift
│   │   ├── UsageView.swift          # 用量统计
│   │   └── Components/
│   │       └── PlaceholderView.swift
│   │
│   ├── Config/
│   │   ├── Constants.swift
│   │   ├── Prompts.swift            # V2 Prompt 固定层
│   │   └── AppConfig.swift
│   │
│   └── Utils/
│       ├── Logger.swift
│       └── NetworkMonitor.swift
│
├── VilsayiOS/                       # iOS Target（预留）
│   └── README.md
│
└── backend/                         # 后端服务（独立仓库或子目录）
    ├── src/
    │   ├── auth/                    # 认证模块
    │   ├── usage/                   # 用量统计
    │   ├── billing/                 # 计费模块
    │   └── api/                     # REST API
    └── README.md
```

---

## 四、悬浮按钮技术实现

```swift
// Entry/FloatingButton.swift
// 使用 NSPanel 实现始终置顶、可拖动的悬浮窗

class FloatingButtonWindow: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 100, y: 100, width: 60, height: 60),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        self.level = .floating          // 始终置顶
        self.isOpaque = false           // 透明背景
        self.backgroundColor = .clear
        self.hasShadow = true
        self.collectionBehavior = [
            .canJoinAllSpaces,          // 所有桌面可见
            .fullScreenAuxiliary
        ]
        self.isMovableByWindowBackground = true  // 可拖动
    }
}

// 悬浮按钮支持两种触发模式（用户在设置中选择）
enum TriggerMode {
    case push    // 按住录音，松开结束
    case toggle  // 点击开始，再点结束
}

// 取消机制：
// 1. Push 模式：录音中按 ESC → 取消
// 2. Toggle 模式：录音中按 ESC → 取消
// 3. 两种模式：录音中拖动按钮到屏幕边缘 → 取消（可选）
```

---

## 五、改词功能技术实现

```swift
// Core/SelectSpeakService.swift

class SelectSpeakService {

    // 检测当前是否有选中文字
    func getSelectedText() -> String? {
        // 使用 AXUIElement 读取当前焦点元素的选中文字
        let systemElement = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?
        AXUIElementCopyAttributeValue(
            systemElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )
        // 读取 kAXSelectedTextAttribute
        // 返回选中文字，无选中返回 nil
    }

    // 构建改词专用 Prompt
    func buildEditPrompt(original: String, instruction: String) -> String {
        return """
        原文：\(original)
        用户指令：\(instruction)
        请根据用户指令修改原文，只输出修改后的文字，不要任何解释。
        """
    }
}

// Pipeline 中的判断逻辑：
// 触发热键时 → 检查是否有选中文字
// 有选中文字 → 进入改词模式
// 无选中文字 → 正常输入模式
```

---

## 六、账号与后端 API

### 6.1 认证流程

```
邮箱注册：
POST /auth/register
  body: { email, password }
  → 发送验证邮件
  → 用户点击验证链接
  → 账号激活

邮箱登录：
POST /auth/login
  body: { email, password }
  → 返回 JWT Token

Apple ID：
客户端获取 identityToken
POST /auth/apple
  body: { identityToken, authorizationCode }
  → 验证 Token → 创建/登录账号

微信登录：
客户端获取 code
POST /auth/wechat
  body: { code }
  → 换取 access_token → 获取 openid → 创建/登录账号

Google 登录：
POST /auth/google
  body: { idToken }
  → 验证 Token → 创建/登录账号
```

### 6.2 核心 API 端点

```
认证
POST   /auth/register          注册
POST   /auth/login             登录
POST   /auth/logout            登出
POST   /auth/refresh           刷新 Token
POST   /auth/apple             Apple 登录
POST   /auth/wechat            微信登录
POST   /auth/google            Google 登录
POST   /auth/forgot-password   忘记密码
POST   /auth/reset-password    重置密码

用量
GET    /usage/current          当前用量
GET    /usage/history          历史用量
POST   /usage/record           记录一次使用（App 每次调用后上报）

订阅
GET    /billing/plan           当前套餐
POST   /billing/subscribe      订阅升级
DELETE /billing/cancel         取消订阅

用户
GET    /user/profile           用户信息
PUT    /user/profile           更新用户信息
DELETE /user/account           注销账号
```

---

## 七、核心接口定义（Swift）

```swift
// AI1
protocol ASRService {
    func startStream() async throws -> AsyncStream<String>
    func stop()
    var isAvailable: Bool { get }
}

// VAD 断句
protocol VADBuffer {
    func feed(_ text: String)
    var onSentenceComplete: ((String) -> Void)? { get set }
}

// AI2
protocol PolishService {
    func polish(_ text: String, profile: UserProfile?) async throws -> AsyncStream<String>
}

// 改词
protocol SelectSpeakService {
    func getSelectedText() -> String?
    func edit(original: String, instruction: String) async throws -> AsyncStream<String>
}

// AI3
protocol RawLogger {
    func log(raw: String, polished: String)
}

protocol ProfileService {
    func get() -> UserProfile?
    func update(_ profile: UserProfile)
    func getCandidates() -> [DictionaryCandidate]
    func approveCandidate(_ id: Int)
    func rejectCandidate(_ id: Int)
}

// 认证
protocol AuthService {
    func currentUser() -> User?
    func loginWithEmail(email: String, password: String) async throws -> User
    func loginWithApple() async throws -> User
    func loginWithWeChat() async throws -> User
    func loginWithGoogle() async throws -> User
    func logout()
    var isLoggedIn: Bool { get }
}
```

---

## 八、数据库表结构

```swift
// 本地 SQLite（设备端，GRDB）
raw_log:              原始语料，只追加
user_profile:         AI3 画像
dictionary:           用户词典
dictionary_candidates: AI3 推荐候选词
analyzer_state:       AI3 触发状态

// 远端 PostgreSQL（服务器端）
users:                用户账号
auth_providers:       第三方登录关联
sessions:             登录会话
usage_records:        使用记录
subscriptions:        订阅状态
```

---

## 九、V2 Prompt 结构

```
§0 身份内核（固定层）
你是一位语言整理师，处理 ASR 产生的原始文字。
任务是还原说话人的真实意图，不是逐字复现，不是重写。
原则一：忠于意图，而非字面
原则二：最小干预
原则三：推断用 [推断] 标注

§2 处理规则（固定层）
P1 自我纠正识别
P2 填充词处理
P3 同音字纠偏
P4 断句重组
P5 多语言边界

§1 用户专属（动态层，从本地 SQLite 读取）
§1.1 口头禅与保留词
§1.2 思维结构特征
§1.3 语气与风格
§1.4 高频词典

实现约定：**不得**在 `Prompts` 固定字符串中直接拼接「§1」占位符。结构化画像数据由 `PromptComposer` 在代码层拼成**自然语言段落**，再与 §0、§2 组成完整 System Prompt 传给 LLM（见 `Core/PromptComposer.swift`、`Config/UserProfile.swift`）。

改词模式专用 Prompt（SelectSpeak）：
接收 [原文] + [用户指令]，只输出修改结果
```

---

## 十、关键常量

```swift
enum Constants {
    static let analyzerTriggerThreshold = 20
    static let analyzerRecentSessions = 50
    static let vadPauseMs = 800
    static let maxTotalLatencyMs = 1500   // 死亡线
    static let polishTimeoutMs = 5000
    static let profileMinConfidence: Double = 0.3
    static let profileMaxDictItems = 200
    static let asrFallbackModel = "openai_whisper-base"
    static let floatingButtonDefaultPosition = CGPoint(x: 100, y: 200)
}
```

---

## 十一、已知隐患

| 隐患 | 风险 | 处理方案 |
|------|------|---------|
| 悬浮按钮遮挡内容 | 中 | 用户可拖动，默认位置远离中心 |
| 改词时 AXUIElement 读取失败 | 中 | 降级为普通输入模式 |
| 微信登录审核周期长 | 高 | 先上线其他3种，微信后补 |
| VAD 误判停顿 | 中 | 800ms 可在设置调整；当前主断句边界多为**松键** |
| ASR 断网 / 本地录音路径 | 中 | 麦克风录音走 **WhisperKit**；Paraformer 需公网 URL，与本地 caf 不直接打通（见 `VILSAY_PHASE1_3_NOTES.md`） |
| **辅助功能未授权** | **高** | `CGEventTap` 失败则热键/ESC 可能无效；菜单「开始录音」+ UI 提示 + `AppState.hotkeyAccessibilityRequired` |
| 沙盒下首次拉取 Whisper 模型 | 中 | 需 `network.client`；或可 **Bundle 嵌入** `WhisperModels/openai_whisper-base` |
| AXUIElement 权限被拒 | 高 | Onboarding 明确引导 |
| macOS 14 以下不支持 | 中 | App Store 设置最低版本 |
| 后端 TBD 导致延期 | 中 | 先做客户端，后端并行开发 |

---

## 十二、多平台预留

```
iOS Target（预留）：
├── Core/ AI3/ DB/ → 直接复用
├── Entry/HotkeyManager → 改为手势
├── Entry/FloatingButton → 改为悬浮按钮手势
├── Entry/TextInjector → 改为键盘扩展
└── UI/ → 重写适配手机

Android（极低优先级）：
└── 届时评估 KMP（Kotlin Multiplatform）
```

---

## 十三、macOS 沙盒、权限与 ASR 路径

| 项 | Entitlements / 行为 | 说明 |
|----|----------------------|------|
| App Sandbox | `com.apple.security.app-sandbox` | 默认开启 |
| 出网 | `com.apple.security.network.client` | DashScope、WhisperKit **在线拉模**需要 |
| 麦克风 | `com.apple.security.device.audio-input` + `NSMicrophoneUsageDescription` | 录音必需 |
| 辅助功能 | **无 entitlement**；用户于系统设置中勾选 | **CGEventTap**、全局 ESC 依赖；未授权时 `HotkeyManager` 仅日志 + `AppState` 提示 |

**ASR 路径（简表）**

| 音频来源 | 当前实现 |
|----------|----------|
| 麦克风录制的本地 `.caf` | **WhisperASRFallback**（WhisperKit）；可选包内模型目录见 `WhisperModelLocator` |
| 公网可访问 URL 的音频 | **DashScopeASRClient**（Paraformer 异步任务） |

---

## 十四、全局热键（CGEventTap）与 FN/Globe

Phase 1～3 **统一**使用 `HotkeyManager` + **`CGEventTap`**（`flagsChanged` / `keyDown` / `keyUp`），**不再**使用 KeyboardShortcuts。

- **右 Option（0x3D）**：`flagsChanged` 检测按下/抬起，配合 `AppConfig.triggerMode`（Push/Toggle）。
- **FN/🌐（0x3F）**：`flagsChanged` + function 位，约 **75ms** 防抖；无硬件支持时由 `GlobeKeyHardwareCapabilities` 与设置项约束。
- **ESC（53）**：`keyDown` → `Pipeline.cancel()`；Tap 创建失败时可能尝试 `NSEvent` 全局监听作补充，**仍依赖辅助功能**。
- **自定义热键占位**：`HotkeyBindingMode.custom` 时热键不触发录音（仅保留扩展点）。

参考实现：`Entry/HotkeyManager.swift`。第三方 GPL 代码仅借鉴思路，不复制。

---

| 版本 | 日期 | 变更内容 |
|------|------|---------|
| 1.0 | 2026-03-22 | 初始版本 |
| 1.1 | 2026-03-22 | 新增悬浮按钮、改词、账号体系、后端架构、官网 |
| 1.2 | 2026-03-22 | §1 动态层由 `PromptComposer` 生成自然语言；规约第九章补充实现约定 |
| 1.3 | 2026-03-22 | 与实现对齐：CGEventTap、Paraformer/Whisper 路径、剪贴板注入、沙盒表；移除 KeyboardShortcuts 为当前热键方案；关联微架构门禁与预检文档 |

---
# 文档结束
