# CLAUDE.md
# Cursor 开发初始化文件
# ⚠️ 每次开新对话 Cursor 会自动读取此文件
# ⚠️ 不要删除或重命名此文件

---

## 项目概览

**产品名：** Vilsay
**类型：** macOS 原生语音润色 App
**技术栈：** Swift 5.9+ / SwiftUI / macOS 14+
**职责：** Cursor 负责开发，Kimi 负责测试验证

---

## 必读文档（每次开发前确认已读）

```
Docs/VILSAY_TECH_ARCH.md     技术架构、接口定义、数据结构
Docs/VILSAY_UI_UX.md         界面规范、文案规范、交互规范
Docs/VILSAY_DEV_TASKS.md     任务清单、当前进度、验收标准
Docs/voice_polish_prompt.md  V2 Prompt 完整设计（直接用于 Prompts.swift）
```

需要时参考：
```
Docs/VILSAY_PRD.md           产品需求、竞品对照
Docs/VILSAY_ONBOARDING.md    Onboarding 状态机（Week 6 后开发）
Docs/voice_ai_architecture.md AI3 架构推导过程
```

---

## 三个 AI 的职责边界

```
AI-1  阿里云 DashScope 流式 ASR（主）
      WhisperKit 本地（断网自动降级）
      只管声音变文字，不做任何文字处理

AI-2  Qwen 流式润色
      System Prompt = §0§2 固定层 + §1 动态层（来自 AI3）
      只管文字润色，不管数据存储

AI-3  内置 Qwen 分析，用开发者 Key，用户完全不可见
      异步运行，任何情况不阻塞 AI-1 和 AI-2
      只分析原始 ASR，不读润色结果
```

---

## 开发原则

```
1. 先前端后后端
2. 先主链路后 AI3
3. 主链路代码不动，新功能只加不改
4. 出错静默失败，写日志，不弹窗打断用户
5. 每完成一个 Task 更新 VILSAY_DEV_TASKS.md 状态
6. 不确定的设计决策问架构师，不自行决定
```

---

## 目录结构

```
Vilsay/
├── App/          App 入口、AppDelegate
├── Entry/        热键、悬浮按钮、录音、文字注入
├── Core/         主链路：Pipeline、VAD、ASR、润色、改词
├── AI3/          用户画像：RawLogger、Analyzer、Profile
├── Auth/         账号登录：Apple、微信、Google、邮箱
├── DB/           SQLite：GRDB、Schema、Migrations
├── UI/           界面：菜单栏、悬浮按钮、设置、词典
├── Config/       常量、Prompt 固定层、运行时配置
└── Utils/        日志、网络监控
```

---

## 关键常量（不可随意修改）

```swift
analyzerTriggerThreshold = 20   // AI3 触发阈值
analyzerRecentSessions = 50     // AI3 分析条数
vadPauseMs = 800                // VAD 断句阈值
maxTotalLatencyMs = 1500        // 性能死亡线
polishTimeoutMs = 5000          // AI2 超时
profileMinConfidence = 0.3      // Profile 清理阈值
```

---

## 当前开发进度

> ⚠️ 每次完成 Task 后在 VILSAY_DEV_TASKS.md 更新状态

当前 Week：**Week 1**
当前 Task：**W1-01 创建 Xcode 项目**

---

## 交付给 Kimi 测试的规范

每个 Task 完成后：
1. 在 VILSAY_DEV_TASKS.md 标注 ✅ 和完成日期
2. 写清楚「验收标准」是否全部通过
3. 遇到问题记录在「未知风险登记表」
4. Kimi 会根据任务书的验收标准逐项测试
