import Combine
import Foundation
import AppPluginCore
import AppPluginHost

enum UtilityStatus: Equatable { case off, active, permissionRequired, failed(Int32) }

@MainActor
protocol UtilityDriver: AnyObject, Sendable {
    func start() -> UtilityStatus
    func stop()
}

@MainActor
final class UtilityController: ObservableObject, PluginController {
    let descriptor: PluginDescriptor
    @Published private(set) var enabled = false
    @Published private(set) var status = UtilityStatus.off
    private let driver: any UtilityDriver
    private var started = false
    private var statusTimer: AnyCancellable?
    var changes: AnyPublisher<Void, Never> { objectWillChange.map { _ in () }.eraseToAnyPublisher() }
    var isRunning: Bool { false }
    var connectionState: PluginConnectionState {
        switch status {
        case .off: .off
        case .active: .ready
        case .permissionRequired: .setup
        case .failed: .attention
        }
    }
    init(id: String, driver: any UtilityDriver) {
        descriptor = PluginDescriptor(id: id, name: id)
        self.driver = driver
    }
    deinit {
        // Host stop is synchronous. This fallback also works with Swift 6.0.
        let driver = driver
        Task { @MainActor in driver.stop() }
    }
    func setEnabled(_ value: Bool) {
        enabled = value
        reconcile()
    }
    func start() {
        started = true
        reconcile()
    }
    func stop() {
        started = false
        reconcile()
    }
    func refreshData() { reconcile() }

    private func reconcile() {
        guard started && enabled else {
            statusTimer = nil
            driver.stop()
            if status != .off { status = .off }
            return
        }
        let next = driver.start()
        if status != next { status = next }
        // Re-check revocation/tap interruption even when the settings page is closed.
        // start() is idempotent; this never displays a permission prompt.
        if statusTimer == nil {
            statusTimer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()
                .sink { [weak self] _ in
                    Task { @MainActor [weak self] in self?.refreshData() }
                }
        }
    }
}
