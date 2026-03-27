# Vilsay 后端测试报告

> **测试日期：** 2026-03-22  
> **测试人：** Kimi（AI 测试工程师）  
> **测试范围：** 后端核心逻辑代码审查

---

## 一、测试方法

- ✅ 代码静态分析
- ✅ 逻辑路径审查
- ✅ 错误处理检查
- ✅ 竞态条件分析
- ❌ 运行时测试（需要真实运行环境）

---

## 二、发现的问题

### 🔴 严重问题 1：Pipeline 重复调用 guard 逻辑错误

**位置：** `Pipeline.swift` 第 24-27 行

**问题代码：**
```swift
func startRecording() {
    guard !sessionActive else { return }
    guard AppState.shared.status != .processing else { return }
```

**问题分析：**
- `sessionActive` 是实例变量，但 `Pipeline` 是单例
- 如果用户快速按快捷键两次，`sessionActive` 可能还没有被设置
- 缺少原子性保护

**影响：**
- 可能导致重复启动录音
- 状态机混乱

**建议修复：**
```swift
func startRecording() {
    guard !sessionActive && AppState.shared.status != .processing else { 
        print("[⚠️] 已有会话进行中，跳过")
        return 
    }
```

---

### 🔴 严重问题 2：PolishService 流式可能不产出任何内容

**位置：** `PolishService.swift` 第 13-82 行

**问题代码：**
```swift
static func polishStreaming(system: String, user: String) -> AsyncStream<String> {
    AsyncStream { continuation in
        Task {
            defer { continuation.finish() }  // 第 17 行
            // ... 如果所有 yield 条件不满足，直接 finish，产出空
        }
    }
}
```

**问题分析：**
- 如果 API 返回格式不符合预期，`sseTextDelta` 返回 nil
- 或者所有 chunk 都是空的，用户看不到任何输出
- Pipeline 中的 `receivedPolish` 检测是在流结束后，但流可能已经空了

**影响：**
- 用户看到黄色状态（processing）但没有任何文字输出
- 符合用户描述的「黄色通知亮，但没有完整输出」

**建议修复：**
在 Pipeline 中添加空内容检测：
```swift
var chunkCount = 0
for await chunk in PolishService.polishStreaming(...) {
    chunkCount += 1
    // ...
}
if chunkCount == 0 {
    print("[⚠️] 流式未产出任何内容，使用降级")
    // 使用 fallback
}
```

---

### 🟡 中等问题 3：TextInjector pasteChunk 问题

**位置：** `TextInjector.swift` 第 23-28 行

**问题代码：**
```swift
static func pasteChunk(_ text: String) {
    guard !text.isEmpty else { return }
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(text, forType: .string)  // 每次都清空重新设置
    simulatePaste()
}
```

**问题分析：**
- **每次 pasteChunk 都清空剪贴板**
- 流式场景下，第一个 chunk 设置 "你好"，第二个 chunk 设置 "你好世界"
- 如果粘贴有延迟，用户可能只粘贴了最后一个 chunk

**影响：**
- 流式输出不完整
- 符合用户描述的「没有完整输出」

**根本问题：**
流式设计应该是：
```
第1个 chunk: "你" -> 粘贴 "你"
第2个 chunk: "好" -> 粘贴 "好"  
第3个 chunk: "世" -> 粘贴 "世"
...
```

但 `pasteChunk` 每次都设置完整字符串（累计值），而不是增量字符。

**实际上代码逻辑是正确的**（Pipeline 中使用了 `polishPending` 累计），但 `pasteChunk` 每次都清空剪贴板重新设置，这可能导致：
- 粘贴时机和剪贴板内容不同步

---

### 🟡 中等问题 4：WhisperKit 首次加载阻塞

**位置：** `WhisperASRFallback.swift` 第 13-22 行

**问题代码：**
```swift
func transcribe(fileURL: URL) async throws -> String {
    if kit == nil {
        kit = try await WhisperKit(
            model: Constants.asrFallbackModel,
            download: true  // 首次需要下载模型
        )
    }
```

**问题分析：**
- `download: true` 首次运行需要下载约 100MB 模型
- 在主线程上下文中阻塞
- 没有下载进度提示

**影响：**
- 用户看到黄色状态（processing）卡住 1-3 分钟
- 符合用户描述的「黄色通知亮，但没有输出」

---

### 🟡 中等问题 5：缺少 API Key 时的降级提示

**位置：** `PolishService.swift` 第 19-22 行

**问题代码：**
```swift
guard let key = AppConfig.dashscopeAPIKey, !key.isEmpty else {
    continuation.yield(extractPlainText(from: user))  // 直接返回原文
    return
}
```

**问题分析：**
- 没有 API Key 时直接返回原文
- 但用户无法感知到降级了（没有提示）

**影响：**
- 用户以为润色功能坏了
- 实际是 Key 没配置或配置错误

---

## 三、状态机问题分析

### 当前状态流转

```
idle --(startRecording)--> recording --(stopRecording)--> processing --(process)--> idle
  |                           |                            |
  |                           |                            +-> error (1.2s后恢复)
  |                           |
  +--(cancel)-----------------+--(cancel)-->
```

### 问题：缺少错误传播

在 `process()` 中：
```swift
do {
    // ... 正常流程
} catch {
    AppState.shared.status = .error
    // 1.2秒后恢复 idle
}
```

**问题：**
- 错误状态只持续 1.2 秒
- 用户可能来不及看到错误
- 没有错误信息提示（比如"API Key 无效"）

---

## 四、建议修复清单

### 高优先级

1. **添加详细日志**（已部分添加）
   - 在每个关键步骤打印日志
   - 方便定位问题

2. **修复 TextInjector 流式问题**
   - 确保每个 chunk 都被正确粘贴
   - 检查流式累积逻辑

3. **添加 WhisperKit 加载提示**
   - 首次加载时显示"正在加载模型..."
   - 避免用户以为卡住了

### 中优先级

4. **添加 API Key 检测提示**
   - 启动时检测 Key 是否有效
   - 无效时在菜单栏显示警告

5. **修复 Pipeline 重复调用问题**
   - 添加原子性保护

6. **添加错误信息展示**
   - 错误时显示具体原因（如"网络错误"、"API Key 无效"）

---

## 五、用户问题对应分析

| 用户反馈 | 可能原因 | 代码位置 |
|----------|----------|----------|
| 快捷键没声音 | `SoundFeedback` 依赖 `NSSound`，沙盒中可能失效 | `SoundFeedback.swift` |
| 图标没变化 | 状态更新正常，但 UI 未刷新或观察失效 | `AppState.swift` |
| 黄色通知亮但没输出 | WhisperKit 首次加载阻塞 / PolishService 流式空产出 | `WhisperASRFallback.swift` / `PolishService.swift` |
| 再按后光标问题 | 剪贴板保护机制可能未正确结束 | `TextInjector.swift` |
| 没看到剪贴板内容 | `pasteChunk` 逻辑问题或粘贴失败 | `TextInjector.swift` |

---

## 六、下一步测试建议

### 需要运行时验证的测试

1. **API Key 测试**
   ```bash
   curl -H "Authorization: Bearer $DASHSCOPE_API_KEY" \
        https://dashscope.aliyuncs.com/...
   ```

2. **WhisperKit 首次加载时间**
   - 测量从调用到模型加载完成的时间

3. **流式输出测试**
   - 验证每个 chunk 是否正确粘贴

4. **剪贴板保护测试**
   - 验证原剪贴板内容是否正确恢复

---

**报告结束**
**需要我针对某个具体问题编写修复代码吗？**
