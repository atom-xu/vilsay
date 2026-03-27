# macOS 键盘热键选择完整分析

## 🎯 目标
找到一个**不会与系统功能冲突**、**容易按到**、**可以完全拦截**的键位。

---

## 📊 所有可能的键位分析

### ❌ 已排除的键位（有问题）

| 键位 | 问题 | 严重程度 |
|------|------|---------|
| **Option（左/右）** | NSEvent 无法区分左右 | 🔴 高 |
| **Siri 键** | 长按会触发系统 Siri | 🔴 高 |
| **播放/暂停** | 与媒体控制冲突 | 🔴 高 |
| **Command** | 与所有快捷键冲突 | 🔴 极高 |
| **Control** | 与终端等工具冲突 | 🟠 中 |
| **Shift** | 打字时会误触 | 🟠 中 |

---

## ✅ 可用的键位方案

### 方案 1：**Fn 键 / 🌐 Globe 键**（最推荐）

**keyCode**: `0x3F` (63)  
**检测方式**: `NSEvent.ModifierFlags.function`

#### 优点：
- ✅ **位置完美**（键盘左下角，大拇指可按）
- ✅ **很少冲突**（主要用于切换功能键）
- ✅ **可以完全拦截**（NSEvent 可检测）
- ✅ **新款 MacBook 有独立 🌐 Globe 键**

#### 缺点：
- ⚠️ 旧款 MacBook 可能需要配合 F1-F12 使用
- ⚠️ 用户需要在系统设置中调整功能键行为

#### 系统设置要求：
```
系统设置 → 键盘 → 键盘快捷键 → 功能键
✅ 勾选「将 F1、F2 等键用作标准功能键」
```

---

### 方案 2：**Caps Lock 键**（最稳定）

**keyCode**: `0x39` (57)  
**检测方式**: `NSEvent.ModifierFlags.capsLock`

#### 优点：
- ✅ **100% 可拦截**（系统不保护）
- ✅ **位置方便**（小拇指可按）
- ✅ **几乎不用**（99% 的人不用大写锁定）
- ✅ **可以用 Karabiner-Elements 重新映射**

#### 缺点：
- ⚠️ Caps Lock 是切换状态，不是按住状态（需要特殊处理）

#### 解决方案：
```swift
// 使用 Caps Lock 的「按下」和「松开」来模拟 Push 模式
private static var capsLockWasOn = false

let isCapsLockOn = event.modifierFlags.contains(.capsLock)

if isCapsLockOn && !capsLockWasOn {
    // Caps Lock 开启 → 开始录音
    onHotkeyDown()
} else if !isCapsLockOn && capsLockWasOn {
    // Caps Lock 关闭 → 结束录音
    onHotkeyUp()
}

capsLockWasOn = isCapsLockOn
```

---

### 方案 3：**右 Command 键**（备选）

**keyCode**: `0x36` (54)  
**检测方式**: 检查 keyCode + `.command` 修饰符

#### 优点：
- ✅ 位置方便（空格右侧）
- ✅ 很少单独使用

#### 缺点：
- ⚠️ 与快捷键可能冲突（如 Cmd+C、Cmd+V）
- ⚠️ 需要在 keyDown 时检查是否有其他键组合

#### 解决方案：
```swift
// 只在「单独按下右 Command」时触发
if keyCode == 0x36 && event.modifierFlags == .command {
    // 单独按右 Command
}
```

---

### 方案 4：**Escape 键**（不推荐）

**keyCode**: `0x35` (53)  
**检测方式**: 直接检测 keyCode

#### 优点：
- ✅ 位置明显（左上角）
- ✅ 可以完全拦截

#### 缺点：
- ❌ **与「取消录音」功能冲突**（你已经用 ESC 取消了）
- ❌ 很多应用用 ESC 退出全屏

---

## 🏆 最终推荐方案

### **优先级排序**：

1. **🥇 Fn / 🌐 Globe 键**（最推荐）
   - 位置、功能、体验都最好
   - 适合 2021 年后的新款 MacBook

2. **🥈 Caps Lock 键**（最稳定）
   - 100% 可靠，无冲突
   - 需要特殊处理切换状态

3. **🥉 右 Command 键**（备选）
   - 位置方便
   - 需要处理组合键

---

## 💡 我的建议（综合方案）

### **方案 A：优先 Fn/Globe，回退 Caps Lock**

```swift
enum HotkeyMode {
    case fnGlobe    // 优先使用
    case capsLock   // 备选
}

// 在应用启动时自动检测
static func install() {
    let hasGlobeKey = GlobeKeyHardwareCapabilities.isGlobeModifierLikelyAvailable
    
    if hasGlobeKey {
        // 使用 Fn/Globe 键
        installFnListener()
    } else {
        // 降级到 Caps Lock
        installCapsLockListener()
    }
}
```

### **方案 B：让用户选择**

在设置界面提供选项：
```
热键选择：
○ Fn / 🌐 Globe 键（推荐）
○ Caps Lock 键（稳定）
○ 右 Command 键（备选）
```

---

## 🎯 立即可实施的最佳方案

基于你的需求（要么 Fn/Globe，要么 Siri），我推荐：

### **使用 Fn/Globe 键 + 提供「禁用 Siri」选项**

1. **默认使用 Fn/Globe 键**（keyCode 0x3F）
2. **在设置中提供「使用 Siri 键」选项**
3. **如果用户选择 Siri 键**，引导禁用系统 Siri

---

## 📝 技术实现细节

### Fn/Globe 键检测（NSEvent）

```swift
// flagsChanged 事件
let isFnPressed = event.modifierFlags.contains(.function)

// 边缘触发
if isFnPressed != lastFnState {
    lastFnState = isFnPressed
    
    if isFnPressed {
        onHotkeyDown()
    } else {
        onHotkeyUp()
    }
}
```

### Caps Lock 键检测（特殊处理）

```swift
// Caps Lock 是切换状态，需要模拟按住
private static var capsLockToggleTime: Date?
private static var isRecording = false

let isCapsLockOn = event.modifierFlags.contains(.capsLock)

if isCapsLockOn && !isRecording {
    // 开启 → 开始录音
    isRecording = true
    capsLockToggleTime = Date()
    onHotkeyDown()
    
} else if !isCapsLockOn && isRecording {
    // 关闭 → 结束录音
    isRecording = false
    onHotkeyUp()
}
```

---

## 🚀 我现在应该做什么？

给我一个明确的选择：

### 选项 1：使用 **Fn/Globe 键**
- 我立即实现 Fn/Globe 键检测
- 适合新款 MacBook

### 选项 2：使用 **Caps Lock 键**
- 我实现 Caps Lock 状态检测
- 最稳定，100% 可靠

### 选项 3：**双方案**（Fn/Globe + Caps Lock 备选）
- 自动检测硬件
- 新 MacBook 用 Fn，旧设备用 Caps Lock

### 选项 4：使用 **Siri 键 + 禁用系统 Siri**
- 需要用户手动禁用 Siri
- 我已经实现了 `SiriManager`

---

你选哪个？我立即实现！🎯
