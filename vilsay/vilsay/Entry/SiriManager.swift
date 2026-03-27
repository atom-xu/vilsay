//
//  SiriManager.swift
//  管理系统 Siri 的启用/禁用
//

import Foundation
import os.log

enum SiriManager {
    private static let log = Logger(subsystem: "com.vilsay.app", category: "SiriManager")
    
    /// 检查 Siri 是否已禁用
    static func isSiriDisabled() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        task.arguments = ["read", "com.apple.assistant.support", "Assistant Enabled"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            
            log.info("Siri 状态检查: \(output ?? "未知")")
            
            // 如果返回 "0" 或 "false"，说明已禁用
            return output == "0" || output?.lowercased() == "false"
        } catch {
            log.error("检查 Siri 状态失败: \(error.localizedDescription)")
            return false
        }
    }
    
    /// 禁用 Siri（需要用户授权）
    static func disableSiri() async throws {
        log.info("正在禁用系统 Siri...")
        
        // 构建 AppleScript（需要用户授权）
        let script = """
        do shell script "defaults write com.apple.assistant.support 'Assistant Enabled' -bool false && \
        defaults write com.apple.Siri VoiceTriggerUserEnabled -bool false && \
        killall Siri 2>/dev/null || true" with administrator privileges
        """
        
        try await executeAppleScript(script)
        log.info("✅ Siri 已禁用")
    }
    
    /// 启用 Siri
    static func enableSiri() async throws {
        log.info("正在启用系统 Siri...")
        
        let script = """
        do shell script "defaults write com.apple.assistant.support 'Assistant Enabled' -bool true && \
        defaults write com.apple.Siri VoiceTriggerUserEnabled -bool true" with administrator privileges
        """
        
        try await executeAppleScript(script)
        log.info("✅ Siri 已启用")
    }
    
    // MARK: - Private Helpers
    
    private static func executeAppleScript(_ source: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global().async {
                var error: NSDictionary?
                
                guard let scriptObject = NSAppleScript(source: source) else {
                    continuation.resume(throwing: NSError(
                        domain: "SiriManager",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "无法创建 AppleScript"]
                    ))
                    return
                }
                
                scriptObject.executeAndReturnError(&error)
                
                if let error = error {
                    continuation.resume(throwing: NSError(
                        domain: "SiriManager",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "执行失败: \(error.description)"]
                    ))
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
