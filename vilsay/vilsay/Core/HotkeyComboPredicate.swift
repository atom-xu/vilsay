//
//  HotkeyComboPredicate.swift
//

import CoreGraphics

/// Fn / 右 ⌥ 组合键是否应进入「录音中则 cancel」分支的纯逻辑（与 `CGEventTap` 无关，便于单元测试）。
enum HotkeyComboPredicate {
    private static let keyCodeRightOption: UInt16 = 0x3D
    private static let keyCodeFunction: UInt16 = 0x3F

    /// `Fn + 其他键` 是否应尝试取消；真正 cancel 仍由 `Pipeline.isRecordingSessionActive` 等约束。
    static func shouldAttemptFnComboCancel(type: CGEventType, keyCode: UInt16, fnIsPressed: Bool) -> Bool {
        guard fnIsPressed, keyCode != keyCodeFunction else { return false }
        return type == .keyDown || type == .flagsChanged
    }

    /// `右 ⌥ + 其他键` 是否应尝试取消。
    static func shouldAttemptRightOptionComboCancel(type: CGEventType, keyCode: UInt16, rightOptionHeld: Bool) -> Bool {
        type == .keyDown && rightOptionHeld && keyCode != keyCodeRightOption
    }
}
