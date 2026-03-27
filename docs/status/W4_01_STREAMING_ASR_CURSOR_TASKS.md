# W4-01 · WebSocket 流式 ASR 任务书

**版本**: 1.0 | **日期**: 2026-03-25
**前置阅读**: `docs/spec/VILSAY_TECH_ARCH.md`、`docs/VILSAY_TECH_SPEC_SUPPLEMENT.md §一`
**关联微架构**: 见本文件「架构设计」章节

---

## 背景与目标

当前 ASR 路径：
```
麦克风 → 整段 .wav 文件 → Whisper（本地）→ 润色
```

目标路径：
```
麦克风 → PCM 音频流 → DashScope Paraformer WebSocket（实时）→ 润色
                   ↘ 同时写 .wav 文件（Whisper 兜底）
```

收益：
- **不再需要 OSS**：音频直接推给 DashScope，无需公网 URL
- **延迟更低**：WebSocket 实时返回识别结果，与录音并行
- **VADBuffer 可接入**：实时 partial text 可检测 800ms 停顿

---

## 架构设计（微架构）

### 数据流

```
AVAudioEngine.installTap（每 100ms 回调一次）
    │
    ├─→ Data（PCM 16-bit LE）→ DashScopeStreamingASRClient.send(chunk)
    │                                   │
    │                          WebSocket → DashScope paraformer-realtime-v2
    │                                   │
    │                          onPartialText（可选：喂给 VADBuffer）
    │                          onFinalText → Pipeline.deliverStreamingASRResult
    │
    └─→ AVAudioFile.write（同帧写入 .wav，Whisper 兜底用）
```

### 路由决策（Pipeline）

```swift
// stopRecording() 触发时：
if let streamingResult = streamingASR.finalText, !streamingResult.isEmpty {
    // WebSocket 已给出结果，直接用
    await deliverASRThroughVADToPolish(streamingResult)
} else {
    // WebSocket 超时/失败/无 Key → Whisper 兜底
    await runWhisperFallback(fileURL: url)
}
```

### 会话生命周期

```
Pipeline.beginRecordingSession()
    → DashScopeStreamingASRClient.startSession(taskId: sessionUUID)
    → AVAudioEngine 启动 + tap 安装

录音中（tap 回调，每 100ms）
    → client.send(pcmChunk)

Pipeline.stopRecording()
    → client.finishTask()     ← 发 finish-task，等 DashScope 返回最终结果
    → AVAudioEngine 停止 tap
    → 最多等 3 秒拿结果，超时 → Whisper 兜底
```

---

## 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `Entry/AudioCapture.swift` | **重写** | AVAudioRecorder → AVAudioEngine + installTap + AVAudioFile |
| `Core/DashScopeStreamingASRClient.swift` | **新建** | WebSocket 客户端 |
| `Core/Pipeline.swift` | **修改** | 路由逻辑，接入 streaming client |
| `Config/AppConfig.swift` | **修改** | 新增 `streamingASREnabled` / `streamingASRModel` |

**不修改**：`WhisperASRFallback`、`VADBuffer`、`PolishService`、`TextInjector`

---

## 任务一：重写 AudioCapture（AVAudioEngine）

```
目标文件：Entry/AudioCapture.swift

当前：AVAudioRecorder → 写整段 .wav 文件
目标：AVAudioEngine + installTap → 同时（1）流式 PCM 回调 + （2）写 .wav 文件

具体要求：

1. 将 AVAudioRecorder 替换为 AVAudioEngine + AVAudioFile：
   - engine = AVAudioEngine()
   - inputNode = engine.inputNode
   - 请求 16kHz 单声道格式：
     AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)
   - 若 inputNode 硬件格式不是 16kHz，使用 AVAudioConverter 降采样后写文件和回调

2. installTap(onBus: 0, bufferSize: 1600, format: ...) 实现：
   - 每次回调将 PCMBuffer 转为 Data（16-bit LE）
   - 调用 onPCMChunk?(data)（外部注入的回调，可为 nil）
   - 同时 append 到 AVAudioFile（写 .wav，用于 Whisper 兜底）

3. 新增属性：
   var onPCMChunk: ((Data) -> Void)?   // Pipeline 设置，streaming client 消费

4. stop() 时：
   - removeTap(onBus: 0)
   - engine.stop()
   - 关闭 AVAudioFile（文件完整可读）
   - onPCMChunk = nil

5. 保持现有接口不变：
   - start() async throws
   - stop()
   - fileURL: URL?（仍指向写好的 .wav）
   - discardFile()
   - AudioCaptureError（保留 recordStartFailed / excludedForDiagnostics）

6. DiagnosticsExclusion.excludeMicrophoneHAL 判断保留

验收：
□ MicTestController（设置内试录）使用同一 AudioCapture，录 3 秒能播放（说明文件完整）
□ onPCMChunk 回调以约 100ms 间隔触发，data 非空
□ stop() 后 fileURL 指向可读的 .wav 文件
□ xcodebuild test -only-testing:vilsayTests 全绿（无新测试失败）
```

---

## 任务二：新建 DashScopeStreamingASRClient

```
目标文件：Core/DashScopeStreamingASRClient.swift

WebSocket 端点：wss://dashscope.aliyuncs.com/api-ws/v1/inference/
协议文档参考：DashScope 语音识别 WebSocket 实时接口

接口设计：

@MainActor
final class DashScopeStreamingASRClient: NSObject {
    static let shared = DashScopeStreamingASRClient()

    // 外部注入回调
    var onPartialText: ((String) -> Void)?   // 实时 partial（可选，给 VAD）
    var onFinalText: ((String) -> Void)?     // 最终识别结果

    // 状态
    private(set) var isConnected = false
    private(set) var finalText: String?      // 本次会话最终结果

    // 生命周期
    func startSession(taskId: UUID, apiKey: String, model: String) async throws
    func send(pcmChunk: Data)                // 发送 PCM 音频块
    func finishTask() async                  // 发 finish-task，等最终结果
    func cancel()                            // 强制断开，不等结果

    // 内部
    private var webSocket: URLSessionWebSocketTask?
    private var sessionTaskId: String?
    private var receiveTask: Task<Void, Never>?
}

协议实现要点：

1. startSession：
   - 建立 WebSocket 连接（URLSession.webSocketTask）
   - 发送 run-task 消息：
     {
       "header": {"action":"run-task","task_id":"<uuid>","streaming":"duplex"},
       "payload": {
         "task_group":"audio","task":"asr","function":"recognition",
         "model":"<model>",
         "parameters": {"sample_rate":16000,"format":"pcm"},
         "input":{}
       }
     }
   - 启动 receiveLoop()（Task.detached 持续接收消息）

2. send(pcmChunk)：
   - webSocket?.send(.data(pcmChunk), completionHandler:)
   - 若未连接静默丢弃

3. finishTask()：
   - 发送 finish-task 消息
   - 等待 onFinalText 回调，最多 3 秒（超时视为失败）

4. receiveLoop()：
   接收 WebSocket 消息，解析 JSON：
   - event == "result-generated"：
     - 取 payload.output.sentence.text
     - sentence_end == false → onPartialText?(text)
     - sentence_end == true  → finalText = text; onFinalText?(text)
   - event == "task-finished" → 结束接收循环
   - event == "task-failed" → log 错误，cancel()
   - 连接断开 → log，cancel()

5. 错误处理：
   - 任何异常静默失败（Pipeline 会走 Whisper 兜底）
   - 不向 AppState 写入错误（避免干扰主链路错误展示）

验收：
□ 配置 DASHSCOPE_API_KEY 后，说一句话，Xcode 控制台能看到 WebSocket partial/final text
□ 无 API Key 时 startSession 直接返回（不 throw，不崩溃）
□ 网络断开时 send/finishTask 不崩溃
```

---

## 任务三：修改 Pipeline 接入流式 ASR

```
目标文件：Core/Pipeline.swift、Config/AppConfig.swift

AppConfig.swift 新增：

/// 流式 ASR 开关：有 DASHSCOPE_API_KEY 且网络可用时自动开启
static var streamingASREnabled: Bool {
    hasDashScopeAPIKey && NetworkMonitor.shared.isConnected
}

/// 流式 ASR 模型，默认 paraformer-realtime-v2
static var streamingASRModel: String {
    ProcessInfo.processInfo.environment["VILSAY_STREAMING_ASR_MODEL"]
    ?? UserDefaults.standard.string(forKey: "vilsay.streaming_asr_model")
    ?? "paraformer-realtime-v2"
}

Pipeline.swift 修改三处：

【1】beginRecordingSession() — 录音启动后，立即开 WebSocket：

    // 现有 audio.start() 之后，新增：
    if AppConfig.streamingASREnabled, let key = AppConfig.dashscopeAPIKey {
        audio.onPCMChunk = { [weak self] data in
            Task { @MainActor in
                DashScopeStreamingASRClient.shared.send(pcmChunk: data)
            }
        }
        try? await DashScopeStreamingASRClient.shared.startSession(
            taskId: sessionUUID,   // 用 Pipeline 现有的 pendingPushSessionId 或新建
            apiKey: key,
            model: AppConfig.streamingASRModel
        )
    }

【2】stopRecording() — 松键时，先拿 WebSocket 结果，再决定是否用 Whisper：

    // 现有 audio.stop() 之后，替换 process(fileURL:) 调用：
    audio.onPCMChunk = nil   // 停止推流

    if AppConfig.streamingASREnabled {
        await DashScopeStreamingASRClient.shared.finishTask()
    }

    if let streamResult = DashScopeStreamingASRClient.shared.finalText,
       !streamResult.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        // 流式结果有效，直接送润色
        DashScopeStreamingASRClient.shared.finalText = nil
        await deliverASRThroughVADToPolish(streamResult, asrProvider: "paraformer-streaming")
    } else {
        // 兜底：Whisper 处理文件
        DashScopeStreamingASRClient.shared.finalText = nil
        await process(fileURL: url)   // 原有逻辑不变
    }

【3】cancel() — 取消时同时断开 WebSocket：

    // 现有 audio.stop() / discardFile() 之后，新增：
    audio.onPCMChunk = nil
    DashScopeStreamingASRClient.shared.cancel()

验收：
□ 有 API Key + 网络：说一句话，PerformanceTracker 日志中 ASR 来源为 paraformer-streaming
□ 无 API Key：走 Whisper，日志 ASR 来源为 whisper，主链路不受影响
□ WebSocket 超时（手动断网后说话）：等 3 秒后走 Whisper，不卡死
□ ESC 取消：WebSocket 断开，无残留连接
□ xcodebuild test -only-testing:vilsayTests 全绿
```

---

## 整体验收标准

```bash
# 单元测试（不回归）
cd vilsay
xcodebuild -scheme vilsay -destination 'platform=macOS' \
  test -only-testing:vilsayTests 2>&1 | tail -5
# 期望：TEST SUCCEEDED
```

**手动验收（需 DASHSCOPE_API_KEY）**：

```
1. 按热键说「今天天气怎么样」
   → Xcode 控制台出现 WebSocket partial/final text
   → 识别结果正确润色并注入
   → 全链路延迟 < 1.5s（与 Whisper 相比应有明显提升）

2. 断开网络后说话
   → 等约 3 秒
   → 走 Whisper 兜底，结果正常注入
   → 菜单栏无错误提示（WebSocket 失败静默处理）

3. 说话中途 ESC
   → 无文字注入
   → WebSocket 连接正常断开（不留后台任务）

4. 设置内试录功能正常（AudioCapture 重写后仍可录音、播放）
```

---

## 注意事项

1. **不要修改 `WhisperASRFallback`**：兜底路径必须保持完整
2. **不要修改 `PolishService` / `TextInjector`**：下游不感知 ASR 来源
3. **`DiagnosticsExclusion.excludeMicrophoneHAL`**：AudioCapture 重写后此判断必须保留
4. **MicTestController**（`SettingsDiagnosticsSection.swift`）用了同一个 `AudioCapture` 类，重写后试录功能必须仍然正常

---

# 文档结束
