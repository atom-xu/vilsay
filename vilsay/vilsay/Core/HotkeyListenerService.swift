//
//  HotkeyListenerService.swift
//  独立进程热键监听服务（参考 VoiceInk macos-globe-listener）
//

import AppKit
import ApplicationServices
import Foundation
import os.log

/// 🔑 VoiceInk 风格的独立进程热键监听器（参考实现）。
/// **说明**：独立可执行文件需单独 Xcode Target；与 `vilsayApp` 同模块时不能使用 `@main`。
enum HotkeyListenerService {
    private static let listenerLog = Logger(subsystem: "com.vilsay.hotkey-listener", category: "Service")
    private static var installedTap: CFMachPort?

    /// 若将来拆分为独立 Target，在 `main` 中调用并 `RunLoop.main.run()`。
    static func runStandaloneProcess() {
        listenerLog.info("🚀 HotkeyListenerService 启动")
        installEventTap()
        RunLoop.main.run()
    }
    
    private static func installEventTap() {
        let mask = (1 << CGEventType.flagsChanged.rawValue)
        
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,  // VoiceInk 同样使用链首插入
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: eventCallback,
            userInfo: nil
        ) else {
            listenerLog.error("❌ CGEventTap 创建失败（需要辅助功能权限）")
            // 输出错误到 stdout（主进程可以监听）
            print("ERROR:NO_ACCESSIBILITY")
            fflush(stdout)
            exit(1)
        }
        
        installedTap = tap
        CGEvent.tapEnable(tap: tap, enable: true)

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)

        listenerLog.info("✅ EventTap 已安装（独立进程）")
        print("READY")
        fflush(stdout)
    }
    
    private static let eventCallback: CGEventTapCallBack = { proxy, type, event, userInfo in
        // 自动重启（VoiceInk 的核心机制）
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            listenerLog.warning("⚠️ EventTap 被禁用，重新启用")
            if let tap = HotkeyListenerService.installedTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        
        guard type == .flagsChanged else {
            return Unmanaged.passUnretained(event)
        }
        
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        
        // 🌐 Fn/Globe 键（0x3F）
        if keyCode == 0x3F {
            let fnBit = UInt64(NSEvent.ModifierFlags.function.rawValue)
            let pressed = (event.flags.rawValue & fnBit) != 0
            
            // 输出到 stdout（VoiceInk 风格）
            print(pressed ? "FN_DOWN" : "FN_UP")
            fflush(stdout)
        }
        
        // 右 Option 键（0x3D）
        if keyCode == 0x3D {
            let pressed = event.flags.contains(.maskAlternate)
            print(pressed ? "RIGHT_OPTION_DOWN" : "RIGHT_OPTION_UP")
            fflush(stdout)
        }
        
        return Unmanaged.passUnretained(event)
    }
}
