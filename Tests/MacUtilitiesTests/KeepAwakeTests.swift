import Foundation
import Testing
@testable import MacUtilitiesIntegration

private final class TestPowerAssertion: PowerAssertion {
    var isApplied = true
    var releases = 0
    func release() { releases += 1; isApplied = false }
}

@Suite("KeepAwakeTests")
struct KeepAwakeTests {
    @Test @MainActor func controllerReleaseStopsActiveAssertion() async {
        let defaults = UserDefaults(suiteName: "KeepAwakeTests-" + UUID().uuidString)!
        let assertion = TestPowerAssertion()
        let driver = KeepAwakeDriver(makeAssertion: { _, _ in .created(assertion) })
        var model: KeepAwakeController? = KeepAwakeController(driver: driver, settings: KeepAwakeSettings(defaults: defaults))
        model?.setEnabled(true); model?.start()
        #expect(model?.status == .active)
        model = nil
        for _ in 0..<20 where assertion.releases == 0 { await Task.yield() }
        #expect(assertion.releases == 1)
    }

    @Test @MainActor func inactiveNewAssertionIsReleasedAndIndefiniteSessionHasNoTimeout() {
        let defaults = UserDefaults(suiteName: "KeepAwakeTests-" + UUID().uuidString)!
        let assertion = TestPowerAssertion()
        assertion.isApplied = false
        var timeout: TimeInterval? = 99
        let driver = KeepAwakeDriver(makeAssertion: { _, seconds in timeout = seconds; return .created(assertion) })
        let model = KeepAwakeController(driver: driver, settings: KeepAwakeSettings(defaults: defaults))
        model.setEnabled(true); model.start()
        #expect(timeout == nil && assertion.releases == 1 && model.status == .failed(-3))
        #expect(model.deadline == nil && model.connectionState == .attention)
        model.stop()
    }

    @Test @MainActor func timedSessionExpiresWithoutReacquiringAndCanRestartFromOwlControl() {
        let defaults = UserDefaults(suiteName: "KeepAwakeTests-" + UUID().uuidString)!
        var clock = Date(timeIntervalSince1970: 1_000)
        var assertions: [TestPowerAssertion] = []
        var requests: [(KeepAwakeMode, TimeInterval?)] = []
        let driver = KeepAwakeDriver(makeAssertion: { mode, timeout in
            requests.append((mode, timeout))
            let assertion = TestPowerAssertion(); assertions.append(assertion)
            return .created(assertion)
        })
        let model = KeepAwakeController(driver: driver, settings: KeepAwakeSettings(defaults: defaults), now: { clock })
        model.selectDuration(.minutes15)
        model.setEnabled(true)
        #expect(assertions.isEmpty && model.menuBarItem == nil)
        model.start()
        #expect(model.status == .active && model.isKeepAwakeApplied)
        #expect(model.menuBarItem?.title.isEmpty == false, "The shared popover must not show an unnamed settings row")
        #expect(model.deadline == Date(timeIntervalSince1970: 1_900))
        #expect(requests.count == 1 && requests[0].0 == .displayAndSystem && requests[0].1 == 900)
        let activeIcon = model.menuBarItem?.iconPNG
        clock = Date(timeIntervalSince1970: 1_899)
        model.refreshData()
        #expect(model.status == .active && assertions.count == 1)
        clock = Date(timeIntervalSince1970: 1_900)
        model.refreshData(); model.refreshData()
        #expect(model.status == .off && model.didExpire && model.enabled)
        #expect(assertions.count == 1 && assertions[0].releases == 1)
        #expect(!model.isKeepAwakeApplied && model.menuBarItem?.iconPNG != activeIcon)
        model.toggleSession()
        #expect(model.status == .active && !model.didExpire && assertions.count == 2)
        #expect(model.deadline == Date(timeIntervalSince1970: 2_800))
        model.toggleSession()
        model.refreshData()
        #expect(model.status == .off && model.enabled && assertions[1].releases == 1 && assertions.count == 2)
        model.stop()
        #expect(model.menuBarItem == nil)
    }

    @Test @MainActor func optionsPersistWithoutEnablingAndModeChangeReleasesPreviousAssertion() {
        let defaults = UserDefaults(suiteName: "KeepAwakeTests-" + UUID().uuidString)!
        var assertions: [TestPowerAssertion] = []
        var modes: [KeepAwakeMode] = []
        let driver = KeepAwakeDriver(makeAssertion: { mode, _ in
            modes.append(mode)
            let assertion = TestPowerAssertion(); assertions.append(assertion)
            return .created(assertion)
        })
        let model = KeepAwakeController(driver: driver, settings: KeepAwakeSettings(defaults: defaults))
        model.selectMode(.system)
        model.selectDuration(.hour)
        #expect(assertions.isEmpty)
        let restored = KeepAwakeSettings(defaults: defaults)
        #expect(restored.mode == .system && restored.duration == .hour)
        model.setEnabled(true); model.start()
        #expect(modes == [.system])
        model.selectMode(.displayAndSystem)
        #expect(modes == [.system, .displayAndSystem] && assertions[0].releases == 1)
        model.setEnabled(false); model.stop()
        #expect(assertions[1].releases == 1 && model.deadline == nil)
        #expect(restored.mode == .displayAndSystem && restored.duration == .hour)
    }

    @Test @MainActor func creationAndReadbackFailuresNeverClaimActiveAndReleaseResources() {
        let defaults = UserDefaults(suiteName: "KeepAwakeTests-" + UUID().uuidString)!
        var shouldFail = true
        var assertion = TestPowerAssertion()
        let driver = KeepAwakeDriver(makeAssertion: { _, _ in
            shouldFail ? .failed(-45) : .created(assertion)
        })
        let model = KeepAwakeController(driver: driver, settings: KeepAwakeSettings(defaults: defaults))
        model.setEnabled(true); model.start()
        #expect(model.status == .failed(-45) && !model.isKeepAwakeApplied && model.deadline == nil)
        shouldFail = false
        model.toggleSession()
        #expect(model.status == .active && model.isKeepAwakeApplied)
        assertion.isApplied = false
        model.refreshData()
        #expect(model.status == .failed(-3) && !model.isKeepAwakeApplied && assertion.releases == 1)
        model.refreshData()
        #expect(model.status == .failed(-3), "Failed readback must require explicit retry")
        assertion = TestPowerAssertion()
        model.toggleSession()
        #expect(model.status == .active)
        model.stop(); model.stop()
        #expect(assertion.releases == 1 && !model.isKeepAwakeApplied)
    }

    @Test @MainActor func invalidStoredOptionsFallBackWithoutChangingOtherPreferences() {
        let defaults = UserDefaults(suiteName: "KeepAwakeTests-" + UUID().uuidString)!
        defaults.set("old-unknown", forKey: KeepAwakeSettings.modeKey)
        defaults.set(-30, forKey: KeepAwakeSettings.durationKey)
        defaults.set("preserve", forKey: "other-setting")
        let settings = KeepAwakeSettings(defaults: defaults)
        #expect(settings.mode == .displayAndSystem && settings.duration == .indefinite)
        #expect(defaults.string(forKey: "other-setting") == "preserve")
    }
}
