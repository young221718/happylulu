import AppPluginCore
import AppPluginHost
import Combine
import Foundation
import SwiftUI

@MainActor
final class KeepAwakeController: ObservableObject, PluginController, PluginMenuBarProviding, PluginPanelProviding {
    let descriptor = PluginDescriptor(id: KeepAwakeModule.id, name: "Keep Awake")
    @Published private(set) var enabled = false
    @Published private(set) var status = UtilityStatus.off
    @Published private(set) var mode: KeepAwakeMode
    @Published private(set) var duration: KeepAwakeDuration
    @Published private(set) var deadline: Date?
    @Published private(set) var didExpire = false
    private let driver: KeepAwakeDriver
    private let settings: KeepAwakeSettings
    private let now: () -> Date
    let localize: PluginLocalizer
    private var started = false
    private var sessionRequested = true
    private var timer: AnyCancellable?
    var changes: AnyPublisher<Void, Never> { objectWillChange.map { _ in () }.eraseToAnyPublisher() }
    var isRunning: Bool { false }
    var isKeepAwakeApplied: Bool { status == .active }
    var connectionState: PluginConnectionState {
        switch status {
        case .active: .ready
        case .failed: .attention
        case .permissionRequired: .setup
        case .off: .off
        }
    }
    var panelView: AnyView { AnyView(KeepAwakeControlView(model: self)) }
    var panelHeight: CGFloat { 52 }
    var menuBarItem: PluginMenuBarItem? {
        guard started && enabled else { return nil }
        let title: String
        switch status {
        case .active: title = localize("유지 중", "Awake")
        case .failed, .permissionRequired: title = localize("실패", "Failed")
        case .off: title = localize("해제됨", "Off")
        }
        return PluginMenuBarItem(id: descriptor.id, title: title, accessibilityLabel: statusText,
            iconPNG: KeepAwakeOwl.png(active: isKeepAwakeApplied), iconIsTemplate: true)
    }
    var statusText: String {
        switch status {
        case .active: localize("잠자기 방지 요청 적용 중", "Keep-awake request applied")
        case .failed(let code): localize("잠자기 방지 실패 (\(code))", "Keep-awake failed (\(code))")
        case .off: didExpire ? localize("시간 종료 · 해제됨", "Timer ended · released") : localize("잠자기 방지 꺼짐", "Keep awake off")
        case .permissionRequired: localize("권한 필요", "Permission required")
        }
    }
    init(driver: KeepAwakeDriver = KeepAwakeDriver(), settings: KeepAwakeSettings = KeepAwakeSettings(),
         now: @escaping () -> Date = Date.init, localize: @escaping PluginLocalizer = { ko, _ in ko }) {
        self.driver = driver; self.settings = settings; self.now = now; self.localize = localize
        mode = settings.mode; duration = settings.duration
    }
    deinit {
        let driver = driver
        Task { @MainActor in driver.stop() }
    }
    func setEnabled(_ value: Bool) {
        if value && !enabled { sessionRequested = true; didExpire = false }
        enabled = value
        reconcile()
    }
    func start() { started = true; reconcile() }
    func stop() { started = false; reconcile() }
    func refreshData() { reconcile() }
    func toggleSession() {
        guard started && enabled else { return }
        sessionRequested = !isKeepAwakeApplied
        driver.stop(); deadline = nil; didExpire = false; status = .off
        reconcile()
    }
    func selectMode(_ value: KeepAwakeMode) {
        guard value != mode else { return }
        settings.mode = value; mode = value
        restartIfRequested()
    }
    func selectDuration(_ value: KeepAwakeDuration) {
        guard value != duration else { return }
        settings.duration = value; duration = value
        restartIfRequested()
    }
    private func restartIfRequested() {
        driver.stop(); deadline = nil; status = .off
        reconcile()
    }
    private func reconcile() {
        guard started && enabled && sessionRequested else {
            timer = nil; driver.stop(); deadline = nil
            if status != .off { status = .off }
            return
        }
        if let deadline, now() >= deadline {
            sessionRequested = false; didExpire = true
            reconcile()
            return
        }
        // Fail closed after creation/readback errors until the user explicitly retries.
        if case .failed = status { return }
        driver.mode = mode
        driver.timeout = duration.seconds
        let next = driver.start()
        if next == .active && status != .active { deadline = duration.seconds.map { now().addingTimeInterval($0) } }
        if next != .active { driver.stop(); deadline = nil; timer = nil }
        if status != next { status = next }
        if next == .active && timer == nil {
            timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect().sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.refreshData() }
            }
        }
    }
}
