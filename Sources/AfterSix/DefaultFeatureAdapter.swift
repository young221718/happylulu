import Foundation
import Combine
import AppPluginCore
import AppPluginHost
import CalendarSyncServices

/// Core attendance never touches optional services.
@MainActor
final class DefaultFeatureAdapter: FeatureAdapter {
    let descriptor = FeatureAdapterDescriptor(id: "builtin", name: "happylulu", features: Set(AppFeature.allCases))
    init(sync: CalendarSyncModel? = nil) {}
    func calendarEvents(in interval: DateInterval) async throws -> [FeatureCalendarEvent] { [] }
    func leaveSnapshot() -> PluginSnapshot? { nil }
    func requestHalfDayAccess() async throws { throw FeatureAdapterFailure.unavailable }
    func halfDayTitles(on day: Date, timeZone: TimeZone) async throws -> [String] { [] }
}

@MainActor
final class MacCalendarFeatureAdapter: FeatureAdapter {
    let descriptor = FeatureAdapterDescriptor(id: "mac-calendar", name: "Mac Calendar", features: [.calendar, .halfDay])
    private let sync: CalendarSyncModel
    private lazy var halfDays = HalfDayCalendarReader()
    init(sync: CalendarSyncModel) { self.sync = sync }
    func calendarEvents(in interval: DateInterval) async throws -> [FeatureCalendarEvent] {
        try await sync.featureEvents(in: interval).map {
            FeatureCalendarEvent(systemEvent: $0, sync: sync, sourceID: descriptor.id)
        }
    }
    func leaveSnapshot() -> PluginSnapshot? { nil }
    func requestHalfDayAccess() async throws { try await halfDays.requestAccess() }
    func halfDayTitles(on day: Date, timeZone: TimeZone) async throws -> [String] {
        try await halfDays.titles(on: day, timeZone: timeZone)
    }
}

@MainActor
final class LocalPluginController: ObservableObject, PluginController {
    let descriptor: PluginDescriptor
    @Published private(set) var enabled = false
    private let onChange: (Bool) -> Void
    var changes: AnyPublisher<Void, Never> { objectWillChange.map { _ in () }.eraseToAnyPublisher() }
    var isRunning: Bool { false }
    var connectionState: PluginConnectionState { enabled ? .ready : .off }
    init(id: String, name: String, onChange: @escaping (Bool) -> Void = { _ in }) {
        descriptor = PluginDescriptor(id: id, name: name); self.onChange = onChange
    }
    func setEnabled(_ value: Bool) { enabled = value; onChange(value) }
    func start() { onChange(enabled) }
    func stop() { onChange(false) }
    func refreshData() {}
}

@MainActor
final class LeaveDetectionFeatureAdapter: FeatureAdapter {
    let descriptor = FeatureAdapterDescriptor(id: "leave-detection", name: "Leave recognition", features: [])
    func calendarEvents(in interval: DateInterval) async throws -> [FeatureCalendarEvent] { [] }
    func leaveSnapshot() -> PluginSnapshot? { nil }
    func requestHalfDayAccess() async throws { throw FeatureAdapterFailure.unsupported }
    func halfDayTitles(on day: Date, timeZone: TimeZone) async throws -> [String] { [] }
}

extension FeatureCalendarEvent {
    @MainActor
    init(systemEvent event: SystemCalendarDisplayEvent, sync: CalendarSyncModel, sourceID: String) {
        self.init(sourceID: sourceID, eventID: event.id, calendarID: event.calendarID,
            title: event.title, start: event.start, end: event.end, isAllDay: event.isAllDay,
            location: event.location, duplicateIdentity: sync.displayIdentity(for: event),
            contentSignature: event.contentSignature, allowsContentMatching: event.allowsContentMatching)
    }
}
