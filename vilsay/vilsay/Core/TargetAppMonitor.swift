//
//  TargetAppMonitor.swift
//

import AppKit
import ApplicationServices
import Foundation
/// 在显示悬浮 UI 之前捕获前台应用 PID，注入前再激活该应用，避免焦点被本应用抢走（参考 Kimi / VoiceInk）。
@MainActor
final class TargetAppMonitor {
    static let shared = TargetAppMonitor()

    private(set) var capturedPID: pid_t?
    private(set) var capturedAppName: String?
    /// V14：前台应用 Bundle ID，供 Prompt §A 与 raw_log.target_app_id。
    private(set) var capturedBundleIdentifier: String?

    private init() {}

    /// 在显示悬浮按钮等 UI **之前**调用，记录当前前台应用。
    func captureTargetApp() {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return
        }
        capturedPID = frontApp.processIdentifier
        capturedAppName = frontApp.localizedName
        capturedBundleIdentifier = frontApp.bundleIdentifier
    }

    /// 注入前将焦点切回目标应用。
    func activateTargetApp() -> Bool {
        guard let pid = capturedPID else { return false }
        guard let app = NSRunningApplication(processIdentifier: pid) else {
            return false
        }
        return app.activate(options: [.activateIgnoringOtherApps])
    }

    /// 改词模式：读取**已捕获应用**内焦点元素的选中文本（需辅助功能权限）。
    /// **注意**：在 `MainActor` 上同步调用时，若前台应用 AX 无响应会长时间卡住主线程；录音主链路请用 `getSelectedTextAsync()`。
    func getSelectedText() -> String? {
        guard let pid = capturedPID else { return nil }
        return Self.copySelectedText(for: pid)
    }

    /// 在后台执行 AX 读选区，并与超时竞速，**不阻塞** `MainActor`（避免「按 Fn 后整 app 假死、无浮窗无音效」）。
    func getSelectedTextAsync(timeoutNanoseconds: UInt64) async -> String? {
        guard let pid = capturedPID else { return nil }
        return await withTaskGroup(of: String?.self) { group in
            group.addTask {
                await Task.detached(priority: .userInitiated) {
                    Self.copySelectedText(for: pid)
                }.value
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                return nil
            }
            let first = await group.next()!
            group.cancelAll()
            return first
        }
    }

    /// 在任意线程调用；勿在 `MainActor` 上同步执行（可能阻塞）。
    private nonisolated static func copySelectedText(for pid: pid_t) -> String? {
        let appElement = AXUIElementCreateApplication(pid)
        var focusedElement: CFTypeRef?
        let fr = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        guard fr == .success, let focused = focusedElement else { return nil }
        let element = focused as! AXUIElement

        var selectedText: CFTypeRef?
        let sr = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedText)
        guard sr == .success, let str = selectedText as? String else { return nil }
        let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func clear() {
        capturedPID = nil
        capturedAppName = nil
        capturedBundleIdentifier = nil
    }
}
