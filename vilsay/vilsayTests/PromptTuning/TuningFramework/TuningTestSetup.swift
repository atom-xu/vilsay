//
//  TuningTestSetup.swift
//  vilsay — 调优框架：测试环境初始化
//

import Foundation
@testable import vilsay

/// 调优测试的环境配置。在测试套件 init 或 setUp 中调用。
enum TuningTestSetup {

    /// 为 aiCommand 测试用例注册 UserDefaults override。
    /// 调用后 `com.vilsay.test.aicommand` 会被解析为 `.aiCommand` 模式。
    static func enableAICommandTestBundle() {
        OutputModeResolver.setUserOverride(
            bundleID: "com.vilsay.test.aicommand",
            mode: .aiCommand
        )
    }

    /// 清理 aiCommand 测试 override。
    static func disableAICommandTestBundle() {
        OutputModeResolver.setUserOverride(
            bundleID: "com.vilsay.test.aicommand",
            mode: nil
        )
    }

    /// 一次性设置所有测试用例需要的 override。
    static func setupAll() {
        enableAICommandTestBundle()
    }

    /// 清理所有测试 override。
    static func teardownAll() {
        disableAICommandTestBundle()
    }
}
