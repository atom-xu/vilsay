//
//  HotkeyComboLogicTests.swift
//  vilsayTests
//

import CoreGraphics
import Testing
@testable import vilsay

/// 组合键「是否应尝试 cancel」的纯逻辑模拟；不包含真实 `CGEventTap` / HID（需在真机用日志验收）。
struct HotkeyComboLogicTests {

    @Test func fnCombo_fnKeyAloneDoesNotTriggerCancelPredicate() {
        let fnKey: UInt16 = 0x3F
        #expect(
            HotkeyComboPredicate.shouldAttemptFnComboCancel(
                type: CGEventType.flagsChanged,
                keyCode: fnKey,
                fnIsPressed: true
            ) == false
        )
        #expect(
            HotkeyComboPredicate.shouldAttemptFnComboCancel(
                type: CGEventType.keyDown,
                keyCode: fnKey,
                fnIsPressed: true
            ) == false
        )
    }

    @Test func fnCombo_otherKeyWhileFnHeld_triggersPredicate() {
        #expect(
            HotkeyComboPredicate.shouldAttemptFnComboCancel(
                type: CGEventType.keyDown,
                keyCode: 3,
                fnIsPressed: true
            ) == true
        )
        #expect(
            HotkeyComboPredicate.shouldAttemptFnComboCancel(
                type: CGEventType.flagsChanged,
                keyCode: 96,
                fnIsPressed: true
            ) == true
        )
    }

    @Test func fnCombo_fnNotPressed_noPredicate() {
        #expect(
            HotkeyComboPredicate.shouldAttemptFnComboCancel(
                type: CGEventType.keyDown,
                keyCode: 3,
                fnIsPressed: false
            ) == false
        )
    }

    @Test func rightOptionCombo_predicateMatchesKeyDownOnly() {
        let rightOpt: UInt16 = 0x3D
        #expect(
            HotkeyComboPredicate.shouldAttemptRightOptionComboCancel(
                type: CGEventType.keyDown,
                keyCode: 40,
                rightOptionHeld: true
            ) == true
        )
        #expect(
            HotkeyComboPredicate.shouldAttemptRightOptionComboCancel(
                type: CGEventType.flagsChanged,
                keyCode: 40,
                rightOptionHeld: true
            ) == false
        )
        #expect(
            HotkeyComboPredicate.shouldAttemptRightOptionComboCancel(
                type: CGEventType.keyDown,
                keyCode: rightOpt,
                rightOptionHeld: true
            ) == false
        )
    }
}
