import Foundation
import IOKit.pwr_mgt

protocol PowerAssertion: AnyObject {
    var isApplied: Bool { get }
    func release()
}

enum PowerAssertionCreation {
    case created(any PowerAssertion), failed(Int32)
}

private final class NativePowerAssertion: PowerAssertion {
    private var id: IOPMAssertionID?
    init(id: IOPMAssertionID) { self.id = id }
    var isApplied: Bool {
        guard let id, let properties = IOPMAssertionCopyProperties(id)?.takeRetainedValue() as? [String: Any] else { return false }
        return (properties[kIOPMAssertionLevelKey] as? NSNumber)?.intValue == kIOPMAssertionLevelOn
    }
    func release() {
        guard let id else { return }
        IOPMAssertionRelease(id)
        self.id = nil
    }
    deinit { if let id { IOPMAssertionRelease(id) } }

    static func create(mode: KeepAwakeMode, timeout: TimeInterval?) -> PowerAssertionCreation {
        var properties: [String: Any] = [
            kIOPMAssertionTypeKey: mode == .system ? kIOPMAssertionTypePreventUserIdleSystemSleep : kIOPMAssertionTypePreventUserIdleDisplaySleep,
            kIOPMAssertionNameKey: mode == .system ? "HappyLulu — Keep system awake" : "HappyLulu — Keep display awake",
            kIOPMAssertionLevelKey: kIOPMAssertionLevelOn
        ]
        if let timeout {
            properties[kIOPMAssertionTimeoutKey] = timeout
            properties[kIOPMAssertionTimeoutActionKey] = kIOPMAssertionTimeoutActionRelease
        }
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithProperties(properties as CFDictionary, &id)
        guard result == kIOReturnSuccess else { return .failed(result) }
        return .created(NativePowerAssertion(id: id))
    }
}

@MainActor
final class KeepAwakeDriver: UtilityDriver {
    private var assertion: (any PowerAssertion)?
    private let makeAssertion: (KeepAwakeMode, TimeInterval?) -> PowerAssertionCreation
    var mode = KeepAwakeMode.displayAndSystem
    var timeout: TimeInterval?

    init(makeAssertion: @escaping (KeepAwakeMode, TimeInterval?) -> PowerAssertionCreation = NativePowerAssertion.create) {
        self.makeAssertion = makeAssertion
    }

    func start() -> UtilityStatus {
        if assertion == nil {
            switch makeAssertion(mode, timeout) {
            case .failed(let code): return .failed(code)
            case .created(let value): assertion = value
            }
        }
        guard assertion?.isApplied == true else { stop(); return .failed(-3) }
        return .active // Applied OS request; this does not guarantee lid-closed operation.
    }

    func stop() {
        assertion?.release()
        assertion = nil
    }
}
