//
//  FloatingTriggerGestureModifier.swift
//  vilsay
//

import SwiftUI

/// Push / Toggle 手势 → `Pipeline`（Week 3）。
/// 注意：不可标为 `private`，否则同模块内其他文件无法使用（Swift 的 `private` 仅当前文件可见）。
struct FloatingTriggerGestureModifier: ViewModifier {
    @ObservedObject private var state = AppState.shared

    func body(content: Content) -> some View {
        if state.triggerMode == .push {
            content.gesture(pushHoldGesture)
        } else {
            content.onTapGesture(perform: toggleTap)
        }
    }

    private var pushHoldGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                state.isPushPressed = true
                Pipeline.shared.onHotkeyPushDown()
            }
            .onEnded { _ in
                state.isPushPressed = false
                Task { await Pipeline.shared.onHotkeyPushUp() }
            }
    }

    private func toggleTap() {
        Task { await Pipeline.shared.toggleRecording() }
    }
}
