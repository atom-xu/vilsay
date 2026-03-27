# 开发任务：Fn 组合键检测与热键健康检查

> **仓库路径**：`docs/status/HOTKEY_FN_COMBO_DETECTION_TASK.md`（任务/现状类，对齐 `REPO_FILE_LAYOUT`）。  
> 源码根目录：`vilsay/vilsay/`（下文「Core/」等均相对此路径）。

## 📋 任务概述

实现 Fn 组合键实时检测、启动时热键健康自检、多层保护机制。

---

## 📚 必读文档

**请按顺序阅读以下文件：**

1. **`docs/spec/HOTKEY_ARCHITECTURE.md`** — 架构设计文档（核心原理，技术规约）
2. **`vilsay/vilsay/Entry/HotkeyManager.swift`** — 当前热键实现
3. **`vilsay/vilsay/Core/Pipeline.swift`** — 录音流程 + 看门狗
4. **`vilsay/vilsay/App/AppDelegate.swift`** — 应用启动入口
5. **`vilsay/vilsay/Core/PermissionManager.swift`** — 权限管理参考

---

## 📁 文件位置规范

### 新建文件位置
```
vilsay/vilsay/
├── Core/
│   ├── HotkeyHealthChecker.swift  ← 新建（Phase 2）
│   ├── Pipeline.swift             ← 已存在，需修改
│   └── HotkeyManager.swift        ← 在 Entry/，需修改（见下）
├── Entry/
│   └── HotkeyManager.swift
├── UI/
│   └── SettingsRootView.swift     ← 已存在，需修改（Phase 3）
```

（注：原稿写 `Core/HotkeyManager.swift`，以工程实际 **`Entry/HotkeyManager.swift`** 为准。）

### 文档位置
```
docs/spec/HOTKEY_ARCHITECTURE.md              ← 架构（规约）
docs/status/HOTKEY_FN_COMBO_DETECTION_TASK.md  ← 本文档（任务）
docs/HOTKEY_FIX_SUMMARY.md
docs/HOTKEY_RELEASE_DEBUG_REPORT.md
docs/PERMISSIONS_OPTIMIZATION_REPORT.md
```

### 文件头注释规范
```swift
//  文件名.swift
//

import ...
```

---

## 🎯 开发任务清单

### Phase 1: 核心按键检测（优先级：🔴 最高）

**文件**: `Entry/HotkeyManager.swift`

**任务 1.1**: 实现 Fn + 其他键的实时检测

**实现注意**：`Pipeline.sessionActive` 当前为 `private`；落地时请在 `Pipeline` 增加只读 `var isRecordingSessionActive: Bool`，或用 `AppState.shared.status == .recording || .editMode` 判断是否在录。

```swift
// 在 eventTapCallback / route 中维护 Fn 状态并处理组合键
private static var fnIsPressed = false

// 检测 Fn 键状态（flagsChanged 上与现有 handleFunctionFlagsChanged 协同，避免重复逻辑）
if keyCode == keyCodeFunction {
    fnIsPressed = (event.flags.rawValue & functionModifierBits) != 0
}

// 检测 Fn + 其他键（keyDown 事件）
if type == .keyDown && fnIsPressed && keyCode != keyCodeFunction {
    log.info("🛑 检测到 Fn + 键(\(keyCode))，中断录音")
    Task { @MainActor in
        await Pipeline.shared.cancel()
    }
}

// 检测 Fn + 其他修饰/媒体键（flagsChanged，keyCode 非 0x3F）
if type == .flagsChanged && fnIsPressed && keyCode != keyCodeFunction {
    log.info("🛑 检测到 Fn + 功能键(\(keyCode))，中断录音")
    Task { @MainActor in
        await Pipeline.shared.cancel()
    }
}
```

**验收标准**:
- [ ] Fn + F5 不触发录音，系统正常调节亮度
- [ ] 录音中按 Fn + F11，立即中断录音
- [ ] Fn 单独按下，正常触发录音

---

### Phase 2: 启动时热键健康检查（优先级：🟡 中）

**新建文件**: `Core/HotkeyHealthChecker.swift`

**文件头格式**:
```swift
//  HotkeyHealthChecker.swift
//

import Foundation
import os.log

@MainActor
final class HotkeyHealthChecker {
    // ...
}
```

**参考**: `docs/spec/HOTKEY_ARCHITECTURE.md` 中的 "模块 1：热键健康检查器"

**任务 2.1**: 创建健康检查器
```swift
@MainActor
final class HotkeyHealthChecker {
    static let shared = HotkeyHealthChecker()
    
    enum HealthStatus {
        case healthy
        case degraded
        case unavailable
    }
    
    struct HealthReport {
        let status: HealthStatus
        let canUseEventTap: Bool
        let canUseFnKey: Bool
        let canUseRightOption: Bool
        let issues: [String]
        let suggestions: [String]
    }
    
    func performStartupCheck() async -> HealthReport {
        var report = HealthReport(...)
        
        // 1. 检查 EventTap 是否创建成功
        report.canUseEventTap = HotkeyManager.eventTap != nil
        
        // 2. 检查硬件支持
        report.canUseFnKey = GlobeKeyHardwareCapabilities.isGlobeModifierLikelyAvailable
        report.canUseRightOption = true
        
        // 3. 生成问题和建议
        if !report.canUseEventTap {
            report.issues.append("辅助功能权限未授予")
            report.suggestions.append("请在系统设置中授予辅助功能权限")
        }
        
        // 4. 确定状态
        report.status = determineStatus(report)
        
        return report
    }
}
```

**说明**：若 `HotkeyManager.eventTap` 为 `private`，健康检查需通过 `HotkeyManager` 暴露只读查询 API（例如 `static var isEventTapInstalled: Bool`），避免破坏封装。

**任务 2.2**: 在 AppDelegate 中集成
```swift
// AppDelegate.swift

func applicationDidFinishLaunching(_ notification: Notification) {
    // 现有代码...
    
    // ⭐️ 新增：热键健康检查
    Task {
        let report = await HotkeyHealthChecker.shared.performStartupCheck()
        handleHealthReport(report)
    }
}

private func handleHealthReport(_ report: HotkeyHealthChecker.HealthReport) {
    switch report.status {
    case .healthy:
        Self.log.info("✅ 热键系统正常")
        
    case .degraded:
        Self.log.warning("⚠️ 热键系统部分可用: \(report.issues)")
        // 显示提示（可选）
        
    case .unavailable:
        Self.log.error("❌ 热键系统不可用: \(report.issues)")
        // 显示错误提示
    }
}
```

**验收标准**:
- [ ] 应用启动时输出健康检查日志
- [ ] 如果 EventTap 失败，显示友好提示
- [ ] 如果 Fn 不可用，自动切换到右 Option

---

### Phase 3: 设置界面增强（优先级：🟢 低）

**文件**: `UI/SettingsRootView.swift`

**任务 3.1**: 添加热键状态显示

参考 `docs/spec/HOTKEY_ARCHITECTURE.md` 中的 "用户界面增强" 部分

```swift
// 在 permissionsSection 下方添加

private var hotkeyHealthSection: some View {
    GroupBox("热键系统") {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: hotkeyHealthIcon)
                    .foregroundStyle(hotkeyHealthColor)
                Text("系统状态")
                Spacer()
                Text(hotkeyHealthText)
                    .foregroundStyle(.secondary)
            }
            
            if let issues = healthReport?.issues, !issues.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("检测到的问题：")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    ForEach(issues, id: \.self) { issue in
                        Text("• \(issue)")
                            .font(.caption)
                    }
                }
            }
            
            Button("重新检测") {
                Task {
                    healthReport = await HotkeyHealthChecker.shared.performStartupCheck()
                }
            }
        }
    }
}
```

**验收标准**:
- [ ] 设置页面显示热键健康状态
- [ ] 显示检测到的问题列表
- [ ] "重新检测"按钮可用

---

## 🧪 测试要求

### 必须通过的测试场景

**场景 1: Fn + F5（快速组合）**
```
操作：快速按下 Fn + F5
预期：不触发录音，系统调节亮度
日志：🛑 检测到 Fn + 功能键(96)，中断录音
```

**场景 2: Fn 长按 + F11（慢速组合）**
```
操作：
1. 按住 Fn 3 秒
2. 按下 F11
预期：立即中断录音，系统调节音量
日志：🛑 检测到 Fn + 功能键(103)，中断录音
```

**场景 3: Fn 单独使用（正常录音）**
```
操作：
1. 按住 Fn 2 秒
2. 说话
3. 松开 Fn
预期：正常录音并停止
日志：录音启动 → 录音停止
```

**场景 4: 看门狗保护**
```
操作：
1. 按住 Fn
2. 等待 5 秒（如果松开事件丢失）
预期：看门狗在 2-4 秒内检测并停止
日志：🐕 看门狗检测到按键已松开但录音未停止
```

**场景 5: 启动自检**
```
操作：启动应用
预期：
- 输出健康检查日志
- 权限检查通过
- 热键系统正常
日志：✅ 热键系统正常
```

---

## 📝 代码规范

1. **日志格式**:
   ```swift
   Self.log.info("✅ 成功信息")
   Self.log.warning("⚠️ 警告信息")
   Self.log.error("❌ 错误信息")
   Self.log.debug("🔍 调试信息")
   ```

2. **Emoji 使用**:
   - ✅ 成功/正常
   - ⚠️ 警告/降级
   - ❌ 错误/失败
   - 🔹 函数调用
   - 🛑 中断/停止
   - 🐕 看门狗
   - 🔍 检查/诊断

3. **注释规范**:
   ```swift
   // ⭐️ 新增功能
   // 🔧 修复bug
   // 📊 性能优化
   ```

---

## ⚠️ 注意事项

1. **不要删除现有的看门狗逻辑** - 它是备份保护机制
2. **保持向后兼容** - 右 Option 键仍需正常工作
3. **所有 Task 都要在 MainActor** - 避免线程问题
4. **错误处理** - 所有可能失败的操作都要 try-catch
5. **日志充分** - 便于调试和问题定位

---

## 📞 遇到问题？

**常见问题参考**: `docs/HOTKEY_RELEASE_DEBUG_REPORT.md`

**架构文档**: `docs/spec/HOTKEY_ARCHITECTURE.md`

**关键调试点**:
1. EventTap 是否创建成功？看 `eventTap != nil`（或通过封装 API）
2. Fn 键是否被检测？看 `fnIsPressed` 状态变化
3. 看门狗是否运行？看 `🐕 看门狗检查 #N` 日志
4. 组合键是否触发？看 `🛑 检测到 Fn + 键` 日志

---

## ✅ 完成标准

**Phase 1 完成标准**:
- [ ] 5 个测试场景全部通过
- [ ] 日志输出完整清晰
- [ ] 无编译警告或错误

**Phase 2 完成标准**:
- [ ] 启动时输出健康检查报告
- [ ] 权限问题能正确检测
- [ ] 降级策略正常工作

**Phase 3 完成标准**:
- [ ] 设置页面正确显示状态
- [ ] UI 响应流畅
- [ ] 无 SwiftUI 警告

---

**开发时长估计**: 
- Phase 1: 2-3 小时
- Phase 2: 1-2 小时  
- Phase 3: 1 小时

**总计**: 约 4-6 小时

---

**最后更新**: 2026-03-23  
**优先级**: Phase 1 > Phase 2 > Phase 3
