# VILSAY · 技术架构文档
# Tech Architecture Document
# 版本：1.4 | 日期：2026-03-25
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

### 2.1 系统架构（闭环）

```
┌───────────────────────────────────────────────────────┐
│                    用户层                              │
│    Typeless 风格浮层胶囊  +  菜单栏状态图标            │
│    录音中：红点+波形+✕ | 处理中："思考中..." | 完成预览  │
└───────────────────────────────────────────────────────┘
                          ↓ 热键 / 按钮事件
┌───────────────────────────────────────────────────────┐
│                  Entry Layer 接入层                    │
│  HotkeyManager       FloatingPill        TextInjector │
│  CGEventTap（需辅助功能） NSPanel capsule  剪贴板粘贴注入 │
│                   TargetAppMonitor                    │
│                   捕获目标App bundleID → 域名提示       │
└───────────────────────────────────────────────────────┘
              ↓ 音频流 + App上下文           ↑ 润色文字
┌───────────────────────────────────────────────────────┐
│              Core Pipeline 主链路（同步）               │
│                                                       │
│  AudioCapture → ASR → VADBuffer → PromptComposer     │
│  AVAudioEngine  Paraformer REST                → PolishService │
│                WhisperKit（本地 caf）             Qwen SSE │
│                ↓ confidence                           │
│  ASR 输出含置信度(avgLogprob) → 低置信区域标注 → AI2   │
│                                                       │
│  SelectSpeakService（改词模式）                        │
│  检测选中文字 → 特殊 Prompt → 替换原文                 │
└───────────────────────────────────────────────────────┘
              ↓ 异步 Task，不阻塞主链路    ↑ 误差反馈
┌───────────────────────────────────────────────────────┐
│           AI3 暗线（完全异步 + 闭环反馈）              │
│                                                       │
│  RawLogger → AnalyzerTrigger → AI3Analyzer            │
│  写入raw_log  计数满20条触发    Qwen分析画像           │
│  +asr_confidence               ↓                     │
│  +user_flagged     →      ProfileService              │
│  +target_app_id              写入user_profile          │
│                              推荐词写入candidates       │
│                              ↓                        │
│                         语言报告卡（显式）              │
│                         用户逐条保留/删除标签           │
│                                                       │
│  ◆ 闭环路径：                                         │
│    用户标记"有误" → raw_log.user_flagged_error=true    │
│    → AI3 分析错误模式 → 更新词典/画像                  │
│    → PromptComposer 下轮注入修正提示                   │
└───────────────────────────────────────────────────────┘
              ↓                         ↑ 账号/用量
┌─────────────────┐         ┌───────────────────────────┐
│   Data Layer    │         │      Backend Server       │
│   本地 SQLite   │         │                           │
│   raw_log       │         │  ◆ 混合计费模式           │
│   user_profile  │         │  无Key用户→Pro计划(代理)   │
│   dictionary    │         │  自带Key→直连DashScope     │
│   candidates    │         │                           │
│   analyzer_state│         │   账号 / 计费 / 用量统计   │
│                 │         │   PostgreSQL + Redis       │
│                 │         │   REST API / JWT           │
│                 │         │                           │
│                 │         │      产品官网              │
│                 │         │   Next.js + 用量查看       │
└─────────────────┘         └───────────────────────────┘
```

### 2.2 商业模式（混合制）

| 用户类型 | API Key | 请求路径 | 计费方 |
|----------|---------|----------|--------|
| 免费/Pro 用户 | 无自有 Key | App → 自有后端(代理) → DashScope | Vilsay 后端计费 |
| 自带 Key 用户 | 有 DashScope Key | App → DashScope 直连 | 用户自费 |

`AppConfig` 路径判断：有 Key → 直连，无 Key → 后端代理。Pro 计划包含 ASR + 润色额度，自带 Key 用户免服务器成本。

### 2.3 开环 → 闭环演进

**V1（当前，开环）**：ASR → 润色 → 注入，无纠错反馈路径。错误不会自动改善。

**V1.5（Week 5-6，半闭环）**：
- ASR 置信度透传至 AI2，低置信区域更激进纠偏
- 用户可在浮层标记"有误"，写入 `raw_log.user_flagged_error`
- AI3 分析错误模式 → 更新词典/画像 → 下轮 Prompt 注入修正
- 拼音同音纠偏：`CFStringTransform` 将 ASR 输出和词典转拼音，匹配相似度

**V2（远期）**：WER 自动追踪、错误分类统计、Prompt A/B 测试

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
// AI1 — ASR 输出结构
struct ASRResult {
    let text: String
    let confidence: Double      // WhisperKit: avgLogprob → 归一化 0~1；Paraformer: 整段置信度
    let provider: ASRProvider   // .whisperKit / .dashScope
}

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

// AI2 — 润色（接收 App 上下文 + ASR 置信度）
protocol PolishService {
    func polish(_ text: String,
                profile: UserProfile?,
                asrConfidence: Double?,
                targetAppBundleID: String?) async throws -> AsyncStream<String>
}

// 改词
protocol SelectSpeakService {
    func getSelectedText() -> String?
    func edit(original: String, instruction: String) async throws -> AsyncStream<String>
}

// AI3 — 日志含置信度 + 错误标记
protocol RawLogger {
    func log(raw: String, polished: String,
             asrConfidence: Double?, targetAppBundleID: String?)
}

protocol ProfileService {
    func get() -> UserProfile?
    func update(_ profile: UserProfile)
    func getCandidates() -> [DictionaryCandidate]
    func approveCandidate(_ id: Int)
    func rejectCandidate(_ id: Int)
}

// 用户错误反馈（闭环路径）
protocol ErrorFeedbackService {
    func flagError(logId: Int64)         // 用户在浮层点"有误"
    func getFlaggedErrors() -> [RawLogEntry]  // AI3 分析用
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

raw_log:                     // 原始语料，只追加
  id: Int64 (PK)
  raw_text: String           // ASR 原始输出
  polished_text: String      // 润色结果
  asr_provider: String       // "whisperKit" / "dashScope"
  asr_confidence: Double?    // ★ 新增：ASR 置信度（0~1）
  target_app_id: String?     // ★ 新增：目标 App bundleIdentifier
  user_flagged_error: Bool   // ★ 新增：用户标记"有误"（闭环反馈）
  created_at: Date

user_profile:                // AI3 画像（JSON 存储）
  id: Int64 (PK)
  profile_json: String       // UserProfile 序列化
  updated_at: Date

dictionary:                  // 用户词典
  id: Int64 (PK)
  word: String
  type: String               // 术语/人名/口头禅/…
  pinyin: String?            // ★ 新增：拼音（CFStringTransform 生成，同音纠偏用）
  source: String             // "ai3" / "user_manual"
  created_at: Date

dictionary_candidates:       // AI3 推荐候选词
  id: Int64 (PK)
  word: String
  type: String
  state: String              // "pending" / "approved" / "dismissed"
  pinyin: String?            // ★ 新增
  created_at: Date

analyzer_state:              // AI3 触发状态
  id: Int64 (PK)
  unanalyzed_count: Int
  last_analyzed_log_id: Int64?  // ★ 新增：上次分析到的 raw_log.id（去重）
  last_triggered_at: Date?

// 远端 PostgreSQL（服务器端）
users:                用户账号
auth_providers:       第三方登录关联
sessions:             登录会话
usage_records:        使用记录（含 asr_provider、is_byok 标记）
subscriptions:        订阅状态（free / pro / byok）
```

---

## 九、V3 Prompt 结构（含 App 上下文与 ASR 置信度）

V3 在 V2 基础上新增两个上下文层：App 域名提示（零冷启动）和 ASR 置信度提示（自适应纠偏强度）。

```
§0 身份内核（固定层）
你是一位语言整理师，处理 ASR 产生的原始文字。
任务是还原说话人的真实意图，不是逐字复现，不是重写。
原则一：忠于意图，而非字面
原则二：最小干预
原则三：推断用 [推断] 标注

§A App 上下文提示（动态层，零冷启动，TargetAppMonitor 提供）
由 PromptComposer 根据 targetAppBundleID → 域名映射生成：
  - com.apple.mail / com.tencent.foxmail → "用户正在写邮件，注意正式语体"
  - com.tencent.xinWeChat / com.apple.MobileSMS → "用户在聊天，保留口语化表达"
  - com.microsoft.Word / com.apple.Pages → "用户在写文档，注意段落完整性"
  - 未知 App → 不注入此层（最小干预原则）
映射表维护在 PromptComposer.appContextMap，可扩展。

§C ASR 置信度提示（动态层，Pipeline 传入）
当 ASR 置信度 < asrLowConfidenceThreshold 时注入：
  "本次语音识别置信度较低（{confidence}），请特别注意同音字纠偏，
   对不通顺的词组优先尝试同音替换。"
高置信度时不注入此层（最小干预原则）。

§1 用户专属（动态层，从本地 SQLite 读取，AI3 生成）
§1.1 口头禅与保留词
§1.2 思维结构特征
§1.3 语气与风格
§1.4 高频词典
§1.P 拼音同音纠偏提示（词典中有 pinyin 字段的条目）
  "以下词汇容易被 ASR 误识别为同音词，遇到发音相似的错误请优先替换：
   [词典词] (pinyin) → 常见误识别：[同音错误示例]"

§2 处理规则（固定层）
P1 自我纠正识别
P2 填充词处理
P3 同音字纠偏（V3 增强：结合 §1.P 拼音提示）
P4 断句重组
P5 多语言边界

完整拼接顺序：§0 → §A（可选）→ §C（可选）→ §1（可选）→ §2
```

**实现约定：**
- **不得**在 `Prompts` 固定字符串中直接拼接占位符
- 结构化数据由 `PromptComposer` 在代码层拼成**自然语言段落**
- §A 和 §C 为零冷启动层，无需用户数据积累即可工作（Day 1 可用）
- §1 需 AI3 积累 20 次使用后才有数据
- 见 `Core/PromptComposer.swift`、`Config/UserProfile.swift`

**拼音同音纠偏实现（§1.P）：**
- 使用 macOS 内置 `CFStringTransform(kCFStringTransformMandarinLatin)` 转拼音
- 词典入库时自动生成 pinyin 字段
- PromptComposer 将高频词典中有 pinyin 的条目生成纠偏提示
- 比 MiniLM 嵌入更适合中文同音字场景，零额外依赖

**改词模式专用 Prompt（SelectSpeak）：**
接收 [原文] + [用户指令]，只输出修改结果

---

## 十、关键常量

```swift
enum Constants {
    // — 原有 —
    static let analyzerTriggerThreshold = 20
    static let analyzerRecentSessions = 50
    static let vadPauseMs = 800
    static let maxTotalLatencyMs = 1500   // 死亡线
    static let polishTimeoutMs = 5000
    static let profileMinConfidence: Double = 0.3
    static let profileMaxDictItems = 200
    static let asrFallbackModel = "openai_whisper-base"
    static let floatingButtonDefaultPosition = CGPoint(x: 100, y: 200)

    // — V1.4 新增 —
    static let asrLowConfidenceThreshold: Double = 0.4   // 低于此值注入 §C 置信度提示
    static let pinyinSimilarityThreshold: Double = 0.8   // 拼音相似度阈值（编辑距离归一化）
    static let pipelineAbsoluteDeadlineMs = 35_000       // Pipeline 绝对超时（防 continuation 泄漏）
    static let polishResourceTimeoutMs = 30_000          // SSE 总时长上限（timeoutIntervalForResource）
    static let floatingPillPreviewDurationMs = 2_000     // 完成后预览文字显示时长
    static let floatingPillPreviewMaxChars = 20          // 预览文字截取长度
}
```

---

## 十一、已知隐患

| 隐患 | 风险 | 处理方案 | 状态 |
|------|------|---------|------|
| 悬浮按钮遮挡内容 | 中 | 用户可拖动，默认位置远离中心 | — |
| 改词时 AXUIElement 读取失败 | 中 | 降级为普通输入模式 | — |
| 微信登录审核周期长 | 高 | 先上线其他3种，微信后补 | — |
| VAD 误判停顿 | 中 | 800ms 可在设置调整；当前主断句边界多为**松键** | — |
| ASR 断网 / 本地录音路径 | 中 | 麦克风录音走 **WhisperKit**；Paraformer 需公网 URL | — |
| **辅助功能未授权** | **高** | Onboarding 引导 + `AppState.hotkeyAccessibilityRequired` | — |
| 沙盒下首次拉取 Whisper 模型 | 中 | 需 `network.client`；或 Bundle 嵌入 | — |
| AXUIElement 权限被拒 | 高 | Onboarding 明确引导 | — |
| macOS 14 以下不支持 | 中 | App Store 设置最低版本 | — |
| 后端 TBD 导致延期 | 中 | 先做客户端，后端并行开发 | — |
| ~~流式粘贴剪贴板竞态~~ | ~~高~~ | ~~已修复：单次累积粘贴~~ | ✅ 已解决 |
| ~~SSE keep-alive 无限挂~~ | ~~高~~ | ~~已修复：timeoutIntervalForResource=30s~~ | ✅ 已解决 |
| ~~continuation 泄漏~~ | ~~高~~ | ~~已修复：35s TaskGroup 绝对 deadline~~ | ✅ 已解决 |
| ASR 无错误反馈路径（开环） | 高 | V1.4 闭环：置信度透传 + 用户标记 + AI3 学习 | W5-6 开发中 |
| free_monthly_quota=500 vs 规约200 | 低 | 待产品确认 | 待定 |
| AppError 未统一 | 中 | W6 打磨 | W6 |
| jwt_secret 硬编码 | 高 | 生产必须改环境变量 | 上线前 |
| dev_expose_verification_token=True | 高 | 生产必须改 False | 上线前 |

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

## 十五、质量度量与持续优化

### 15.1 质量指标

| 指标 | 数据来源 | 用途 |
|------|----------|------|
| ASR 置信度分布 | raw_log.asr_confidence | 监控 ASR 质量，低置信度高占比 → 提示用户改善录音环境 |
| 用户标记错误率 | raw_log.user_flagged_error / total | 衡量端到端质量；目标 < 5% |
| AI3 词典命中率 | 润色时词典匹配次数 / 总润色次数 | 衡量个性化学习有效性 |
| 拼音纠偏命中率 | 同音替换采纳次数 / 候选次数 | 评估拼音纠偏精度 |

### 15.2 错误分类（AI3 分析维度）

| 错误类型 | 示例 | 纠正策略 |
|----------|------|----------|
| 同音字 | "事业" → "试验" | 拼音匹配 + 词典 |
| 吞字/多字 | "我们去" → "我去" | ASR 置信度低区域提示 |
| 语序混乱 | 口语自我纠正 | P1 规则（自我纠正识别） |
| 专有名词 | 人名/术语 | 词典 + App 上下文 |

### 15.3 远期：Prompt A/B 测试框架

当积累足够错误样本后，可对比不同 Prompt 策略的纠错率。当前阶段仅做数据采集，不做自动 A/B。

---

| 版本 | 日期 | 变更内容 |
|------|------|---------|
| 1.0 | 2026-03-22 | 初始版本 |
| 1.1 | 2026-03-22 | 新增悬浮按钮、改词、账号体系、后端架构、官网 |
| 1.2 | 2026-03-22 | §1 动态层由 `PromptComposer` 生成自然语言；规约第九章补充实现约定 |
| 1.3 | 2026-03-22 | 与实现对齐：CGEventTap、Paraformer/Whisper 路径、剪贴板注入、沙盒表；移除 KeyboardShortcuts 为当前热键方案；关联微架构门禁与预检文档 |
| 1.4 | 2026-03-25 | **闭环架构演进**：§2 架构图改为闭环（用户反馈→AI3→Prompt）；新增 §2.2 混合商业模式、§2.3 开环→闭环演进路径；§7 接口增加 ASR 置信度 + App 上下文参数 + ErrorFeedbackService；§8 DB 表增加 asr_confidence/user_flagged_error/pinyin/last_analyzed_log_id 字段；§9 升级 V3 Prompt（§A App 上下文 + §C 置信度 + §1.P 拼音纠偏）；§10 新增 6 个常量；§11 隐患表增加已解决项和新项；新增 §15 质量度量 |

---
# 文档结束
