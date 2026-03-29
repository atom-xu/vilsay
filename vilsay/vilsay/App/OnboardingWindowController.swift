//
//  OnboardingWindowController.swift
//  vilsay
//

import AppKit
import SwiftUI

/// W2-04：首次启动引导窗口。
final class OnboardingWindowController {
    private var window: NSWindow?

    func showIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: UserDefaultsKeys.onboardingDone) else { return }

        let view = OnboardingView { [weak self] in
            self?.close()
        }
        let host = NSHostingController(rootView: view)
        host.view.translatesAutoresizingMaskIntoConstraints = false

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        w.title = "欢迎使用 Vilsay"
        w.contentViewController = host
        w.setContentSize(NSSize(width: 480, height: 560))
        w.isReleasedWhenClosed = false
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w
    }

    func close() {
        window?.close()
        window = nil

        // UX Fix #1：Onboarding 完成后显示主窗口
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            for w in NSApp.windows {
                if (w.identifier?.rawValue == "main" || w.title == "Vilsay"),
                   w.title != "欢迎使用 Vilsay" {
                    w.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                    break
                }
            }
        }
    }
}
