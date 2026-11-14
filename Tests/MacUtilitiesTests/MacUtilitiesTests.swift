import Testing
import Foundation
import CoreGraphics
import AppPluginHost
import IOKit.pwr_mgt
@testable import MacUtilitiesIntegration

@MainActor
private final class FakeDriver: UtilityDriver {
    var result = UtilityStatus.active
    var active = false
    var acquisitions = 0
    var releases = 0
    func start() -> UtilityStatus {
        if result == .active, !active { active = true; acquisitions += 1 }
        if result != .active { stop() }
        return result
    }
    func stop() {
        if active { releases += 1; active = false }
    }
}

private final class FakeScrollTap: ScrollTap {
    var isActive = true
}

@Suite("MacUtilitiesTests")
struct MacUtilitiesTests {
    @Test @MainActor func scrollDriverHandlesPermissionCreationFailureInterruptionAndRelease() {
        var trusted = false
        var creates = 0
        var creationSucceeds = true
        weak var current: FakeScrollTap?
        let driver = ScrollReverseDriver(isTrusted: { trusted }, makeTap: {
            creates += 1
            guard creationSucceeds else { return nil }
            let tap = FakeScrollTap(); current = tap; return tap
        })
        #expect(driver.start() == .permissionRequired && creates == 0)
        trusted = true; creationSucceeds = false
        #expect(driver.start() == .failed(-1) && current == nil)
        creationSucceeds = true
        #expect(driver.start() == .active && creates == 2)
        #expect(driver.start() == .active && creates == 2)
        weak var interrupted = current
        current?.isActive = false
        #expect(driver.start() == .active && creates == 3 && interrupted == nil)
        interrupted = current
        trusted = false
        #expect(driver.start() == .permissionRequired && current == nil && interrupted == nil)
        trusted = true
        #expect(driver.start() == .active)
        driver.stop(); driver.stop()
        #expect(current == nil)
    }

    @Test @MainActor func effectsRequireBothEnableAndRunningHost() {
        let driver = FakeDriver()
        let model = UtilityController(id: "fixture", driver: driver)
        #expect(!model.enabled && model.status == .off && driver.acquisitions == 0)
        model.start()
        model.refreshData()
        #expect(driver.acquisitions == 0)
        model.setEnabled(true)
        #expect(driver.active && driver.acquisitions == 1)
        #expect(model.status == .active && model.connectionState == .ready)
        #expect(!model.isRunning, "A long-lived utility must not block application updates")
        model.start()
        model.refreshData()
        #expect(driver.acquisitions == 1)
        model.stop()
        model.stop()
        model.refreshData()
        #expect(driver.releases == 1 && !driver.active && model.status == .off)
        #expect(model.enabled, "Host shutdown preserves the catalog's enabled choice")
        model.start()
        #expect(driver.acquisitions == 2)
        model.setEnabled(false)
        model.start()
        #expect(driver.releases == 2 && !driver.active && model.connectionState == .off)
    }

    @Test @MainActor func enablingBeforeHostStartDoesNotAcquireResources() {
        let driver = FakeDriver()
        let model = UtilityController(id: "fixture", driver: driver)
        model.setEnabled(true)
        model.refreshData()
        #expect(driver.acquisitions == 0)
        model.start()
        #expect(driver.acquisitions == 1)
        model.stop()
    }

    @Test @MainActor func permissionFailureRetryAndRevocationAreVisible() {
        let driver = FakeDriver()
        driver.result = .permissionRequired
        let model = UtilityController(id: "fixture", driver: driver)
        model.setEnabled(true)
        model.start()
        #expect(model.connectionState == .setup && !driver.active)
        driver.result = .failed(-1)
        model.refreshData()
        #expect(model.connectionState == .attention && !driver.active)
        driver.result = .active
        model.refreshData()
        #expect(model.connectionState == .ready && driver.active)
        driver.result = .permissionRequired
        model.refreshData()
        #expect(model.connectionState == .setup && driver.releases == 1)
        model.setEnabled(false)
        driver.result = .active
        model.refreshData()
        #expect(!driver.active && model.status == .off)
    }

    @Test @MainActor func releasingControllerStopsItsEffect() async {
        let driver = FakeDriver()
        var model: UtilityController? = UtilityController(id: "fixture", driver: driver)
        model?.setEnabled(true)
        model?.start()
        #expect(driver.active)
        model = nil
        for _ in 0..<20 where driver.active { await Task.yield() }
        #expect(!driver.active && driver.releases == 1)
    }

    @Test func zeroAndExtremeWheelValuesDoNotOverflow() {
        let event = wheel()
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: Int64(Int16.min))
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64(Int32.min))
        #expect(event.getIntegerValueField(.scrollWheelEventDeltaAxis1) == Int64(Int16.min))
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: 0)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: -32768)
        ScrollWheelTransform.apply(to: event)
        #expect(event.getIntegerValueField(.scrollWheelEventDeltaAxis1) == Int64(Int16.max))
        #expect(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) == Int64(Int32.max))
        #expect(event.getIntegerValueField(.scrollWheelEventDeltaAxis2) == 0)
        #expect(event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1) > 32767)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["HAPPY_LULU_TEST_POWER_ASSERTION"] == "1"))
    @MainActor func nativeDisplayAssertionIsAcquiredOnceAndReleased() throws {
        func ownedAssertions() throws -> Int {
            var result: Unmanaged<CFDictionary>?
            try #require(IOPMCopyAssertionsByProcess(&result) == kIOReturnSuccess)
            let byProcess = try #require(result?.takeRetainedValue() as? [NSNumber: [[String: Any]]])
            return (byProcess[NSNumber(value: ProcessInfo.processInfo.processIdentifier)] ?? []).filter {
                $0[kIOPMAssertionNameKey] as? String == "HappyLulu — Keep display awake"
            }.count
        }
        let before = try ownedAssertions()
        let driver = KeepAwakeDriver()
        defer { driver.stop() }
        #expect(driver.start() == .active)
        #expect(driver.start() == .active)
        #expect(try ownedAssertions() == before + 1)
        driver.stop()
        driver.stop()
        #expect(try ownedAssertions() == before)
    }

    private func wheel(continuous: Int64 = 0, phase: Int64 = 0, momentum: Int64 = 0) -> CGEvent {
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: 3, wheel2: -2, wheel3: 0)!
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: continuous)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: 24)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: -16)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 3.5)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: -2.25)
        event.flags = [.maskShift]
        return event
    }

    @Test func reversesBothWheelAxesAndPreservesEventMetadata() {
        let event = wheel()
        let timestamp = event.timestamp
        ScrollWheelTransform.apply(to: event)
        #expect(event.getIntegerValueField(.scrollWheelEventDeltaAxis1) == -3)
        #expect(event.getIntegerValueField(.scrollWheelEventDeltaAxis2) == 2)
        #expect(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) == -24)
        #expect(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2) == 16)
        #expect(event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1) == -3.5)
        #expect(event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2) == 2.25)
        #expect(event.timestamp == timestamp && event.flags == [.maskShift])
        #expect(event.type == .scrollWheel)
    }

    @Test func continuousPhaseAndMomentumEventsRemainByteIdentical() {
        for event in [wheel(continuous: 1), wheel(phase: 1), wheel(momentum: 1), CGEvent(source: nil)!] {
            let original = event.data as Data?
            ScrollWheelTransform.apply(to: event)
            #expect(event.data as Data? == original)
        }
    }
}
