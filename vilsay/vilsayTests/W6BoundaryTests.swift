//
//  W6BoundaryTests.swift
//  W6-04：可自动化的边界/契约小集（无系统权限依赖）
//

import Foundation
import Testing
@testable import vilsay

@Suite("W6 边界与契约")
struct W6BoundaryTests {

    @Test("用量上报请求体字段为 snake_case，与 FastAPI 对齐")
    func usageRecordBodyUsesSnakeCase() throws {
        let body = UsageRecordAPIRequest(
            type: "polish",
            durationMs: 1200,
            asrProvider: "whisperKit",
            clientVersion: "1.2.3"
        )
        let enc = JSONEncoder()
        enc.keyEncodingStrategy = .convertToSnakeCase
        let data = try enc.encode(body)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(obj?["type"] as? String == "polish")
        #expect(obj?["duration_ms"] as? Int == 1200)
        #expect(obj?["asr_provider"] as? String == "whisperKit")
        #expect(obj?["client_version"] as? String == "1.2.3")
    }

    @Test("Onboarding：已具备双权限且 saved=2 时进入登录步")
    func onboardingResumeToLogin() {
        let step = OnboardingResume.resolveStartStep(fromSaved: 2, micGranted: true, axTrusted: true)
        #expect(step == 3)
    }

    @Test("浮层预览时长为正且合理（ms）")
    func floatingPillPreviewDuration() {
        #expect(Constants.floatingPillPreviewDurationMs > 0)
        #expect(Constants.floatingPillPreviewDurationMs <= 30_000)
    }

    @Test("性能目标死亡线已定义（W6-03 对照日志）")
    func latencyBudgetDefined() {
        #expect(Constants.maxTotalLatencyMs > 0)
        #expect(Constants.maxTotalLatencyMs <= 10_000)
    }
}
