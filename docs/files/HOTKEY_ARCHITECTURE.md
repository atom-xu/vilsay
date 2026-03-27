# 热键系统架构设计文档

## 🎯 核心原理

```
Fn 单独使用 = 录音触发器
Fn + 任何其他键 = 系统快捷键 → 立即中断录音
```

**关键点**：
- 无需时间判断
- 无需音频检测  
- 实时按键检测
- 立即响应中断

---

## 📐 按键检测逻辑

```
EventTap 监听所有键盘事件
    ↓
检测到事件
    ↓
是 Fn 键？
    ├─ 是 → 更新 fnIsPressed 状态
    │       ├─ pressed = true → 准备录音
    │       └─ pressed = false → 停止录音
    │
    └─ 否 → 是其他键？
            └─ fnIsPressed == true？
                └─ 是 → 🛑 Fn组合键！立即中断录音！
```

---

## 🔧 实现细节

### 状态管理

```swift
// HotkeyManager.swift
private static var fnIsPressed = false  // Fn 键当前状态
```

### 事件检测

```swift
private static let eventTapCallback: CGEventTapCallBack = { proxy, type, event, userInfo in
    let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
    
    // 1. 追踪 Fn 键状态
    if keyCode == keyCodeFunction {
        if type == .flagsChanged {
            fnIsPressed = (event.flags.rawValue & functionModifierBits) != 0
        }
    }
    
    // 2. 检测 Fn + 键盘键 (keyDown 事件)
    if type == .keyDown && fnIsPressed && keyCode != keyCodeFunction {
        log.info("🛑 Fn + 键(\(keyCode)) → 中断录音")
        Task { @MainActor in
            if Pipeline.shared.sessionActive {
                await Pipeline.shared.cancel()
            }
        }
    }
    
    // 3. 检测 Fn + 功能键 (flagsChanged 事件)
    if type == .flagsChanged && fnIsPressed && keyCode != keyCodeFunction {
        log.info("🛑 Fn + 功能键(\(keyCode)) → 中断录音")
        Task { @MainActor in
            if Pipeline.shared.sessionActive {
                await Pipeline.shared.cancel()
            }
        }
    }
    
    return Unmanaged.passUnretained(event)
}
```

---

## 🛡️ 多层保护机制

```
第一层：实时按键检测
  ↓ (如果按键事件丢失)
第二层：看门狗 (2秒检查)
  ↓ (如果看门狗失败)
第三层：最大时长 (60秒)
  ↓ (如果以上都失败)
第四层：ESC 应急
  ↓ (最后手段)
第五层：菜单栏手动停止
```

---

## 📊 场景处理

### 场景 1：Fn + F5 (快速组合，0.05秒)
```
0s:    Fn 按下 → fnIsPressed = true
0.05s: F5 按下 → 检测到组合键 → 不启动录音
0.1s:  系统处理亮度调节
```

### 场景 2：Fn 长按 3 秒 + F11
```
0s:  Fn 按下 → 开始录音
3s:  F11 按下 → 检测到组合键 → 立即中断录音
3s:  系统处理音量调节
```

### 场景 3：Fn 单独使用
```
0s:  Fn 按下 → 开始录音
5s:  录音中...
10s: Fn 松开 → 停止录音
```

### 场景 4：异常情况（松开事件丢失）
```
0s:  Fn 按下 → 开始录音
2s:  用户松开 Fn（事件丢失）
4s:  看门狗检测到 → 强制停止
```

---

## 🏗️ 模块设计

### 模块 1：HotkeyHealthChecker (热键健康检查器)

**职责**：启动时检测热键系统可用性

```swift
@MainActor
final class HotkeyHealthChecker {
    enum HealthStatus {
        case healthy      // 完全正常
        case degraded    // 部分功能
        case unavailable // 不可用
    }
    
    struct HealthReport {
        let status: HealthStatus
        let canUseEventTap: Bool
        let canUseFnKey: Bool
        let canUseRightOption: Bool
        let issues: [String]
        let suggestions: [String]
    }
    
    func performStartupCheck() async -> HealthReport
}
```

**检查项**：
1. EventTap 是否创建成功
2. 辅助功能权限是否授予
3. Fn 键硬件是否支持
4. 右 Option 键是否可用

### 模块 2：看门狗 (Watchdog)

**已在 Pipeline.swift 实现**

**职责**：2 秒检查一次，防止按键事件丢失

```swift
// 检查项
1. isPushPressed 状态
2. sessionActive 状态
3. triggerMode 模式

// 触发条件
triggerMode == .push && !isPushPressed && sessionActive == true
```

### 模块 3：热键优先级管理

**优先级**：
```
1. Fn/🌐 (主热键)
2. 右 Option (备选热键)
3. 菜单栏 (降级方案)
```

**切换逻辑**：
```swift
if !GlobeKeyHardwareCapabilities.isGlobeModifierLikelyAvailable {
    // 自动使用右 Option
    AppState.shared.hotkeyBindingMode = .builtinRightOption
}
```

---

## 🧪 测试场景

### 测试 1：Fn + 功能键组合
```
输入：Fn + F5
预期：不录音，系统调节亮度
验证：日志中有 "🛑 Fn + 功能键(96)"
```

### 测试 2：录音中使用组合键
```
输入：
1. 按住 Fn 2 秒
2. 按 F11
预期：立即中断录音
验证：录音时长 < 3 秒
```

### 测试 3：看门狗触发
```
输入：
1. 按住 Fn 开始录音
2. 手动杀掉键盘事件
预期：2-4 秒内自动停止
验证：日志中有 "🐕 看门狗检测到"
```

---

## ⚙️ 配置选项

```swift
struct HotkeyConfiguration {
    let primaryKey: HotkeyBindingMode = .fnGlobe
    let fallbackKey: HotkeyBindingMode = .builtinRightOption
    let allowSystemCombo: Bool = true          // 允许系统组合键
    let watchdogIntervalSec: Int = 2           // 看门狗检查间隔
    let maxRecordingDurationSec: Int = 60      // 最大录音时长
}
```

---

## 📝 开发检查清单

### 必须实现
- [ ] Fn + 其他键实时检测
- [ ] 立即中断录音逻辑
- [ ] 启动时健康检查
- [ ] 降级策略 (Fn → 右Option → 菜单栏)

### 必须测试
- [ ] Fn + F1-F12 所有功能键
- [ ] Fn + 字母键 (如 Fn + Space)
- [ ] 录音中触发组合键
- [ ] 看门狗保护
- [ ] 启动自检通过

### 性能要求
- [ ] 按键响应 < 50ms
- [ ] 中断延迟 < 100ms
- [ ] 不阻塞主线程
- [ ] 内存占用 < 5MB

---

## 🚨 常见问题

### Q1: 为什么不用时间判断？
**A**: 时间判断无法处理"用户按住 Fn 很久才决定按其他键"的情况，且增加复杂度。

### Q2: 如果用户只是轻触 Fn 怎么办？
**A**: 有 150ms 的最短按住时间保护（Constants.minHoldDurationSeconds）

### Q3: 看门狗为什么还需要？
**A**: 作为备份保护，防止按键事件在系统层面丢失。

---

## 📊 性能指标

| 指标 | 目标值 | 实测值 |
|------|--------|--------|
| 按键检测延迟 | < 50ms | TBD |
| 中断响应时间 | < 100ms | TBD |
| 看门狗触发率 | < 1% | TBD |
| EventTap CPU | < 0.5% | TBD |

---

## 触发方式（TriggerMode）与主热键（2026-03 落地）

与早期「文档里不写时间判」的设想不同，**当前产品**在 **物理 Fn（XPC `HotkeyMonitor` → `HotkeyManager`）** 上采用 **用户可选的两种互斥模式**（与 `AppState.triggerMode` 一致，悬浮球同步）：

| 模式 | 主热键行为 |
|------|------------|
| **单击** | 仅识别短按（松开时间 &lt; `Constants.fnTapVersusHoldMs`，约 250ms）：一下开始录音、再一下结束；按住过久再松开 → 不触发 |
| **长按** | 仅识别按住 ≥ 分界后进入 Push：定时器触发 `fnHoldPushDown`，松手 `fnHoldPushUp`；短按快松 → 不触发 |

判别逻辑见 `Entry/FnHotkeyDiscrimination.swift`；**不再**在同一模式下混用「短按=切换 + 长按=按住说」的自动二选一。

上文「无需时间判断」仍适用于 **Fn + 其他键** 的中断语义；**主录音触发** 与 **组合键中断** 是两条独立设计。

---

**版本**: 2.1  
**更新**: 2026-03-25  
**状态**: 设计完成 + 与实现对齐（主热键模式）
