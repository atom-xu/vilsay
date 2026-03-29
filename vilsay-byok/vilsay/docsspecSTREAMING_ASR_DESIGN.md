# 流式 ASR 技术方案（架构师决策）

**文档版本**：v1.0  
**架构师**：AI Architect  
**评审日期**：2026-03-23  
**状态**：已批准，可进入开发

---

## 📋 执行摘要

**目标**：将当前「整段录音 → ASR → 润色」改为「实时流式 ASR → 文本 VAD → 流式润色」，提升用户体验（延迟从 3-5 秒降至 < 1 秒）。

**核心技术栈**：
- DashScope 实时语音识别（WebSocket）
- 800ms 文本 VAD（基于停顿检测）
- 流式润色（Server-Sent Events）

**预期性能**：
- 首字延迟：< 500ms（说话 → 看到文字）
- 润色延迟：< 1 秒（停止说话 → 文本注入）
- 总延迟：< 1.5 秒（比当前提升 70%）

---

## 🔧 1. DashScope 实时语音识别接入

### 1.1 WebSocket 协议设计

**端点**：`wss://nls-gateway.cn-shanghai.aliyuncs.com/ws/v1`

**鉴权方式**：Token 模式
```swift
// 客户端生成 Token（HMAC-SHA256）
let timestamp = Date().timeIntervalSince1970
let signature = HMACSHA256(
    key: DASHSCOPE_API_KEY,
    data: "APPKEY=\(appKey)&TIMESTAMP=\(timestamp)"
)
let token = "APPKEY=\(appKey)&TIMESTAMP=\(timestamp)&SIGNATURE=\(signature)"

// WebSocket 连接
var request = URLRequest(url: URL(string: "wss://...")!)
request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
```

**音频帧格式**：
- 采样率：16kHz（与当前录音一致）
- 编码：PCM 16-bit（无需额外转换）
- 帧大小：20ms（320 字节 = 16kHz * 2 bytes * 0.02s）
- 发送频率：每 20ms 发送一帧

**协议流程**：
```
客户端                                  DashScope 服务端
  │                                           │
  ├─────── WebSocket 连接 ──────────────────→│
  │                                           │
  ├─────── 开始识别消息 ─────────────────────→│
  │         {                                 │
  │           "header": {                     │
  │             "message_id": "uuid",         │
  │             "task_id": "session_id",      │
  │             "namespace": "SpeechTranscriber"│
  │           },                              │
  │           "payload": {                    │
  │             "format": "pcm",              │
  │             "sample_rate": 16000,         │
  │             "enable_intermediate_result": true│
  │           }                               │
  │         }                                 │
  │                                           │
  ├─────── 音频帧 1 (Binary) ───────────────→│
  │                                           │
  │←─────── 部分结果 (Partial) ───────────────┤
  │         { "text": "今天天气" }            │
  │                                           │
  ├─────── 音频帧 2 (Binary) ───────────────→│
  │                                           │
  │←─────── 部分结果 (Partial) ───────────────┤
  │         { "text": "今天天气很好" }        │
  │                                           │
  ├─────── 音频帧 N (Binary) ───────────────→│
  │                                           │
  │←─────── 最终结果 (Final) ─────────────────┤
  │         { "text": "今天天气很好", "is_final": true }│
  │                                           │
  ├─────── 结束识别消息 ─────────────────────→│
  │                                           │
  │←─────── 关闭连接 ─────────────────────────┤
```

### 1.2 客户端实现（StreamingASRClient.swift）

**核心类设计**：
```swift
@MainActor
final class StreamingASRClient: NSObject, URLSessionWebSocketDelegate {
    // WebSocket 连接
    private var webSocketTask: URLSessionWebSocketTask?
    
    // 回调
    var onPartialResult: ((String) -> Void)?
    var onFinalResult: ((String) -> Void)?
    var onError: ((Error) -> Void)?
    
    // 连接管理
    func connect() async throws {
        let url = URL(string: "wss://nls-gateway.cn-shanghai.aliyuncs.com/ws/v1")!
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        
        // 发送开始消息
        try await sendStartMessage()
        
        // 开始接收消息
        receiveMessages()
    }
    
    // 发送音频帧
    func sendAudioFrame(_ data: Data) async throws {
        let message = URLSessionWebSocketTask.Message.data(data)
        try await webSocketTask?.send(message)
    }
    
    // 结束识别
    func finish() async throws {
        try await sendStopMessage()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
    }
    
    // 接收消息（递归）
    private func receiveMessages() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }
            
            switch result {
            case .success(.string(let text)):
                self.handleTextMessage(text)
                self.receiveMessages()  // 继续接收
                
            case .failure(let error):
                self.onError?(error)
                
            default:
                break
            }
        }
    }
    
    // 处理识别结果
    private func handleTextMessage(_ text: String) {
        guard let json = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let payload = json["payload"] as? [String: Any],
              let result = payload["result"] as? String else {
            return
        }
        
        let isFinal = (payload["is_final"] as? Bool) ?? false
        
        Task { @MainActor in
            if isFinal {
                self.onFinalResult?(result)
            } else {
                self.onPartialResult?(result)
            }
        }
    }
}
```

### 1.3 音频采集改造（AudioCapture.swift）

**当前实现**：录音完成后保存文件  
**改造目标**：实时流式发送

```swift
// AudioCapture.swift 增加流式模式
final class AudioCapture {
    private var streamingClient: StreamingASRClient?
    var isStreamingMode = false  // 由设置控制
    
    // 音频输入回调（每 20ms 调用一次）
    private let inputCallback: AudioQueueInputCallback = { userData, queue, bufferRef, startTime, numPackets, packetDesc in
        guard let userData = userData else { return }
        let capture = Unmanaged<AudioCapture>.fromOpaque(userData).takeUnretainedValue()
        
        let buffer = bufferRef.pointee
        let audioData = Data(bytes: buffer.mAudioData, count: Int(buffer.mAudioDataByteSize))
        
        // 如果是流式模式，立即发送
        if capture.isStreamingMode {
            Task {
                try? await capture.streamingClient?.sendAudioFrame(audioData)
            }
        } else {
            // 否则写入文件（当前逻辑）
            capture.writeToFile(audioData)
        }
    }
    
    func startStreaming() {
        isStreamingMode = true
        streamingClient = StreamingASRClient()
        
        Task {
            try? await streamingClient?.connect()
        }
    }
}
```

### 1.4 错误处理与降级

**降级策略**：
```swift
// Pipeline.swift - 统一入口
private func processWithStreamingASR() async throws -> String {
    // 尝试流式 ASR
    do {
        return try await streamingASRWithTimeout()
    } catch {
        Self.log.warning("流式 ASR 失败，降级到整段识别: \(error)")
        
        // 降级到整段 ASR
        audio.stop()
        guard let fileURL = audio.fileURL else {
            throw ASRError.noAudioFile
        }
        
        return try await WhisperASRFallback.shared.transcribe(fileURL: fileURL)
    }
}

private func streamingASRWithTimeout() async throws -> String {
    try await withThrowingTaskGroup(of: String.self) { group in
        // 流式 ASR 任务
        group.addTask {
            // ... 流式逻辑
        }
        
        // 超时任务（5 秒）
        group.addTask {
            try await Task.sleep(for: .seconds(5))
            throw ASRError.timeout
        }
        
        // 返回第一个完成的结果
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
```

---

## 🎯 2. 800ms 文本 VAD 设计

### 2.1 状态机设计

```
┌─────────────────────────────────────────────────────┐
│              文本 VAD 状态机                         │
├─────────────────────────────────────────────────────┤
│                                                     │
│   [IDLE] ──── 首字 ────→ [ACCUMULATING]            │
│                              │                      │
│                              │ 持续接收文本          │
│                              │                      │
│                              ↓                      │
│                    800ms 无新文本                    │
│                              │                      │
│                              ↓                      │
│                        [TRIGGERED]                  │
│                              │                      │
│                              │ 触发润色              │
│                              │                      │
│                              ↓                      │
│                          [POLISHING]                │
│                              │                      │
│                              │ 润色完成              │
│                              │                      │
│                              ↓                      │
│                           [IDLE]                    │
│                                                     │
│   取消（ESC）── 任何状态 ───→ [CANCELLED] ──→ [IDLE] │
│                                                     │
└─────────────────────────────────────────────────────┘
```

### 2.2 代码实现（StreamingVADBuffer.swift）

```swift
@MainActor
final class StreamingVADBuffer {
    enum State {
        case idle
        case accumulating
        case triggered
        case polishing
        case cancelled
    }
    
    private(set) var state: State = .idle
    private var accumulatedText = ""
    private var lastUpdateTime: Date?
    private var timerTask: Task<Void, Never>?
    
    // 配置
    private let silenceThreshold: TimeInterval = 0.8  // 800ms
    
    // 回调
    var onSentenceComplete: ((String) -> Void)?
    
    // 流式文本输入（每次 Partial Result 调用）
    func feedPartial(_ text: String) {
        guard state != .cancelled && state != .polishing else { return }
        
        // 首字到达
        if state == .idle {
            state = .accumulating
            accumulatedText = text
            lastUpdateTime = Date()
            startSilenceTimer()
            return
        }
        
        // 继续积累
        if state == .accumulating {
            accumulatedText = text
            lastUpdateTime = Date()
            // 重置定时器
            timerTask?.cancel()
            startSilenceTimer()
        }
    }
    
    // 最终结果（Final Result）
    func acceptFinal(_ text: String) {
        guard state != .cancelled else { return }
        
        accumulatedText = text
        triggerCompletion()
    }
    
    // 取消
    func cancel() {
        state = .cancelled
        timerTask?.cancel()
        accumulatedText = ""
    }
    
    // 启动静音定时器
    private func startSilenceTimer() {
        timerTask?.cancel()
        timerTask = Task {
            try? await Task.sleep(for: .seconds(silenceThreshold))
            
            guard !Task.isCancelled else { return }
            guard state == .accumulating else { return }
            
            // 800ms 内无新文本，触发完成
            if let lastUpdate = lastUpdateTime,
               Date().timeIntervalSince(lastUpdate) >= silenceThreshold {
                triggerCompletion()
            }
        }
    }
    
    // 触发完成
    private func triggerCompletion() {
        guard !accumulatedText.isEmpty else { return }
        
        state = .triggered
        timerTask?.cancel()
        
        let text = accumulatedText
        accumulatedText = ""
        
        // 标记为润色中
        state = .polishing
        
        // 回调（触发润色）
        onSentenceComplete?(text)
        
        // 润色完成后重置状态（由外部调用 reset()）
    }
    
    // 重置（润色完成后调用）
    func reset() {
        state = .idle
        accumulatedText = ""
        lastUpdateTime = nil
    }
}
```

### 2.3 与 Pipeline 集成

```swift
// Pipeline.swift
private var streamingVAD = StreamingVADBuffer()

private func beginStreamingSession() {
    streamingVAD.reset()
    
    // 设置回调
    streamingVAD.onSentenceComplete = { [weak self] text in
        guard let self else { return }
        Task {
            await self.runPolishInjectAfterVAD(asrText: text, asrMs: 0)
            self.streamingVAD.reset()  // 润色完成，可以接收下一句
        }
    }
    
    // 启动流式 ASR
    audio.streamingClient?.onPartialResult = { [weak self] text in
        self?.streamingVAD.feedPartial(text)
    }
    
    audio.streamingClient?.onFinalResult = { [weak self] text in
        self?.streamingVAD.acceptFinal(text)
    }
}
```

---

## 🌐 3. 云端 vs 本地路径决策

### 3.1 统一策略

**产品规则**：
| 用户设置 | 网络状态 | 实际行为 | 用户提示 |
|---------|---------|---------|---------|
| 云端模式 | 有网 | 使用流式 ASR | 无 |
| 云端模式 | 无网 | 降级本地 Whisper | "⚠️ 无网络，使用本地识别" |
| 云端模式 | 弱网 | 5s 超时后降级 | "⚠️ 网络较慢，使用本地识别" |
| 本地模式 | 任何 | 始终本地 Whisper | 无 |

**代码实现**：
```swift
// Pipeline.swift
private func selectASRPath() async throws -> String {
    let mode = AppState.shared.recognitionMode
    let isConnected = NetworkMonitor.shared.isConnected
    
    switch mode {
    case .cloud:
        if !isConnected {
            Self.log.info("⚠️ 无网络，降级到本地识别")
            AppState.shared.asrFallbackReason = "无网络连接"
            return try await useLocalWhisper()
        }
        
        do {
            return try await useStreamingASR()
        } catch ASRError.timeout {
            Self.log.warning("⚠️ 流式 ASR 超时，降级到本地")
            AppState.shared.asrFallbackReason = "网络较慢"
            return try await useLocalWhisper()
        } catch {
            Self.log.error("❌ 流式 ASR 失败: \(error)")
            AppState.shared.asrFallbackReason = "云端服务暂时不可用"
            return try await useLocalWhisper()
        }
        
    case .local:
        return try await useLocalWhisper()
    }
}
```

### 3.2 用户设置界面

```swift
// SettingsRootView.swift
Picker("语音识别", selection: $recognitionMode) {
    Text("云端识别（推荐）").tag(RecognitionMode.cloud)
    Text("本地识别（离线可用）").tag(RecognitionMode.local)
}
.help("""
云端识别：
• 准确率更高
• 支持实时流式识别
• 需要网络连接
• 无网时自动降级到本地

本地识别：
• 完全离线可用
• 隐私性更好
• 准确率略低
• 首次使用需下载模型
""")

// 降级提示
if let reason = appState.asrFallbackReason {
    HStack {
        Image(systemName: "exclamationmark.triangle")
            .foregroundColor(.orange)
        Text("已降级到本地识别：\(reason)")
            .font(.caption)
    }
}
```

---

## 📊 4. 性能目标与监控

### 4.1 性能指标

| 指标 | 当前值 | 目标值 | 测量方法 |
|------|-------|-------|---------|
| 首字延迟 | 3-5s | < 500ms | 开始说话 → 首个 Partial Result |
| 润色延迟 | N/A | < 1s | Final Result → 文本注入完成 |
| 总延迟 | 3-5s | < 1.5s | 开始说话 → 文本注入完成 |
| 准确率 | 95% | > 97% | 人工标注对比 |

### 4.2 监控埋点

```swift
// PerformanceTracker.swift
struct StreamingASRMetrics {
    let firstCharLatency: TimeInterval  // 首字延迟
    let finalResultLatency: TimeInterval  // 最终结果延迟
    let polishLatency: TimeInterval  // 润色延迟
    let totalLatency: TimeInterval  // 总延迟
    let fallbackReason: String?  // 降级原因（若有）
}

extension PerformanceTracker {
    static func logStreamingASR(_ metrics: StreamingASRMetrics) {
        // 上报到后端或本地日志
        Self.log.info("""
        [StreamingASR]
        - 首字延迟: \(Int(metrics.firstCharLatency * 1000))ms
        - 最终结果: \(Int(metrics.finalResultLatency * 1000))ms
        - 润色延迟: \(Int(metrics.polishLatency * 1000))ms
        - 总延迟: \(Int(metrics.totalLatency * 1000))ms
        - 降级原因: \(metrics.fallbackReason ?? "无")
        """)
    }
}
```

---

## 🚀 5. 实施计划

### Phase 1（1 周）：基础流式 ASR
- [ ] 实现 `StreamingASRClient.swift`
- [ ] WebSocket 连接与鉴权
- [ ] 音频帧实时发送
- [ ] Partial / Final 结果接收
- [ ] 单元测试（Mock WebSocket）

### Phase 2（1 周）：文本 VAD
- [ ] 实现 `StreamingVADBuffer.swift`
- [ ] 800ms 静音检测
- [ ] 状态机完整覆盖
- [ ] 取消/中断处理
- [ ] 集成测试

### Phase 3（0.5 周）：Pipeline 集成
- [ ] 改造 `AudioCapture` 支持流式
- [ ] `Pipeline` 流式路径
- [ ] 降级策略完整实现
- [ ] 错误处理与日志

### Phase 4（0.5 周）：性能优化与监控
- [ ] 性能埋点
- [ ] 延迟优化（并行化）
- [ ] 用户设置界面
- [ ] 文档与示例

**总计**：3 周（包含测试）

---

## 📝 风险与缓解

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| DashScope API 变更 | 高 | 抽象 `ASRProvider` 接口，易于切换 |
| 网络不稳定 | 中 | 5s 超时 + 自动降级 + 重连机制 |
| 延迟未达标 | 中 | 预留优化时间，必要时调整目标 |
| 用户体验混乱 | 低 | 明确的降级提示与文档 |

---

## ✅ 验收标准

1. **功能完整性**：
   - [ ] 流式 ASR 正常工作（有网环境）
   - [ ] 800ms VAD 准确触发
   - [ ] 无网时自动降级本地
   - [ ] 取消/中断正常工作

2. **性能达标**：
   - [ ] 首字延迟 < 500ms（90% 情况）
   - [ ] 总延迟 < 1.5s（90% 情况）
   - [ ] 准确率 > 95%

3. **用户体验**：
   - [ ] 降级提示清晰友好
   - [ ] 设置界面文案准确
   - [ ] 无卡顿、无闪烁

4. **代码质量**：
   - [ ] 单元测试覆盖率 > 80%
   - [ ] 集成测试通过
   - [ ] 文档完整

---

**批准**：架构师  
**日期**：2026-03-23  
**下一步**：进入开发阶段
