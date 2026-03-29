//
//  main.swift
//  HotkeyMonitor
//
//  子进程无音频栈：不得 import AVFoundation 或任何录音 API。
//

import Foundation

let service = HotkeyMonitorService()
service.run()
RunLoop.main.run()
