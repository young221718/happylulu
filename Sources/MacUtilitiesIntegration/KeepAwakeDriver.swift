import Foundation
import IOKit.pwr_mgt

@MainActor
final class KeepAwakeDriver: UtilityDriver {
    private var assertion: IOPMAssertionID?

    func start() -> UtilityStatus {
        if assertion != nil { return .active }
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn), "HappyLulu — Keep display awake" as CFString, &id)
        guard result == kIOReturnSuccess else { return .failed(result) }
        assertion = id
        return .active
    }

    func stop() {
        guard let id = assertion else { return }
        IOPMAssertionRelease(id)
        assertion = nil
    }

    deinit { if let assertion { IOPMAssertionRelease(assertion) } }
}
