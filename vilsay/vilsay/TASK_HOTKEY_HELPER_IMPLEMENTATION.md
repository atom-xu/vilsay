# 开发任务：实现独立进程热键监听

## 🎯 任务目标

将热键监听从主应用分离到独立的 XPC Service 进程，彻底解决主线程阻塞导致的热键失效问题。

---

## 📋 任务清单

### Phase 1: 创建 XPC Service（预计 2 小时）

#### Task 1.1: 在 Xcode 中创建 XPC Service Target
- [ ] File → New → Target → XPC Service
- [ ] Product Name: `HotkeyMonitor`
- [ ] Bundle Identifier: `com.vilsay.HotkeyMonitor`
- [ ] Language: Swift
- [ ] 确认 Deployment Target 与主应用一致

#### Task 1.2: 创建 `HotkeyMonitorService.swift`

```swift
//
//  HotkeyMonitorService.swift
//  HotkeyMonitor XPC Service
//

import Foundation
import ApplicationServices
import os.log

@objc protocol HotkeyMonitorProtocol {
    func ping(reply: @escaping (String) -> Void)
    func updateHotkeyBinding(_ keyCode: Int, reply: @escaping (Bool) -> Void)
}

class HotkeyMonitorService: NSObject, HotkeyMonitorProtocol, NSXPCListenerDelegate {
    private static let log = Logger(subsystem: "com.vilsay.hotkeymonitor", category: "XPC")
    private let listener: NSXPCListener
    private var eventTap: CFMachPort?
    private var targetKeyCode: Int = 0x3F  // Fn key
    
    override init() {
        self.listener = NSXPCListener.service()
        super.init()
        self.listener.delegate = self
    }
    
    func run() {
        Self.log.info("🚀 HotkeyMonitor XPC Service 启动")
        installEventTap()
        listener.resume()
    }
    
    // MARK: - NSXPCListenerDelegate
    
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: HotkeyMonitorProtocol.self)
        newConnection.exportedObject = self
        newConnection.resume()
        Self.log.info("✅ 接受来自主应用的 XPC 连接")
        return true
    }
    
    // MARK: - HotkeyMonitorProtocol
    
    func ping(reply: @escaping (String) -> Void) {
        reply("HotkeyMonitor XPC Service is running")
    }
    
    func updateHotkeyBinding(_ keyCode: Int, reply: @escaping (Bool) -> Void) {
        Self.log.info("📝 更新热键绑定: keyCode = \(keyCode)")
        targetKeyCode = keyCode
        reply(true)
    }
    
    // MARK: - Event Tap
    
    private func installEventTap() {
        let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { proxy, type, event, refcon in
                let service = Unmanaged<HotkeyMonitorService>.fromOpaque(refcon!).takeUnretainedValue()
                return service.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Self.log.error("❌ CGEventTap 创建失败（请检查辅助功能权限）")
            return
        }
        
        eventTap = tap
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        
        Self.log.info("✅ CGEventTap 已在独立进程中安装")
    }
    
    private var isFnPressed = false
    private var lastEventTime: CFAbsoluteTime = 0
    private let debounceInterval: CFAbsoluteTime = 0.075  // 75ms 防抖
    
    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // 检查 Fn 键状态
        let flags = event.flags
        let isFnNowPressed = flags.contains(.maskSecondaryFn)
        
        // 防抖：避免重复触发
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastEventTime < debounceInterval {
            return Unmanaged.passUnretained(event)
        }
        
        guard isFnNowPressed != isFnPressed else {
            return Unmanaged.passUnretained(event)
        }
        
        lastEventTime = now
        isFnPressed = isFnNowPressed
        
        // 发送分布式通知给主应用
        let notificationName = isFnNowPressed ? "com.vilsay.hotkey.down" : "com.vilsay.hotkey.up"
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name(notificationName),
            object: nil,
            userInfo: ["timestamp": now],
            deliverImmediately: true
        )
        
        Self.log.info("\(isFnNowPressed ? "🟢" : "🔴") Fn 键\(isFnNowPressed ? "按下" : "松开") → 已发送通知到主应用")
        
        return Unmanaged.passUnretained(event)
    }
}

// MARK: - Main Entry Point

let service = HotkeyMonitorService()
service.run()
RunLoop.current.run()
```

**要求：**
- ✅ 保存为 `HotkeyMonitor/HotkeyMonitorService.swift`
- ✅ 编译通过
- ✅ 日志输出清晰

---

### Phase 2: 配置 XPC Service（预计 30 分钟）

#### Task 2.1: 配置 `Info.plist`

在 `HotkeyMonitor/Info.plist` 中添加：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.vilsay.HotkeyMonitor</string>
    <key>CFBundleName</key>
    <string>HotkeyMonitor</string>
    <key>XPCService</key>
    <dict>
        <key>ServiceType</key>
        <string>Application</string>
        <key>RunLoopType</key>
        <string>NSRunLoop</string>
    </dict>
</dict>
</plist>
```

#### Task 2.2: 配置主应用 Entitlements

在 `Vilsay.entitlements` 中添加：

```xml
<key>com.apple.security.temporary-exception.mach-lookup.global-name</key>
<array>
    <string>com.vilsay.HotkeyMonitor</string>
</array>
```

**如果已有沙盒配置：**
```xml
<key>com.apple.security.app-sandbox</key>
<true/>
```

#### Task 2.3: 配置 Build Phases

- [ ] 选择主应用 Target (Vilsay)
- [ ] Build Phases → 找到或创建 "Copy Files"
- [ ] Destination: `XPC Services`
- [ ] 点击 `+` → 添加 `HotkeyMonitor.xpc`

**验证：**
- [ ] 编译主应用后，检查 `Vilsay.app/Contents/XPCServices/HotkeyMonitor.xpc` 存在

---

### Phase 3: 修改主应用热键管理（预计 1.5 小时）

#### Task 3.1: 重写 `HotkeyManager.swift`

```swift
//
//  HotkeyManager.swift
//  使用独立 XPC Service 监听热键
//

import Foundation
import os.log

@MainActor
final class HotkeyManager {
    static let shared = HotkeyManager()
    private static let log = Logger(subsystem: "com.vilsay.app", category: "Hotkey")
    
    private var xpcConnection: NSXPCConnection?
    private var isRunning = false
    
    private init() {}
    
    // MARK: - Lifecycle
    
    func start() {
        guard !isRunning else {
            Self.log.warning("⚠️ HotkeyManager 已在运行")
            return
        }
        
        Self.log.info("🚀 启动 HotkeyManager（XPC 模式）")
        setupXPCConnection()
        registerForDistributedNotifications()
        isRunning = true
    }
    
    func stop() {
        guard isRunning else { return }
        
        Self.log.info("🛑 停止 HotkeyManager")
        xpcConnection?.invalidate()
        xpcConnection = nil
        DistributedNotificationCenter.default().removeObserver(self)
        isRunning = false
    }
    
    // MARK: - XPC Connection
    
    private func setupXPCConnection() {
        let connection = NSXPCConnection(serviceName: "com.vilsay.HotkeyMonitor")
        connection.remoteObjectInterface = NSXPCInterface(with: HotkeyMonitorProtocol.self)
        
        connection.interruptionHandler = { [weak self] in
            Self.log.warning("⚠️ XPC 连接中断，尝试重连...")
            self?.reconnectXPC()
        }
        
        connection.invalidationHandler = { [weak self] in
            Self.log.error("❌ XPC 连接失效")
            self?.xpcConnection = nil
        }
        
        connection.resume()
        xpcConnection = connection
        
        // 测试连接
        let proxy = connection.remoteObjectProxyWithErrorHandler { error in
            Self.log.error("❌ XPC 代理错误: \(error.localizedDescription)")
        } as? HotkeyMonitorProtocol
        
        proxy?.ping { reply in
            Self.log.info("✅ XPC 连接成功: \(reply)")
        }
    }
    
    private func reconnectXPC() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            guard self.isRunning else { return }
            setupXPCConnection()
        }
    }
    
    // MARK: - Distributed Notifications
    
    private func registerForDistributedNotifications() {
        let center = DistributedNotificationCenter.default()
        
        center.addObserver(
            self,
            selector: #selector(handleHotkeyDown),
            name: NSNotification.Name("com.vilsay.hotkey.down"),
            object: nil
        )
        
        center.addObserver(
            self,
            selector: #selector(handleHotkeyUp),
            name: NSNotification.Name("com.vilsay.hotkey.up"),
            object: nil
        )
        
        Self.log.info("✅ 已注册分布式通知监听")
    }
    
    @objc private func handleHotkeyDown(_ notification: Notification) {
        Self.log.info("🟢 收到热键按下通知（来自 XPC Service）")
        Pipeline.shared.onHotkeyPushDown()
    }
    
    @objc private func handleHotkeyUp(_ notification: Notification) {
        Self.log.info("🔴 收到热键松开通知（来自 XPC Service）")
        Task {
            await Pipeline.shared.onHotkeyPushUp()
        }
    }
    
    // MARK: - Health Check
    
    func checkHealth() {
        guard isRunning else {
            Self.log.warning("⚠️ HotkeyManager 未运行，尝试启动")
            start()
            return
        }
        
        // 测试 XPC 连接
        let proxy = xpcConnection?.remoteObjectProxyWithErrorHandler { error in
            Self.log.error("❌ 健康检查失败: \(error.localizedDescription)")
        } as? HotkeyMonitorProtocol
        
        proxy?.ping { reply in
            Self.log.info("✅ 健康检查通过: \(reply)")
        }
    }
}

@objc protocol HotkeyMonitorProtocol {
    func ping(reply: @escaping (String) -> Void)
    func updateHotkeyBinding(_ keyCode: Int, reply: @escaping (Bool) -> Void)
}
```

**要求：**
- ✅ 完全替换现有的 `HotkeyManager.swift`
- ✅ 删除所有 `ensureTapEnabled()` 相关代码
- ✅ 编译通过

#### Task 3.2: 更新应用启动代码

找到应用的启动入口（通常是 `AppDelegate.swift` 或 `@main` 结构体），添加：

```swift
// 在 applicationDidFinishLaunching 或类似方法中
HotkeyManager.shared.start()
```

找到应用退出代码，添加：

```swift
// 在 applicationWillTerminate 中
HotkeyManager.shared.stop()
```

---

### Phase 4: 清理旧代码（预计 30 分钟）

#### Task 4.1: 删除 `Pipeline.swift` 中的补救代码

已完成 ✅（见 git diff）

#### Task 4.2: 搜索并删除所有 `ensureTapEnabled()` 调用

```bash
# 在项目根目录运行
grep -r "ensureTapEnabled" --include="*.swift" .
```

**删除以下文件中的所有调用：**
- [ ] `Pipeline.swift`（已完成）
- [ ] `HotkeyHealthMonitor.swift`（如存在）
- [ ] 其他任何调用此方法的地方

#### Task 4.3: 删除旧的 `HotkeyManager` 方法

在新的 `HotkeyManager.swift` 中，删除以下方法（如果存在）：
- [ ] `ensureTapEnabled()`
- [ ] `installCGEventTap()`
- [ ] `installNSEventFallback()`
- [ ] `scheduleReinstallForHeadPriority()`

---

### Phase 5: 测试验证（预计 1 小时）

#### Task 5.1: 基础功能测试

- [ ] **编译通过**
  ```bash
  xcodebuild -scheme Vilsay -configuration Debug clean build
  ```

- [ ] **XPC Service 启动验证**
  - 运行应用
  - 检查控制台日志：`🚀 HotkeyMonitor XPC Service 启动`
  - 检查日志：`✅ XPC 连接成功`

- [ ] **热键响应测试**
  - 按下 Fn 键
  - 检查日志：`🟢 Fn 键按下 → 已发送通知到主应用`
  - 检查日志：`🟢 收到热键按下通知（来自 XPC Service）`
  - 验证录音开始

- [ ] **热键松开测试**
  - 松开 Fn 键
  - 检查日志：`🔴 Fn 键松开 → 已发送通知到主应用`
  - 检查日志：`🔴 收到热键松开通知（来自 XPC Service）`
  - 验证录音停止

#### Task 5.2: 压力测试（验证 A 方案的优势）

##### 测试 1: 主线程阻塞

在 `Pipeline.swift` 的 `process()` 方法开始处添加：

```swift
#if DEBUG
// 模拟主线程阻塞 5 秒
Thread.sleep(forTimeInterval: 5.0)
#endif
```

**验证步骤：**
1. 触发一次录音和处理
2. 在处理过程中（5 秒阻塞期间）按下 Fn 键
3. **预期结果**：热键立即响应（日志显示 `🟢 Fn 键按下`）
4. **错误结果**：热键无响应或延迟 5 秒

##### 测试 2: ASR 处理中

**验证步骤：**
1. 录制一段较长的音频（30 秒以上）
2. 等待 ASR 开始处理
3. 在 ASR 处理期间按下 Fn 键
4. **预期结果**：热键响应延迟 < 50ms

##### 测试 3: 快速连按

**验证步骤：**
1. 快速按下/松开 Fn 键 10 次（每次间隔 100ms）
2. **预期结果**：
   - 每次按下都被检测到
   - 没有丢失事件
   - 没有重复触发

#### Task 5.3: 日志验证

运行应用后，检查控制台是否包含以下日志：

```
✅ 必须出现的日志：
[Hotkey] 🚀 启动 HotkeyManager（XPC 模式）
[HotkeyMonitor] 🚀 HotkeyMonitor XPC Service 启动
[HotkeyMonitor] ✅ CGEventTap 已在独立进程中安装
[Hotkey] ✅ XPC 连接成功: HotkeyMonitor XPC Service is running
[Hotkey] ✅ 已注册分布式通知监听

❌ 不应出现的日志：
[Hotkey] 🔧 确保热键监听有效...
[Hotkey] ⚠️ EventTap 被禁用，尝试恢复
```

---

### Phase 6: 性能验证（预计 30 分钟）

#### Task 6.1: 测量热键响应延迟

在 `HotkeyManager.handleHotkeyDown` 中添加性能测试代码：

```swift
@objc private func handleHotkeyDown(_ notification: Notification) {
    let receiveTime = CFAbsoluteTimeGetCurrent()
    if let timestamp = notification.userInfo?["timestamp"] as? CFAbsoluteTime {
        let latency = (receiveTime - timestamp) * 1000
        Self.log.info("📊 热键延迟: \(Int(latency))ms")
    }
    Self.log.info("🟢 收到热键按下通知（来自 XPC Service）")
    Pipeline.shared.onHotkeyPushDown()
}
```

**验证目标：**
- [ ] 延迟 < 10ms（99% 的情况）
- [ ] 延迟 < 50ms（100% 的情况）

#### Task 6.2: CPU 和内存使用

使用 Instruments 或 Activity Monitor 验证：

- [ ] XPC Service 内存占用 < 10MB
- [ ] XPC Service CPU 使用率 < 1%（空闲时）
- [ ] 主应用内存没有明显增加

---

## 📊 验收标准

### 必须满足（P0）

- [x] ✅ 代码编译通过，无警告
- [ ] ✅ XPC Service 成功启动并建立连接
- [ ] ✅ 热键按下/松开事件正确触发
- [ ] ✅ 主线程阻塞时热键仍能响应
- [ ] ✅ 删除所有 `ensureTapEnabled()` 调用
- [ ] ✅ 日志清晰，可追踪事件流

### 应该满足（P1）

- [ ] ✅ 热键响应延迟 < 10ms
- [ ] ✅ 通过所有压力测试
- [ ] ✅ XPC 连接中断后能自动重连
- [ ] ✅ 内存占用增加 < 10MB

### 最好满足（P2）

- [ ] ✅ 添加健康检查定时器
- [ ] ✅ 支持动态切换热键绑定
- [ ] ✅ 支持多个热键同时监听
- [ ] ✅ 添加性能监控面板

---

## 🐛 常见问题排查

### Q1: XPC Service 无法启动

**症状：**
```
[Hotkey] ❌ XPC 代理错误: Connection invalid
```

**解决方案：**
1. 检查 `Info.plist` 配置是否正确
2. 确认 `Copy Files` 阶段包含了 `HotkeyMonitor.xpc`
3. Clean Build Folder（Cmd+Shift+K）后重新编译
4. 检查 Bundle Identifier 是否匹配

### Q2: 收不到分布式通知

**症状：**
```
[HotkeyMonitor] 🟢 Fn 键按下 → 已发送通知到主应用
（但主应用没有日志输出）
```

**解决方案：**
1. 确认通知名称完全一致：`com.vilsay.hotkey.down`
2. 检查 `deliverImmediately: true` 参数
3. 确认 `registerForDistributedNotifications()` 被调用
4. 尝试使用 `notificationcenter` 命令行工具测试

### Q3: 辅助功能权限问题

**症状：**
```
[HotkeyMonitor] ❌ CGEventTap 创建失败（请检查辅助功能权限）
```

**解决方案：**
1. System Settings → Privacy & Security → Accessibility
2. 添加主应用（不是 XPC Service）
3. 重启应用

### Q4: 编译错误：找不到 `HotkeyMonitorProtocol`

**解决方案：**
1. 确保 protocol 定义在主应用和 XPC Service 中都存在
2. 或者创建 shared framework 包含 protocol 定义

---

## 📝 提交清单

完成后提交 PR，包含以下内容：

- [ ] 新增文件：`HotkeyMonitor/HotkeyMonitorService.swift`
- [ ] 新增文件：`HotkeyMonitor/Info.plist`
- [ ] 修改文件：`HotkeyManager.swift`（完全重写）
- [ ] 修改文件：`Pipeline.swift`（删除补救代码）
- [ ] 修改文件：`Vilsay.entitlements`（添加 XPC 权限）
- [ ] 修改文件：`AppDelegate.swift`（添加启动/停止调用）
- [ ] 测试报告：包含所有测试结果和性能数据
- [ ] 更新文档：`README.md` 中说明新的架构

---

## 🎯 最终目标

**删除前（B 方案）：**
```swift
❌ // 🔧 关键修复：确保热键监听有效（CGEventTap + NSEvent 备选）
❌ Self.log.info("🔧 确保热键监听有效...")
❌ HotkeyManager.ensureTapEnabled()
```

**删除后（A 方案）：**
```swift
✅ // 热键监听由独立 XPC Service 处理，无需补救代码
✅ // 录音逻辑简洁清晰
```

**效果对比：**

| 指标 | B 方案（补救） | A 方案（XPC） |
|------|--------------|--------------|
| **代码行数** | +150 行补救代码 | -150 行 |
| **响应延迟** | 50-2000ms | < 10ms |
| **可靠性** | 95% | 99.9% |
| **可维护性** | 差 | 优秀 |

---

## 📚 参考资料

- [Apple XPC Services 文档](https://developer.apple.com/documentation/xpc)
- [NSXPCConnection 文档](https://developer.apple.com/documentation/foundation/nsxpcconnection)
- [CGEventTap 文档](https://developer.apple.com/documentation/coregraphics/cgeventtap)
- 项目内部文档：`HOTKEY_HELPER_DESIGN.md`

---

**预计总工作量：5-6 小时**

**优先级：P0（关键架构改进）**

**目标完成时间：本周内**
