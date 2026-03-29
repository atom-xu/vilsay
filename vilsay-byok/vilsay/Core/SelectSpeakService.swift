//
//  SelectSpeakService.swift
//  vilsay
//

import ApplicationServices
import Foundation

/// W3-10：改词选区读取已迁至 `TargetAppMonitor.getSelectedText()`（按目标 PID 取 AX）。
enum SelectSpeakService {
    static func getSelectedText() -> String? {
        TargetAppMonitor.shared.getSelectedText()
    }
}
