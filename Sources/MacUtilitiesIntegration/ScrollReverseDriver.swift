import ApplicationServices
import Foundation

protocol ScrollTap: AnyObject {
    var isActive: Bool { get }
}

/// Owns the native handles without a callback context pointing to a Swift owner.
/// Core Foundation invalidation/removal also clean up when ARC releases off-main.
private final class ScrollEventTap: ScrollTap {
    let port: CFMachPort
    private let source: CFRunLoopSource
    var isActive: Bool { CFMachPortIsValid(port) && CGEvent.tapIsEnabled(tap: port) }

    init?() {
        let mask = CGEventMask(1) << CGEventType.scrollWheel.rawValue
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, _ in
                if type == .scrollWheel { ScrollWheelTransform.apply(to: event) }
                // Disabled taps are detected/recreated by the controller's status check.
                return Unmanaged.passUnretained(event)
            }, userInfo: nil) else { return nil }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            CFMachPortInvalidate(port)
            return nil
        }
        self.port = port
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
    }

    deinit {
        CGEvent.tapEnable(tap: port, enable: false)
        CFMachPortInvalidate(port)
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
    }
}

@MainActor
final class ScrollReverseDriver: UtilityDriver {
    private var tap: (any ScrollTap)?
    private let isTrusted: () -> Bool
    private let makeTap: () -> (any ScrollTap)?

    init(isTrusted: @escaping () -> Bool = { AXIsProcessTrusted() },
         makeTap: @escaping () -> (any ScrollTap)? = { ScrollEventTap() }) {
        self.isTrusted = isTrusted
        self.makeTap = makeTap
    }

    func start() -> UtilityStatus {
        guard isTrusted() else {
            stop()
            return .permissionRequired
        }
        if let tap, tap.isActive { return .active }
        stop()
        guard let newTap = makeTap() else { return .failed(-1) }
        guard newTap.isActive else { return .failed(-2) }
        tap = newTap
        return .active
    }

    func stop() { tap = nil }
}
