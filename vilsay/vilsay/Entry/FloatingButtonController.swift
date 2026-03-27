//
//  FloatingButtonController.swift
//

import AppKit
import Combine
import SwiftUI

/// NSPanel 悬浮按钮（TECH_ARCH 第四章）。
/// 在 `Pipeline` 捕获目标应用 PID 并准备录音后再 `showIfNeeded()`，避免过早抢焦点。
/// `NSHostingController` 内嵌 SwiftUI 时，单例 `ObservableObject` 的更新有时不触发重绘，故订阅 `objectWillChange` 并刷新 `rootView`。
final class FloatingButtonController {
    static let shared = FloatingButtonController()

    private var panel: NSPanel?
    private var hosting: NSHostingController<FloatingButtonView>?
    private var stateCancellable: AnyCancellable?

    private init() {}

    /// 首次调用时创建面板；之后根据 AppState 自动显示/隐藏。
    func showIfNeeded() {
        if let panel {
            panel.orderFrontRegardless()
            return
        }

        let host = NSHostingController(rootView: FloatingButtonView())
        hosting = host
        // W6-01：完成预览含「有误」按钮，略加宽避免截断
        let pillW: CGFloat = 300
        let pillH: CGFloat = 72   // 单行 bar ~40pt + 上下各 16pt 阴影空间
        host.view.frame = CGRect(x: 0, y: 0, width: pillW, height: pillH)
        host.view.wantsLayer = true
        host.view.layer?.backgroundColor = NSColor.clear.cgColor
        host.view.layer?.isOpaque = false

        let contentRect = NSRect(x: 0, y: 0, width: pillW, height: pillH)
        let panel = NSPanel(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.contentView = host.view
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // 关掉矩形窗口阴影，让 SwiftUI 的 shape-level shadow 按形状投影
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.setFrameAutosaveName("VilsayFloatingPill")

        if let screen = NSScreen.main {
            let vf = screen.visibleFrame
            let origin = NSPoint(
                x: vf.midX - pillW / 2,
                y: vf.minY + 60
            )
            panel.setFrameOrigin(origin)
        }

        self.panel = panel

        // 根据状态决定是否显示：仅 recording / processing / editMode / 预览时显示
        updateVisibility(panel: panel, status: AppState.shared.status)

        // 必须在下一轮 RunLoop 再改 rootView，否则易与当前 layout 重入触发
        stateCancellable = AppState.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { [weak self] in
                    guard let self, let host = self.hosting, let panel = self.panel else { return }
                    host.rootView = FloatingButtonView()
                    host.view.needsLayout = true
                    host.view.needsDisplay = true
                    self.updateVisibility(panel: panel, status: AppState.shared.status)
                }
            }
    }

    private func updateVisibility(panel: NSPanel, status: AppStatus) {
        let shouldShow: Bool
        let state = AppState.shared
        // 预览期间也显示
        let inPreview = state.floatingPreviewDismissAt.map { $0 > Date() } ?? false
        let hasTransientError = state.transientErrorFlash != nil
        shouldShow = status == .recording || status == .processing
            || status == .injecting || status == .editMode || inPreview || hasTransientError
        if shouldShow {
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
    }
}
