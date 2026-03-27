# Week 5 + 6 · Cursor 开发任务书

**版本**: 1.1 | **日期**: 2026-03-25
**前置阅读**: `docs/spec/VILSAY_TECH_ARCH.md`、`docs/spec/voice_polish_prompt.md`、`docs/VILSAY_TECH_SPEC_SUPPLEMENT.md`
**架构师**: Claude | **开发**: Cursor

> **调整说明（2026-03-25）**：
> - Week 5 = AI3 数据层 + 分析层（原计划不变）
> - Week 6 = 联调打磨 + 上架准备（原计划不变）
> - **Week 7（新）** = Onboarding 完整实现 + 官网（从 Week 6+ 移入，单独排期）
> - Week 6 结束后进行全程序 Review，再进入 Week 7

---

## 开发原则（本阶段特别约束）

```
1. AI3 暗线铁律：AI3 任何操作（写 DB、调 Qwen）必须在 Task.detached(priority: .background) 中执行
   不得 await 在主链路上；任何情况下 Pipeline 不等 AI3 结果
2. DB 操作封装：所有 SQLite 读写通过 DB/ 层暴露接口，UI/Core 不直接操作 GRDB
3. PromptComposer 不改 Prompts.swift：§0§2 固定层只读；§1 由 PromptComposer 在运行时拼装
4. 置信度门禁：profile 字段 confidence < Constants.profileMinConfidence(0.3) 时不注入 §1
5. 本周不改 Pipeline.swift 主链路逻辑，只在末尾加 RawLogger 旁路钩子
```

---

## 任务总览

| Week | ID | 摘要 | 依赖 |
|------|-----|------|------|
| **W5** | W5-01 | GRDB SQLite 初始化：建库、Schema、迁移 | - |
| **W5** | W5-02 | RawLogger：Pipeline 末尾异步写入 raw_log | W5-01 |
| **W5** | W5-03 | DictionaryView DB 接入：替换假数据 | W5-01 |
| **W5** | W5-04 | AnalyzerTrigger：计数满 20 触发 AI3 | W5-02 |
| **W5** | W5-05 | AI3Analyzer：读日志 → Qwen 分析 → 写 Profile + Candidates | W5-04 |
| **W5** | W5-06 | PromptComposer V3：§A App上下文 + §C 置信度 + §1 画像 + §1.P 拼音 | W5-05 |
| **W5** | W5-07 | 词典推荐 UI 接入：Tab2 真实数据 + 角标 | W5-05 |
| **W5** | W5-08 | 清除数据接入：设置页按钮真实执行 | W5-01 |
| **W6** | W6-01 | 浮层重设计：Typeless 风格 pill + 取消按钮 + 波形 | - |
| **W6** | W6-02 | 菜单栏图标优化 + 录音中"停止"菜单项 | - |
| **W6** | W6-03 | 性能验证（死亡线 1500ms） | W5 全部 |
| **W6** | W6-04 | 边界场景覆盖测试 | W6-03 |
| **W6** | W6-05 | App Store 材料准备 | - |
| **W6** | W6-06 | 隐私政策页（App 内嵌） | - |
| **W6** | W6-07 | TestFlight 内测上传 | W6-03~06 |

---

## WEEK 5 · AI3 + 数据层

---

### W5-01 · GRDB SQLite 初始化

```
目标文件：
  vilsay/DB/Database.swift         ← 单例，GRDB DatabasePool
  vilsay/DB/Schema.swift           ← 所有 Record 结构体 + TableRecord
  vilsay/DB/Migrations.swift       ← 迁移序列（版本号 1 起步）
  vilsay/App/AppDelegate.swift     ← 启动时调用 AppDatabase.shared.setup()

表结构（5张表）：

1. raw_log
   - id:           INTEGER PRIMARY KEY AUTOINCREMENT
   - asr_text:     TEXT NOT NULL          ← 原始 ASR 文字（AI3 分析用）
   - polished_text:TEXT NOT NULL          ← 润色结果
   - duration_ms:  INTEGER                ← ASR 耗时
   - session_id:   TEXT                   ← Pipeline 本次会话 UUID
   - asr_provider: TEXT                   ← ★ 新增："whisperKit"|"dashScope"
   - asr_confidence: REAL                 ← ★ 新增：ASR 置信度 0~1（WhisperKit avgLogprob 归一化）
   - target_app_id: TEXT                  ← ★ 新增：目标 App bundleIdentifier
   - user_flagged_error: INTEGER DEFAULT 0 ← ★ 新增：用户标记"有误"（闭环反馈）
   - created_at:   TEXT NOT NULL          ← ISO8601

2. user_profile
   - id:           INTEGER PRIMARY KEY AUTOINCREMENT
   - key:          TEXT NOT NULL UNIQUE   ← "habitual_words"|"thinking_style"|"tone"|"dictionary"
   - value:        TEXT NOT NULL          ← JSON 字符串（具体格式见 W5-05）
   - confidence:   REAL NOT NULL DEFAULT 0.0
   - updated_at:   TEXT NOT NULL

3. dictionary
   - id:           INTEGER PRIMARY KEY AUTOINCREMENT
   - word:         TEXT NOT NULL UNIQUE
   - context:      TEXT                   ← 用户备注或 AI3 上下文
   - pinyin:       TEXT                   ← ★ 新增：CFStringTransform 生成，同音纠偏用
   - source:       TEXT NOT NULL          ← "manual"|"ai"
   - created_at:   TEXT NOT NULL

4. dictionary_candidates
   - id:           INTEGER PRIMARY KEY AUTOINCREMENT
   - word:         TEXT NOT NULL
   - score:        REAL NOT NULL DEFAULT 0.5
   - context:      TEXT
   - pinyin:       TEXT                   ← ★ 新增
   - state:        TEXT DEFAULT "pending" ← ★ 改为文本枚举："pending"|"approved"|"dismissed"
   - from_analysis_at: TEXT NOT NULL

5. analyzer_state
   - id:           INTEGER PRIMARY KEY DEFAULT 1  ← 只有一行
   - total_logged_count:   INTEGER NOT NULL DEFAULT 0
   - last_trigger_count:   INTEGER NOT NULL DEFAULT 0
   - last_analyzed_log_id: INTEGER         ← ★ 新增：上次分析到的 raw_log.id（去重）
   - last_run_at:          TEXT

GRDB Record 示例（Schema.swift）：
  struct RawLogRecord: FetchableRecord, PersistableRecord {
      var id: Int64?
      var asrText: String
      var polishedText: String
      var durationMs: Int?
      var sessionId: String?
      var createdAt: String
      static var databaseTableName = "raw_log"
  }
  // 其余 4 个表同样定义 Record 结构体

迁移（Migrations.swift）：
  static func registerMigrations(_ migrator: inout DatabaseMigrator) {
      migrator.registerMigration("v1_create_tables") { db in
          // CREATE TABLE raw_log ...
          // CREATE TABLE user_profile ...
          // ...（5 张表）
          // INSERT OR IGNORE INTO analyzer_state (id) VALUES (1)
      }
  }

Database.swift 单例：
  final class AppDatabase {
      static let shared = AppDatabase()
      private(set) var dbPool: DatabasePool!

      func setup() throws {
          let url = try FileManager.default
              .url(for: .applicationSupportDirectory, in: .userDomainMask,
                   appropriateFor: nil, create: true)
              .appendingPathComponent("vilsay/vilsay.sqlite")
          try FileManager.default.createDirectory(
              at: url.deletingLastPathComponent(),
              withIntermediateDirectories: true)
          dbPool = try DatabasePool(path: url.path)
          var migrator = DatabaseMigrator()
          Migrations.registerMigrations(&migrator)
          try migrator.migrate(dbPool)
      }
  }

验收：
□ App 冷启动后 ~/Library/Application Support/vilsay/vilsay.sqlite 存在
□ sqlite3 命令查询 5 张表结构正确
□ analyzer_state 表有 id=1 的初始行
□ 重启后已有数据保留（迁移幂等）
```

---

### W5-02 · RawLogger：Pipeline 末尾异步写入

```
目标文件：
  vilsay/AI3/RawLogger.swift       ← 实现
  vilsay/Core/Pipeline.swift       ← 末尾添加钩子（只加，不改主链路）

RawLogger.swift：
  enum RawLogger {
      /// 异步写入 raw_log，并通知 AnalyzerTrigger 计数。
      /// 必须在 Task.detached(priority: .background) 中调用，不阻塞调用方。
      static func logAsync(asr: String, polished: String,
                           durationMs: Int, sessionId: String,
                           asrProvider: String? = nil,
                           asrConfidence: Double? = nil,
                           targetAppBundleID: String? = nil) {
          Task.detached(priority: .background) {
              let trimmedASR = asr.trimmingCharacters(in: .whitespacesAndNewlines)
              let trimmedPolished = polished.trimmingCharacters(in: .whitespacesAndNewlines)
              guard !trimmedASR.isEmpty else { return }
              do {
                  try AppDatabase.shared.dbPool.write { db in
                      var record = RawLogRecord(
                          asrText: trimmedASR,
                          polishedText: trimmedPolished,
                          durationMs: durationMs,
                          sessionId: sessionId,
                          asrProvider: asrProvider,
                          asrConfidence: asrConfidence,
                          targetAppBundleID: targetAppBundleID,
                          userFlaggedError: false,
                          createdAt: ISO8601DateFormatter().string(from: Date())
                      )
                      try record.insert(db)
                      // 同步更新 analyzer_state total_logged_count
                      try db.execute(sql: """
                          UPDATE analyzer_state
                          SET total_logged_count = total_logged_count + 1
                          WHERE id = 1
                      """)
                  }
                  // 计数后通知触发器检查
                  await AnalyzerTrigger.shared.checkAndFire()
              } catch {
                  // 静默失败，不影响主链路
              }
          }
      }
  }

Pipeline.swift 接入点（在 runPolishInjectAfterVAD 末尾，AppState 更新之前）：
  // 在 fullPolishForTrace 有值且非空时写入
  let sid = UUID().uuidString
  RawLogger.logAsync(
      asr: asrText,
      polished: fullPolishForTrace,
      durationMs: Int(asrMs),
      sessionId: sid
  )
  // ⚠️ 不 await，不阻塞

取消路径（Pipeline.cancel()）不调用 RawLogger：
  在 cancel() 中设置 cancelled = true，RawLogger 只在正常完成路径调用

验收：
□ 说 5 句正常完成 → raw_log 有 5 条（sqlite3 查询）
□ 取消录音 → 不写入
□ Pipeline 延迟无可感知变化（RawLogger 在 background Task 中）
□ DB 写入失败时 App 不崩溃
```

---

### W5-03 · DictionaryView DB 接入

```
目标文件：
  vilsay/DB/DictionaryRepository.swift   ← 新建，封装词典 CRUD
  vilsay/UI/DictionaryView.swift         ← 替换假数据，接真实 DB

DictionaryRepository.swift：
  final class DictionaryRepository: ObservableObject {
      @Published var entries: [DictionaryRecord] = []

      func load() {
          Task.detached(priority: .userInitiated) {
              let items = (try? AppDatabase.shared.dbPool.read { db in
                  try DictionaryRecord.fetchAll(db)
              }) ?? []
              await MainActor.run { self.entries = items }
          }
      }

      func add(word: String, context: String?) {
          Task.detached(priority: .userInitiated) {
              var r = DictionaryRecord(
                  word: word.trimmingCharacters(in: .whitespacesAndNewlines),
                  context: context,
                  source: "manual",
                  createdAt: ISO8601DateFormatter().string(from: Date())
              )
              try? AppDatabase.shared.dbPool.write { db in try r.insert(db) }
              await self.load()
          }
      }

      func delete(id: Int64) {
          Task.detached(priority: .userInitiated) {
              try? AppDatabase.shared.dbPool.write { db in
                  try DictionaryRecord.deleteOne(db, id: id)
              }
              await self.load()
          }
      }
  }

DictionaryView.swift：
  - 注入 @StateObject var repo = DictionaryRepository()
  - .onAppear { repo.load() }
  - Tab1 列表绑定 repo.entries，删除调 repo.delete(id:)
  - 添加弹窗确认后调 repo.add(word:context:)

验收：
□ 添加词条后重启 App，词条仍存在
□ 删除词条后重启，词条消失
□ 词条列表实时刷新（add/delete 后无需手动刷新）
```

---

### W5-04 · AnalyzerTrigger：计数满 20 触发 AI3

```
目标文件：
  vilsay/AI3/AnalyzerTrigger.swift

约束：
  - total_logged_count 和 last_trigger_count 均持久化在 analyzer_state 表（W5-01 已建）
  - 每次 checkAndFire 读取当前计数，差值 >= 20 时触发
  - 触发后立即更新 last_trigger_count = total_logged_count（防重复触发）
  - AI3Analyzer.analyze() 在 Task.detached(priority: .background) 中调用

actor AnalyzerTrigger {
    static let shared = AnalyzerTrigger()

    func checkAndFire() async {
        guard let state = try? AppDatabase.shared.dbPool.read({ db in
            try AnalyzerStateRecord.fetchOne(db)
        }) else { return }

        let diff = state.totalLoggedCount - state.lastTriggerCount
        guard diff >= Constants.analyzerTriggerThreshold else { return }

        // 先锁住，防并发重复触发
        try? AppDatabase.shared.dbPool.write { db in
            try db.execute(sql: """
                UPDATE analyzer_state
                SET last_trigger_count = total_logged_count
                WHERE id = 1
            """)
        }

        // 后台触发分析，不 await
        Task.detached(priority: .background) {
            await AI3Analyzer.shared.analyze()
        }
    }
}

验收：
□ 说第 20 句后 Console 出现 AI3Analyzer 开始日志（DEBUG）
□ 说第 21～39 句期间不重复触发
□ 说第 40 句再次触发
□ 重启后计数不归零（从 DB 读取）
```

---

### W5-05 · AI3Analyzer：日志 → Qwen → Profile + Candidates

```
目标文件：
  vilsay/AI3/AI3Analyzer.swift
  vilsay/AI3/ProfileService.swift     ← Profile 读写封装

AI3Analyzer 职责：
  1. 读取最近 50 条 raw_log（仅 asr_text，不读 polished_text）
  2. 构建分析 Prompt（见下方格式）
  3. 调用 Qwen（开发者 Key，非用户 Key）
  4. 解析 JSON 响应 → 更新 user_profile + dictionary_candidates

⚠️ 开发者 Key 读取：
  DEBUG：AppConfig.dashscopeAPIKey（与 AI2 共享，可接受；生产应换独立 Key）
  Release：从 Bundle 内置环境变量或 Keychain 读取（Phase 1 可先用同一 Key）

分析 Prompt 格式：
  System:
    你是一个语言习惯分析助手。分析以下用户的语音转写记录，提取用户的语言特征。
    用 JSON 格式返回，包含以下字段：
    {
      "habitual_words": [{"word": "...", "action": "keep|simplify|remove", "confidence": 0.0-1.0}],
      "thinking_style": {"expand": "...", "topic_switch_signals": ["..."], "close_signals": ["..."], "confidence": 0.0-1.0},
      "tone": {"overall": "...", "sentence_length": "short|medium|long", "mixed_lang": "...", "confidence": 0.0-1.0},
      "dictionary_candidates": [{"word": "...", "context": "...", "score": 0.0-1.0}]
    }
    所有字段均可为空数组或 null，不得编造。
    vocabulary 候选词仅提取名词、专有名词、缩写，不含口头禅。

  User:
    以下是最近 [N] 条语音记录（仅原始转写，非润色结果）：
    1. [asr_text_1]
    2. [asr_text_2]
    ...

ProfileService.swift 写入逻辑：
  - 解析 JSON 后，对每个 key（habitual_words/thinking_style/tone）：
    * 若 DB 无此 key → 直接 INSERT，confidence = 响应中的 confidence
    * 若 DB 已有 → 加权平均更新：new_conf = old_conf * 0.6 + new_conf * 0.4
    * confidence < Constants.profileMinConfidence(0.3) → 不写入（或删除已有低置信条目）
  - dictionary_candidates：score >= 0.5 且 word 不在 dictionary 表中 → INSERT OR IGNORE

ProfileService.swift 接口（供 PromptComposer 读取）：
  enum ProfileService {
      static func getProfile() -> UserProfile?   // 从 DB 读取并组装
      static func getCandidates() -> [DictionaryCandidate]
      static func approveCandidate(id: Int64)    // → 移入 dictionary 表
      static func dismissCandidate(id: Int64)    // → dismissed = 1
  }

UserProfile 结构（Config/UserProfile.swift，已存在占位，可补充字段）：
  struct UserProfile {
      var habitualWords: [HabitualWord]     // confidence >= 0.3
      var thinkingStyle: ThinkingStyle?
      var tone: ToneProfile?
      var dictionaryItems: [DictionaryItem] // 来自 dictionary 表 source=ai + manual
  }

验收：
□ 手动说 20 句 → DB user_profile 有至少 1 条非空记录
□ 多次分析后 confidence 值变化（加权更新）
□ dictionary_candidates 有候选词条目
□ AI3Analyzer 运行时 Pipeline 延迟不受影响（Background Task）
□ Qwen 调用失败时 DB 不写入（静默失败，有 os.log ERROR）
```

---

### W5-06 · PromptComposer V3 动态注入（§A + §C + §1 + §1.P）

```
目标文件：
  vilsay/Core/PromptComposer.swift   ← 已存在，扩展为 V3 五层 Prompt
  vilsay/Core/TargetAppMonitor.swift  ← 已存在，需暴露 bundleIdentifier

V3 升级说明（相对 V2）：
  V2 = §0 + §1(可选) + §2
  V3 = §0 + §A(App上下文,可选) + §C(置信度提示,可选) + §1(画像+拼音,可选) + §2
  新增 §A、§C 为零冷启动层，Day 1 即可工作，无需等 AI3 积累

签名变更：
  // V2（当前）
  static func systemPrompt(for profile: UserProfile?) -> String

  // V3（新）
  static func systemPrompt(
      for profile: UserProfile?,
      targetAppBundleID: String? = nil,
      asrConfidence: Double? = nil
  ) -> String

实现规则：

func systemPrompt(for profile: UserProfile?,
                  targetAppBundleID: String?,
                  asrConfidence: Double?) -> String {
    var sections: [String] = []
    sections.append(Prompts.personaCore)      // §0 固定

    // §A App 上下文提示（零冷启动，来自 TargetAppMonitor）
    if let bundleID = targetAppBundleID,
       let hint = Self.appContextMap[bundleID] {
        sections.append("【场景提示】\(hint)")
    }

    // §C ASR 置信度提示（低置信时注入）
    if let conf = asrConfidence, conf < Constants.asrLowConfidenceThreshold {
        let pct = Int(conf * 100)
        sections.append("【识别质量提示】本次语音识别置信度较低（\(pct)%），请特别注意同音字纠偏，对不通顺的词组优先尝试同音替换。")
    }

    // §1 用户专属（需 AI3 积累 20 句后）
    if let p = profile, !p.isEmpty {
        var s1 = ""
        let minC = Constants.profileMinConfidence
        // §1.1 口头禅
        let keeps = p.habitualWords.filter { $0.confidence >= minC }
        if !keeps.isEmpty {
            let lines = keeps.map { "\($0.word)（\($0.action)）" }.joined(separator: "、")
            s1 += "用户口头禅与保留词：\(lines)\n"
        }
        // §1.2 思维结构
        if let ts = p.thinkingStyle, ts.confidence >= minC {
            s1 += "思维结构：\(ts.expand)；话题切换信号：\(ts.topicSwitchSignals.joined(separator: "/"))\n"
        }
        // §1.3 语气
        if let tone = p.tone, tone.confidence >= minC {
            s1 += "语气风格：\(tone.overall)，句子长度偏好：\(tone.sentenceLength)\n"
        }
        // §1.4 词典
        if !p.dictionaryItems.isEmpty {
            let dict = p.dictionaryItems.prefix(Constants.profileMaxDictItems)
                .map { "\($0.type)·\($0.word)" }.joined(separator: "、")
            s1 += "高频词典：\(dict)\n"
        }
        // §1.P 拼音同音纠偏提示
        let pinyinItems = p.dictionaryItems.filter { $0.pinyin != nil }
        if !pinyinItems.isEmpty {
            let hints = pinyinItems.prefix(50)
                .map { "\($0.word)(\($0.pinyin!))" }.joined(separator: "、")
            s1 += "以下词汇容易被语音误识别为同音词，遇到发音相似的错误请优先替换为正确词汇：\(hints)\n"
        }
        if !s1.isEmpty {
            sections.append("【用户专属】\n\(s1.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }

    sections.append(Prompts.processingEngine)  // §2 固定
    return sections.joined(separator: "\n\n---\n\n")
}

// App 上下文映射表（可扩展）
static let appContextMap: [String: String] = [
    "com.apple.mail": "用户正在写邮件，注意正式语体",
    "com.tencent.foxmail": "用户正在写邮件，注意正式语体",
    "com.microsoft.Outlook": "用户正在写邮件，注意正式语体",
    "com.tencent.xinWeChat": "用户在聊天，保留口语化表达",
    "com.apple.MobileSMS": "用户在聊天，保留口语化表达",
    "com.tencent.qq": "用户在聊天，保留口语化表达",
    "com.microsoft.Word": "用户在写文档，注意段落完整性和正式用语",
    "com.apple.Pages": "用户在写文档，注意段落完整性",
    "com.apple.Notes": "用户在记笔记，保持简洁",
    "com.notion.id": "用户在写笔记/文档，注意结构化表达",
]
// 未命中映射表时不注入 §A（最小干预原则）

拼音生成工具函数（Utils/ 或 DB 层）：
  func toPinyin(_ text: String) -> String {
      let mutable = NSMutableString(string: text) as CFMutableString
      CFStringTransform(mutable, nil, kCFStringTransformMandarinLatin, false)
      CFStringTransform(mutable, nil, kCFStringTransformStripDiacritics, false)
      return mutable as String
  }
  // 词典入库时自动调用，填充 pinyin 字段

Pipeline 调用变更：
  // Pipeline.runPolishInjectAfterVAD 中：
  let profile = ProfileService.getProfile()
  let bundleID = TargetAppMonitor.shared.targetBundleIdentifier  // 已有属性
  let confidence = lastASRConfidence  // Pipeline 从 ASR 结果中保存
  let system = PromptComposer.systemPrompt(
      for: profile,
      targetAppBundleID: bundleID,
      asrConfidence: confidence
  )

⚠️ 不得在 Prompts.swift 固定字符串中直接写占位符
⚠️ §A 和 §C 无数据时不注入空段落

验收：
□ 无 Profile 时 systemPrompt 只含 §0 + §2（与现有行为一致）
□ 在微信中使用 → Prompt 包含"聊天，保留口语化"（DEBUG 日志可见）
□ 在 Mail 中使用 → Prompt 包含"邮件，正式语体"
□ 在未知 App 中使用 → 无 §A 层
□ WhisperKit 低置信度 → Prompt 包含"置信度较低"提示
□ 高置信度 → 无 §C 层
□ Profile 非空时输出包含口头禅/风格段落 + 拼音纠偏提示
□ 低置信 Profile（confidence < 0.3）不注入
□ 说 20 句触发 AI3 后，第 21 句润色 Prompt 已包含 §1 内容
□ 词典词条入库后 pinyin 字段自动填充
```

---

### W5-07 · 词典推荐 UI 接入

```
目标文件：
  vilsay/UI/DictionaryView.swift     ← Tab2 接真实 candidates
  vilsay/App/AppState.swift          ← candidatesCount 角标

Tab2 推荐列表：
  @StateObject var candidateRepo = CandidateRepository()

  CandidateRepository（新建或与 DictionaryRepository 合并）：
    @Published var candidates: [DictionaryCandidate] = []   // dismissed == 0 的

    func load() { /* 从 dictionary_candidates 读取 dismissed=0 */ }
    func approve(id: Int64) { ProfileService.approveCandidate(id: id); load() }
    func dismiss(id: Int64) { ProfileService.dismissCandidate(id: id); load() }

候选词 Cell：
  - 显示 word + context（若有）+ score（进度条或 %）
  - 「加入词典」按钮 → approve → 从 Tab2 移除，Tab1 出现
  - 「忽略」按钮 → dismiss → 从 Tab2 移除

角标（AppState.candidatesCount）：
  - AppState 新增 @Published var candidatesCount: Int = 0
  - AI3Analyzer 写完 candidates 后在 MainActor 上更新：
      await MainActor.run { AppState.shared.candidatesCount = newCount }
  - DictionaryView Tab2 标签：「智能推荐（\(count)）」
  - 角标归零：全部 approve/dismiss 后

验收：
□ AI3 触发后，Tab2 出现候选词（最多来自最新一次分析）
□ 加入词典后词条在 Tab1 出现，Tab2 消失
□ 角标数字正确（pending 候选词数量）
□ 忽略后 dismissed=1，重启后不再显示
```

---

### W5-08 · 清除数据接入

```
目标文件：
  vilsay/UI/SettingsRootView.swift   ← 清除按钮接真实逻辑
  vilsay/DB/Database.swift           ← 新增 clearAIData() 方法

AppDatabase.clearAIData()：
  func clearAIData() throws {
      try dbPool.write { db in
          try db.execute(sql: "DELETE FROM raw_log")
          try db.execute(sql: "DELETE FROM user_profile")
          try db.execute(sql: "DELETE FROM dictionary_candidates")
          try db.execute(sql: """
              UPDATE analyzer_state
              SET total_logged_count = 0, last_trigger_count = 0, last_run_at = NULL
              WHERE id = 1
          """)
          // dictionary 表不清除（用户手动词典保留）
      }
  }

SettingsRootView：
  - 「清除 AI 学习数据」按钮 → 确认对话框 → 调 AppDatabase.shared.clearAIData()
  - 成功后：AppState.shared.candidatesCount = 0
  - 对话框文案：「将清除所有语音记录、AI 画像和推荐词，手动词典不受影响。」

验收：
□ 点击清除 → 确认 → raw_log/user_profile/candidates 为空
□ analyzer_state 计数归零（下次从 0 开始计）
□ dictionary 表保留
□ 清除后下一次说话重新开始积累
```

---

## Week 5 里程碑验收

```
□ 说 20 句（正常完成，不取消）→ AI3 自动触发，user_profile 写入
□ AI3 触发后润色 Prompt 包含用户语言特征（§1 非空）
□ 词典页 Tab2 显示 AI3 推荐词，可加入 / 忽略
□ 手动词典持久化（重启不丢）
□ 清除功能正确（词典保留）
□ 全程 Pipeline 延迟无变化（AI3 在 background Task）
□ ★ 在微信/Mail 中使用时 Prompt 包含 App 上下文提示（§A）
□ ★ 低 ASR 置信度时 Prompt 包含纠偏强化提示（§C）
□ ★ 词典词条自动生成拼音字段
□ ★ raw_log 记录包含 asr_confidence 和 target_app_id
```

---

## WEEK 6 · 联调打磨 + 上架准备

---

### W6-01 · 浮层重设计（Typeless 风格）

```
目标文件：
  vilsay/Entry/FloatingButtonView.swift      ← 重写视觉层
  vilsay/Entry/FloatingButtonController.swift ← 补充取消逻辑

设计目标：参考 Typeless 的 pill/胶囊形态，替换现有圆形按钮

状态映射：

  idle（待机）：
    不显示，或极小的"可拖动锚点"（用户可选择是否常显）

  recording（录音中）：
    ┌─────────────────────────────────┐
    │  🔴  ▃▅▇▅▃▂▄▆▄  [  ✕  ]       │  (pill，宽约 180pt)
    └─────────────────────────────────┘
    - 左：红色录音指示点（闪烁）
    - 中：实时音频波形（AVAudioEngine 峰值电平驱动，不需要 ASR）
    - 右：✕ 取消按钮 → 点击调 Pipeline.shared.cancel()

  processing（转写 + 润色，对用户是同一个黑盒）：
    ┌─────────────────────────────────┐
    │  ◌  思考中...                    │
    └─────────────────────────────────┘
    - .processing 和 .injecting 均显示"思考中..."，不区分内部步骤
    - 用户不需要知道是在转写还是润色

  完成后短暂（2s → 触碰延长至 5s）：
    ┌───────────────────────────────────────┐
    │  [润色后文字前 20 字]...    [ ⚠ 有误 ]│
    └───────────────────────────────────────┘
    - 直接显示文字，不说"完成"，让内容本身说话
    - 2 秒后自动消失；鼠标悬停时延长至 5s（方便点击"有误"）
    - 数据来源：AppState.shared.lastPipelinePolishedText
    - 「⚠ 有误」按钮（闭环反馈入口）：
      点击 → raw_log 最新一条 user_flagged_error = true
      点击后按钮变 ✓ + "已记录"，0.5s 后 pill 消失
      不弹确认框，一键完成（无感原则）

  editMode（改词模式录音中）：
    ┌─────────────────────────────────┐
    │  🔵  听指令...  ▃▅▇▅▃▂  [  ✕  ]│
    └─────────────────────────────────┘
    - 蓝色指示点取代红色，文案"听指令..."取代波形左侧空白

技术实现要点：
  - 波形动画：订阅 AudioCapture.onPCMLevelUpdate（新增，基于 AVAudioEngine metering）
    每 50ms 更新一次，SwiftUI Canvas 绘制5条竖线
  - pill 位置：默认屏幕底部居中，可拖动，位置持久化 UserDefaults
  - NSPanel 改为更窄的 collectionBehavior：canJoinAllSpaces + fullScreenAuxiliary
  - ✕ 点击后 pill 立即消失（不等 processing 完成）

⚠️ 不破坏现有 Push/Toggle 模式逻辑，✕ 只是 cancel() 的 UI 入口

验收：
□ 录音中可见波形 + ✕ 按钮
□ 点 ✕ 后录音停止，无文字输出（与 ESC 等效）
□ 完成后出现 2s 文字预览然后消失
□ 鼠标悬停预览时延长显示至 5s
□ 点击"有误"后 raw_log 最新条目 user_flagged_error=1（sqlite3 查询验证）
□ 点击"有误"按钮变为"已记录"然后消失
□ 改词模式颜色正确区分
□ 拖动位置重启后保持
```

---

### W6-02 · 菜单栏图标优化 + 录音中停止项

```
目标文件：
  vilsay/UI/MenuBarRootMenu.swift     ← 录音中追加「停止录音」菜单项
  vilsay/Assets.xcassets/             ← 图标资源更新

菜单栏图标状态（Template 图片，随系统深浅色自适应）：
  idle       → 麦克风轮廓（细线，灰色）
  recording  → 实心麦克风（黑/白）+ 可选红点徽章
  processing → 麦克风 + 旋转圆弧（系统 spinner 替代或自绘）
  attention  → 麦克风 + 橙色感叹号徽章
  error      → 麦克风 + 红色 ✕ 徽章

菜单栏菜单（录音中状态追加）：
  当 sessionActive == true 时，在菜单顶部追加：
  ┌─────────────────────┐
  │  ⏹ 停止录音          │  ← 点击 = onHotkeyPushUp / stopRecording()
  │  ✕ 取消（不输出）    │  ← 点击 = cancel()
  ├─────────────────────┤
  │  ... 其他菜单项 ...  │
  └─────────────────────┘

图标设计要求：
  - SF Symbol 优先（mic, mic.fill, waveform 等）
  - 状态切换通过 NSStatusItem.button.image 更新
  - 图标尺寸 18×18pt，模板图片（template image）

验收：
□ 录音中菜单顶部有「停止录音」和「取消」两项
□ 「停止录音」处理音频并输出；「取消」不输出
□ 菜单栏图标随 5 种状态正确切换
□ 深色/浅色模式下图标均清晰
```

---

### W6-03 · 性能验证（死亡线）

```
验收标准（10次平均，本机测量）：
□ 松开热键 → 文字出现 < 1500ms（Whisper 已预载状态）
□ 待机内存 < 100MB（Activity Monitor）
□ 录音中 CPU < 20%（Activity Monitor）
□ AI3 触发时 Pipeline 延迟不增加

测量方法：
  - PerformanceTracker 日志已有 [Performance] ASR/Polish/Inject 行
  - 连续 10 次测量，取平均值
  - 如超标，优先排查：Whisper 未预载、网络请求串行化、MainActor 阻塞

常见超标原因与对策：
  Whisper 未预载 → 确认 scheduleWhisperPreloadAfterRecordingReleased() 已调用
  Polish SSE 慢  → 确认 qwen-turbo（非 qwen-max）；polishTimeoutMs=5000 已设
  Inject 多次粘贴 → 已在本轮修复为单次粘贴，确认无回归
```

---

### W6-02 · 边界场景覆盖

```
每个场景记录「预期行为」与「实际结果」：

□ 断网完整流程
    预期：云端 ASR 失败 → 自动降 Whisper → 正常出字；UI 提示"本地识别"
□ 权限拒绝处理
    预期：麦克风拒绝 → 友好提示 + 权限中心入口；辅助功能拒绝 → 热键无效 + 提示
□ 说空话（纯停顿，< 0.2s）
    预期：过短音频被过滤，不进入 ASR，AppState.status 回到 idle
□ 极长句子（录音 > 30s）
    预期：maxPushRecordingSeconds=300 内不强制停止；Whisper 完整转写
□ 纯英文输入
    预期：Whisper language="zh" 仍能识别英文；Qwen 正常润色
□ 中英混合
    预期：Whisper 混合输出；§2.5 多语言边界规则生效
□ 注入到不支持粘贴的 App（终端 Terminal）
    预期：activateTargetApp 成功；Cmd+V 无效但不崩溃；无异常日志
□ 快速连续触发（松开 < 300ms 后再按）
    预期：postStopCooldownSeconds=0.3 拦截，状态不混乱
□ Push/Toggle 模式切换
    预期：设置页切换后立即生效，无需重启
□ 改词后再改词
    预期：第二次选中新文字后按热键，正确替换第二次的内容
□ 未登录状态触发（Auth 完成前的状态）
    预期：未登录不阻塞录音（Phase 1 不限制）；计费拦截仅登录用户生效

不通过时：记录 Bug，归入 Bugfix 列表，Week 6 内修复后重测
```

---

### W6-03 · App Store 材料准备

```
□ App 图标：1024×1024 PNG（无圆角，App Store Connect 自动裁剪）
  设计方向：简洁麦克风 + 文字/波形元素，参考 UI/UX 规范色彩

□ macOS 截图：至少 3 张，推荐 5 张
  1280×800 或 1440×900（Retina 2x 提交 2560×1600）
  场景建议：
    - 截图1：悬浮按钮 + 菜单栏 · 主界面
    - 截图2：录音中状态（按钮红色）
    - 截图3：文字注入效果（before/after 对比）
    - 截图4：设置页 · API 配置
    - 截图5：词典页 · 推荐词

□ App 名：Vilsay
□ 副标题：说话，比打字更快
□ 描述文案（中文，500字以内）：
  见 PRD 产品亮点，重点强调：语音输入→自动润色→直接粘贴，支持各类 App

□ 关键词（100字以内）：
  语音输入,语音识别,文字润色,AI写作,语音转文字,效率工具,输入法

□ 隐私政策 URL：https://vilsay.com/privacy（Week 7 官网上线前需有效）
□ 年龄分级：4+
□ 类别：效率工具（Productivity）
□ 价格：免费（含应用内购买）
```

---

### W6-04 · 隐私政策页（App 内嵌）

```
目标文件：
  vilsay/UI/PrivacyPolicyView.swift   ← 新建，WebView 加载或本地 Markdown 渲染

方案 A（推荐）：WKWebView 加载 https://vilsay.com/privacy
  - 无网时显示"加载失败，请访问 vilsay.com/privacy 查看"

方案 B（兜底）：内嵌静态 HTML/文本，随 App 打包
  - 内容见 PRD 第七章，中英双语

设置页接入：
  - 现有版本号/隐私政策行 → 点击打开 PrivacyPolicyView（Sheet 或新窗口）

验收：
□ 设置页隐私政策链接可点击
□ 打开后显示完整隐私内容（或加载失败友好提示）
```

---

### W6-05 · TestFlight 内测

```
前提：
□ Xcode Archive 成功（无编译错误）
□ App Store Connect 已创建 App 记录
□ Bundle ID：com.vilsay.app（与 Info.plist 一致）

步骤：
□ Xcode → Product → Archive
□ Distribute → App Store Connect → Upload
□ App Store Connect → TestFlight → 添加内测用户（邮件邀请）
□ 内测周期：至少 7 天
□ 收集 Crash Report（Xcode Organizer）+ 用户反馈
□ 修复 P0 Bug 后上传 Build 2
□ 最终提交正式审核

⚠️ 提交前确认清单（W4-PROD-01 内容）：
□ JWT_SECRET 非测试值（环境变量注入）
□ DEV_EXPOSE_VERIFICATION_TOKEN=false
□ AppConfig.backendAPIBaseURL 指向生产域名
□ VILSAY_GOOGLE_CLIENT_ID 已填真实值
□ DashScope API Key 在 Release 走代理（不直连）
```

---

## Week 6 里程碑验收

```
□ 10 次热键测量平均 < 1500ms
□ 所有边界场景通过或有已知 Bug 记录
□ 浮层 pill 完成态可点"有误"标记错误（闭环反馈路径可用）
□ App Store Connect 上有待审核 Build
□ TestFlight 至少 3 名内测用户已安装
```

---

## Week 7（新安排）

> 周期：Week 6 全部完成 + 全程序 Review 后开始

### W7-A · Onboarding 完整实现
> 详细状态机见 `docs/log/VILSAY_ONBOARDING.md`

```
4 步流程完整实现（替换 W2-04 占位版本）：
  Step1 欢迎页
  Step2 麦克风权限请求 + 结果检测
  Step3 辅助功能权限引导（含系统设置深链 + 轮询检测）
  Step4 账号登录（接 W4 Auth 逻辑）

状态管理：
  UserDefaults "onboarding_done" Bool
  权限轮询：NSApplication.didBecomeActiveNotification 触发重检

Whisper 预载时机接入：
  Onboarding 完成后（Step4 Done）→ 调用 WhisperASRFallback.shared.preloadIfNeeded()
  进度展示在 Onboarding 完成页或设置页
```

### W7-B · 产品官网
> 详细任务见原 `VILSAY_DEV_TASKS.md` W7-01 ~ W7-05

```
W7-01 Next.js 项目初始化 + Tailwind
W7-02 首页（Landing）：Hero + 演示 GIF + 功能亮点 + 定价 + 下载
W7-03 文档页：快速开始 / 功能说明 / FAQ
W7-04 用量面板（需登录，调后端 API）
W7-05 法律页：隐私政策 + 服务条款
```

---

## 全程序 Review（Week 6 结束后）

> 由架构师主导，在 Week 7 开始前完成

Review 范围：
```
1. 主链路稳定性：Pipeline 所有 await 是否有兜底 timeout
2. 内存安全：strong/weak capture 一致性；Continuation 无泄漏
3. 并发安全：MainActor 访问的状态是否有竞态；NSLock 使用正确性
4. DB 完整性：迁移路径测试（v1→v2）；写失败时 App 行为
5. AI3 隔离性：任何 AI3 操作挂死时主链路是否不受影响
6. 账号体系：Token 过期处理；Keychain 清除路径
7. 上架合规：隐私说明与实际数据采集一致；权限使用说明
8. 性能死亡线回归测试（10次）
9. ★ 闭环路径验证：user_flagged_error → AI3 分析 → 词典/画像更新 → Prompt 改善
10. ★ App 上下文映射覆盖率：常用 App 是否有合理提示
11. ★ BYOK 路径验证：自带 Key 用户直连 DashScope 功能完整
```

---

## V1.4 增量补丁（2026-03-25 架构升级后新增）

> **背景**：架构文档 `VILSAY_TECH_ARCH.md` 已从 v1.3 升级至 v1.4，引入闭环反馈、App 上下文注入、ASR 置信度透传、拼音同音纠偏。以下任务在 Week 5 已交付代码基础上增量修改，**不破坏**已有功能。
>
> **前置阅读**：`docs/spec/VILSAY_TECH_ARCH.md` v1.4 §2.3、§7、§8、§9、§10、§15

---

### 任务总览（增量）

| ID | 摘要 | 依赖 | 改动文件 |
|----|------|------|----------|
| V14-01 | DB Migration v2：5 张表加 V1.4 新字段 | W5-01 已完成 | Migrations.swift, Schema.swift |
| V14-02 | TargetAppMonitor 暴露 bundleIdentifier | - | TargetAppMonitor.swift |
| V14-03 | toPinyin 工具 + 词典入库自动生成拼音 | V14-01 | Utils/PinyinHelper.swift(新), DictionaryRepository.swift, AI3Analyzer.swift |
| V14-04 | PromptComposer V3：§A + §C + §1.P | V14-01, V14-02, V14-03 | PromptComposer.swift |
| V14-05 | RawLogger 扩签 + Pipeline 穿透 | V14-01, V14-02 | RawLogger.swift, Pipeline.swift |
| V14-06 | ErrorFeedbackService：用户标记"有误" | V14-01 | AI3/ErrorFeedbackService.swift(新) |
| W6-01 | 浮层 pill 重设计（Typeless 风格 + 有误按钮） | V14-06 | FloatingButtonView.swift, FloatingButtonController.swift |
| W6-02 | 菜单栏图标状态 + 录音中停止/取消菜单项 | - | MenuBarRootMenu.swift, Assets |

**执行顺序建议**：V14-01 → V14-02 → V14-03 → (V14-04 + V14-05 并行) → V14-06 → W6-01 + W6-02 并行

---

### V14-01 · DB Migration v2：新增字段

```
目标文件：
  vilsay/DB/Migrations.swift     ← 注册 v2 迁移
  vilsay/DB/Schema.swift         ← Record 结构体加字段

迁移内容（v2_add_v14_columns）：

migrator.registerMigration("v2_add_v14_columns") { db in
    // raw_log 加 4 列
    try db.alter(table: "raw_log") { t in
        t.add(column: "asr_provider", .text)            // "whisperKit"|"dashScope"
        t.add(column: "asr_confidence", .double)        // 0~1
        t.add(column: "target_app_id", .text)           // bundleIdentifier
        t.add(column: "user_flagged_error", .integer)
            .notNull().defaults(to: 0)                  // 0/1 bool
    }

    // dictionary 加 pinyin
    try db.alter(table: "dictionary") { t in
        t.add(column: "pinyin", .text)                  // CFStringTransform 生成
    }

    // dictionary_candidates 加 pinyin + state 替代 dismissed
    try db.alter(table: "dictionary_candidates") { t in
        t.add(column: "pinyin", .text)
        t.add(column: "state", .text).defaults(to: "pending")
            // "pending"|"approved"|"dismissed"
    }
    // 迁移已有数据：dismissed=1 → state="dismissed"，dismissed=0 → state="pending"
    try db.execute(sql: """
        UPDATE dictionary_candidates SET state = CASE
            WHEN dismissed = 1 THEN 'dismissed'
            ELSE 'pending'
        END
    """)

    // analyzer_state 加 last_analyzed_log_id
    try db.alter(table: "analyzer_state") { t in
        t.add(column: "last_analyzed_log_id", .integer) // 上次分析到的 raw_log.id
    }
}

Schema.swift Record 变更：

struct RawLogRecord: Codable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var asrText: String
    var polishedText: String
    var durationMs: Int?
    var sessionId: String?
    var asrProvider: String?           // ★ 新增
    var asrConfidence: Double?         // ★ 新增
    var targetAppId: String?           // ★ 新增
    var userFlaggedError: Bool         // ★ 新增，默认 false
    var createdAt: String
    static let databaseTableName = "raw_log"
}

struct DictionaryRecord 加：
    var pinyin: String?                // ★ 新增

struct DictionaryCandidateRecord 加：
    var pinyin: String?                // ★ 新增
    var state: String                  // ★ 新增，替代 dismissed（但保留 dismissed 列兼容）

struct AnalyzerStateRecord 加：
    var lastAnalyzedLogId: Int64?      // ★ 新增

验收：
□ 已有 v1 数据库升级到 v2 不丢数据（sqlite3 查询旧记录仍在）
□ 新建数据库直接跑 v1+v2 迁移正常
□ raw_log 新记录可写入 asr_provider/asr_confidence/target_app_id/user_flagged_error
□ dictionary_candidates 旧 dismissed=1 行迁移后 state="dismissed"
□ xcodebuild build + test 通过
```

---

### V14-02 · TargetAppMonitor 暴露 bundleIdentifier

```
目标文件：
  vilsay/Core/TargetAppMonitor.swift

当前现状：
  captureTargetApp() 用 NSRunningApplication(pid:) 拿到 app，
  保存了 capturedPID 和 capturedAppName，但没有暴露 bundleIdentifier

修改：

class TargetAppMonitor {
    // 已有
    private(set) var capturedPID: pid_t?
    private(set) var capturedAppName: String?

    // ★ 新增
    private(set) var capturedBundleIdentifier: String?

    func captureTargetApp() {
        let frontApp = NSWorkspace.shared.frontmostApplication
        capturedPID = frontApp?.processIdentifier
        capturedAppName = frontApp?.localizedName
        capturedBundleIdentifier = frontApp?.bundleIdentifier  // ★ 新增
    }

    func clear() {
        capturedPID = nil
        capturedAppName = nil
        capturedBundleIdentifier = nil  // ★ 新增
    }
}

验收：
□ 在微信中触发录音 → capturedBundleIdentifier == "com.tencent.xinWeChat"
□ 在 Mail 中触发 → "com.apple.mail"
□ clear() 后为 nil
```

---

### V14-03 · toPinyin 工具 + 词典自动拼音

```
目标文件：
  vilsay/Utils/PinyinHelper.swift       ← 新建
  vilsay/DB/DictionaryRepository.swift  ← add() 时自动填拼音
  vilsay/AI3/AI3Analyzer.swift          ← 候选词入库时自动填拼音

PinyinHelper.swift：

enum PinyinHelper {
    /// 将中文转为无声调拼音，空格分隔。非中文字符保留原文。
    /// 示例："事业" → "shi ye"，"API接口" → "API jie kou"
    static func toPinyin(_ text: String) -> String {
        let mutable = NSMutableString(string: text) as CFMutableString
        CFStringTransform(mutable, nil, kCFStringTransformMandarinLatin, false)
        CFStringTransform(mutable, nil, kCFStringTransformStripDiacritics, false)
        return (mutable as String)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

DictionaryRepository.swift 修改：

func add(word: String, context: String?) {
    // ... 已有逻辑
    var r = DictionaryRecord(
        word: word.trimmingCharacters(in: .whitespacesAndNewlines),
        context: context,
        pinyin: PinyinHelper.toPinyin(word),  // ★ 自动填拼音
        source: "manual",
        createdAt: ISO8601DateFormatter().string(from: Date())
    )
    // ...
}

AI3Analyzer.swift 修改：
  候选词写入 dictionary_candidates 时：
    pinyin: PinyinHelper.toPinyin(candidate.word)
  approveCandidate 移入 dictionary 表时保留 pinyin

验收：
□ 手动添加"事业" → dictionary 表 pinyin 列 = "shi ye"
□ AI3 推荐词入 dictionary_candidates 后 pinyin 非空
□ approve 移入 dictionary 后 pinyin 保留
□ 英文 / 数字不崩溃（原样返回）
```

---

### V14-04 · PromptComposer V3：§A + §C + §1.P

```
目标文件：
  vilsay/Core/PromptComposer.swift

签名变更：
  // 旧（V2，已实现）
  static func systemPrompt(for profile: UserProfile?) -> String

  // 新（V3）
  static func systemPrompt(
      for profile: UserProfile?,
      targetAppBundleID: String? = nil,
      asrConfidence: Double? = nil
  ) -> String
  // 默认参数保证旧调用方不报错

实现（在 §0 之后、§1 之前插入 §A 和 §C）：

static func systemPrompt(
    for profile: UserProfile?,
    targetAppBundleID: String? = nil,
    asrConfidence: Double? = nil
) -> String {
    var sections: [String] = []
    sections.append(Prompts.personaCore)      // §0

    // §A App 上下文（零冷启动）
    if let bundleID = targetAppBundleID,
       let hint = appContextMap[bundleID] {
        sections.append("【场景提示】\(hint)")
    }

    // §C ASR 置信度（低于阈值时注入）
    if let conf = asrConfidence,
       conf < Constants.asrLowConfidenceThreshold {
        let pct = Int(conf * 100)
        sections.append(
            "【识别质量提示】本次语音识别置信度较低（\(pct)%），" +
            "请特别注意同音字纠偏，对不通顺的词组优先尝试同音替换。"
        )
    }

    // §1 用户专属（已有逻辑保持不变）
    if let p = profile, !p.isEmpty {
        var s1 = ""
        // ... §1.1~§1.4 逻辑不变 ...

        // §1.P 拼音同音纠偏提示（新增）
        let pinyinItems = p.dictionaryItems.filter { $0.pinyin != nil && !$0.pinyin!.isEmpty }
        if !pinyinItems.isEmpty {
            let hints = pinyinItems.prefix(50)
                .map { "\($0.word)(\($0.pinyin!))" }
                .joined(separator: "、")
            s1 += "以下词汇容易被语音误识别为同音词，" +
                  "遇到发音相似的错误请优先替换为正确词汇：\(hints)\n"
        }

        if !s1.isEmpty {
            sections.append("【用户专属】\n\(s1.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }

    sections.append(Prompts.processingEngine)  // §2
    return sections.joined(separator: "\n\n---\n\n")
}

// App 上下文映射表
private static let appContextMap: [String: String] = [
    // 邮件
    "com.apple.mail": "用户正在写邮件，注意正式语体",
    "com.tencent.foxmail": "用户正在写邮件，注意正式语体",
    "com.microsoft.Outlook": "用户正在写邮件，注意正式语体",
    // 聊天
    "com.tencent.xinWeChat": "用户在聊天，保留口语化表达",
    "com.apple.MobileSMS": "用户在聊天，保留口语化表达",
    "com.tencent.qq": "用户在聊天，保留口语化表达",
    // 文档
    "com.microsoft.Word": "用户在写文档，注意段落完整性和正式用语",
    "com.apple.Pages": "用户在写文档，注意段落完整性",
    // 笔记
    "com.apple.Notes": "用户在记笔记，保持简洁",
    "notion.id": "用户在写笔记/文档，注意结构化表达",
]

UserProfile.DictionaryItem 需加字段：
  struct DictionaryItem {
      let word: String
      let type: String
      let pinyin: String?   // ★ 新增
  }

Constants.swift 需加：
  static let asrLowConfidenceThreshold: Double = 0.4

⚠️ 旧调用 PromptComposer.systemPrompt(for: profile) 仍然编译通过（默认参数 nil）
⚠️ 不改 Prompts.swift

验收：
□ 旧调用方式编译不报错（默认参数兼容）
□ 在微信中录音 → DEBUG 日志显示 Prompt 含"聊天，保留口语化"
□ 在 Mail 中 → 含"邮件，正式语体"
□ 在 Terminal 中 → 无 §A 段（未映射 App 不注入）
□ 低置信度(< 0.4) → 含"识别质量提示"
□ 高置信度(≥ 0.4) → 无 §C 段
□ 词典有拼音的条目 → §1.P 段含"同音词"提示
□ 词典为空 → 无 §1 和 §1.P
```

---

### V14-05 · RawLogger 扩签 + Pipeline 穿透

```
目标文件：
  vilsay/AI3/RawLogger.swift
  vilsay/Core/Pipeline.swift

RawLogger.swift 签名扩展：

static func logAsync(
    asr: String,
    polished: String,
    durationMs: Int,
    sessionId: String,
    asrProvider: String? = nil,        // ★ 新增
    asrConfidence: Double? = nil,      // ★ 新增
    targetAppBundleID: String? = nil   // ★ 新增
) {
    Task.detached(priority: .background) {
        // ... 已有 trim + guard 逻辑 ...
        var record = RawLogRecord(
            asrText: trimmedASR,
            polishedText: trimmedPolished,
            durationMs: durationMs,
            sessionId: sessionId,
            asrProvider: asrProvider,           // ★
            asrConfidence: asrConfidence,       // ★
            targetAppId: targetAppBundleID,     // ★
            userFlaggedError: false,            // ★ 默认未标记
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
        // ... 已有 insert + updateAnalyzerState 逻辑 ...
    }
}

Pipeline.swift 修改（两处）：

1. PromptComposer 调用（runPolishInjectAfterVAD 中，约 617-618 行附近）：
   // 旧
   let profile = ProfileService.getProfile()
   let system = PromptComposer.systemPrompt(for: profile)
   // 新
   let profile = ProfileService.getProfile()
   let bundleID = TargetAppMonitor.shared.capturedBundleIdentifier
   let confidence = lastASRConfidence  // 见下方说明
   let system = PromptComposer.systemPrompt(
       for: profile,
       targetAppBundleID: bundleID,
       asrConfidence: confidence
   )

2. RawLogger 调用（runPolishInjectAfterVAD 末尾）：
   // 旧
   RawLogger.logAsync(asr: asrText, polished: fullPolishForTrace,
                      durationMs: Int(asrMs), sessionId: UUID().uuidString)
   // 新
   RawLogger.logAsync(
       asr: asrText,
       polished: fullPolishForTrace,
       durationMs: Int(asrMs),
       sessionId: UUID().uuidString,
       asrProvider: usageAsrProvider,                           // 已有（"whisperKit"/"dashScope"）
       asrConfidence: lastASRConfidence,                        // 新增
       targetAppBundleID: TargetAppMonitor.shared.capturedBundleIdentifier
   )

3. ASR 置信度获取：
   Pipeline 中 WhisperKit 路径已经返回转写结果，
   WhisperKit TranscriptionResult 包含 avgLogprob。
   在 WhisperKit 成功返回处保存：
     self.lastASRConfidence = normalizeWhisperConfidence(result.avgLogprob)
   归一化公式（简单 sigmoid 映射）：
     private func normalizeWhisperConfidence(_ avgLogprob: Float) -> Double {
         // avgLogprob 通常在 -2.0 ~ 0.0 之间
         // 映射到 0.0 ~ 1.0：-1.0 → 0.5, -0.5 → 0.73, -2.0 → 0.12
         return Double(1.0 / (1.0 + exp(-2.0 * (avgLogprob + 1.0))))
     }
   Pipeline 需要加一个实例属性：
     private var lastASRConfidence: Double?

   DashScope REST 路径（Paraformer）如果没有返回置信度，lastASRConfidence = nil 即可。

⚠️ 除上述三处外，Pipeline 主链路逻辑不动

验收：
□ 录音完成后 raw_log 新行有 asr_provider + asr_confidence + target_app_id
□ sqlite3 查询确认数据正确
□ WhisperKit 路径 confidence 在 0~1 范围
□ DashScope 路径 confidence 为 NULL（预期）
□ 旧 RawLogger 调用方式仍编译（默认参数兼容）
□ Pipeline 延迟无变化
```

---

### V14-06 · ErrorFeedbackService：用户标记"有误"

```
目标文件：
  vilsay/AI3/ErrorFeedbackService.swift    ← 新建

实现：

enum ErrorFeedbackService {

    /// 将最新一条 raw_log 标记为用户已标记错误
    static func flagLatestError() {
        Task.detached(priority: .userInitiated) {
            do {
                try await AppDatabase.shared.dbPool.write { db in
                    // 取最新一条 raw_log
                    if let latest = try RawLogRecord
                        .order(Column("id").desc)
                        .fetchOne(db) {
                        var updated = latest
                        updated.userFlaggedError = true
                        try updated.update(db)
                    }
                }
            } catch {
                // 静默失败，写日志
                os_log(.error, "ErrorFeedbackService.flagLatestError failed: %{public}@",
                       error.localizedDescription)
            }
        }
    }

    /// 查询所有用户标记的错误（供 AI3Analyzer 分析用）
    static func getFlaggedErrors() async -> [RawLogRecord] {
        (try? await AppDatabase.shared.dbPool.read { db in
            try RawLogRecord
                .filter(Column("user_flagged_error") == true)
                .order(Column("id").desc)
                .limit(50)
                .fetchAll(db)
        }) ?? []
    }
}

W6-01 浮层的"有误"按钮调用此 service：
  Button("⚠ 有误") {
      ErrorFeedbackService.flagLatestError()
      // UI 反馈（见 W6-01）
  }

AI3Analyzer.swift 增量修改（可选，非阻塞）：
  在 analyze() 开头读取 flagged 错误，加入分析 Prompt：
    let flagged = await ErrorFeedbackService.getFlaggedErrors()
    if !flagged.isEmpty {
        // 在分析 Prompt 的 User 消息中追加：
        // "以下记录被用户标记为识别/润色有误，请特别关注这些错误模式：\n..."
    }

验收：
□ 调用 flagLatestError() 后 sqlite3 查询最新行 user_flagged_error=1
□ 连续说两句后 flag → 只标记最新一条
□ raw_log 为空时调用不崩溃
□ getFlaggedErrors() 返回所有已标记行
```

---

### W6-01 · 浮层重设计（Typeless 风格 pill）

```
目标文件：
  vilsay/Entry/FloatingButtonView.swift       ← 重写视觉层
  vilsay/Entry/FloatingButtonController.swift  ← 补充波形 + 取消 + 有误交互

设计目标：当前圆形按钮(56×56)改为 Typeless 风格胶囊 pill

状态映射与视觉（替换现有 Circle）：

  idle（待机）：
    不显示，或极小锚点（用户设置中可选常显）
    → 现有 opacity 逻辑保持

  recording（录音中）：
    ┌─────────────────────────────────┐
    │  🔴  ▃▅▇▅▃▂▄▆▄  [  ✕  ]       │  宽约 180pt，高 40pt
    └─────────────────────────────────┘
    - 左侧：8pt 红色圆点，opacity 闪烁动画（0.3~1.0，1Hz）
    - 中间：5 条竖线实时音频波形
      数据源：AudioCapture 新增 onPCMLevelUpdate 回调，每 50ms 更新一次
      或简化方案：AVAudioEngine installTap 取 RMS → 5 个柱状条高度
    - 右侧：✕ 按钮（SF Symbol: xmark.circle.fill，灰色）
      点击 → Pipeline.shared.cancel()
    - 背景：.ultraThinMaterial 或半透明深色
    - 圆角：capsule（Capsule() shape）

  processing（"思考中..."）：
    ┌─────────────────────────────────┐
    │  ◌  思考中...                    │  宽约 140pt
    └─────────────────────────────────┘
    - 左侧：旋转 spinner（ProgressView() 小尺寸）
    - 文字："思考中..."
    - .processing 和 .injecting 均显示此状态（对用户是同一个黑盒）

  completed（完成预览，2s）：
    ┌───────────────────────────────────────┐
    │  [润色文字前20字]...    [ ⚠ 有误 ]    │  宽自适应
    └───────────────────────────────────────┘
    - 左侧：润色结果前 20 字 + "..."（来自 AppState.shared.lastPolishedText）
    - 右侧："⚠ 有误"文字按钮（SF Symbol: exclamationmark.triangle）
      点击 → ErrorFeedbackService.flagLatestError()
      点击后按钮变 ✓ "已记录"（0.5s 后 pill 消失）
    - 默认 2 秒后消失
    - 鼠标悬停（onHover）时延长至 5 秒（方便点"有误"）

  editMode（改词模式录音中）：
    ┌─────────────────────────────────┐
    │  🔵  听指令...  ▃▅▇▅▃▂  [  ✕  ]│
    └─────────────────────────────────┘
    - 蓝色指示点替代红色
    - "听指令..."文字在波形左侧

SwiftUI 实现要点：

  Capsule()
      .fill(.ultraThinMaterial)
      .frame(width: pillWidth, height: 40)
      .overlay {
          HStack(spacing: 8) {
              // 左侧指示点/spinner/文字 根据状态切换
              // 中间波形/文字
              // 右侧按钮
          }
          .padding(.horizontal, 12)
      }
      .shadow(radius: 4)

  波形视图（简化方案）：
  struct AudioWaveformView: View {
      let levels: [CGFloat]  // 5 个值，0~1
      var body: some View {
          HStack(spacing: 3) {
              ForEach(0..<5, id: \.self) { i in
                  RoundedRectangle(cornerRadius: 1.5)
                      .fill(.white.opacity(0.8))
                      .frame(width: 3, height: max(4, levels[i] * 20))
              }
          }
          .frame(height: 20)
      }
  }

  AudioCapture 新增（最小改动）：
  // 在已有的 installTap 中顺带取 RMS
  var onAudioLevelUpdate: ((Float) -> Void)?
  // 在 tap block 中：
  let rms = ... // 计算 buffer RMS
  onAudioLevelUpdate?(rms)

NSPanel 改为 pill 尺寸：
  - contentRect 改为 (width: 200, height: 50)
  - 其余 level/collectionBehavior 不变
  - 位置：默认屏幕底部水平居中，y = 80pt
  - 可拖动，位置持久化 UserDefaults

✕ 点击后：
  - Pipeline.shared.cancel()
  - pill 立即消失（AppState.status → .idle → opacity 0）

"有误"点击后：
  - ErrorFeedbackService.flagLatestError()
  - 按钮文字变 "✓ 已记录"（withAnimation）
  - 0.5s 后 pill 消失

⚠️ 不破坏现有 Push/Toggle 模式逻辑
⚠️ ESC 仍然走 HotkeyManager → Pipeline.cancel()，与 ✕ 等效

验收：
□ 录音中可见胶囊 pill + 波形 + ✕ 按钮（不再是圆形）
□ 波形随说话声音变化（至少有明显起伏）
□ 点 ✕ 后录音停止，无文字输出（与 ESC 等效）
□ 完成后出现润色文字预览 + "⚠ 有误"按钮
□ 默认 2s 消失，鼠标悬停延长
□ 点"有误"后按钮变"✓ 已记录"然后消失
□ sqlite3 查询确认 user_flagged_error=1
□ 改词模式蓝色指示点 + "听指令..."
□ pill 可拖动，位置重启后保持
□ 深色/浅色模式下 pill 均清晰可读
```

---

### W6-02 · 菜单栏图标状态 + 录音中停止/取消

```
目标文件：
  vilsay/UI/MenuBarRootMenu.swift
  vilsay/Assets.xcassets/           ← 图标资源

菜单栏图标状态切换（5 种，SF Symbol Template Image）：

  idle       → mic               （麦克风轮廓，系统自适应深浅色）
  recording  → mic.fill          （实心麦克风）
  processing → mic.badge.ellipsis （带省略号角标）或自绘旋转
  attention  → mic.badge.exclamationmark
  error      → mic.badge.xmark

  实现方式：
    NSStatusItem.button?.image = NSImage(systemSymbolName: "mic.fill",
        accessibilityDescription: "Vilsay 录音中")
    // 根据 AppState.shared.status 切换
    // 在 AppState.status didSet 中或 Combine publisher 中更新

录音中菜单追加（sessionActive == true 时）：

  // MenuBarRootMenu.swift 现有菜单结构中，在最前面条件插入：
  if appState.sessionActive || appState.status == .recording
     || appState.status == .processing {

      Button("⏹ 停止录音") {
          Pipeline.shared.stopRecording()
          // 正常走 ASR → 润色 → 注入流程
      }

      Button("✕ 取消（不输出）") {
          Pipeline.shared.cancel()
      }

      Divider()
  }

  // 非录音状态时，保持现有"开始录音"按钮

图标尺寸：
  - 18×18pt（@2x 提交 36×36）
  - 使用 SF Symbol，无需自制图标
  - .renderingMode(.template) 确保适应深浅色

验收：
□ idle 状态：麦克风轮廓图标
□ 录音中：实心麦克风，菜单顶部有「⏹ 停止录音」和「✕ 取消」
□ 「停止录音」→ 正常处理并输出文字
□ 「取消」→ 不输出，回到 idle
□ processing 状态：图标切换（带角标或动画）
□ 深色/浅色模式下图标均清晰
□ 非录音状态菜单恢复正常（无停止/取消项）
```

---

### Constants.swift 新增常量

```
在已有 Constants 枚举中追加（不改已有值）：

static let asrLowConfidenceThreshold: Double = 0.4
static let pipelineAbsoluteDeadlineMs = 35_000
static let polishResourceTimeoutMs = 30_000
static let floatingPillPreviewDurationMs = 2_000
static let floatingPillPreviewMaxChars = 20
```

---

### V1.4 增量里程碑验收

```
□ v2 迁移正常，旧数据不丢
□ 在微信/Mail 中录音 → Prompt 含 App 上下文提示
□ WhisperKit 低置信度 → Prompt 含"识别质量"提示
□ 词典词条有拼音字段
□ raw_log 记录含 asr_confidence + target_app_id
□ 浮层为 pill 胶囊形态，非圆形
□ 浮层完成态有"有误"按钮，点击后 DB 标记
□ 菜单栏图标随状态切换
□ 录音中菜单有"停止"和"取消"选项
□ xcodebuild build + test 通过
□ 全程 Pipeline 延迟无变化
```

---

## 架构 Review 修复任务（2026-03-25，Review 后产出）

> **背景**：全程序架构 Review 发现 8 个问题（2 CRITICAL + 3 HIGH + 1 MEDIUM + 1 MEDIUM + 1 LOW）。
> 以下修复任务按严重度排序，**全部在 Week 7 开始前完成**。
>
> **原则**：最小改动修复，不引入新功能，不改接口签名。

---

### FIX-01 · ErrorFeedbackService.flagLatestError() 原子化 【CRITICAL】

```
问题：
  当前实现先 fetch MAX(id) 再 update，fetch 和 update 之间如果 RawLogger 插入新行，
  会标记错误的（旧的）记录。

目标文件：
  vilsay/AI3/ErrorFeedbackService.swift

修复：将 fetch+update 改为单条原子 SQL

static func flagLatestError() {
    Task.detached(priority: .userInitiated) {
        do {
            try await AppDatabase.shared.dbPool.write { db in
                try db.execute(sql: """
                    UPDATE raw_log
                    SET user_flagged_error = 1
                    WHERE id = (SELECT MAX(id) FROM raw_log)
                """)
            }
        } catch {
            os_log(.error, "flagLatestError failed: %{public}@",
                   error.localizedDescription)
        }
    }
}

验收：
□ 快速连续说两句后立即点"有误" → sqlite3 确认最新行 user_flagged_error=1
□ 空表时调用不崩溃
□ xcodebuild test 通过
```

---

### FIX-02 · AI3Analyzer 使用 last_analyzed_log_id 去重 【CRITICAL】

```
问题：
  analyze() 每次读最近 50 条 raw_log，不看 last_analyzed_log_id，
  导致同一批日志被多次分析，置信度加权平均向同一方向累积漂移。

目标文件：
  vilsay/AI3/AI3Analyzer.swift
  vilsay/DB/Schema.swift（AnalyzerStateRecord 已有字段，无需改）

修复：

func analyze() async {
    // 1. 读取 analyzer_state.last_analyzed_log_id
    guard let state = try? await AppDatabase.shared.dbPool.read({ db in
        try AnalyzerStateRecord.fetchOne(db)
    }) else { return }

    let sinceId = state.lastAnalyzedLogId ?? 0

    // 2. 只读 id > sinceId 的新日志（最多 50 条）
    let newLogs = (try? await AppDatabase.shared.dbPool.read { db in
        try RawLogRecord
            .filter(Column("id") > sinceId)
            .order(Column("id").asc)
            .limit(Constants.analyzerRecentSessions)
            .fetchAll(db)
    }) ?? []

    guard !newLogs.isEmpty else { return }

    // 3. 正常分析逻辑（用 newLogs 替代原来的 recentLogs）...

    // 4. 分析完成后更新 last_analyzed_log_id
    let maxId = newLogs.last!.id!
    try? await AppDatabase.shared.dbPool.write { db in
        try db.execute(
            sql: "UPDATE analyzer_state SET last_analyzed_log_id = ? WHERE id = 1",
            arguments: [maxId]
        )
    }
}

验收：
□ 说 20 句 → AI3 触发 → last_analyzed_log_id 更新为最新 raw_log.id
□ 再说 19 句 → 不触发（未满 20 新增）
□ 再说 1 句（第 40 句）→ 触发 → 只分析第 21~40 条
□ clearAIData() 后 last_analyzed_log_id 回 NULL → 下轮从 0 开始
```

---

### FIX-03 · ProfileService.insertCandidates() 去重 【HIGH】

```
问题：
  insertCandidates 只检查 dictionary 表是否已有该词，
  不检查 dictionary_candidates 表是否已有 pending 同词条目，
  导致同一词多次出现在候选列表。

目标文件：
  vilsay/AI3/ProfileService.swift

修复：在 insertCandidates 中加一行检查

private static func insertCandidates(_ arr: [[String: Any]],
                                     db: Database, now: String) throws {
    let existingWords = try Set<String>(
        String.fetchAll(db, sql: "SELECT word FROM dictionary")
    )
    // ★ 新增：也检查已有候选词（pending 和 dismissed 都不重复插入）
    let existingCandidates = try Set<String>(
        String.fetchAll(db, sql: "SELECT word FROM dictionary_candidates")
    )

    for c in arr {
        // ... 已有验证 ...
        if existingWords.contains(w) { continue }
        if existingCandidates.contains(w) { continue }  // ★ 新增
        var rec = DictionaryCandidateRecord(...)
        try rec.insert(db)
    }
}

验收：
□ AI3 两次分析同一批日志 → dictionary_candidates 无重复词条
□ dismissed 的词不会因新一轮分析重新出现
□ approved 后再分析 → 不会再插入候选（dictionary 表已有）
```

---

### FIX-04 · Pipeline ASR 转写超时保护 【HIGH】

```
问题：
  WhisperKit transcribeWithMetrics 和 DashScope transcribe* 均无超时，
  转写卡死时整个 Pipeline 永挂。

目标文件：
  vilsay/Core/Pipeline.swift

修复：用 TaskGroup 给 ASR 转写加 60s 超时

在 process(fileURL:) 中，将 ASR 调用包在超时保护中：

private func process(fileURL url: URL) async {
    // ... 已有 asrText 变量 ...

    // ★ ASR 转写超时保护（60s）
    let asrResult: (text: String, confidence: Double?, provider: String)? =
        await withTaskGroup(of: (String, Double?, String)?.self) { group in
            group.addTask { [self] in
                // 已有的 ASR 路由逻辑（DashScope → Whisper fallback）
                // 返回 (asrText, confidence, provider)
                // ...现有代码迁入此处...
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                return nil  // 超时哨兵
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }

    guard let result = asrResult else {
        // ASR 超时
        os_log(.error, "[Pipeline] ASR timeout after 60s")
        await MainActor.run { AppState.shared.status = .idle }
        return
    }

    // 使用 result.text, result.confidence, result.provider 继续 ...
}

验收：
□ 正常转写不受影响（远小于 60s）
□ 模拟 Whisper 卡死（断点/sleep）→ 60s 后自动超时，状态回 idle
□ 超时后不崩溃、不泄漏
```

---

### FIX-05 · Pipeline VAD continuation 泄漏兜底 【HIGH】

```
问题：
  deliverASRThroughVADToPolish 中 withCheckedContinuation 依赖
  vad.onSentenceComplete 回调来 resume，但若 VAD 永不触发回调，
  continuation 永久泄漏。

目标文件：
  vilsay/Core/Pipeline.swift

修复：给整个 deliverASRThroughVADToPolish 加外层超时

在调用方（process 函数中调用 deliverASRThroughVADToPolish 处）包一层：

// ★ 整体 VAD+Polish 超时保护（40s，大于内层 35s per-segment）
await withTaskGroup(of: Void.self) { group in
    group.addTask {
        await self.deliverASRThroughVADToPolish(
            asrText: asrText,
            asrMs: asrMs,
            usageAsrProvider: provider,
            asrConfidence: confidence
        )
    }
    group.addTask {
        try? await Task.sleep(nanoseconds: 40_000_000_000)
    }
    _ = await group.next()
    group.cancelAll()
}

// 如果是超时退出，确保状态回 idle
if AppState.shared.status != .idle {
    AppState.shared.status = .idle
}

说明：
  - 外层 40s > 内层 per-segment 35s，正常情况内层先完成
  - 如果 VAD 永不回调，40s 后外层超时强制退出
  - cancelAll() 会取消 deliverASRThroughVADToPolish 中的 Task

验收：
□ 正常使用不受影响（VAD 正常触发远小于 40s）
□ 强制 VAD 不回调（测试场景）→ 40s 后状态自动回 idle
□ 不出现 double-resume crash（finish() 内部有 resumed 守卫）
```

---

### FIX-06 · Pipeline audio.start() 超时 【MEDIUM】

```
问题：
  audio.start() 是 async throws，若麦克风初始化异常可能长时间阻塞。

目标文件：
  vilsay/Core/Pipeline.swift

修复：给 audio.start() 加 5s 超时

// 在 beginRecordingSession() 中：
do {
    try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask { try await self.audio.start() }
        group.addTask {
            try await Task.sleep(nanoseconds: 5_000_000_000)
            throw CancellationError()
        }
        try await group.next()
        group.cancelAll()
    }
} catch {
    os_log(.error, "[Pipeline] audio.start() failed or timeout: %{public}@",
           error.localizedDescription)
    AppState.shared.status = .idle
    return
}

验收：
□ 正常录音启动不受影响
□ 麦克风权限拒绝时快速失败（< 5s），状态回 idle
```

---

### FIX-07 · AI3Analyzer getCandidates() 改异步 【MEDIUM】

```
问题：
  analyze() 末尾 ProfileService.getCandidates() 是同步阻塞 DB 读取，
  在 background 线程执行时可能因 DB 争用卡顿。

目标文件：
  vilsay/AI3/AI3Analyzer.swift

修复：改为异步读取

// 旧
let pending = ProfileService.getCandidates().count
await MainActor.run { AppState.shared.candidatesCount = pending }

// 新
let pending = (try? await AppDatabase.shared.dbPool.read { db in
    try DictionaryCandidateRecord
        .filter(Column("state") == "pending")
        .fetchCount(db)
}) ?? 0
await MainActor.run {
    AppState.shared.candidatesCount = pending
    AppState.shared.dictionaryBadgeCount = pending
}

验收：
□ AI3 触发后角标数字正确
□ 无 background 线程阻塞（Instruments Thread Checker 无警告）
```

---

### FIX-08 · FloatingButtonView 动画清理 【LOW】

```
问题：
  recordingDotPulse 在 onAppear 启动闪烁动画，
  但缺少 onDisappear 重置，切换状态后动画资源未释放。

目标文件：
  vilsay/Entry/FloatingButtonView.swift

修复：在录音指示点的 onAppear 附近加 onDisappear

// 在红色闪烁圆点的修饰符中：
.onAppear {
    withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
        recordingDotPulse = true
    }
}
.onDisappear {              // ★ 新增
    recordingDotPulse = false
}

验收：
□ 从录音切到处理状态时红点动画停止
□ 无 SwiftUI 动画警告
```

---

### Review 修复里程碑验收

```
□ FIX-01: 并发写入时"有误"标记正确行
□ FIX-02: AI3 只分析新增日志，last_analyzed_log_id 正确更新
□ FIX-03: 候选词无重复
□ FIX-04: ASR 60s 超时后不永挂
□ FIX-05: VAD 不回调时 40s 后状态回 idle
□ FIX-06: audio.start() 5s 超时
□ FIX-07: AI3 角标更新无阻塞
□ FIX-08: 录音指示点动画对称清理
□ xcodebuild build + test 全部通过
□ 10 次正常录音回归测试：延迟无变化
```

---

# 文档结束
