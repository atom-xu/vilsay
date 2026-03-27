# 热键松开无响应问题 - 调试报告

## 🔍 问题描述

**症状**：
- 按下右 Option 键可以开始录音 ✅
- 松开右 Option 键后录音无法停止 ❌
- 日志中看到按下事件，但看不到松开事件

**关键日志**：
```
右Option键事件 - keyCode: 61, pressed: true, currentLogicalDown: false
✅ 触发边缘事件 - pressed: true, triggerMode: push
🔹 onHotkeyPushDown 被调用
   → 启动延迟任务（0.150000秒后开始录音）
✅ 录音启动成功

// ❌ 这里应该有松开事件，但没有出现
```

---

## 🛠️ 已添加的调试功能

### 1. **HotkeyManager.swift - 增强日志**

#### EventTap 回调增强
```swift
private static let eventTapCallback: CGEventTapCallBack = { proxy, type, event, userInfo in
    // 检测 EventTap 被禁用的情况
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        HotkeyManager.log.warning("🔴 EventTap 被禁用: ...")
        // 自动重新启用
        CGEvent.tapEnable(tap: tap, enable: true)
    }
    
    // 记录所有事件
    let eventType = type.rawValue
    let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
    HotkeyManager.log.debug("EventTap 收到事件 - type: \(eventType), keyCode: \(keyCode)")
    
    // ...
}
```

#### 路由函数增强
```swift
private static func route(type: CGEventType, event: CGEvent) {
    let bindingMode = AppConfig.hotkeyBindingMode
    log.debug("route() - type: \(type.rawValue), bindingMode: \(bindingMode.rawValue)")
    
    // 详细记录每个步骤
    // ...
}
```

#### 右 Option 处理函数增强
```swift
private static func handleRightOptionFlagsChanged(_ event: CGEvent) {
    // 检测左 Option 键冲突
    if keyCode == 0x3A {
        log.info("⚠️ 检测到左 Option 键变化")
    }
    
    // 检测其他修饰键
    let hasCommand = event.flags.contains(.maskCommand)
    let hasControl = event.flags.contains(.maskControl)
    let hasShift = event.flags.contains(.maskShift)
    
    // 记录完整的 flags 状态
    log.info("右Option键事件 - keyCode: \(keyCode), pressed: \(pressed), rawFlags: \(String(format: "0x%llx", rawFlags))")
    
    // 检测状态变化
    if pressed == rightOptionLogicalDown {
        log.warning("⚠️ 状态未变化，跳过")
        return
    }
    
    // ...
}
```

---

## 🔬 可能的原因分析

### 原因 1：EventTap 被系统禁用
**症状**：
- 录音启动后，系统可能因为超时或用户输入禁用了 EventTap
- 松开键的事件无法被捕获

**检测方法**：
- 查看日志中是否有 `🔴 EventTap 被禁用` 的警告
- 如果有，说明系统临时禁用了事件监听

**现状**：
- ✅ 已添加自动重新启用功能
- ✅ 已添加日志记录

### 原因 2：修饰键状态异常
**症状**：
- 松开右 Option 时，`maskAlternate` 标志仍然为 true
- 可能是因为左 Option 同时被按下，或者系统键盘状态异常

**检测方法**：
- 查看 `rawFlags` 的值
- 检查是否有其他修饰键被同时按下

**现状**：
- ✅ 已添加 rawFlags 日志
- ✅ 已添加其他修饰键检测
- ✅ 已添加左 Option 键冲突检测

### 原因 3：CGEvent keyCode 问题
**症状**：
- 松开时的 keyCode 可能不是 61 (0x3D)
- 导致事件被忽略

**检测方法**：
- 查看所有 `flagsChanged` 事件的 keyCode
- 确认松开时是否触发了其他 keyCode

**现状**：
- ✅ 已添加所有 keyCode 的调试日志
- ✅ 会记录非 61 的 flagsChanged 事件

### 原因 4：音频录制阻塞主线程
**症状**：
- AudioRecorder 的操作阻塞了主线程
- 导致 EventTap 回调无法及时处理

**检测方法**：
- 查看 `EventTap 收到事件` 的日志
- 如果有松开事件但没有 `右Option键事件`，说明被阻塞

**现状**：
- ✅ EventTap 使用 DispatchQueue.main.async 避免阻塞
- ⚠️ 但如果主线程被其他操作占用，仍可能延迟

### 原因 5：macOS 系统 Bug
**症状**：
- 某些 macOS 版本的 CGEvent API 有 bug
- 特定硬件（如外接键盘）可能有问题

**检测方法**：
- 测试内置键盘 vs 外接键盘
- 测试不同的 macOS 版本

---

## 🧪 调试步骤

### 步骤 1：运行增强日志版本
1. 编译并运行新版本
2. 按下并松开右 Option 键
3. 收集完整日志

**期望看到的日志**：
```
EventTap 收到事件 - type: 12, keyCode: 61  // 按下
route() - type: 12, bindingMode: builtinRightOption
右Option键事件 - keyCode: 61, pressed: true, currentLogicalDown: false, rawFlags: 0xXXXX
✅ 触发边缘事件 - pressed: true
🔹 onHotkeyPushDown 被调用

// ... 录音开始 ...

EventTap 收到事件 - type: 12, keyCode: 61  // 松开 ❓
route() - type: 12, bindingMode: builtinRightOption
右Option键事件 - keyCode: 61, pressed: false, currentLogicalDown: true, rawFlags: 0xXXXX
✅ 触发边缘事件 - pressed: false
🔹 onHotkeyPushUp 被调用
```

### 步骤 2：检查 EventTap 状态
查看日志中是否有：
- `🔴 EventTap 被禁用`
- `✅ EventTap 已重新启用`

如果有，说明问题在于系统禁用了事件监听。

### 步骤 3：检查修饰键状态
对比按下和松开时的 `rawFlags` 值：
- 按下时应该包含 `maskAlternate` 位
- 松开时应该不包含 `maskAlternate` 位

参考值：
```
maskAlternate = 0x80000 (524288)
```

### 步骤 4：测试硬件
1. 使用内置键盘测试
2. 使用外接键盘测试
3. 比较结果

### 步骤 5：测试其他修饰键
尝试使用 FN/🌐 模式：
1. 在设置中切换到 FN/🌐
2. 测试是否有同样的问题
3. 对比日志

---

## 🔧 临时解决方案

### 方案 1：ESC 键取消（已实现）
用户可以按 ESC 键手动停止录音
- ✅ 已在 HotkeyManager 中实现
- ✅ 全局生效

### 方案 2：最大录音时长（已实现）
录音会在 300 秒（5 分钟）后自动停止
- ✅ 已在 Pipeline 中实现
- ⚠️ 但 5 分钟太长，用户体验差

### 方案 3：添加菜单栏停止按钮
在录音时，菜单栏显示"停止录音"按钮
- ⚠️ 需要实现

### 方案 4：缩短最大录音时长
将 `maxPushRecordingSeconds` 从 300 秒改为更短的时间（如 60 秒）
- ✅ 简单有效
- ⚠️ 但治标不治本

---

## 💡 建议的修复方案

### 短期方案：双保险机制

#### 1. 缩短超时时间
```swift
// Constants.swift
static let maxPushRecordingSeconds: TimeInterval = 60  // 从 300 改为 60
```

#### 2. 添加看门狗定时器
每 5 秒检查一次键盘状态：
```swift
// 在 Pipeline 中添加
private var watchdogTask: Task<Void, Never>?

private func startWatchdog() {
    watchdogTask?.cancel()
    watchdogTask = Task { @MainActor [weak self] in
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(5))
            guard let self, self.sessionActive else { break }
            
            // 检查 isPushPressed 状态
            if !AppState.shared.isPushPressed && AppState.shared.triggerMode == .push {
                Self.log.warning("⚠️ 检测到按键已松开但录音未停止，强制停止")
                await self.stopRecording()
                break
            }
        }
    }
}
```

### 中期方案：改进事件捕获

#### 1. 使用 NSEvent 监听作为备份
```swift
// 在 HotkeyManager 中添加
private static var optionKeyMonitor: Any?

static func installBackupMonitor() {
    optionKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { event in
        // 备份的事件监听
        return event
    }
}
```

#### 2. 使用轮询检测键盘状态
```swift
// 定期检查 CGEventSource 的修饰键状态
let source = CGEventSource(stateID: .combinedSessionState)
let flags = CGEventSource.flagsState(source)
let optionPressed = flags.contains(.maskAlternate)
```

### 长期方案：切换到 Toggle 模式

考虑将 Toggle 模式设为默认：
- ✅ 不依赖于松开事件的检测
- ✅ 更可靠
- ⚠️ 但用户习惯可能需要调整

---

## 📊 下一步行动

### 立即执行
1. ✅ 运行增强日志版本
2. ✅ 收集完整的按下-松开日志
3. 📋 分析 EventTap 是否被禁用
4. 📋 分析 rawFlags 的变化

### 如果 EventTap 被禁用
- 实现自动恢复机制（已完成）
- 添加用户提示

### 如果 rawFlags 异常
- 检查是否有左 Option 冲突
- 检查其他修饰键影响
- 考虑使用 keyCode 而不是 flags 检测

### 如果都正常但仍无松开事件
- 实现看门狗定时器
- 添加备份的键盘监听
- 缩短超时时间

---

## 🔗 相关代码位置

- `HotkeyManager.swift:131-162` - handleRightOptionFlagsChanged
- `HotkeyManager.swift:94-107` - eventTapCallback
- `HotkeyManager.swift:114-130` - route
- `Pipeline.swift:199-221` - onHotkeyPushUp
- `Pipeline.swift:83-95` - scheduleMaxRecordingDurationIfNeeded

---

**创建时间**: 2026-03-23
**状态**: 🔍 调试中
**优先级**: 🔴 高
