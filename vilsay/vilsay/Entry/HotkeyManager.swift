//
//  HotkeyManager.swift
//  嵌入式 XPC Service（HotkeyMonitor）监听 Fn；事件经 XPC 回传主应用。
//
//  注意：`HotkeyMonitorClientProtocol` 的实现 **不得** 放在 `@MainActor` 类型内部，否则 XPC 在非主线程回调时可能
//  同步等待 MainActor，与主线程互等 → 日志停刷、菜单栏假死。桥接类为文件级 + `DispatchQueue.main.async` 投递。
//
//  MainActor 竞态（Step 4）：`interruptionHandler` 仅置 `needsXPCReconnect`；`performSoftReconnect` 在 utility 队列
//  `invalidate` 后 `DispatchQueue.main.async` + `Task { @MainActor in setupXPCConnection() }`。
//

import Foundation
import os.log

@objc protocol HotkeyMonitorClientProtocol {
    /// `timestamp` 为 XPC 进程内 `CFAbsoluteTimeGetCurrent()`，用于延迟统计。
    func hotkeyEdgeDidChange(isDown: Bool, timestamp: TimeInterval)
}

@objc protocol HotkeyMonitorProtocol {
    func ping(reply: @escaping (String) -> Void)
    func updateHotkeyBinding(_ keyCode: Int, reply: @escaping (Bool) -> Void)
}

/// 将 `NSXPCConnection` 传入 `DispatchQueue.global` 闭包时满足 `@Sendable`（连接本身非 Sendable）。
private final class NSXPCConnectionHolder: @unchecked Sendable {
    let connection: NSXPCConnection?
    init(_ connection: NSXPCConnection?) { self.connection = connection }
}

/// 文件级 NSObject，避免继承 `@MainActor` 隔离；在 XPC 回调线程上立即返回。
private final class HotkeyXPCClientBridge: NSObject, HotkeyMonitorClientProtocol {
    func hotkeyEdgeDidChange(isDown: Bool, timestamp: TimeInterval) {
        // 单跳上主线程即可；避免 main.async 再包一层 Task 加重调度（Fn 边沿频繁时放大 CPU）。
        Task { @MainActor in
            HotkeyManager.shared.applyFnEdgeFromXPC(isDown: isDown, remoteTimestamp: timestamp)
        }
    }
}

/// 热键管理器：XPC 双向通道（主进程导出 `HotkeyMonitorClientProtocol`）。
@MainActor
final class HotkeyManager {
    static let shared = HotkeyManager()

    private static let log = Logger(subsystem: "com.vilsay.app", category: "Hotkey")

    private var xpcConnection: NSXPCConnection?
    private let xpcClientBridge = HotkeyXPCClientBridge()

    private(set) var isRunning = false

    /// 与 XPC 下发的 Fn 按下/松开成对；用于长按定时器判断是否仍按住。
    private var fnKeyDown = false
    private var fnPressStartAt: Date?
    /// 是否已在按住期间越过 `fnTapVersusHoldMs` 并调用 `fnHoldPushDown`。
    private var fnLongPressArmed = false
    private var fnLongPressTask: Task<Void, Never>?
    /// XPC 中断/失效后 **禁止** 在 `interruptionHandler` 栈上同步 `invalidate()`（会与 XPC 运行时互等导致主线程卡死、日志停刷）。
    /// 仅置位，由 `checkHealth` / 回前台时 `performSoftReconnect()` 在后台 `invalidate` 后再回主线程 `setup`。
    private var needsXPCReconnect = false

    private init() {}

    // MARK: - Lifecycle

    /// 与历史调用点兼容（等价于 `shared.start()`）。
    static func install() {
        shared.start()
    }

    func start() {
        guard !DiagnosticsExclusion.excludeHotkeyXPC else {
            Self.log.warning("🧪 VILSAY_EXCLUDE_HOTKEY_XPC=1：不启动热键 XPC")
            return
        }
        guard !isRunning else {
            Self.log.warning("⚠️ HotkeyManager 已在运行")
            return
        }

        Self.log.info("🚀 启动 HotkeyManager（XPC 双向）")
        setupXPCConnection()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }

        Self.log.info("🛑 停止 HotkeyManager")
        needsXPCReconnect = false
        xpcConnection?.invalidate()
        xpcConnection = nil
        fnLongPressTask?.cancel()
        fnLongPressTask = nil
        fnKeyDown = false
        fnPressStartAt = nil
        fnLongPressArmed = false
        isRunning = false
    }

    // MARK: - XPC

    private func setupXPCConnection() {
        let connection = NSXPCConnection(serviceName: "com.vilsay.HotkeyMonitor")
        connection.exportedInterface = NSXPCInterface(with: HotkeyMonitorClientProtocol.self)
        connection.exportedObject = xpcClientBridge
        connection.remoteObjectInterface = NSXPCInterface(with: HotkeyMonitorProtocol.self)

        connection.interruptionHandler = {
            // 切勿在此回调内 Task.sleep + MainActor.invalidate：易与 XPC 内部锁互等，主线程永久卡死。
            Self.log.info("ℹ️ HotkeyMonitor XPC 中断（已推迟重连，避免卡死）")
            Task { @MainActor in
                HotkeyManager.shared.needsXPCReconnect = true
            }
        }

        connection.invalidationHandler = {
            Self.log.error("❌ XPC 连接失效")
            Task { @MainActor in
                HotkeyManager.shared.clearXPCConnectionAndMarkReconnect()
            }
        }

        connection.resume()
        xpcConnection = connection

        let proxy = connection.remoteObjectProxyWithErrorHandler { error in
            Self.log.error("❌ XPC 代理错误: \(error.localizedDescription)")
        } as? HotkeyMonitorProtocol

        proxy?.ping { reply in
            Self.log.info("✅ XPC 连接成功: \(reply)")
        }
    }

    @MainActor
    private func clearXPCConnectionAndMarkReconnect() {
        xpcConnection = nil
        needsXPCReconnect = true
    }

    /// 在 **utility 队列** 上对旧连接 `invalidate()`，再回到主线程 `setupXPCConnection()`，避免在主线程/XPC 回调栈上同步 `invalidate` 导致死锁。
    @MainActor
    private func performSoftReconnect() {
        guard isRunning else { return }
        Self.log.info("🔁 正在重连 HotkeyMonitor XPC（后台 invalidate）…")
        let holder = NSXPCConnectionHolder(xpcConnection)
        xpcConnection = nil
        DispatchQueue.global(qos: .utility).async {
            holder.connection?.invalidate()
            DispatchQueue.main.async {
                Task { @MainActor in
                    guard HotkeyManager.shared.isRunning else { return }
                    HotkeyManager.shared.setupXPCConnection()
                }
            }
        }
    }

    @MainActor
    private func tryReconnectIfNeeded(reason: String) -> Bool {
        guard isRunning, needsXPCReconnect else { return false }
        needsXPCReconnect = false
        Self.log.info("🔁 因 \(reason) 触发 XPC 软重连")
        performSoftReconnect()
        return true
    }

    // MARK: - Fn 边沿（由 XPC 客户端协议回调，经 main.async 投递）

    /// 与 `HotkeyXPCClientBridge` 同文件，`fileprivate` 供桥接调用。
    fileprivate func applyFnEdgeFromXPC(isDown: Bool, remoteTimestamp: TimeInterval) {
        if isDown {
            handleFnDown(remoteTimestamp: remoteTimestamp)
        } else {
            handleFnUp(remoteTimestamp: remoteTimestamp)
        }
    }

    private func handleFnDown(remoteTimestamp: TimeInterval) {
        let receiveTime = CFAbsoluteTimeGetCurrent()
        let latencyMs = (receiveTime - remoteTimestamp) * 1000
        Self.log.info("📊 热键延迟: \(Int(latencyMs))ms")
        Self.log.info("🟢 收到 Fn 按下（XPC）")

        if AppState.shared.hotkeySelfTestAwaiting {
            AppState.shared.hotkeySelfTestMessage = "已收到 Fn 热键事件（按下）。"
            AppState.shared.hotkeySelfTestAwaiting = false
            return
        }

        fnLongPressTask?.cancel()
        fnLongPressArmed = false
        fnKeyDown = true
        fnPressStartAt = Date()

        switch AppState.shared.triggerMode {
        case .toggle:
            // 单击模式：不启动长按定时器，松开时仅按「短按」判一次切换。
            Self.log.debug("Fn 按下（单击模式：不识别长按录音）")
        case .push:
            fnLongPressTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(Constants.fnTapVersusHoldMs))
                guard !Task.isCancelled else { return }
                guard let self else { return }
                guard self.fnKeyDown else { return }
                self.fnLongPressArmed = true
                Self.log.info("Fn 长按分界到达（≥ \(Constants.fnTapVersusHoldMs)ms）→ fnHoldPushDown")
                Pipeline.shared.fnHoldPushDown()
            }
            Self.log.debug("Fn 按下（长按模式：等待 \(Constants.fnTapVersusHoldMs)ms 分界）")
        }
    }

    private func handleFnUp(remoteTimestamp: TimeInterval) {
        let receiveTime = CFAbsoluteTimeGetCurrent()
        let latencyMs = (receiveTime - remoteTimestamp) * 1000
        Self.log.info("📊 热键松开延迟: \(Int(latencyMs))ms")
        Self.log.info("🔴 收到 Fn 松开（XPC）")

        fnLongPressTask?.cancel()
        fnLongPressTask = nil
        fnKeyDown = false

        let start = fnPressStartAt
        fnPressStartAt = nil

        guard let start else {
            Self.log.warning("Fn 松开但无按下时间戳")
            return
        }

        let elapsedMs = Date().timeIntervalSince(start) * 1000
        let wasArmed = fnLongPressArmed
        fnLongPressArmed = false

        let mode = AppState.shared.triggerMode
        switch FnHotkeyDiscrimination.dispositionOnRelease(triggerMode: mode, elapsedMs: elapsedMs, longPressArmed: wasArmed) {
        case .emitToggle:
            Self.log.info("Fn 单击模式：短按（约 \(Int(elapsedMs))ms）→ Toggle")
            Task { await Pipeline.shared.onHotkeyToggle() }
        case .emitLongPressUp:
            Self.log.info("Fn 长按模式：松开（约 \(Int(elapsedMs))ms）→ fnHoldPushUp")
            Task { await Pipeline.shared.fnHoldPushUp() }
        case .ignore:
            switch mode {
            case .toggle:
                Self.log.debug("Fn 单击模式：按住过久或非短按释放（约 \(Int(elapsedMs))ms），忽略")
            case .push:
                Self.log.debug("Fn 长按模式：未达长按分界即松开（约 \(Int(elapsedMs))ms），忽略")
            }
        }
    }

    // MARK: - 兼容旧 API

    static var isEventTapInstalled: Bool {
        shared.isRunning
    }

    static func checkHealth() {
        shared.checkHealth()
    }

    func checkHealth() {
        guard !DiagnosticsExclusion.excludeHotkeyXPC else { return }
        guard isRunning else {
            Self.log.warning("⚠️ HotkeyManager 未运行，尝试启动")
            start()
            return
        }

        if tryReconnectIfNeeded(reason: "健康检查（待重连标志）") {
            return
        }

        if xpcConnection == nil {
            Self.log.warning("⚠️ XPC 无连接，尝试建立")
            performSoftReconnect()
            return
        }

        let proxy = xpcConnection?.remoteObjectProxyWithErrorHandler { error in
            Self.log.error("❌ 健康检查失败: \(error.localizedDescription)")
            Task { @MainActor in
                HotkeyManager.shared.needsXPCReconnect = true
            }
        } as? HotkeyMonitorProtocol

        proxy?.ping { reply in
            Self.log.info("✅ 健康检查通过: \(reply)")
        }
    }

    /// 前台/唤醒时由 `AppDelegate` 调用；主线程上可能从通知回调触发，故 `nonisolated`。
    nonisolated static func scheduleReinstallForHeadPriority() {
        Task { @MainActor in
            _ = HotkeyManager.shared.tryReconnectIfNeeded(reason: "回前台")
        }
    }
}
