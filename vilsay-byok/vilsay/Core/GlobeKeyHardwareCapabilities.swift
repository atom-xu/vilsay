//
//  GlobeKeyHardwareCapabilities.swift
//

import Darwin
import Foundation
import os.log

/// 启动时探测：🌐/FN 作为修饰键常见于 **MacBook 内置键盘**；外接键盘常无此键，设置页应禁用对应选项。
enum GlobeKeyHardwareCapabilities {
    private static let log = Logger(subsystem: "com.vilsay.app", category: "Hardware")
    
    /// `sysctl hw.model` 含 `MacBook` 时视为可能具备 FN/🌐 修饰（与内置键盘验收场景一致）。
    static let isGlobeModifierLikelyAvailable: Bool = {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &buf, &size, nil, 0)
        let model = String(cString: buf)
        
        // 🔍 调试：打印型号信息
        log.info("🖥️ 硬件型号: \(model)")
        
        let hasGlobeKey = model.contains("MacBook")
        log.info("🎹 Fn/Globe 键检测: \(hasGlobeKey ? "有" : "无")")
        
        return hasGlobeKey
    }()
}
