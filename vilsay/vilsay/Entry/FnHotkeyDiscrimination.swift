//
//  FnHotkeyDiscrimination.swift
//  全局 Fn：与 `AppState.triggerMode` 对齐——**单击模式**只认短按切换，**长按模式**只认按住/松手（可单测）。
//

import Foundation

/// 松开 Fn 时主应用应采取的动作（不含自测分支）。
enum FnHotkeyReleaseDisposition: Equatable {
    /// 单击模式：短按释放 → `Pipeline.onHotkeyToggle()`。
    case emitToggle
    /// 长按模式：已越过按住分界并 `fnHoldPushDown` 后释放 → `Pipeline.fnHoldPushUp()`。
    case emitLongPressUp
    /// 当前模式下不应产生录音（例如单击模式按住过久后松开；长按模式未达分界即松开）。
    case ignore
}

enum FnHotkeyDiscrimination {
    /// - Parameters:
    ///   - longPressArmed: 是否在按住期间已触发长按定时器（仅长按模式会置为 true）。
    static func dispositionOnRelease(
        triggerMode: TriggerMode,
        elapsedMs: Double,
        longPressArmed: Bool,
        tapVersusHoldMs: UInt64 = Constants.fnTapVersusHoldMs
    ) -> FnHotkeyReleaseDisposition {
        switch triggerMode {
        case .toggle:
            if longPressArmed { return .ignore }
            if elapsedMs < Double(tapVersusHoldMs) { return .emitToggle }
            return .ignore
        case .push:
            if longPressArmed { return .emitLongPressUp }
            return .ignore
        }
    }
}
