import Testing
@testable import FirmingoWorkbenchCore

/// Foreground test admission holds the screen awake without replacing the original host policy on repeated updates.
@Test func foregroundTestRestoresTheOriginalIdleTimerSetting() {
    var policy = WorkbenchIdleTimerPolicy()
    let result1 = policy.update(isForeground: true, isRunning: false, currentValue: false)
    #expect(!result1)
    let result2 = policy.update(isForeground: true, isRunning: true, currentValue: false)
    #expect(result2)
    let result3 = policy.update(isForeground: true, isRunning: true, currentValue: true)
    #expect(result3)
    let result4 = policy.update(isForeground: true, isRunning: false, currentValue: true)
    #expect(!result4)
    let result5 = policy.update(isForeground: true, isRunning: false, currentValue: true)
    #expect(result5)
}

/// Real backgrounding releases ownership; return reacquires the current host setting and preserves an already-disabled timer.
@Test func backgroundReleasesIdlePreventionAndReturnCapturesTheCurrentSetting() {
    var policy = WorkbenchIdleTimerPolicy()
    let result6 = policy.update(isForeground: false, isRunning: true, currentValue: false)
    #expect(!result6)
    let result7 = policy.update(isForeground: true, isRunning: true, currentValue: false)
    #expect(result7)
    let result8 = policy.update(isForeground: false, isRunning: true, currentValue: true)
    #expect(!result8)
    let result9 = policy.update(isForeground: true, isRunning: true, currentValue: true)
    #expect(result9)
    let result10 = policy.update(isForeground: true, isRunning: false, currentValue: true)
    #expect(result10)
}
