//
//  TextInjector.swift
//

import AppKit
import Carbon.HIToolbox

/// W3-08：剪贴板 + Cmd+V 注入。整段流式只在 **begin → 多次 pasteChunk → end** 各一次：开始时保存 `general.string`，结束时 **一次性** 还原。
enum TextInjector {
    private static var savedPasteboardString: String?
    private static var sessionOpen = false

    static func beginProtectedPasteSession() {
        guard !sessionOpen else { return }
        sessionOpen = true
        savedPasteboardString = NSPasteboard.general.string(forType: .string)
    }

    static func pasteChunk(_ text: String) {
        guard !text.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        simulatePaste()
    }

    static func endProtectedPasteSession() {
        guard sessionOpen else { return }
        sessionOpen = false
        let saved = savedPasteboardString
        savedPasteboardString = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let pb = NSPasteboard.general
            if let saved {
                pb.clearContents()
                pb.setString(saved, forType: .string)
            }
        }
    }

    static func insertAtFrontmost(_ text: String) {
        beginProtectedPasteSession()
        pasteChunk(text)
        endProtectedPasteSession()
    }

    private static func simulatePaste() {
        let src = CGEventSource(stateID: .hidSystemState)
        let vKey: CGKeyCode = CGKeyCode(kVK_ANSI_V)
        guard
            let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true),
            let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
