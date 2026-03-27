//
//  HotkeyMonitorService.swift
//  HotkeyMonitor XPC Service
//
//  职责边界：仅 CGEventTap（Fn 边沿）+ XPC 与主应用双向通信。
//  禁止在本 target 引入或使用 AVFoundation / AVAudioRecorder / AVAudioEngine / AVAudioSession（录音仅在主应用）。
//

import ApplicationServices
import Foundation
import os.log

@objc protocol HotkeyMonitorClientProtocol {
    func hotkeyEdgeDidChange(isDown: Bool, timestamp: TimeInterval)
}

@objc protocol HotkeyMonitorProtocol {
    func ping(reply: @escaping (String) -> Void)
    func updateHotkeyBinding(_ keyCode: Int, reply: @escaping (Bool) -> Void)
}

final class HotkeyMonitorService: NSObject, HotkeyMonitorProtocol, NSXPCListenerDelegate {
    private static let log = Logger(subsystem: "com.vilsay.hotkeymonitor", category: "XPC")

    private let listener: NSXPCListener
    /// 与主 RunLoop 分离：Fn 边沿在此串行投递 XPC，避免 `DispatchQueue.main.async` 在主线程上无限堆积（密集 `flagsChanged` 时曾触发 Jet/Jetsam）。
    private let xpcOutboundQueue = DispatchQueue(label: "com.vilsay.hotkeymonitor.xpc.outbound", qos: .userInteractive)
    /// 有界队列 + 单路 drain：防止 `async` 块或边沿在极端抖动下无限堆积（配合 Xcode 对 XPC 附加调试器时更易 OOM）。
    private let fnEdgeLock = NSLock()
    private var fnEdgeBuffer: [(down: Bool, t: TimeInterval)] = []
    private var fnEdgeDrainScheduled = false
    private static let fnEdgeBufferCap = 64

    private var eventTap: CFMachPort?
    private var targetKeyCode: Int = 0x3F // Fn

    private var isFnPressed = false

    /// 主应用导出的回调接口（通过 `NSXPCConnection.remoteObjectProxy` 调用）。
    private var appClientProxy: HotkeyMonitorClientProtocol?
    private weak var appConnection: NSXPCConnection?
    /// 与 `appClientProxy` 同步：主进程已连接且未在断开流程中（避免误打 Fn 日志）。
    private var clientConnected = false

    override init() {
        listener = NSXPCListener.service()
        super.init()
        listener.delegate = self
    }

    func run() {
        Self.log.info("🚀 HotkeyMonitor XPC Service 启动")
        installEventTap()
        listener.resume()
    }

    // MARK: - NSXPCListenerDelegate

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        appConnection?.invalidate()
        appConnection = newConnection

        newConnection.exportedInterface = NSXPCInterface(with: HotkeyMonitorProtocol.self)
        newConnection.exportedObject = self
        newConnection.remoteObjectInterface = NSXPCInterface(with: HotkeyMonitorClientProtocol.self)

        let conn = newConnection
        let peerDisconnected: () -> Void = { [weak self] in
            self?.onPeerXPCDisconnected(connection: conn)
        }
        newConnection.invalidationHandler = peerDisconnected
        newConnection.interruptionHandler = peerDisconnected

        newConnection.resume()

        appClientProxy = newConnection.remoteObjectProxyWithErrorHandler { err in
            Self.log.error("❌ 主应用客户端代理错误: \(err.localizedDescription)")
        } as? HotkeyMonitorClientProtocol

        clientConnected = true
        DispatchQueue.main.async { [weak self] in
            self?.enableEventTapIfInstalled()
        }

        Self.log.info("✅ 已接受主应用 XPC 连接（双向：可回调主进程）")
        return true
    }

    /// 仅当失效的是**当前**这条 `NSXPCConnection` 时才清理；否则异步 `invalidation` 可能在替换连接后误清 `appConnection`（竞态）。
    private func onPeerXPCDisconnected(connection: NSXPCConnection) {
        guard appConnection === connection else {
            Self.log.debug("忽略陈旧 XPC 断开回调（已有新连接）")
            return
        }
        Self.log.warning("⚠️ 主应用 XPC 断开（失效或中断）")
        appClientProxy = nil
        appConnection = nil
        clientConnected = false
        DispatchQueue.main.async { [weak self] in
            self?.disableEventTapForDisconnect()
        }
    }

    private func enableEventTapIfInstalled() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func disableEventTapForDisconnect() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        Self.log.info("🔇 已暂停 CGEventTap（主应用已断开；重连后将恢复）")
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
        let eventMask: CGEventMask = 1 << CGEventType.flagsChanged.rawValue

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { _, type, event, refcon in
                guard let refcon else {
                    return Unmanaged.passUnretained(event)
                }
                let service = Unmanaged<HotkeyMonitorService>.fromOpaque(refcon).takeUnretainedValue()
                return service.handleEvent(type: type, event: event)
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

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            guard clientConnected else {
                return Unmanaged.passUnretained(event)
            }
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard clientConnected else {
            return Unmanaged.passUnretained(event)
        }

        guard type == .flagsChanged else {
            return Unmanaged.passUnretained(event)
        }

        let flags = event.flags
        let isFnNowPressed = flags.contains(.maskSecondaryFn)

        guard isFnNowPressed != isFnPressed else {
            return Unmanaged.passUnretained(event)
        }

        isFnPressed = isFnNowPressed

        let now = CFAbsoluteTimeGetCurrent()
        // 勿在 EventTap 回调里同步调用主应用 XPC。独立串行队列 + 有界缓冲，避免边沿/async 堆积导致子进程被 Jetsam。
        guard clientConnected, appClientProxy != nil else {
            Self.log.warning("⚠️ 尚无主应用 XPC 客户端，丢弃 Fn 边沿（请先启动主应用并完成连接）")
            return Unmanaged.passUnretained(event)
        }
        enqueueFnEdgeForXPC(isDown: isFnNowPressed, timestamp: now)

        return Unmanaged.passUnretained(event)
    }

    private func enqueueFnEdgeForXPC(isDown: Bool, timestamp: TimeInterval) {
        var startDrain = false
        fnEdgeLock.lock()
        if fnEdgeBuffer.count >= Self.fnEdgeBufferCap {
            let drop = fnEdgeBuffer.count - (Self.fnEdgeBufferCap - 1)
            fnEdgeBuffer.removeFirst(drop)
            Self.log.warning("⚠️ Fn 边沿积压 ≥ \(Self.fnEdgeBufferCap)，已丢弃最旧 \(drop) 条（防止 HotkeyMonitor 内存暴涨）")
        }
        fnEdgeBuffer.append((isDown, timestamp))
        if !fnEdgeDrainScheduled {
            fnEdgeDrainScheduled = true
            startDrain = true
        }
        fnEdgeLock.unlock()

        guard startDrain else { return }
        xpcOutboundQueue.async { [weak self] in
            self?.drainFnEdgeBufferForXPC()
        }
    }

    private func drainFnEdgeBufferForXPC() {
        while true {
            fnEdgeLock.lock()
            guard !fnEdgeBuffer.isEmpty else {
                fnEdgeDrainScheduled = false
                fnEdgeLock.unlock()
                return
            }
            let edge = fnEdgeBuffer.removeFirst()
            fnEdgeLock.unlock()

            guard clientConnected, let client = appClientProxy else { continue }
            client.hotkeyEdgeDidChange(isDown: edge.down, timestamp: edge.t)
        }
    }
}
