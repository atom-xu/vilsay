# 热键识别问题诊断与修复

## ❌ 之前存在的问题

### 问题 1：双层监听冲突（已修复）

**症状**：
- 按一次右 Option，触发两次 `onHotkeyPushDown()`
- 日志显示重复的事件处理

**原因**：
```swift
// 旧代码：同时运行两个监听器
static func install() {
    installCGEventTap()        // 监听器 1
    installNSEventFallback()   // 监听器 2 ❌ 同时运行！
}

// 结果：同一个按键事件被处理两次
// CGEventTap 触发 → applyBindingEdge(pressed: true)
// NSEvent 也触发 → applyBindingEdge(pressed: true)  ❌ 重复！
```

**修复**：
```swift
// 新代码：优先使用 CGEventTap，失败时才启用 NSEvent
static func install() {
    let success = installCGEventTap()
    if !success {
        // 只有 CGEventTap 失败时才启用备选
        installNSEventFallback()
    }
}
```

---

### 问题 2：NSEvent 无法区分左右 Option（已标注）

**症状**：
- 设置了「右 Option」，但左 Option 也会触发
- 无法准确控制使用哪个 Option 键

**原因**：
```swift
// NSEvent 的限制
let isOptionPressed = modifierFlags.contains(.option)
// ⚠️ 无论是左 Option(0x3A) 还是右 Option(0x3D)，都返回 true

// 而 CGEventTap 可以区分
let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
if keyCode == 0x3D {  // ✅ 只有右 Option
    // ...
}
```

**解决方案**：
- 优先使用 CGEventTap（可以区分左右）
- NSEvent 仅作为备选（并标注警告）

```swift
log.info("✅ NSEvent 备选监听已安装（⚠️ 无法区分左右 Option）")
```

---

### 问题 3：状态管理混乱（已修复）

**症状**：
- 某些情况下热键按下后无法松开
- 状态与实际按键不同步

**原因**：
```swift
// 两个监听器共享同一个状态变量
private static var rightOptionLogicalDown = false

// CGEventTap 设置
rightOptionLogicalDown = true

// NSEvent 检查（已经是 true，跳过）
if isOptionPressed && !rightOptionLogicalDown {
    // ❌ 不会执行
}
```

**修复**：
- 只运行一个监听器，避免状态冲突
- 每个监听器独立检测边缘变化

---

## ✅ 当前的解决方案

### 架构：分层降级策略

```
┌─────────────────────────────────────┐
│     HotkeyManager.install()         │
├─────────────────────────────────────┤
│                                     │
│  1. 尝试 CGEventTap（首选）          │
│     ✅ 可以区分左右 Option           │
│     ✅ 系统级监听（优先级高）         │
│     ✅ 可以拦截其他应用的快捷键       │
│     │                               │
│     └─ 成功 → 结束                   │
│     │                               │
│     └─ 失败 ↓                        │
│                                     │
│  2. 启用 NSEvent（备选）             │
│     ⚠️ 无法区分左右 Option           │
│     ✅ 不需要辅助功能权限（某些情况）  │
│     ✅ 比轮询更高效                  │
│                                     │
└─────────────────────────────────────┘
```

### 代码实现

```swift
static func install() {
    teardown()
    
    // 优先使用 CGEventTap
    let success = installCGEventTap()
    if !success {
        log.warning("⚠️ CGEventTap 失败，启用 NSEvent 备选方案")
        installNSEventFallback()
    }
    
    lastTapInstallTime = Date()
}
```

### 运行时行为

#### 场景 1：正常情况（有辅助功能权限）
```
[Hotkey] ✅ CGEventTap 已安装（主方案）
[Hotkey] 右Option键事件 - keyCode: 61, pressed: true
[Hotkey] → 调用 onHotkeyPushDown()
```

#### 场景 2：无辅助功能权限
```
[Hotkey] ❌ CGEventTap 创建失败（请授予辅助功能权限）
[Hotkey] ⚠️ CGEventTap 失败，启用 NSEvent 备选方案
[Hotkey] ✅ NSEvent 备选监听已安装（⚠️ 无法区分左右 Option）
[Hotkey] 🟢 NSEvent 检测到 Option 按下 （⚠️ 左右不区分）
[Hotkey] → 调用 onHotkeyPushDown()
```

#### 场景 3：运行时恢复
```
[Hotkey] ⚠️ EventTap 被禁用，尝试恢复
[Hotkey] 🔄 尝试重新安装 EventTap (1/3)
[Hotkey] ✅ CGEventTap 已安装（主方案）
```

---

## 🔍 如何验证修复

### 1. 检查启动日志

**成功**：
```
[Hotkey] ✅ CGEventTap 已安装（主方案）
[HotkeyHealth] 🔍 启动热键健康监控
```

**降级到备选**：
```
[Hotkey] ❌ CGEventTap 创建失败
[Hotkey] ⚠️ CGEventTap 失败，启用 NSEvent 备选方案
[Hotkey] ✅ NSEvent 备选监听已安装（⚠️ 无法区分左右 Option）
```

### 2. 测试热键响应

**按下右 Option**：
```
// CGEventTap 模式（精确）
[Hotkey] 右Option键事件 - keyCode: 61, pressed: true
[Hotkey] → 调用 onHotkeyPushDown()
[Pipeline] 🔹 onHotkeyPushDown 被调用
[Pipeline] → 启动延迟任务（0.15秒后开始录音）

// NSEvent 模式（备选）
[Hotkey] 🟢 NSEvent 检测到 Option 按下 （⚠️ 左右不区分）
[Hotkey] → 调用 onHotkeyPushDown()
[Pipeline] 🔹 onHotkeyPushDown 被调用
```

**松开右 Option**：
```
// CGEventTap 模式
[Hotkey] 右Option键事件 - keyCode: 61, pressed: false
[Hotkey] → 调用 onHotkeyPushUp()
[Pipeline] 🔹 onHotkeyPushUp 被调用

// NSEvent 模式
[Hotkey] 🔴 NSEvent 检测到 Option 松开 （⚠️ 左右不区分）
[Hotkey] → 调用 onHotkeyPushUp()
[Pipeline] 🔹 onHotkeyPushUp 被调用
```

### 3. 验证无重复触发

**正确的日志**（每次按键只触发一次）：
```
[Hotkey] 右Option键事件 - keyCode: 61, pressed: true
[Hotkey] → 调用 onHotkeyPushDown()
[Pipeline] 🔹 onHotkeyPushDown 被调用
[Pipeline] → 启动延迟任务（0.15秒后开始录音）
```

**错误的日志**（之前的重复触发问题）：
```
❌ 已修复
[Hotkey] 右Option键事件 - keyCode: 61, pressed: true
[Hotkey] → 调用 onHotkeyPushDown()
[Hotkey] 🟢 NSEvent 检测到 Option 按下
[Hotkey] → 调用 onHotkeyPushDown()  ❌ 重复！
```

---

## 📊 CGEventTap vs NSEvent 对比

| 特性 | CGEventTap | NSEvent |
|------|-----------|---------|
| **区分左右 Option** | ✅ 可以（keyCode: 0x3D） | ❌ 无法 |
| **需要辅助功能权限** | ✅ 必须 | ⚠️ 某些情况需要 |
| **监听优先级** | 🔥 系统级（高） | 📱 应用级（低） |
| **可拦截其他应用** | ✅ 可以 | ❌ 不可以 |
| **防抖控制** | 需要手动实现（75ms） | 系统自动处理 |
| **可靠性** | ⚠️ 可能被禁用 | ✅ 较稳定 |
| **性能** | ✅ 高效 | ✅ 高效 |

**结论**：CGEventTap 是首选，NSEvent 是保底方案。

---

## 🎯 总结

### ✅ 已解决的问题

1. **双层监听冲突** - 现在只运行一个监听器
2. **状态管理混乱** - 避免竞态条件
3. **重复触发** - 每次按键只触发一次

### ⚠️ 已知限制

1. **NSEvent 无法区分左右 Option** - 但作为备选可接受
2. **需要辅助功能权限** - CGEventTap 的系统要求

### 🚀 未来改进方向

如果需要更高的可靠性，可以考虑：
1. **独立进程方案**（VoiceInk 风格）- 热键监听独立于主进程
2. **键盘扩展**（Keyboard Extension）- 系统级键盘监听
3. **驱动程序**（Kernel Extension）- 最高优先级（但需要签名）

**当前方案已足够稳定，建议先运行并收集用户反馈。**
