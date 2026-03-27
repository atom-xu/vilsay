//
//  TuningDiagnosticTest.swift
//  临时诊断：确认测试进程能否读到 API Key
//

import Foundation
import Testing
@testable import vilsay

@Suite("调优诊断")
struct TuningDiagnosticTest {

    @Test("诊断: API Key 可达性")
    func apiKeyReachability() {
        let envKey = ProcessInfo.processInfo.environment["DASHSCOPE_API_KEY"]
        let appConfigKey = AppConfig.dashscopeAPIKey
        let helperKey = PromptTuningHelper.apiKey
        let udKey = UserDefaults.standard.string(forKey: "vilsay.dashscope_api_key")

        print("┌─── API Key 诊断 ───┐")
        print("│ ENV DASHSCOPE_API_KEY: \(envKey != nil ? "✅ 有值(\(envKey!.prefix(8))...)" : "❌ nil")")
        print("│ AppConfig.dashscopeAPIKey: \(appConfigKey != nil ? "✅ 有值(\(appConfigKey!.prefix(8))...)" : "❌ nil")")
        print("│ PromptTuningHelper.apiKey: \(helperKey != nil ? "✅ 有值(\(helperKey!.prefix(8))...)" : "❌ nil")")
        print("│ UserDefaults direct: \(udKey != nil ? "✅ 有值(\(udKey!.prefix(8))...)" : "❌ nil")")
        print("│ Bundle ID: \(Bundle.main.bundleIdentifier ?? "nil")")
        print("└────────────────────┘")

        // 写入文件供外部读取
        var info = "ENV: \(envKey != nil ? "YES" : "NO")\n"
        info += "AppConfig: \(appConfigKey != nil ? "YES" : "NO")\n"
        info += "Helper: \(helperKey != nil ? "YES" : "NO")\n"
        info += "UserDefaults: \(udKey != nil ? "YES" : "NO")\n"
        info += "BundleID: \(Bundle.main.bundleIdentifier ?? "nil")\n"
        try? info.write(toFile: "/tmp/vilsay_key_diag.txt", atomically: true, encoding: .utf8)

        let anyAvailable = envKey != nil || appConfigKey != nil || helperKey != nil
        #expect(anyAvailable, "所有 API Key 来源均为 nil")
    }
}
