# Week 3 风险点处理计划

> **文档用途：** 明确 Week 3 风险点的处理方案和时间安排  
> **创建日期：** 2026-03-22  
> **创建人：** Kimi (测试工程师)  
> **原则：** 风险点在当前开发阶段解决，不推迟到后续版本

---

## 一、风险点清单与处理决策

| # | 风险点 | 原计划 | 决策 | 处理时间 |
|---|--------|--------|------|----------|
| 1 | 阿里云 ASR 占位 | 后续版本接入 | **当前 Week 3 完成** | W3-D6-D7 (2天) |
| 2 | Qwen 润色同步调用 | 后续版本改为流式 | **当前 Week 3 完成** | W3-D6 (1天) |
| 3 | 文字注入剪贴板方案 | 保持当前方案 | **当前 Week 3 优化** | W3-D7 (1天) |
| 4 | 延迟测试 | 后续联调测试 | **当前 Week 3 完成** | W3-D8 (1天) |

---

## 二、详细处理方案

### 风险点 1：W3-03 阿里云 ASR WebSocket 流式

**当前状态：**
- DashScopeASRClient.transcribeFileIfAvailable() 返回 nil
- 自动降级到 WhisperKit

**问题：**
- 与任务书要求"流式输出文字"不符
- WhisperKit 本地识别精度可能不如云端

**处理方案：**

```swift
// DashScopeASRClient.swift - 需要实现
enum DashScopeASRClient {
    static func transcribeStreaming(_ audioStream: AsyncStream<Data>) -> AsyncStream<String> {
        // 1. 建立 WebSocket 连接 wss://dashscope.aliyuncs.com/...
        // 2. 发送实时音频流（分块上传）
        // 3. 接收流式识别结果（增量返回）
        // 4. 通过 AsyncStream 逐字输出
    }
}
```

**技术要点：**
- WebSocket 库：使用 Apple Native `URLSessionWebSocketTask`
- 音频分片：每 100ms 发送一个音频包
- Token 管理：从环境变量获取，支持短期 Token
- 降级策略：WebSocket 连接失败时降级到 WhisperKit

**验收标准：**
```
□ 建立 WebSocket 连接成功
□ 说话后实时打印识别文字（延迟 < 500ms）
□ 断句后触发 VAD 传给 AI2
□ 连接失败自动降级到 WhisperKit
```

**工作量：** 2天

---

### 风险点 2：W3-07 Qwen 润色 SSE 流式

**当前状态：**
- polishStreaming 方法为模拟流式（单次请求后 yield）
- 用户看不到逐字输出效果

**问题：**
- 与任务书要求"流式输出润色结果"不符
- 用户体验：需要等待完整结果才能看到文字

**处理方案：**

```swift
// PolishService.swift - 需要改为 SSE 流式
static func polishStreamingSSE(
    system: String,
    user: String
) -> AsyncThrowingStream<String, Error> {
    AsyncThrowingStream { continuation in
        Task {
            // 1. 发起 HTTP POST 请求
            // 2. 设置 stream: true 参数
            // 3. 使用 URLSession.bytes 读取 SSE 流
            // 4. 解析 data: {...} 行，提取 content
            // 5. 通过 continuation.yield 逐字输出
        }
    }
}
```

**技术要点：**
- SSE (Server-Sent Events) 格式解析
- 实时 yield 每个 token
- Pipeline 需要适配流式注入（逐字模拟键盘输入）

**验收标准：**
```
□ 润色结果逐字显示
□ 用户可以看到文字实时出现
□ 流式中断时保留已输出内容
```

**工作量：** 1天

---

### 风险点 3：W3-08 文字注入 AXUIElement 方案

**当前状态：**
- 使用剪贴板 + Cmd+V 模拟粘贴
- 可能污染用户剪贴板

**问题：**
- 与任务书要求"AXUIElement 注入光标"不符
- 剪贴板原有内容被覆盖

**处理方案：**

```swift
// TextInjector.swift - 改为 AXUIElement 直接注入
enum TextInjector {
    static func insertWithAXUIElement(_ text: String) {
        // 1. 获取当前焦点元素 AXUIElementCreateSystemWide()
        // 2. 读取 kAXFocusedUIElementAttribute
        // 3. 检查元素是否支持 kAXValueAttribute
        // 4. 获取当前值，在光标位置插入文字
        // 5. 设置 kAXValueAttribute 为新值
        // 6. 失败时降级到剪贴板方案
    }
}
```

**技术要点：**
- 需要 Accessibility 权限（已在 Onboarding 申请）
- 需要处理光标位置（kAXSelectedTextRangeAttribute）
- 部分应用可能不支持直接注入，需要降级方案

**验收标准：**
```
□ 文字直接注入到光标位置
□ 不污染用户剪贴板
□ 微信/VS Code/Safari/备忘录/Slack 均可用
□ 不支持时降级到剪贴板方案
```

**工作量：** 1天

---

### 风险点 4：延迟测试

**当前状态：**
- 未进行实际延迟测量

**问题：**
- Week 3 里程碑要求"延迟 < 1.5 秒（10次平均）"
- 无法验证是否达标

**处理方案：**

```swift
// 在 Pipeline 中添加延迟测量
final class Pipeline {
    private var latencyMetrics: [Double] = []
    
    private func process(fileURL: URL) async {
        let startTime = CFAbsoluteTimeGetCurrent()
        // ... 处理链
        let endTime = CFAbsoluteTimeGetCurrent()
        let latency = (endTime - startTime) * 1000 // ms
        latencyMetrics.append(latency)
        
        // 打印日志供测试
        print("本次延迟: \(Int(latency))ms, 平均: \(Int(averageLatency))ms")
    }
    
    var averageLatency: Double {
        guard !latencyMetrics.isEmpty else { return 0 }
        return latencyMetrics.reduce(0, +) / Double(latencyMetrics.count)
    }
}
```

**测试步骤：**
```
1. 配置 DASHSCOPE_API_KEY 环境变量
2. 打开控制台查看延迟日志
3. 进行 10 次语音输入测试
4. 记录每次延迟并计算平均值
5. 验证是否 < 1500ms
```

**验收标准：**
```
□ 10次平均延迟 < 1500ms
□ 单次最大延迟 < 3000ms
□ 延迟数据可查看（日志或调试菜单）
```

**工作量：** 0.5天 + 测试时间

---

## 三、修订后的 Week 3 时间安排

### 原计划 (W3-D1~D5)
```
D1: HotkeyProcess, AudioCapture
D2: ASRService(阿里云)
D3: VADBuffer, PolishService(Qwen)
D4: TextInjector
D5: Pipeline整合, 测试
```

### 修订后 (W3-D1~D8)
```
D1: ✅ HotkeyProcess, AudioCapture
D2: ⚠️ ASRService(阿里云占位)
D3: ✅ VADBuffer, PolishService(Qwen占位)
D4: ⚠️ TextInjector(剪贴板方案)
D5: ✅ Pipeline整合, 基础测试

--- Week 3 风险处理延期 ---

D6: 阿里云 ASR WebSocket 流式 (W3-03完善)
D7: Qwen SSE 流式 + 文字注入 AXUIElement (W3-07完善 + W3-08优化)
D8: 延迟测试 + 全面回归测试
```

---

## 四、风险处理后的验收标准

### W3-03 阿里云 ASR（修订后）
```
□ WebSocket 连接建立成功
□ 实时音频流上传
□ 流式识别结果返回
□ 延迟 < 500ms（从说话到显示）
□ 断网自动降级到 WhisperKit
```

### W3-07 Qwen 润色（修订后）
```
□ SSE 流式调用
□ 润色结果逐字输出
□ 用户可感知流式效果
□ 失败返回原始文字
```

### W3-08 文字注入（修订后）
```
□ AXUIElement 直接注入光标
□ 不污染用户剪贴板
□ 5个测试场景通过（微信/VS Code/Safari/备忘录/Slack）
□ 不支持时降级到剪贴板
```

### Week 3 里程碑（修订后）
```
□ 按住热键说话，文字出现在前台应用
□ 延迟 < 1.5 秒（10次平均测量）
□ 选中文字说指令，文字被修改
□ ESC 取消无输出
```

---

## 五、与后续 Week 的边界

| Week | 范围 | 不包含（避免范围蔓延）|
|------|------|---------------------|
| **Week 3 修订后** | 主链路完整实现（流式ASR + 流式润色 + AX注入）| 账号体系、用量统计 |
| Week 4 | 账号体系（登录/注册/用量）| AI3、词典推荐 |
| Week 5 | AI3 数据层 + 分析层 | 后端服务器（W4已做基础版）|
| Week 6 | 词典半自动化 + 系统优化 | 官网、高级功能 |

---

## 六、建议决策

**选项 A：按修订计划完成 Week 3（推荐）**
- 延期 3 天（D6-D8）完成流式 ASR、流式润色、AX注入
- 保证 Week 3 里程碑真正达标
- Week 4 开始账号体系开发

**选项 B：当前状态进入 Week 4**
- 风险点作为技术债务进入后续版本
- 主链路可用但体验不完美
- 可能导致 Week 6 测试阶段返工

**建议：选择选项 A**
- 理由：基础功能不扎实会导致后续版本不稳定
- 时间成本：3天延期 vs 可能的 Week 6 返工

---

**文档结束**
**等待架构师/项目负责人决策**
