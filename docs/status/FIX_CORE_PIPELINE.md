# 核心链路修复任务书

> 版本：2.0 | 2026-03-26
> 问题：流式输出未启动、润色功能未启动、AI3 未表现
> 根因：API Key 被"调试开关"挡住 + 所有失败静默降级
> 方案：**设置页即唯一配置入口**——用户填 Key、选模型，保存即全链路生效
> 优先级：**CRITICAL**

---

## 核心思路

**砍掉**：`.env` 自动加载、`asrProxyUIConfigEnabled` 开关、环境变量优先级链
**保留**：环境变量仍可覆盖（给开发者 Xcode Scheme 用），但普通用户不需要知道

```
用户打开设置 → 填 API Key → 选模型 → 保存
                    ↓
  AppConfig 直接从 UserDefaults 读取
                    ↓
  ASR(AI1) + 润色(AI2) + AI3 全部生效
```

---

## FIX-P01 · AppConfig 简化：去掉调试开关门槛（CRITICAL）

**问题**：`AppConfig.dashscopeAPIKey` 有 3 层分支——先检查 `asrProxyUIConfigEnabled`，再检查环境变量，再检查 UserDefaults。普通用户在设置页填了 Key 但没开"调试开关"，Key 就读不到。

**方案**：简化为 **环境变量 > UserDefaults**，两层搞定。所有配置项统一此规则。

**文件**：`Config/AppConfig.swift`

**改动**：

```swift
enum AppConfig {

    // MARK: - 统一读取规则：环境变量 > UserDefaults
    // 环境变量给开发者 Xcode Scheme 用；普通用户只管设置页

    /// 百炼 API Key
    static var dashscopeAPIKey: String? {
        envOrDefaults("DASHSCOPE_API_KEY", key: "vilsay.dashscope_api_key")
    }

    /// 润色模型
    static var dashscopePolishModel: String {
        envOrDefaults("VILSAY_QWEN_MODEL", key: "vilsay.dashscope_model_polish")
            ?? "qwen-turbo"
    }

    /// ASR 模型
    static var dashscopeAsrModel: String {
        envOrDefaults("VILSAY_ASR_MODEL", key: "vilsay.dashscope_model_asr")
            ?? "paraformer-v2"
    }

    /// AI3 分析模型
    static var dashscopeAnalyzerModel: String {
        envOrDefaults("VILSAY_ANALYZER_MODEL", key: "vilsay.dashscope_model_analyzer")
            ?? dashscopePolishModel
    }

    /// 流式 ASR 模型
    static var streamingASRModel: String {
        envOrDefaults("VILSAY_STREAMING_ASR_MODEL", key: "vilsay.streaming_asr_model")
            ?? "paraformer-realtime-v2"
    }

    /// 后端 API 基址
    static var backendAPIBaseURL: URL? {
        guard let raw = envOrDefaults("VILSAY_API_BASE", key: "vilsay.api_base") else {
            return nil
        }
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        return URL(string: s)
    }

    // ... 其余属性同理改造 ...

    // MARK: - 便利

    static var hasDashScopeAPIKey: Bool { dashscopeAPIKey != nil }

    static var streamingASREnabled: Bool {
        hasDashScopeAPIKey && NetworkMonitor.shared.isConnected
    }

    // MARK: - 私有

    /// 统一：环境变量优先，UserDefaults 兜底
    private static func envOrDefaults(_ envKey: String, key defaultsKey: String) -> String? {
        if let env = ProcessInfo.processInfo.environment[envKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !env.isEmpty {
            return env
        }
        if let val = UserDefaults.standard.string(forKey: defaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !val.isEmpty {
            return val
        }
        return nil
    }

    // MARK: - 润色 URL（保持现有逻辑不变）

    static var polishUsesOpenAICompatChatCompletions: Bool {
        #if DEBUG
        if let e = ProcessInfo.processInfo.environment["VILSAY_POLISH_USE_COMPAT"]?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            if e == "1" || e == "true" { return true }
            if e == "0" || e == "false" { return false }
        }
        return dashscopePolishModel.contains("/")
        #else
        return false
        #endif
    }

    static var polishHTTPURL: URL {
        #if DEBUG
        if polishUsesOpenAICompatChatCompletions {
            return URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions")!
        }
        #endif
        return qwenPolishEndpoint
    }

    static var qwenPolishEndpoint: URL {
        #if DEBUG
        URL(string: "https://dashscope.aliyuncs.com/api/v1/services/aigc/text-generation/generation")!
        #else
        if let raw = ProcessInfo.processInfo.environment["VILSAY_POLISH_PROXY_URL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           let u = URL(string: raw), !raw.isEmpty {
            return u
        }
        return URL(string: "https://api.vilsay.com/api/v1/polish")!
        #endif
    }

    // MARK: - 热键 / 触发（不变）

    static var triggerMode: TriggerMode {
        guard let raw = UserDefaults.standard.string(forKey: "vilsay.trigger_mode"),
              let mode = TriggerMode(rawValue: raw) else { return .toggle }
        return mode
    }

    static var hotkeyBindingMode: HotkeyBindingMode {
        GlobeKeyHardwareCapabilities.isGlobeModifierLikelyAvailable ? .fnGlobe : .builtinRightOption
    }

    // MARK: - ASR 代理（简化同理）

    static var asrProxyTranscribeURL: URL? {
        guard let raw = envOrDefaults("VILSAY_ASR_PROXY_URL", key: "vilsay.asr_proxy_transcribe_url")
        else { return nil }
        return URL(string: raw)
    }

    static var asrInternalKey: String? {
        envOrDefaults("VILSAY_ASR_INTERNAL_KEY", key: "vilsay.asr_internal_key")
    }

    static var dashscopeParaformerFileURL: String? {
        envOrDefaults("DASHSCOPE_PARAFORMER_FILE_URL", key: "vilsay.dashscope_paraformer_file_url")
    }

    static var googleOAuthClientId: String? {
        envOrDefaults("VILSAY_GOOGLE_CLIENT_ID", key: "vilsay.google_oauth_client_id")
    }

    static var weChatOAuthAuthorizeURL: URL? {
        guard let raw = envOrDefaults("VILSAY_WECHAT_OAUTH_URL", key: "vilsay.wechat_oauth_url")
        else { return nil }
        return URL(string: raw)
    }
}

// 删除旧的 asrProxyUIConfigEnabled 相关属性和所有 asrProxyUIConfigEnabled 分支
```

**关键删除**：
- 删除 `asrProxyUIConfigEnabledKey` 和 `asrProxyUIConfigEnabled` 属性
- 删除所有 `if asrProxyUIConfigEnabled` 分支
- 保留 `String.nilIfEmpty` 扩展

**验收**：
- [ ] 在设置页填写 Key → `AppConfig.dashscopeAPIKey` 立即返回该值
- [ ] 不需要开任何"调试开关"
- [ ] Xcode Scheme 环境变量优先于 UserDefaults
- [ ] 编译通过，无引用 `asrProxyUIConfigEnabled` 的残留

---

## FIX-P02 · 设置页重构：云端服务区直接显示（CRITICAL）

**问题**：API Key 和模型配置藏在 `if asrProxyUIConfigEnabled` 折叠里，用户根本看不到

**方案**：把"语音识别"区域重构为**始终可见**的云端配置 + 模型选择

**文件**：`UI/SettingsRootView.swift`

### 删除

- 删除 `@AppStorage("vilsay.asr_proxy_ui_config_enabled")` 及 Toggle
- 删除 `if asrProxyUIConfigEnabled { ... }` 条件包裹——内容直接显示

### 重构 recognitionSection

```swift
private var recognitionSection: some View {
    GroupBox {
        VStack(alignment: .leading, spacing: VSpacing.md) {

            // ── 1. 识别模式 & 语言 ──
            Picker("识别模式", selection: $state.recognitionMode) {
                ForEach(RecognitionMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.radioGroup)

            Picker("识别语言", selection: $state.asrSpokenLanguage) {
                ForEach(ASRSpokenLanguage.allCases) { lang in
                    Text(lang.title).tag(lang)
                }
            }
            .pickerStyle(.radioGroup)

            Divider()

            // ── 2. API Key（始终可见） ──
            VStack(alignment: .leading, spacing: VSpacing.xs) {
                HStack {
                    Text("DashScope API Key")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    apiKeyStatusBadge
                }
                HStack(spacing: VSpacing.sm) {
                    SecureField("sk-…", text: $dashscopeKeyStored)
                        .textFieldStyle(.roundedBorder)
                    Button("验证连接") {
                        Task { await testAPIConnection() }
                    }
                    .controlSize(.small)
                    .disabled(dashscopeKeyStored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || apiTestBusy)
                    if apiTestBusy {
                        ProgressView().controlSize(.small)
                    }
                }
                if let result = apiTestResult {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(apiTestSuccess ? VColor.ok : VColor.warn)
                }
                Text("从 dashscope.console.aliyun.com 获取")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Divider()

            // ── 3. 模型选择（始终可见） ──
            HStack(spacing: VSpacing.sm) {
                Button("拉取可用模型") {
                    Task { await refreshDashScopeModels() }
                }
                .controlSize(.small)
                .disabled(modelFetchBusy || dashscopeKeyStored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if modelFetchBusy { ProgressView().controlSize(.small) }
                if let hint = modelFetchHint {
                    Text(hint)
                        .font(.caption2)
                        .foregroundStyle(hint.contains("失败") ? VColor.warn : .secondary)
                }
            }

            modelPicker(title: "ASR 模型", options: asrModelOptions, selection: $modelAsr)
            modelPicker(title: "润色模型", options: textModelOptions, selection: $modelPolish)
            modelPicker(title: "AI3 分析模型", options: textModelOptions, selection: $modelAnalyzer)

            Divider()

            // ── 4. 高级配置（折叠，大多数用户不需要） ──
            DisclosureGroup("高级配置") {
                VStack(alignment: .leading, spacing: VSpacing.sm) {
                    Text("后端 API 基址（账号服务，可留空）")
                        .font(.caption2).foregroundStyle(.tertiary)
                    TextField("例：http://127.0.0.1:8000", text: $apiBaseStored)
                        .textFieldStyle(.roundedBorder)

                    Text("ASR 代理 URL（可留空，用于自建 Paraformer 代理）")
                        .font(.caption2).foregroundStyle(.tertiary)
                    TextField("可选", text: $asrProxyURLStored)
                        .textFieldStyle(.roundedBorder)

                    Text("ASR 内部密钥（可留空）")
                        .font(.caption2).foregroundStyle(.tertiary)
                    TextField("可选", text: $asrInternalKeyStored)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.top, VSpacing.xs)
            }
        }
    } label: {
        Label("语音识别 & 云端服务", systemImage: "waveform")
    }
    .onAppear { ensureModelPickersIncludeSelections() }
}
```

### API Key 状态指示器

```swift
@State private var apiTestBusy = false
@State private var apiTestResult: String?
@State private var apiTestSuccess = false

@ViewBuilder
private var apiKeyStatusBadge: some View {
    let key = dashscopeKeyStored.trimmingCharacters(in: .whitespacesAndNewlines)
    if key.isEmpty {
        Label("未配置", systemImage: "exclamationmark.circle")
            .font(.caption)
            .foregroundStyle(VColor.warn)
    } else if apiTestSuccess {
        Label("已连接", systemImage: "checkmark.circle.fill")
            .font(.caption)
            .foregroundStyle(VColor.ok)
    } else {
        Label("已填写", systemImage: "circle.fill")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
```

### 验证连接

```swift
@MainActor
private func testAPIConnection() async {
    apiTestBusy = true
    apiTestResult = nil
    defer { apiTestBusy = false }

    let key = dashscopeKeyStored.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty else {
        apiTestResult = "请先填写 API Key"
        apiTestSuccess = false
        return
    }

    // 用最轻量的请求测试 Key 是否有效
    // 发一个极短的润色请求
    let body: [String: Any] = [
        "model": modelPolish,
        "input": [
            "messages": [
                ["role": "user", "content": "你好"]
            ]
        ],
        "parameters": ["result_format": "message"]
    ]

    guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
        apiTestResult = "请求构造失败"
        apiTestSuccess = false
        return
    }

    var req = URLRequest(url: URL(string: "https://dashscope.aliyuncs.com/api/v1/services/aigc/text-generation/generation")!)
    req.httpMethod = "POST"
    req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = httpBody
    req.timeoutInterval = 10

    do {
        let (_, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse {
            if (200...299).contains(http.statusCode) {
                apiTestResult = "✓ 连接成功（HTTP \(http.statusCode)）"
                apiTestSuccess = true
            } else if http.statusCode == 401 {
                apiTestResult = "✗ Key 无效（HTTP 401）"
                apiTestSuccess = false
            } else if http.statusCode == 429 {
                apiTestResult = "✓ Key 有效，当前限流（HTTP 429）"
                apiTestSuccess = true // Key 是对的，只是限流
            } else {
                apiTestResult = "✗ 异常（HTTP \(http.statusCode)）"
                apiTestSuccess = false
            }
        }
    } catch {
        apiTestResult = "✗ 网络错误：\(error.localizedDescription)"
        apiTestSuccess = false
    }
}
```

**验收**：
- [ ] 打开设置 → API Key 输入框**直接可见**（不需要开任何开关）
- [ ] 填入 Key → 点"验证连接" → 显示"✓ 连接成功"
- [ ] 模型选择器**直接可见**，不需要开开关
- [ ] 高级配置（后端 URL、ASR 代理）在折叠里，默认不展开
- [ ] 填入 Key 后录音 → 润色生效（不再返回原文）

---

## FIX-P03 · 润色失败反馈（HIGH）

**问题**：PolishService 失败时静默返回原文，用户看不到

**方案**：给 PolishService 加 Logger；Pipeline 检测"润色结果==原文"时更新 AppState；菜单栏/浮层显示提示

**文件**：`Core/PolishService.swift`、`Core/Pipeline.swift`、`App/AppState.swift`、`UI/MenuBarRootMenu.swift`

### PolishService 加日志

在每个 `guard ... else { return }` 处加 `os_log`：

```swift
private static let log = Logger(subsystem: "com.vilsay.app", category: "PolishService")

// 无 Key
guard let apiKey = AppConfig.dashscopeAPIKey, !apiKey.isEmpty else {
    log.warning("⚠️ 无 API Key，跳过润色")
    // ...
}

// HTTP 非 2xx
guard ... (200...299).contains(http.statusCode) else {
    log.error("❌ 润色 API HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
    // ...
}

// 无有效 SSE 输出
if !yieldedAny {
    log.warning("⚠️ 流式润色无有效输出，降级 polishPlain")
    // ...
}
```

### AppState 新增

```swift
@Published var lastPolishDidWork: Bool = true
@Published var lastPolishFailReason: String?
```

### Pipeline 检测

```swift
// 在 RawLogger.logAsync 之前
let polishWorked = !fullPolishForTrace.isEmpty && fullPolishForTrace != asrText
Task { @MainActor in
    AppState.shared.lastPolishDidWork = polishWorked
    AppState.shared.lastPolishFailReason = polishWorked ? nil :
        (AppConfig.hasDashScopeAPIKey ? "润色 API 返回异常" : "未配置 API Key，请在设置中填写")
}
```

### 菜单栏提示

```swift
// MenuBarRootMenu.swift 顶部
if let reason = appState.lastPolishFailReason {
    Section {
        Label("润色未生效", systemImage: "exclamationmark.triangle")
        Text(reason).font(.caption)
        if !AppConfig.hasDashScopeAPIKey {
            Button("打开设置") { appState.selectedNavItem = .settings }
        }
    }
}
```

**验收**：
- [ ] 无 Key → 录音 → 菜单栏显示"润色未生效 - 未配置 API Key"
- [ ] 有 Key 但错误 → "润色 API 返回异常"
- [ ] 正常 → 无提示

---

## FIX-P04 · AI3 手动触发 + 状态可见（HIGH）

**问题**：AI3 需要 20 次才触发，开发/测试时等不起。且运行状态不可见。

**方案**：
1. 设置页新增"AI 个性化学习"区域，显示状态 + 手动触发按钮
2. DEBUG 模式阈值降到 5

**文件**：`UI/SettingsRootView.swift`、`Config/Constants.swift`、`AI3/AI3Analyzer.swift`

### 阈值

```swift
// Constants.swift
static let analyzerTriggerThreshold: Int = {
    #if DEBUG
    return 5
    #else
    return 20
    #endif
}()
```

### 设置页新增 Section（插在 dataSection 之前）

```swift
private var ai3Section: some View {
    GroupBox {
        VStack(alignment: .leading, spacing: VSpacing.sm) {
            HStack {
                Text("已记录会话")
                Spacer()
                Text("\(ai3LogCount) 条").foregroundStyle(.secondary)
            }
            HStack {
                Text("自动触发阈值")
                Spacer()
                Text("每 \(Constants.analyzerTriggerThreshold) 条").foregroundStyle(.secondary)
            }
            HStack {
                Text("待审核推荐词")
                Spacer()
                Text("\(state.candidatesCount) 个")
                    .foregroundStyle(state.candidatesCount > 0 ? VColor.accent : .secondary)
            }
            if let date = ai3LastRunAt {
                HStack {
                    Text("上次分析")
                    Spacer()
                    Text(date).font(.caption).foregroundStyle(.secondary)
                }
            }

            HStack(spacing: VSpacing.sm) {
                Button("立即分析") {
                    guard !ai3Running else { return }
                    ai3Running = true
                    Task {
                        await AI3Analyzer.shared.analyze()
                        await MainActor.run {
                            ai3Running = false
                            refreshAI3Info()
                        }
                    }
                }
                .disabled(ai3Running || ai3LogCount == 0 || !AppConfig.hasDashScopeAPIKey)
                if ai3Running { ProgressView().controlSize(.small) }
            }

            if ai3LogCount == 0 {
                Text("完成录音后才有数据可分析")
                    .font(.caption).foregroundStyle(.tertiary)
            } else if !AppConfig.hasDashScopeAPIKey {
                Text("需要 API Key 才能运行分析")
                    .font(.caption).foregroundStyle(VColor.warn)
            }

            if state.candidatesCount > 0 {
                Button("去词典查看推荐词 →") {
                    state.selectedNavItem = .dictionary
                }
                .font(.caption)
            }
        }
    } label: {
        Label("AI 个性化学习", systemImage: "brain")
    }
    .onAppear { refreshAI3Info() }
}

@State private var ai3LogCount: Int = 0
@State private var ai3LastRunAt: String?
@State private var ai3Running = false

private func refreshAI3Info() {
    Task {
        guard let pool = try? AppDatabase.shared.dbPool else { return }
        let count = try? await pool.read { db in try RawLogRecord.fetchCount(db) }
        let analyzerState = try? await pool.read { db in
            try AnalyzerStateRecord.filter(Column("id") == 1).fetchOne(db)
        }
        let candidates = (try? ProfileService.getCandidates().count) ?? 0
        await MainActor.run {
            ai3LogCount = count ?? 0
            ai3LastRunAt = analyzerState?.lastRunAt
            state.candidatesCount = candidates
            state.dictionaryBadgeCount = candidates
        }
    }
}
```

### body 中插入

```swift
// 在 body VStack 中，dataSection 之前加入
ai3Section
```

### AI3Analyzer 成功后刷新 AppState

```swift
// AI3Analyzer.swift analyze() 成功结尾处
Task { @MainActor in
    let count = (try? ProfileService.getCandidates().count) ?? 0
    AppState.shared.candidatesCount = count
    AppState.shared.dictionaryBadgeCount = count
}
```

**验收**：
- [ ] 设置页看到"AI 个性化学习"区域，显示 N 条记录、阈值
- [ ] 有 Key + 有记录 → 点"立即分析" → 转圈 → 完成 → 推荐词数更新
- [ ] 无 Key → 按钮灰色 + 提示"需要 API Key"
- [ ] DEBUG 模式 5 条自动触发

---

## FIX-P05 · AI3Analyzer 日志完善（MEDIUM）

**文件**：`AI3/AI3Analyzer.swift`

在每个 guard/catch 处加 `os_log`：

```swift
private static let log = Logger(subsystem: "com.vilsay.app", category: "AI3Analyzer")

// 无 Key
guard let apiKey = ... else {
    Self.log.error("AI3：无 API Key，跳过")
    return
}

// 无数据
guard !rows.isEmpty else {
    Self.log.info("AI3：无新数据，跳过")
    return
}

// HTTP 错误
guard (200...299).contains(http.statusCode) else {
    Self.log.error("AI3：HTTP \(http.statusCode)")
    return
}

// JSON 解析失败
guard let json = extractJSON(from: content) else {
    Self.log.error("AI3：JSON 解析失败，原始返回: \(content.prefix(500))")
    return
}

// 成功
Self.log.info("AI3：分析完成，\(rows.count) 条记录")
```

同样给 **RawLogger** 加一条成功日志：

```swift
// RawLogger.swift，insert 成功后
// 在 catch 之前
print("[RawLogger] 记录成功: asr=\(trimmedASR.prefix(30))...")
```

**验收**：
- [ ] Console.app 过滤 `AI3` 或 `RawLogger` 能看到完整日志链路
- [ ] 分析失败时有明确原因

---

## FIX-P06 · 浮层润色状态提示（LOW）

**文件**：`Entry/FloatingButtonView.swift`

在完成态浮层中，如果 `lastPolishDidWork == false`，显示小提示：

```swift
// completionPill 视图中
if !appState.lastPolishDidWork, let reason = appState.lastPolishFailReason {
    Text(reason)
        .font(.system(size: 9))
        .foregroundStyle(VColor.warn)
        .lineLimit(1)
}
```

**验收**：
- [ ] 无 Key 时录音完 → 浮层底部显示黄色小字"未配置 API Key"
- [ ] 正常时 → 不显示

---

## 执行顺序

```
FIX-P01 (AppConfig 简化)    ← 最先，解除 Key 门槛
FIX-P02 (设置页重构)        ← 让用户能填 Key
FIX-P03 (润色反馈)          ← 让用户看到状态
FIX-P04 (AI3 手动触发)      ← 让 AI3 可验证
FIX-P05 (日志)              ← 排障
FIX-P06 (浮层提示)          ← 锦上添花
```

**预估总量**：AppConfig 重写 ~100 行 + 设置页改造 ~150 行 + 其余各 ~30 行，一共不到 400 行代码改动。

---

## 完成后的验证流程

```
1. 打开 App → 设置页
2. 在 "DashScope API Key" 输入框填入 sk-xxx
3. 点"验证连接" → 显示 "✓ 连接成功"
4. 模型选择器确认：ASR=paraformer-v2，润色=qwen-turbo
5. 关闭设置
6. 按住录音 → 松开 → 等 1-2 秒
7. 观察：润色后的文字（不是 ASR 原文）被输入到光标位置
8. 菜单栏无"润色未生效"警告
9. 重复步骤 6 五次（DEBUG 阈值）
10. 打开设置 → "AI 个性化学习" → "已记录 5 条" → 点"立即分析"
11. 分析完成 → "待审核推荐词 N 个" → 点"去词典查看"
12. 词典页面显示 AI 推荐的词汇
```

---

## 变更记录

| 版本 | 日期 | 变更 |
|------|------|------|
| 1.0 | 2026-03-26 | 初始版本（.env 加载方案） |
| 2.0 | 2026-03-26 | **重写**：砍掉 .env，设置页直接配置，去掉调试开关门槛 |
