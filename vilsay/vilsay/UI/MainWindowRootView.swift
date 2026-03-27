//
//  MainWindowRootView.swift
//  vilsay
//

import SwiftUI
import AppKit

/// 主窗口根视图：NavigationSplitView（侧边栏 + 详情区）。
struct MainWindowRootView: View {
    @ObservedObject private var state = AppState.shared

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $state.selectedNavItem)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
        } detail: {
            // TitlebarSeparatorRemover 放在 detail 列内容的 background：
            // updateNSView 会随每次 SwiftUI re-render 触发，在 layout pass 结束后
            // 用 async 重新覆盖 SwiftUI 对 titlebarSeparatorStyle 的默认设置。
            detailView
                .background(TitlebarSeparatorRemover())
        }
        .frame(minWidth: 760, minHeight: 540)
        .task {
            await AuthService.shared.restoreSession()
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch state.selectedNavItem {
        case .dashboard:
            DashboardView()
        case .history:
            HistoryView()
        case .dictionary:
            DictionaryView()
        case .settings:
            SettingsRootView()
        }
    }
}

// MARK: - Titlebar separator remover

/// 关键：SwiftUI 在每次 re-render 后会重置 window.titlebarSeparatorStyle。
/// 用 DispatchQueue.main.async（无延迟）确保在当前 layout pass 结束「之后」执行，
/// 从而覆盖 SwiftUI 的默认值。updateNSView 随每次 SwiftUI 更新触发，持续生效。
/// 使用 nsView.window（非 NSApp.windows）—— updateNSView 调用时 view 已在 window 层级中。
private struct TitlebarSeparatorRemover: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        NSView()
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            nsView.window?.titlebarSeparatorStyle = .none
        }
    }
}
