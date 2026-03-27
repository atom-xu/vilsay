//
//  HotkeyTest.swift
//  最简单的按键检测测试 - 不干扰 Pipeline
//

import AppKit
import Foundation

/// 独立测试：只打印按键状态，不调用任何业务逻辑
class HotkeyTest {
    static let shared = HotkeyTest()
    
    private var timer: Timer?
    private var lastPressed = false
    
    func start() {
        stop()
        print("🧪 开始按键检测测试（每 100ms 检查）")
        
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.check()
        }
    }
    
    func stop() {
        timer?.invalidate()
        timer = nil
    }
    
    private func check() {
        // 方法：检查 NSEvent.modifierFlags（最简单）
        let flags = NSEvent.modifierFlags
        let isPressed = flags.contains(.option)
        
        if isPressed != lastPressed {
            lastPressed = isPressed
            print(isPressed ? "🔴 Option 按下" : "🟢 Option 松开")
        }
    }
}

// 使用方式：
// 在 AppDelegate 或某个按钮里调用：
// HotkeyTest.shared.start()
// 
// 然后按右 Option 键，看控制台输出
