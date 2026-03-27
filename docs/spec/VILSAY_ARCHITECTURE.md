# VILSAY · 完整架构文档
# 版本：2.0 | 日期：2026-03-21
# ⚠️ 每次开新对话，先把这份文档丢给 AI，再开始开发

---

## 一、产品定位（一句话）

**Vilsay 是输入法的升级替代，不是录音 App。**

用户心智：我要打字的时候，说话就够了。
核心交互：按住热键 → 说话 → 松开 → 文字出现在光标位置。
没有「保存录音、回去查看」这个环节。

---

## 二、产品边界（什么不做）

```
❌ 录音保存
❌ 笔记和文件夹系统
❌ 会议记录和摘要
❌ 多语言 UI（只做中文）
❌ 云同步和账号体系（以后再做）
❌ 多 ASR 供应商切换（只用阿里云）
❌ V1 模式（冻结，不暴露给用户）
```

---

## 三、三 AI 架构

### 职责边界（硬性规定，不可混淆）

```
AI1 · ASR 转写层
  职责：声音 → 文字
  实现：阿里云实时语音识别（流式）
  备用：Whisper.cpp 本地（网络断开时自动降级）
  费用：用户自己的阿里云 API Key
  禁止：做任何文字处理，只管转写

AI2 · 润色层
  职责：粗糙文字 → 这个人想说的话
  实现：Qwen（流式输出）
  费用：用户自己的阿里云 API Key（和 AI1 同一个）
  禁止：等完整段落再处理，必须流式输出

AI3 · Analyzer（用户画像）
  职责：持续学习用户的说话方式
  实现：内置，用开发者的 API Key（用户不可见，不可配置）
  触发：累积 20 条对话后异步触发，不阻塞主链路
  禁止：分析润色后的输出（只分析原始 ASR）
  禁止：阻塞 AI1 或 AI2 的任何操作
  保密：不在任何界面暴露 AI3 的存在
```

### 三 AI 隔离原则

```
AI3 挂了 → AI1 AI2 照常运行
AI2 慢了 → AI3 不受影响
任何一个出问题 → 不能拖垮另外两个
```

---

## 四、完整架构图

```
┌─────────────────────────────────────────────────────────┐
│                      用户层（极简）                       │
│         一个热键  +  一个状态指示灯  +  一个设置页         │
└─────────────────────────────────────────────────────────┘
                            ↓ 热键事件
┌─────────────────────────────────────────────────────────┐
│                    Entry Layer（接入层）                   │
│                                                         │
│  ┌──────────────────┐      ┌──────────────────────┐    │
│  │  HotkeyProcess   │      │   TextInjector       │    │
│  │  独立子进程       │      │   注入目标输入框      │    │
│  │  主进程崩了依然活 │      │   模拟键盘粘贴        │    │
│  └──────────────────┘      └──────────────────────┘    │
│           ↓ IPC                       ↑                 │
│  ┌──────────────────┐                │                  │
│  │  AudioCapture    │                │                  │
│  │  麦克风录音       │                │                  │
│  └──────────────────┘                │                  │
└───────────────────────────────────────────────────────┘
                            ↓ 音频流
┌─────────────────────────────────────────────────────────┐
│                  Core Pipeline（主链路，同步）             │
│                                                         │
│  AudioStream                                            │
│       ↓                                                 │
│  ┌─────────────┐                                        │
│  │   AI1       │  阿里云实时 ASR，流式输出               │
│  │   ASRService│  网络断开自动降级 Whisper.cpp           │
│  └─────────────┘                                        │
│       ↓ 文字流（每个词实时输出）                          │
│  ┌─────────────┐                                        │
│  │  VAD Buffer │  句子边界检测                           │
│  │  断句缓冲层  │  停顿 > 800ms → 触发 AI2              │
│  │             │  停顿 < 800ms → 继续缓冲               │
│  └─────────────┘                                        │
│       ↓ 完整句子                                         │
│  ┌─────────────┐                                        │
│  │   AI2       │  Qwen 润色，流式输出                    │
│  │ PolishService│  System Prompt = 固定层 + 动态层       │
│  └─────────────┘                                        │
│       ↓ 润色后文字流                                     │
│  TextInjector（注入光标位置）                             │
│                                                         │
└─────────────────────────────────────────────────────────┘
                    ↓ 异步，setImmediate，不阻塞
┌─────────────────────────────────────────────────────────┐
│                   AI3 暗线（完全异步）                    │
│                                                         │
│  每次对话结束                                            │
│       ↓                                                 │
│  RawLogger → 写入 SQLite raw_log 表                     │
│       ↓                                                 │
│  Counter → 计数 +1                                      │
│       ↓                                                 │
│  if count >= 20 → 触发 Analyzer（setImmediate）          │
│                         ↓                               │
│                  读取最近 50 条原始记录                   │
│                  + 当前 Profile（用于对比）               │
│                         ↓                               │
│                  调用内置 LLM 分析                        │
│                         ↓                               │
│                  差异对比，只更新变化字段                  │
│                         ↓                               │
│                  写回 SQLite profile 表                  │
│                         ↓                               │
│              下次 AI2 调用自动读取注入                    │
│                                                         │
└─────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────┐
│                   Data Layer（数据层）                    │
│                                                         │
│  SQLite（唯一数据源，不依赖任何云服务）                    │
│                                                         │
│  ┌─────────────┐  ┌─────────────┐  ┌───────────────┐  │
│  │  raw_log    │  │  profile    │  │  dictionary   │  │
│  │  原始 ASR   │  │  用户画像   │  │  词典         │  │
│  │  只追加     │  │  AI3 写入   │  │  AI3 推荐     │  │
│  │  不修改     │  │  AI2 读取   │  │  用户确认     │  │
│  └─────────────┘  └─────────────┘  └───────────────┘  │
│                                                         │
│  Config（内存 + 本地文件）                               │
│  ┌─────────────────────────────────────────────────┐   │
│  │  user_api_key（阿里云，AI1+AI2 共用）            │   │
│  │  hotkey（默认 Shift+G，用户可自定义）             │   │
│  │  asr_mode（cloud/local，默认 cloud）             │   │
│  └─────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

---

## 五、目录结构

```
vilsay/
├── main.js                    # Electron 主进程入口
├── preload.js                 # IPC 暴露
│
├── src/
│   ├── entry/                 # 接入层
│   │   ├── HotkeyProcess.ts   # 热键监听（独立子进程）
│   │   ├── AudioCapture.ts    # 麦克风录音
│   │   └── TextInjector.ts    # 文字注入目标 App
│   │
│   ├── core/                  # 核心业务层
│   │   ├── interfaces.ts      # 所有接口定义
│   │   ├── Pipeline.ts        # 主链路编排
│   │   ├── VADBuffer.ts       # 断句缓冲（800ms）
│   │   ├── ASRService.ts      # AI1：阿里云 ASR
│   │   ├── ASRFallback.ts     # AI1 降级：Whisper.cpp
│   │   ├── PolishService.ts   # AI2：Qwen 润色
│   │   ├── PromptComposer.ts  # Prompt 组装（固定层+动态层）
│   │   ├── Analyzer.ts        # AI3：用户画像分析
│   │   ├── RawLogger.ts       # AI3：原始数据收集
│   │   └── ProfileService.ts  # AI3：Profile 读写
│   │
│   ├── db/                    # 数据层
│   │   ├── database.ts        # SQLite 连接管理
│   │   ├── migrations/        # 数据库迁移脚本
│   │   └── schema.sql         # 表结构定义
│   │
│   ├── ui/                    # 界面层（极简）
│   │   ├── App.tsx            # 根组件
│   │   ├── StatusLight.tsx    # 状态指示灯
│   │   ├── SettingsPage.tsx   # 设置页（只有必要配置）
│   │   └── DictionaryPanel.tsx # 词典确认界面（W5）
│   │
│   └── config/
│       ├── constants.ts       # 常量（触发阈值等）
│       └── prompts.ts         # AI2 固定 Prompt 层
│
└── resources/
    └── bin/                   # 原生二进制（globe-listener 等）
```

---

## 六、接口定义（核心，不可随意修改）

```typescript
// src/core/interfaces.ts

// AI1
interface ASRService {
  stream(audio: AudioStream): AsyncIterable<string>
  // 流式输出每个识别到的词，不做任何处理
}

// VAD 缓冲层
interface VADBuffer {
  feed(text: string): void
  // 内部检测停顿，超过 800ms 触发 onSentence
  onSentence(callback: (sentence: string) => void): void
}

// AI2
interface PolishService {
  stream(sentence: string, profile?: UserProfile): AsyncIterable<string>
  // 有 profile 就用，没有也能正常工作
}

// AI3 数据收集
interface RawLogger {
  log(raw: string, polished: string): void
  // 异步写入，调用方不等待
}

// AI3 分析触发
interface Analyzer {
  checkAndRun(userId: string): void
  // 内部判断是否达到触发阈值，达到则异步运行
}

// Profile 读写
interface ProfileService {
  get(userId: string): UserProfile | null
  update(userId: string, profile: Partial<UserProfile>): void
}

// 用户画像结构
interface UserProfile {
  habitualWords: Array<{
    word: string
    action: 'keep' | 'simplify' | 'remove'
    confidence: number
    frequency: number
  }>
  thinkingStyle: {
    openingPattern: string     // 展开方式
    topicSwitchSignals: string[] // 话题切换信号词
    closingSignals: string[]   // 收尾信号词
    confidence: number
  }
  toneProfile: {
    directness: 'direct' | 'indirect'
    formality: 'formal' | 'casual' | 'mixed'
    sentenceLength: 'short' | 'medium' | 'long'
    confidence: number
  }
  dictionary: Array<{
    type: 'person' | 'project' | 'term' | 'place'
    word: string
    note: string
    confidence: number
  }>
  meta: {
    version: number
    lastUpdated: string
    sessionsAnalyzed: number
    totalSessions: number
  }
}
```

---

## 七、AI2 Prompt 结构

### 固定层（代码写死，不随用户变化）

```
## §0 身份内核
你是一位语言整理师，处理语音识别（ASR）产生的原始文字。
任务是还原说话人的真实意图，不是逐字复现，不是重写。

原则一：忠于意图，而非字面
原则二：最小干预，风格是资产不是错误
原则三：推断用 [推断] 标注，不确定用 [待确认] 标注

## §2 处理规则
P1 自我纠正：「A——不对/等一下——B」→ 保留 B
P2 填充词：强噪声删除，弱噪声参考用户习惯
P3 同音字：结合上下文推断，置信度<0.7 标注
P4 断句：按语义单位重组，参考用户风格
P5 多语言：中英分别处理，专有名词锁定原语言
```

### 动态层（运行时从 SQLite 读取，§1 区）

```
## §1 用户专属（由 AI3 自动更新）
### §1.1 口头禅与保留词
[从 profile.habitualWords 注入]

### §1.2 思维结构
[从 profile.thinkingStyle 注入]

### §1.3 语气风格
[从 profile.toneProfile 注入]

### §1.4 词典
[从 profile.dictionary 注入]
```

**§1 区为空时：系统正常工作，进入观察模式，不主动调整风格。**

---

## 八、数据库表结构

```sql
-- 原始语料（只追加，不修改，不删除）
CREATE TABLE raw_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  raw_text TEXT NOT NULL,           -- ASR 原始输出
  polished_text TEXT NOT NULL,      -- AI2 润色结果
  scene TEXT,                       -- 识别的场景类型
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  analyzed INTEGER DEFAULT 0        -- 是否已被 AI3 分析
);

-- 用户画像（AI3 写，AI2 读）
CREATE TABLE user_profile (
  id INTEGER PRIMARY KEY,
  profile_json TEXT NOT NULL,       -- UserProfile JSON
  version INTEGER DEFAULT 1,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- 词典候选（AI3 推荐，用户确认）
CREATE TABLE dictionary_candidates (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  word TEXT NOT NULL,
  type TEXT NOT NULL,
  note TEXT,
  status TEXT DEFAULT 'pending',    -- pending/approved/rejected
  confidence REAL DEFAULT 0.5,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- AI3 触发计数
CREATE TABLE analyzer_state (
  id INTEGER PRIMARY KEY,
  session_count INTEGER DEFAULT 0,  -- 累计对话数
  last_analyzed_at DATETIME,        -- 上次分析时间
  last_analyzed_session INTEGER     -- 上次分析时的 session_count
);
```

---

## 九、关键常量

```typescript
// src/config/constants.ts

export const ANALYZER_TRIGGER_THRESHOLD = 20  // 每 20 次对话触发一次 AI3
export const ANALYZER_RECENT_SESSIONS = 50    // AI3 分析最近 50 条记录
export const VAD_PAUSE_MS = 800               // 停顿超过 800ms 触发 AI2
export const POLISH_TIMEOUT_MS = 5000         // AI2 超时时间
export const PROFILE_MAX_DICT_ITEMS = 200     // 词典最大条目数
export const PROFILE_MIN_CONFIDENCE = 0.3     // 置信度低于此值自动清理
```

---

## 十、已知隐患（开发时注意）

| 隐患 | 说明 | 处理方式 |
|------|------|---------|
| 冷启动 | 前 20 次无 Profile，体验和普通工具一样 | 内置默认规则兜底 |
| 热键冲突 | Shift+G 在某些 App 有原生功能 | 设置页允许自定义热键 |
| VAD 误判 | 说话停顿被误判为句子结束 | 800ms 阈值可在设置里调整 |
| Profile 膨胀 | 长期使用后 Profile 越来越大 | confidence < 0.3 自动清理 |
| AI3 失败 | Analyzer 调用失败 | 静默失败，下次触发时重试 |
| 主进程崩溃 | 热键失效 | HotkeyProcess 独立子进程，不受影响 |
| 网络断开 | 阿里云 ASR 不可用 | 自动降级 Whisper.cpp 本地 |

---

## 十一、开发顺序（五周计划）

```
W1：主链路（最高优先级）
  ✅ HotkeyProcess 独立子进程
  ✅ AudioCapture 录音
  ✅ ASRService 阿里云流式
  ✅ VADBuffer 断句缓冲（800ms）
  ✅ PolishService Qwen 流式
  ✅ TextInjector 注入输入框
  成功标准：热键 → 说话 → 文字注入，延迟 < 1.5 秒

W2：AI3 数据层
  ✅ raw_log 表 + RawLogger
  ✅ analyzer_state 表 + 计数器
  ✅ 触发逻辑（setImmediate，不阻塞）
  成功标准：每次对话自动写入，计数正确

W3：AI3 分析层
  ✅ Analyzer.ts + AI3 Prompt
  ✅ ProfileService 读写
  ✅ 差异对比机制
  成功标准：手动触发一次，人工验证 Profile 质量

W4：动态注入
  ✅ PromptComposer 组装固定层+动态层
  ✅ AI2 调用时自动读取 Profile
  成功标准：润色质量有可感知的提升

W5+：词典半自动化
  ✅ AI3 推荐候选词 → dictionary_candidates 表
  ✅ DictionaryPanel 角标提示 + 确认界面
  成功标准：用户三秒内完成一条词典确认
```

---

## 十二、给每次对话 AI 的初始化指令

**每次新开对话，把这段话发给 AI：**

```
我在开发 Vilsay，一个 macOS 桌面语音润色 App。
请先读取 VILSAY_ARCHITECTURE.md 了解完整架构。
这个 App 有三个 AI：
- AI1：阿里云 ASR 流式转写
- AI2：Qwen 流式润色，Prompt 分固定层和动态层
- AI3：内置用户画像分析，每 20 次对话触发，用户不可见
技术栈：Electron + React + TypeScript
现在进行到：[告诉 AI 当前在做哪一周的哪个模块]
当前问题：[描述具体问题]
```

---

## 十三、不做的决定（以后有人问要能解释）

| 功能 | 为什么不做 |
|------|----------|
| 录音保存 | 定位冲突，Vilsay 是输入替代，不是录音工具 |
| 笔记系统 | 需要配套分析功能才有价值，单独保存没人看 |
| 多 ASR 供应商 | 维护成本高，阿里云体系已经够用 |
| 账号体系 | 等 AI3 Profile 真正有价值了用户才需要同步 |
| V1 模式 | 对外只有一个模式，V1 代码保留作回滚用 |
| Provider Registry | 对我们是过度设计，供应商不会频繁切换 |

---
# 文档结束
# 每次架构调整后更新此文档，保持和代码同步
```
