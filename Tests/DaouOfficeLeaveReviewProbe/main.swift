import Foundation
import AppKit
import Combine
import AppPluginCore
import AfterSixCore

@MainActor
final class DaouLeaveFixture: FeatureAdapter {
    let descriptor = FeatureAdapterDescriptor(id: "daouoffice", name: "Synthetic", features: [.leave])
    var calendarTimeZone: TimeZone? { TimeZone(identifier: "Asia/Seoul") }
    var snapshot: PluginSnapshot?
    func leaveSnapshot() -> PluginSnapshot? { snapshot }
    func calendarEvents(in interval: DateInterval) async throws -> [FeatureCalendarEvent] { [] }
    func requestHalfDayAccess() async throws {}
    func halfDayTitles(on day: Date, timeZone: TimeZone) async throws -> [String] { [] }
}

@MainActor
final class DaouNotificationFixture {
    var allowed = true
    var holdAuthorization = false
    var authorizationWaiter: CheckedContinuation<Bool, Never>?
    var permissionRequests = 0
    var delivered: [String: (String, String)] = [:]
    var deliveryCount = 0
    var holdDelivery = false
    var deliveryWaiter: CheckedContinuation<Void, Never>?
    func authorization() async -> Bool {
        if holdAuthorization { return await withCheckedContinuation { authorizationWaiter = $0 } }
        return allowed
    }
    func requestPermission() async -> Bool { permissionRequests += 1; return allowed }
    func deliver(_ id: String, title: String, body: String) async {
        if holdDelivery { await withCheckedContinuation { deliveryWaiter = $0 } }
        deliveryCount += 1; delivered[id] = (title, body)
    }
    func remove(_ id: String) { delivered[id] = nil }
}

@main
struct DaouLeaveReviewProbe {
    @MainActor
    static func main() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("daou-leave-review-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let fixedCalendar = calendar
        var now = ISO8601DateFormatter().date(from: "2026-11-17T10:00:00+09:00")!
        let adapter = DaouLeaveFixture()
        let router = FeatureAdapterRouter(defaultAdapter: adapter)
        let store = StateStore(url: folder.appendingPathComponent("attendance.json"))
        var initial = AttendanceState(); initial.didOfferLoginItem = true
        try store.save(initial)
        func model() -> AppModel {
            AppModel(store: store, featureRouter: router, allowsLoginItemChanges: false,
                nowProvider: { now }, calendarProvider: { fixedCalendar })
        }
        func publish(_ status: String = "APPROVAL", days: Double = 1, fetchedAt: Date? = nil) {
            adapter.snapshot = PluginSnapshot(pluginID: "daouoffice", fetchedAt: fetchedAt ?? now, leave: nil,
                vacations: [PluginVacation(id: "synthetic-" + status, kind: "연차", status: status, days: days,
                    dates: ["2026-11-17"], periodLabel: "2026-11-17")], events: [], coverage: PluginCoverage())
        }
        publish()
        let proposed = model()
        precondition(proposed.daouLeaveProposal != nil, "Fresh approved leave must propose a change")
        precondition(!proposed.autoApplyDaouLeave && proposed.state == initial, "Default must preserve attendance until confirmation")
        precondition(proposed.dismissDaouLeaveProposal(), "Decline must persist")
        publish(fetchedAt: now.addingTimeInterval(-1))
        precondition(model().daouLeaveProposal == nil, "Repeated fetch and restart must not re-propose the declined change")

        // A changed local value creates a distinct conflict and requires explicit acceptance.
        initial.manualDayTypes["2026-11-17"] = .morningHalf
        let arrivalTime = now.addingTimeInterval(-3600)
        initial.arrivals["2026-11-17"] = Arrival(day: "2026-11-17", time: arrivalTime, source: .manual,
            timeZoneID: "Asia/Seoul", mode: .morningHalf, modeSource: .manual)
        try store.save(initial)
        let conflict = model()
        precondition(conflict.daouLeaveProposal != nil, "Manual conflict must remain reviewable")
        precondition(conflict.setAutoApplyDaouLeave(true), "Explicit opt-in must persist")
        conflict.refresh()
        precondition(conflict.state == initial, "Auto apply must preserve manual arrival and day type")
        precondition(conflict.applyDaouLeaveProposal(), "Explicit acceptance may change today's type")
        precondition(conflict.state.manualDayTypes["2026-11-17"] == .annualLeave, "Acceptance must apply approved leave")
        precondition(conflict.state.arrivals == initial.arrivals, "Acceptance must retain the original arrival")
        precondition(conflict.daouLeaveProposal == nil, "Accepted matching values must not reappear")

        var unlocked = AttendanceState()
        unlocked.arrivals["2026-11-17"] = Arrival(day: "2026-11-17", time: arrivalTime, source: .unlock,
            timeZoneID: "Asia/Seoul", modeSource: .automatic)
        try store.save(unlocked)
        let automatic = model()
        automatic.refresh()
        precondition(automatic.state.manualDayTypes["2026-11-17"] == .annualLeave, "Opt-in may apply to an untouched day")
        precondition(automatic.state.arrivals == unlocked.arrivals, "Automatic application must retain observed arrival history")
        publish("CANCEL"); automatic.refresh()
        precondition(automatic.state.manualDayTypes["2026-11-17"] == .annualLeave, "Cancellation must never erase a saved local value")
        precondition(automatic.setAutoApplyDaouLeave(false), "Turning automatic application off must persist")
        try store.save(unlocked)
        let disabled = model(); publish(); disabled.refresh()
        precondition(disabled.state.manualDayTypes.isEmpty && disabled.daouLeaveProposal != nil, "Off must restore proposals")
        for status in ["CANCEL", "RETURN", "PENDING"] {
            publish(status); precondition(disabled.daouLeaveProposal == nil, "Only approved leave may propose")
        }
        publish(days: 0.5); precondition(disabled.daouLeaveProposal == nil, "Half-day duration cannot invent AM/PM")
        publish(fetchedAt: now.addingTimeInterval(-901)); precondition(disabled.daouLeaveProposal == nil, "Stale snapshots cannot propose or apply")
        adapter.snapshot = nil; precondition(disabled.daouLeaveProposal == nil, "Unavailable attendance/leave must not invent a value")
        publish(); now = now.addingTimeInterval(86400); disabled.refresh()
        precondition(disabled.daouLeaveProposal == nil, "Yesterday's leave must not apply today")
        now = now.addingTimeInterval(-86400); publish()
        var skipped = AttendanceState(); skipped.suppressedDays.insert("2026-11-17")
        try store.save(skipped)
        let skippedModel = model()
        precondition(skippedModel.setAutoApplyDaouLeave(true), "Opt-in must be available on skipped days")
        precondition(skippedModel.state == skipped && skippedModel.daouLeaveProposal?.isSkipped == true,
            "Skipped days must remain unchanged and show their actual previous value")
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let utcCalendar = utc
        now = ISO8601DateFormatter().date(from: "2026-11-17T01:00:00+09:00")!; publish()
        let traveler = AppModel(store: store, featureRouter: router, allowsLoginItemChanges: false,
            nowProvider: { now }, calendarProvider: { utcCalendar })
        precondition(traveler.daouLeaveProposal == nil, "Different civil dates must not address yesterday's local record")
        now = ISO8601DateFormatter().date(from: "2026-11-17T10:00:00+09:00")!; publish()
        let preferences = store.url.appendingPathExtension("daou-review.json")
        let corrupt = Data(#"{"version":99,"automaticallyApply":true}"#.utf8)
        try corrupt.write(to: preferences)
        let unreadable = model(); unreadable.refresh()
        precondition(!unreadable.autoApplyDaouLeave && !unreadable.canChangeDaouLeaveReview && unreadable.state == skipped,
            "Unreadable preferences must disable automatic application and preserve attendance")
        precondition(!unreadable.setAutoApplyDaouLeave(false), "Corrupt preferences cannot be overwritten")
        let preserved = try Data(contentsOf: preferences)
        precondition(preserved == corrupt, "Corrupt preference bytes must be preserved")
        try FileManager.default.removeItem(at: preferences)
        try store.save(AttendanceState())
        func publishArrival(_ at: Date? = nil, fetchedAt: Date? = nil) {
            adapter.snapshot = PluginSnapshot(pluginID: "daouoffice", fetchedAt: now, leave: nil, vacations: [], events: [],
                coverage: PluginCoverage(), todayAttendance: PluginTodayAttendance(day: "2026-11-17", arrival: at,
                    timeZoneID: "Asia/Seoul", fetchedAt: fetchedAt ?? now))
        }
        let serverArrival = ISO8601DateFormatter().date(from: "2026-11-17T07:31:23+09:00")!
        publishArrival(serverArrival)
        let arrivalReview = model()
        precondition(arrivalReview.daouArrivalProposal != nil && arrivalReview.state.arrivals.isEmpty,
            "A valid source arrival must propose without inventing a local record")
        precondition(arrivalReview.dismissDaouArrivalProposal(), "Arrival decline must persist")
        precondition(model().daouArrivalProposal == nil, "Repeated attendance polling/restart must not re-propose")
        try store.save(unlocked)
        let arrivalConflict = model()
        precondition(arrivalConflict.daouArrivalProposal != nil, "Changed local arrival must be compared")
        precondition(!arrivalConflict.applyDaouArrivalProposal(expectedID: "previously-displayed-value"),
            "A source change after displaying a proposal must require another review")
        precondition(arrivalConflict.applyDaouArrivalProposal(), "Explicit confirmation may import exact source arrival")
        let imported = try store.load().arrivals["2026-11-17"]!
        precondition(imported.time == serverArrival && imported.externalSourceID == "daouoffice", "Import must preserve seconds, provenance and restart")
        precondition(arrivalConflict.daouArrivalProposal == nil, "Matching source/current time must not re-propose")
        precondition(arrivalConflict.setAutoApplyDaouArrival(true), "Arrival automation requires its own explicit opt-in")
        let updatedArrival = serverArrival.addingTimeInterval(30)
        publishArrival(updatedArrival); arrivalConflict.refresh()
        precondition(arrivalConflict.state.arrivals["2026-11-17"]?.time == updatedArrival, "Opt-in may update a previous Daou import")
        precondition(arrivalConflict.saveManualClockText("08:42", forDay: "2026-11-17"), "Fixture manual editing must succeed")
        arrivalConflict.refresh()
        precondition(arrivalConflict.state.arrivals["2026-11-17"]?.time != updatedArrival && arrivalConflict.daouArrivalProposal?.hasManualConflict == true,
            "Manual editing must remove external ownership and prevent subsequent auto overwrite")
        precondition(arrivalConflict.setAutoApplyDaouArrival(false), "Arrival automation off must persist")
        let kept = arrivalConflict.state
        publishArrival(nil); arrivalConflict.refresh()
        let savedAfterNull = try store.load()
        precondition(arrivalConflict.state == kept && savedAfterNull == kept && arrivalConflict.daouArrivalProposal == nil,
            "Null source arrival must preserve manual record in memory and on disk")
        publishArrival(updatedArrival, fetchedAt: now.addingTimeInterval(-901))
        precondition(arrivalConflict.daouArrivalProposal == nil, "Stale attendance cannot propose")
        try store.save(AttendanceState())
        publishArrival(nil)
        let panelModel = AppModel(store: StateStore(url: folder.appendingPathComponent("panel-attendance.json")),
            featureRouter: router, allowsLoginItemChanges: false, nowProvider: { now }, calendarProvider: { fixedCalendar })
        let popover = NSPopover()
        func resizePanel() {
            popover.contentSize = panelModel.panelContentSize(menuBarItemCount: 2, pluginPanelHeight: 14)
        }
        resizePanel()
        precondition(popover.contentSize == NSSize(width: 364, height: 444), "No proposal must use the existing base and plugin heights")
        let panelObservation = panelModel.objectWillChange.sink { _ in
            Task { @MainActor in resizePanel() }
        }
        publishArrival(serverArrival); panelModel.refresh()
        for _ in 0..<30 { await Task.yield() }
        precondition(popover.contentSize.height == 476, "A new proposal must resize the actual popover by its visible row height")
        precondition(panelModel.applyDaouArrivalProposal(), "Displayed panel proposal must apply")
        for _ in 0..<30 { await Task.yield() }
        precondition(popover.contentSize.height == 444, "Accepting a proposal must restore the actual popover height")
        publishArrival(updatedArrival); panelModel.refresh()
        for _ in 0..<30 { await Task.yield() }
        precondition(popover.contentSize.height == 476, "A changed source value must expand the popover again")
        precondition(panelModel.dismissDaouArrivalProposal(), "Displayed panel proposal must decline")
        for _ in 0..<30 { await Task.yield() }
        precondition(popover.contentSize.height == 444, "Declining a proposal must restore the actual popover height")
        withExtendedLifetime(panelObservation) {}
        let notifications = DaouNotificationFixture()
        let notificationStore = StateStore(url: folder.appendingPathComponent("notification-attendance.json"))
        func notificationModel() -> AppModel {
            AppModel(store: notificationStore, featureRouter: router, allowsLoginItemChanges: false,
                allowsDaouNotifications: true, nowProvider: { now }, calendarProvider: { fixedCalendar },
                notificationAuthorization: { await notifications.authorization() },
                notificationPermissionRequest: { await notifications.requestPermission() },
                notificationDelivery: { id, title, body in await notifications.deliver(id, title: title, body: body) },
                notificationRemoval: { notifications.remove($0) })
        }
        let alerts = notificationModel()
        alerts.setDaouNotificationRuntimeActive(true)
        publishArrival(serverArrival); alerts.refresh()
        for _ in 0..<40 { await Task.yield() }
        precondition(notifications.permissionRequests == 0 && notifications.deliveryCount == 0,
            "Default-off local alerts must not request system permission or deliver")
        alerts.setDaouNotifications(true)
        for _ in 0..<60 { await Task.yield() }
        precondition(notifications.permissionRequests == 1 && notifications.deliveryCount == 1,
            "Explicit enable must request permission and deliver one real pending proposal")
        let notice = notifications.delivered.values.first!
        precondition(!notice.0.contains("07:31") && !notice.1.contains("2026") && !notice.1.contains("07:31"),
            "Notification text must not expose dates, arrivals or leave values")
        alerts.refresh(); alerts.refresh()
        let reopened = notificationModel(); reopened.setDaouNotificationRuntimeActive(true); reopened.refresh()
        for _ in 0..<60 { await Task.yield() }
        precondition(notifications.deliveryCount == 1 && notifications.delivered.count == 1,
            "Repeated polling and restart must retain one existing notice without repeat delivery")
        precondition(reopened.dismissDaouArrivalProposal(), "Notification proposal decline must persist")
        reopened.refresh()
        for _ in 0..<40 { await Task.yield() }
        precondition(notifications.deliveryCount == 1 && notifications.delivered.isEmpty,
            "Declined proposals must remove their delivered notice and never notify again")
        reopened.setDaouNotificationRuntimeActive(false)
        publishArrival(updatedArrival); reopened.refresh()
        for _ in 0..<40 { await Task.yield() }
        precondition(notifications.deliveryCount == 1, "Inactive host must not deliver new proposal notifications")
        notifications.allowed = false
        reopened.setDaouNotificationRuntimeActive(true); reopened.setDaouNotifications(true)
        for _ in 0..<60 { await Task.yield() }
        precondition(notifications.deliveryCount == 1 && reopened.daouNotificationMessage != nil && reopened.daouArrivalProposal != nil,
            "Denied permission must retain the in-app proposal without delivering a notification")
        notifications.allowed = true; notifications.holdAuthorization = true
        reopened.setDaouNotifications(true)
        for _ in 0..<40 { await Task.yield() }
        precondition(notifications.authorizationWaiter != nil, "Fixture must suspend the permission lookup")
        reopened.setDaouNotifications(false)
        notifications.authorizationWaiter?.resume(returning: true); notifications.authorizationWaiter = nil
        for _ in 0..<60 { await Task.yield() }
        precondition(notifications.deliveryCount == 1, "Disabling notifications must invalidate a delayed authorization result")
        reopened.setDaouNotifications(true)
        for _ in 0..<40 { await Task.yield() }
        precondition(notifications.authorizationWaiter != nil, "Fixture must suspend a second lookup")
        precondition(reopened.applyDaouArrivalProposal(), "Accepting the source value must dismiss the notification candidate")
        notifications.authorizationWaiter?.resume(returning: true); notifications.authorizationWaiter = nil
        for _ in 0..<60 { await Task.yield() }
        precondition(notifications.deliveryCount == 1, "Accepting a proposal must invalidate a delayed authorization result")
        for (offset, action) in [(60.0, "decline"), (90.0, "stop")] {
            publishArrival(serverArrival.addingTimeInterval(offset)); reopened.refresh()
            for _ in 0..<40 { await Task.yield() }
            precondition(notifications.authorizationWaiter != nil, "Fixture must suspend lookup before resolving the proposal")
            if action == "decline" { precondition(reopened.dismissDaouArrivalProposal()) }
            else { reopened.setDaouNotificationRuntimeActive(false) }
            notifications.authorizationWaiter?.resume(returning: true); notifications.authorizationWaiter = nil
            for _ in 0..<60 { await Task.yield() }
            precondition(notifications.deliveryCount == 1, "Decline or host stop must invalidate delayed permission lookup")
        }
        notifications.holdAuthorization = false; notifications.holdDelivery = true
        publishArrival(serverArrival.addingTimeInterval(120))
        reopened.setDaouNotificationRuntimeActive(true); reopened.refresh()
        for _ in 0..<40 { await Task.yield() }
        precondition(notifications.deliveryWaiter != nil, "Fixture must suspend an already submitted system delivery")
        reopened.setDaouNotifications(false)
        notifications.deliveryWaiter?.resume(); notifications.deliveryWaiter = nil
        for _ in 0..<60 { await Task.yield() }
        precondition(notifications.delivered.isEmpty && notifications.deliveryCount == 2,
            "A canceled in-flight system delivery must be removed after its late completion")
        reopened.refresh()
        for _ in 0..<40 { await Task.yield() }
        precondition(notifications.deliveryCount == 2, "An off setting must not retry a canceled request")
        precondition(AppModel.pluginForReviewNotification("daou-review-synthetic") == "daouoffice"
            && AppModel.pluginForReviewNotification("ai-usage-synthetic") == nil,
            "Only Daou request identifiers may route clicks to Daou settings")
        print("PASS Daou leave review: proposals, acceptance, decline/restart deduplication, opt-in/off, manual preservation, cancellation, stale/missing data and day rollover")
    }
}
