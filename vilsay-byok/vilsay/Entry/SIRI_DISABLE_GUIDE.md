# 禁用 macOS Siri 的方法研究

## 🎯 目标
完全禁用系统 Siri，让应用可以占用 Siri 键（keyCode 179）

---

## 方法 1：通过 `defaults` 命令禁用 Siri（推荐）

### 禁用 Siri
```bash
# 禁用 Siri
defaults write com.apple.assistant.support "Assistant Enabled" -bool false

# 禁用 Siri 建议
defaults write com.apple.assistant.support "Siri Data Sharing Opt-In Status" -int 2

# 禁用「嘿 Siri」
defaults write com.apple.Siri VoiceTriggerUserEnabled -bool false

# 禁用 Siri 键盘快捷键
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 176 "<dict><key>enabled</key><false/></dict>"

# 重启 Siri 服务使生效
killall Siri
```

### 恢复 Siri
```bash
# 重新启用 Siri
defaults write com.apple.assistant.support "Assistant Enabled" -bool true
defaults write com.apple.Siri VoiceTriggerUserEnabled -bool true

killall Siri
```

---

## 方法 2：在应用内提供一键禁用功能（Swift 实现）

### 实现代码

```swift
//
//  SiriManager.swift
//  管理系统 Siri 的启用/禁用
//

import Foundation
import os.log

enum SiriManager {
    private static let log = Logger(subsystem: "com.vilsay.app", category: "SiriManager")
    
    /// 检查 Siri 是否已禁用
    static func isSiriDisabled() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        task.arguments = ["read", "com.apple.assistant.support", "Assistant Enabled"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // 如果返回 "0" 或 "false"，说明已禁用
            return output == "0" || output == "false"
        } catch {
            log.error("检查 Siri 状态失败: \(error.localizedDescription)")
            return false
        }
    }
    
    /// 禁用 Siri（需要用户授权）
    static func disableSiri() async throws {
        log.info("正在禁用系统 Siri...")
        
        // 构建 AppleScript（需要用户授权）
        let script = """
        do shell script "defaults write com.apple.assistant.support 'Assistant Enabled' -bool false && \
        defaults write com.apple.Siri VoiceTriggerUserEnabled -bool false && \
        killall Siri" with administrator privileges
        """
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                var error: NSDictionary?
                if let scriptObject = NSAppleScript(source: script) {
                    scriptObject.executeAndReturnError(&error)
                    
                    if let error = error {
                        continuation.resume(throwing: NSError(
                            domain: "SiriManager",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: error.description]
                        ))
                    } else {
                        continuation.resume()
                    }
                } else {
                    continuation.resume(throwing: NSError(
                        domain: "SiriManager",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "无法创建 AppleScript"]
                    ))
                }
            }
        }
    }
    
    /// 启用 Siri
    static func enableSiri() async throws {
        log.info("正在启用系统 Siri...")
        
        let script = """
        do shell script "defaults write com.apple.assistant.support 'Assistant Enabled' -bool true && \
        defaults write com.apple.Siri VoiceTriggerUserEnabled -bool true" with administrator privileges
        """
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                var error: NSDictionary?
                if let scriptObject = NSAppleScript(source: script) {
                    scriptObject.executeAndReturnError(&error)
                    
                    if let error = error {
                        continuation.resume(throwing: NSError(
                            domain: "SiriManager",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: error.description]
                        ))
                    } else {
                        continuation.resume()
                    }
                } else {
                    continuation.resume(throwing: NSError(
                        domain: "SiriManager",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "无法创建 AppleScript"]
                    ))
                }
            }
        }
    }
}
```

---

## 方法 3：在设置界面添加一键禁用按钮

### UI 实现

```swift
//
//  SiriDisableView.swift
//  设置界面中的 Siri 禁用选项
//

import SwiftUI

struct SiriDisableView: View {
    @State private var isSiriDisabled = false
    @State private var isProcessing = false
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Siri 键设置")
                .font(.headline)
            
            HStack {
                Image(systemName: isSiriDisabled ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundColor(isSiriDisabled ? .green : .orange)
                
                Text(isSiriDisabled ? "系统 Siri 已禁用" : "系统 Siri 已启用")
                    .font(.subheadline)
            }
            
            Text("要使用 Siri 键作为热键，需要先禁用系统 Siri。")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack {
                if isSiriDisabled {
                    Button("启用系统 Siri") {
                        Task {
                            await toggleSiri(enable: true)
                        }
                    }
                    .disabled(isProcessing)
                } else {
                    Button("禁用系统 Siri") {
                        Task {
                            await toggleSiri(enable: false)
                        }
                    }
                    .disabled(isProcessing)
                }
                
                if isProcessing {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
        .onAppear {
            checkSiriStatus()
        }
    }
    
    private func checkSiriStatus() {
        isSiriDisabled = SiriManager.isSiriDisabled()
    }
    
    private func toggleSiri(enable: Bool) async {
        isProcessing = true
        errorMessage = nil
        
        do {
            if enable {
                try await SiriManager.enableSiri()
            } else {
                try await SiriManager.disableSiri()
            }
            
            // 等待系统生效
            try await Task.sleep(for: .seconds(1))
            
            checkSiriStatus()
        } catch {
            errorMessage = "操作失败: \(error.localizedDescription)"
        }
        
        isProcessing = false
    }
}
```

---

## 方法 4：使用 IOKit 直接拦截硬件事件（高级）

### 原理
通过 IOKit 在更底层拦截键盘事件，优先级高于系统服务。

```swift
import IOKit
import IOKit.hid

// 注册 HID 事件监听
let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

// 设置过滤条件（键盘设备）
let matchingDict: [String: Any] = [
    kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
    kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard
]

IOHIDManagerSetDeviceMatching(manager, matchingDict as CFDictionary)

// 注册回调
IOHIDManagerRegisterInputValueCallback(manager, { context, result, sender, value in
    let element = IOHIDValueGetElement(value)
    let usage = IOHIDElementGetUsage(element)
    
    // 拦截特定按键
    if usage == kHIDUsage_KeyboardSiri {
        // 处理 Siri 键
        print("拦截到 Siri 键！")
    }
}, nil)

// 启动监听
IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
```

**⚠️ 注意**：这个方法需要额外的系统权限，且可能不稳定。

---

## 📊 方案对比

| 方案 | 优点 | 缺点 | 推荐度 |
|------|------|------|-------|
| **方法 1：defaults 命令** | 简单、稳定 | 需要用户手动执行 | ⭐️⭐️⭐️ |
| **方法 2：应用内禁用** | 用户友好、一键操作 | 需要管理员权限 | ⭐️⭐️⭐️⭐️⭐️ |
| **方法 3：设置界面** | 最佳用户体验 | 需要实现 UI | ⭐️⭐️⭐️⭐️⭐️ |
| **方法 4：IOKit** | 底层拦截 | 复杂、不稳定 | ⭐️⭐️ |

---

## 🎯 最佳实践（推荐）

### 组合方案：应用内一键禁用 + UI 提示

1. **在首次启动时检测** Siri 是否已禁用
2. **如果未禁用**，显示提示：
   ```
   ⚠️ 检测到系统 Siri 已启用
   
   要使用 Siri 键作为热键，建议禁用系统 Siri。
   
   [一键禁用 Siri]  [稍后处理]
   ```
3. **用户点击后**，使用 AppleScript 执行禁用（需要管理员授权）
4. **禁用成功后**，自动安装热键监听

---

## 🚀 实施步骤

### 第 1 步：创建 `SiriManager.swift`
将上面的代码保存为 `SiriManager.swift`

### 第 2 步：在 `AppDelegate` 中检查
```swift
func applicationDidFinishLaunching(_ notification: Notification) {
    // 检查 Siri 状态
    if !SiriManager.isSiriDisabled() {
        // 显示提示对话框
        showSiriDisablePrompt()
    }
    
    // 继续安装热键
    HotkeyManager.install()
}
```

### 第 3 步：添加设置选项
在 `SettingsRootView.swift` 中添加 `SiriDisableView`

---

## ⚠️ 注意事项

1. **需要管理员权限**：禁用 Siri 需要用户输入密码
2. **用户体验**：应该明确告知用户为什么要禁用 Siri
3. **可逆性**：提供「恢复 Siri」的选项
4. **兼容性**：在不同 macOS 版本上测试

---

## 🎯 结论

**我的建议**：
1. ✅ 实现「应用内一键禁用 Siri」功能（方法 2 + 方法 3）
2. ✅ 在设置界面提供开关
3. ✅ 首次启动时提示用户

这样用户体验最好，且技术上可行！

需要我实现完整的代码吗？
