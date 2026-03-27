//
//  vilsayApp.swift
//  vilsay
//
//  【唯一应用入口】整个 target 只能有一个 `@main`。
//  菜单栏 UI 由下方 `MenuBarExtra` + `MenuBarRootMenu` 声明式构建。
//  主窗口通过 `Window("Vilsay", id: "main")` 打开。
//

import SwiftUI

@main
struct vilsayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // 主窗口（侧边栏导航：仪表盘 / 历史 / 词典 / 用量 / 设置）
        Window("Vilsay", id: "main") {
            MainWindowRootView()
        }
        .defaultSize(width: 860, height: 620)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            // ⌘, 打开设置（替代原 Settings scene）
            CommandGroup(replacing: .appSettings) {
                Button("设置...") {
                    AppState.shared.selectedNavItem = .settings
                    openMainWindow()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }

        // 菜单栏常驻（后台快捷控制）
        MenuBarExtra {
            MenuBarRootMenu()
        } label: {
            MenuBarStatusLabel()
        }
        .menuBarExtraStyle(.menu)
    }

    private func openMainWindow() {
        for window in NSApp.windows {
            if window.identifier?.rawValue == "main" ||
               window.title == "Vilsay" {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            }
        }
        // Window scene 未创建时无法用 openWindow，靠 NSApp.activate 触发
        NSApp.activate(ignoringOtherApps: true)
    }
}
