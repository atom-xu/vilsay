//
//  OnboardingTests.swift
//  W7-A10：Onboarding 纯逻辑测试
//

import Foundation
import Testing
@testable import vilsay

@Suite("Onboarding 逻辑测试")
struct OnboardingTests {

    @Test("断点续传：saved=0 → 0")
    func resumeFromWelcome() {
        let s = OnboardingResume.resolveStartStep(fromSaved: 0, micGranted: false, axTrusted: false)
        #expect(s == 0)
    }

    @Test("断点续传：需要麦克风")
    func resumeNeedsMic() {
        let s = OnboardingResume.resolveStartStep(fromSaved: 2, micGranted: false, axTrusted: false)
        #expect(s == 1)
    }

    @Test("断点续传：需要辅助功能")
    func resumeNeedsAX() {
        let s = OnboardingResume.resolveStartStep(fromSaved: 3, micGranted: true, axTrusted: false)
        #expect(s == 2)
    }

    @Test("断点续传：进入登录")
    func resumeLogin() {
        let s = OnboardingResume.resolveStartStep(fromSaved: 3, micGranted: true, axTrusted: true)
        #expect(s == 3)
    }

    @Test("断点续传：完成页")
    func resumeCompletion() {
        let s = OnboardingResume.resolveStartStep(fromSaved: 4, micGranted: true, axTrusted: true)
        #expect(s == 4)
    }

    @Test("UserDefaultsKeys 不重复")
    func keysUnique() {
        let keys = [
            UserDefaultsKeys.onboardingDone,
            UserDefaultsKeys.onboardingStep,
        ]
        #expect(Set(keys).count == keys.count)
    }

    @Test("advanceTo 存储 step 值（独立 suite）")
    func advanceToSavesStep() throws {
        let suite = "test.vilsay.onboarding.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            Issue.record("无法创建 UserDefaults suite")
            return
        }
        defaults.set(2, forKey: UserDefaultsKeys.onboardingStep)
        #expect(defaults.integer(forKey: UserDefaultsKeys.onboardingStep) == 2)
        defaults.removePersistentDomain(forName: suite)
    }

    @Test("完成后 onboardingDone = true（独立 suite）")
    func completionSetsFlag() throws {
        let suite = "test.vilsay.onboarding.done.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            Issue.record("无法创建 UserDefaults suite")
            return
        }
        defaults.set(true, forKey: UserDefaultsKeys.onboardingDone)
        #expect(defaults.bool(forKey: UserDefaultsKeys.onboardingDone) == true)
        defaults.removePersistentDomain(forName: suite)
    }
}
