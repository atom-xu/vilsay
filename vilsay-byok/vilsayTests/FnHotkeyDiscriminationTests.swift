//
//  FnHotkeyDiscriminationTests.swift
//

import Testing
@testable import vilsay

struct FnHotkeyDiscriminationTests {

    @Test func toggleMode_shortTap_emitsToggle() {
        let d = FnHotkeyDiscrimination.dispositionOnRelease(
            triggerMode: .toggle,
            elapsedMs: 100,
            longPressArmed: false,
            tapVersusHoldMs: 250
        )
        #expect(d == .emitToggle)
    }

    @Test func toggleMode_longHold_releaseIgnores() {
        let d = FnHotkeyDiscrimination.dispositionOnRelease(
            triggerMode: .toggle,
            elapsedMs: 400,
            longPressArmed: false,
            tapVersusHoldMs: 250
        )
        #expect(d == .ignore)
    }

    @Test func pushMode_longPressArmed_emitsLongPressUp() {
        let d = FnHotkeyDiscrimination.dispositionOnRelease(
            triggerMode: .push,
            elapsedMs: 400,
            longPressArmed: true,
            tapVersusHoldMs: 250
        )
        #expect(d == .emitLongPressUp)
    }

    @Test func pushMode_shortTap_ignores() {
        let d = FnHotkeyDiscrimination.dispositionOnRelease(
            triggerMode: .push,
            elapsedMs: 100,
            longPressArmed: false,
            tapVersusHoldMs: 250
        )
        #expect(d == .ignore)
    }

    @Test func pushMode_longButNotArmed_ignores() {
        let d = FnHotkeyDiscrimination.dispositionOnRelease(
            triggerMode: .push,
            elapsedMs: 300,
            longPressArmed: false,
            tapVersusHoldMs: 250
        )
        #expect(d == .ignore)
    }

    @Test func toggleMode_boundaryUnder250_toggle() {
        let d = FnHotkeyDiscrimination.dispositionOnRelease(
            triggerMode: .toggle,
            elapsedMs: 249,
            longPressArmed: false,
            tapVersusHoldMs: 250
        )
        #expect(d == .emitToggle)
    }
}
