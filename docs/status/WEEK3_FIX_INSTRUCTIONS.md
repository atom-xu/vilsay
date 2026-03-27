# Week 3 风险点修复指令

> **文档用途：** 给 Cursor 的具体修复指令和技术决策记录  
> **创建日期：** 2026-03-22  
> **决策人：** 架构师  
> **执行人：** Cursor  
> **验收人：** Kimi

---

## 一、技术决策摘要

| 风险点 | 原要求 | 决策 | 原因 |
|--------|--------|------|------|
| W3-03 阿里云 ASR | WebSocket 流式 | 先修复认证问题，REST 亦可接受 | 认证问题是主因，流式是次因 |
| W3-07 Qwen 润色 | SSE 流式 | **必须 SSE 流式** | 影响体感最大，同步 unacceptable |
| W3-08 文字注入 | AXUIElement | **剪贴板 + 保护** | AXUIElement 不稳定，剪贴板方案经 Typeless/VoiceInk 验证 |
| 延迟测试 | < 1.5s | 修复后测试 | 现在测无意义 |

**修复优先级：** W3-07 流式 > W3-03 ASR > W3-08 剪贴板保护

---

## 二、W3-07：Qwen SSE 流式（最高优先级）

### 问题
当前 `polishStreaming` 是同步调用后模拟流式，用户感知「卡顿然后突然出现」。

### 目标
第一个 token 生成立即开始注入，用户看到文字逐字出现。

### 给 Cursor 的指令

```
PolishService 必须使用 Qwen 的流式 API（stream: true），
用 URLSession 的 dataTask + 逐行解析 SSE 响应，
每收到一个 token 立即回调，不等全部完成。
```

### 实现参考

```swift
// PolishService.swift - 修改为真正 SSE 流式
static func polishStreamingSSE(
    system: String,
    user: String
) -> AsyncThrowingStream<String, Error> {
    AsyncThrowingStream { continuation in
        Task {
            guard let key = AppConfig.dashscopeAPIKey, !key.isEmpty else {
                // 无 Key 时直接返回原文
                continuation.yield(extractPlainText(from: user))
                continuation.finish()
                return
            }
            
            // 1. 构造请求体，设置 stream: true
            let body: [String: Any] = [
                "model": AppConfig.qwenModel,
                "input": [
                    "messages": [
                        ["role": "system", "content": system],
                        ["role": "user", "content": user]
                    ]
                ],
                "parameters": [
                    "result_format": "message",
                    "stream": true  // 关键：启用流式
                ]
            ]
            
            guard let httpBody = try? JSONSerialization.data(withJSONObject: body),
                  let url = URL(string: "https://dashscope.aliyuncs.com/api/v1/services/aigc/text-generation/generation") else {
                continuation.yield(extractPlainText(from: user))
                continuation.finish()
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = httpBody
            
            // 2. 使用 dataTask 接收 SSE 流
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                // 错误处理...
            }
            
            // 3. 逐行解析 SSE 格式：data: {...}
            // 4. 每解析出一个 token，立即 continuation.yield(token)
            // 5. 流结束时 continuation.finish()
            
            task.resume()
        }
    }
}
```

### SSE 解析要点

```
SSE 响应格式：
data: {"output": {"choices": [{"message": {"content": "第"}}]}}
data: {"output": {"choices": [{"message": {"content": "一个"}}]}}
data: {"output": {"choices": [{"message": {"content": "token"}}]}}
data: [DONE]

解析逻辑：
1. 按行读取响应体
2. 找以 "data: " 开头的行
3. 去掉 "data: " 前缀，解析 JSON
4. 提取 output.choices[0].message.content
5. 立即 yield 给调用方
```

### 验收标准
```
□ Qwen 请求参数包含 "stream": true
□ 使用 URLSession dataTask 接收流式响应
□ 逐行解析 SSE 格式 data: {...}
□ 每收到一个 token 立即回调（不等全部完成）
□ Pipeline 逐字注入到前台应用
□ 用户可感知文字逐字出现
```

---

## 三、W3-03：阿里云 ASR 认证修复

### 问题诊断
返回 nil 大概率是 **认证问题**，不是流式接口本身的问题。

### 根本原因
阿里云 DashScope 实时语音识别需要：
- WebSocket 连接
- Bearer Token（格式不对或过期会直接失败）

### 处理方法（先隔离测试）

**步骤 1：curl 隔离测试**

```bash
# 先用 curl 测试 Token 和请求格式是否正确
curl -X POST \
  https://dashscope.aliyuncs.com/api/v1/services/asr/transcription \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "paraformer-realtime-v2",
    "input": {
      "sample_rate": 16000,
      "format": "pcm"
    }
  }'
```

**步骤 2：确认 Token 有效**
- 检查 Token 是否过期
- 检查 Token 是否有 ASR 调用权限
- 检查 Token 格式（是否需要 `sk-` 前缀等）

**步骤 3：接进 Swift**
- 确认 curl 通后再接进 `DashScopeASRClient`
- 不要在 App 里调试 API，太难定位

### 给 Cursor 的指令

```
先隔离测试阿里云 DashScope ASR API：
1. 用 curl 或 Postman 单独测试，确认 Token 和请求格式正确
2. 测试通过后再接进 Swift 的 DashScopeASRClient
3. 当前可以先使用 REST API（非 WebSocket），只要能返回识别结果即可
4. 认证通了之后再考虑 WebSocket 流式优化
```

### 验收标准
```
□ curl 测试返回正确识别结果
□ Swift 中 DashScopeASRClient 返回非 nil
□ 网络正常时优先使用云端 ASR
□ 断网时降级到 WhisperKit
```

---

## 四、W3-08：剪贴板保护方案

### 技术决策
**接受剪贴板方案，但做好剪贴板保护。**

### 原因
- AXUIElement 真正能稳定注入的场景很少
- Typeless 和 VoiceInk 实际上也用剪贴板 + 粘贴
- 很多开发者坚持 AXUIElement 反而踩坑

### 优化方案：剪贴板保存→注入→还原

```swift
// TextInjector.swift - 修改为带保护的剪贴板方案
enum TextInjector {
    static func insertAtFrontmost(_ text: String) {
        // 1. 保存当前剪贴板内容
        let saved = NSPasteboard.general.string(forType: .string)
        
        // 2. 写入润色文字
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        
        // 3. 模拟 Cmd+V 粘贴
        simulatePaste()
        
        // 4. 短暂延迟后还原剪贴板（100ms 足够粘贴完成）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let saved = saved {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(saved, forType: .string)
            } else {
                NSPasteboard.general.clearContents()
            }
        }
    }
    
    private static func simulatePaste() {
        let src = CGEventSource(stateID: .hidSystemState)
        let vKey: CGKeyCode = CGKeyCode(kVK_ANSI_V)
        guard
            let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true),
            let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
```

### 给 Cursor 的指令

```
TextInjector 改为剪贴板保护方案：
1. 注入前保存用户当前剪贴板内容
2. 写入润色文字到剪贴板
3. 模拟 Cmd+V 粘贴（速度要快）
4. 100ms 延迟后还原用户原剪贴板内容
5. 确保粘贴动作在 100ms 内完成
```

### 验收标准
```
□ 保存用户原剪贴板内容
□ 润色文字成功注入到前台应用
□ 100ms 内还原用户原剪贴板
□ 用户感知不到剪贴板被「借用」
□ 测试场景：微信/VS Code/Safari/备忘录/Slack
```

---

## 五、延迟测试

### 决策
**三个问题修完之后再测延迟，现在测没有意义。**

### 原因
- W3-03 和 W3-07 修好之后延迟自然会大幅下降
- 现在测的是「同步调用 + 本地识别」的延迟，不代表最终性能
- 修复后再看距离 1.5 秒还差多少

### 测试时机
```
W3-07 流式修复后 → 初步测试
W3-03 ASR 修复后 → 完整测试
W3-08 剪贴板优化后 → 最终测试
```

### 测试方法
```swift
// Pipeline 中添加延迟测量
final class Pipeline {
    private var latencyMetrics: [(date: Date, latencyMs: Double)] = []
    
    private func process(fileURL: URL) async {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // ... 处理链
        
        let endTime = CFAbsoluteTimeGetCurrent()
        let latencyMs = (endTime - startTime) * 1000
        
        latencyMetrics.append((Date(), latencyMs))
        
        // 打印日志
        print("[Latency] 本次: \(Int(latencyMs))ms, 平均: \(Int(averageLatency))ms")
    }
    
    var averageLatency: Double {
        guard !latencyMetrics.isEmpty else { return 0 }
        return latencyMetrics.map { $0.latencyMs }.reduce(0, +) / Double(latencyMetrics.count)
    }
    
    // 调试用：导出延迟报告
    func exportLatencyReport() -> String {
        let lines = latencyMetrics.map { "\($0.date): \($0.latencyMs)ms" }
        return lines.joined(separator: "\n")
    }
}
```

### 验收标准（修复后）
```
□ 10次平均延迟 < 1500ms
□ 单次最大延迟 < 3000ms
□ 延迟数据可导出查看
```

---

## 六、修复优先级和时间安排

### 优先级（从高到低）
```
1. W3-07 Qwen SSE 流式（影响体感最大）
2. W3-03 阿里云 ASR 认证（影响识别精度）
3. W3-08 剪贴板保护（影响用户体验）
```

### 建议时间安排
```
D6（1天）: W3-07 Qwen SSE 流式
          - 修改 PolishService 为真正流式
          - Pipeline 适配逐字注入
          
D7（半天）: W3-03 阿里云 ASR
          - curl 隔离测试认证
          - 修复 DashScopeASRClient
          
D7（半天）: W3-08 剪贴板保护
          - 修改 TextInjector
          - 保存→注入→还原流程
          
D8（1天）: 延迟测试 + 回归测试
          - 测量 10 次平均延迟
          - 验证所有场景
```

---

## 七、验收检查清单

### W3-07 流式验收
- [ ] Qwen 请求参数包含 `"stream": true`
- [ ] 使用 URLSession dataTask 接收 SSE 流
- [ ] 逐行解析 `data: {...}` 格式
- [ ] 每收到一个 token 立即 yield
- [ ] Pipeline 逐字注入到前台
- [ ] 用户可感知文字逐字出现

### W3-03 ASR 验收
- [ ] curl 测试返回正确结果
- [ ] DashScopeASRClient 返回非 nil
- [ ] 网络正常时使用云端 ASR
- [ ] 断网时降级到 WhisperKit

### W3-08 剪贴板验收
- [ ] 保存用户原剪贴板
- [ ] 润色文字成功注入
- [ ] 100ms 内还原剪贴板
- [ ] 5 个测试场景通过

### 延迟验收
- [ ] 10 次平均延迟 < 1500ms
- [ ] 单次最大延迟 < 3000ms

---

## 八、给 Cursor 的汇总指令

```
Week 3 风险点修复（按优先级执行）：

【最高优先】W3-07 Qwen 流式
PolishService 必须使用 Qwen 的流式 API（stream: true），
用 URLSession 的 dataTask + 逐行解析 SSE 响应，
每收到一个 token 立即回调，不等全部完成。

【其次】W3-03 阿里云 ASR  
先隔离测试：用 curl 确认 Token 和请求格式正确，
再接入 Swift。认证问题是主因，先解决认证。

【最后】W3-08 剪贴板保护
接受剪贴板方案，但做好保护：
保存用户剪贴板 → 注入润色文字 → 100ms 后还原。

延迟测试等三个问题修完后再测。
```

---

**文档结束**
**等待 Cursor 修复后 Kimi 验收**
