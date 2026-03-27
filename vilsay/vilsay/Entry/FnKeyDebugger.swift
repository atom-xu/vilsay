//
//  FnKeyDebugger.swift
//  诊断 Fn 键松开检测问题
//

import AppKit
import os.log

@MainActor
final class FnKeyDebugger {
    static let shared = FnKeyDebugger()
    private static let log = Logger(subsystem: "com.vilsay.app", category: "FnDebug")
    
    private var monitor: Any?
    private var localMonitor: Any?
    private var isFnPressed = false
    
    private init() {}
    
    func start() {
        stop()
        
        Self.log.info("🔍 启动 Fn 键调试监听")
        
        // 全局监听
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.checkFn(event, source: "全局")
        }
        
        // 本地监听
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.checkFn(event, source: "本地")
            return event
        }
        
        // 定时轮询（备用）
        startPolling()
    }
    
    private func checkFn(_ event: NSEvent, source: String) {
        let isFnNow = event.modifierFlags.contains(.function)
        
        if isFnNow != isFnPressed {
            isFnPressed = isFnNow
            Self.log.info("[\(source)] Fn 键: \(isFnNow ? "按下" : "松开")")
        }
    }
    
    // 备用：定时轮询（不依赖事件）
    private func startPolling() {
        Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                
                let currentFlags = NSEvent.modifierFlags
                let isFnNow = currentFlags.contains(.function)
                
                if isFnNow != isFnPressed {
                    isFnPressed = isFnNow
                    Self.log.info("[轮询] Fn 键: \(isFnNow ? "按下" : "松开")")
                }
            }
        }
    }
    
    func stop() {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
        if let m = localMonitor {
            NSEvent.removeMonitor(m)
            localMonitor = nil
        }
    }
}
