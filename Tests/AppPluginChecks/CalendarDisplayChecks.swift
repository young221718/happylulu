import Foundation
import AppPluginCore

func checkCalendarDisplayCopies() {
    let date = ISO8601DateFormatter()
    let start = date.date(from: "2026-03-08T01:30:00-05:00")!
    let end = date.date(from: "2026-03-08T03:30:00-04:00")!
    func event(_ id: String, calendar: String = "a", source: String = "fixture", title: String = "Meeting",
               begin: Date? = nil, finish: Date? = nil, allDay: Bool = false, location: String? = "Room") -> FeatureCalendarEvent {
        FeatureCalendarEvent(sourceID: source, eventID: id, calendarID: calendar, title: title,
            start: begin ?? start, end: finish ?? end, isAllDay: allDay, location: location)
    }
    let first = event("one"), copy = event("two", calendar: "b")
    let raw = [copy, first]
    let projected = FeatureCalendarEvent.coalescedForDisplay(raw)
    require(projected.count == 1 && projected[0].id == first.id && projected[0].calendarIDs == ["a", "b"],
        "Exact cross-calendar copies must have a deterministic representative and retain both calendars")
    require(raw.count == 2 && raw[0].calendarIDs == ["b"], "Projection must leave the raw records unchanged")
    require(FeatureCalendarEvent.coalescedForDisplay([first, copy]).map(\.id) == projected.map(\.id),
        "Fetch ordering must not change the displayed event")
    require(FeatureCalendarEvent.coalescedForDisplay([copy]).map(\.id) == [copy.id],
        "A surviving copy must remain visible when its peer disappears")
    for distinct in [event("three"), event("three", source: "different"), event("three", calendar: "b", title: "Other"),
                     event("three", calendar: "b", begin: start.addingTimeInterval(1)),
                     event("three", calendar: "b", finish: end.addingTimeInterval(1)),
                     event("three", calendar: "b", allDay: true), event("three", calendar: "b", location: "Other room")] {
        require(FeatureCalendarEvent.coalescedForDisplay([first, distinct]).count == 2,
            "Distinct source, calendar, title, occurrence time, all-day kind or location must remain visible")
    }
    require(FeatureCalendarEvent.coalescedForDisplay([first, copy, event("three")]).count == 3,
        "Multiple matching candidates in one calendar must not be guessed into pairs")
    require(FeatureCalendarEvent.coalescedForDisplay([event("blank", title: ""), event("blank", calendar: "b", title: "")]).count == 2,
        "Untitled events must not be matched by empty content")
    require(FeatureCalendarEvent.coalescedForDisplay([event("zero", finish: start), event("zero", calendar: "b", finish: start)]).count == 2,
        "Untrustworthy or empty time ranges must not be collapsed")
    let equivalentZone = date.date(from: "2026-03-08T15:30:00+09:00")!
    require(FeatureCalendarEvent.coalescedForDisplay([first, event("zone", calendar: "b", begin: equivalentZone)]).count == 1,
        "Timed copies compare absolute instants across time zones and DST")
    let nextWeek = event("next", calendar: "b", begin: start.addingTimeInterval(7 * 86400), finish: end.addingTimeInterval(7 * 86400))
    require(FeatureCalendarEvent.coalescedForDisplay([first, copy, nextWeek]).count == 2,
        "Different recurring occurrences must remain separate")
    let allStart = date.date(from: "2026-03-08T00:00:00-05:00")!
    let allEnd = date.date(from: "2026-03-09T00:00:00-04:00")!
    let allA = event("all-a", begin: allStart, finish: allEnd, allDay: true)
    let allB = event("all-b", calendar: "b", begin: allStart, finish: allEnd, allDay: true)
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/New_York")!
    let agenda = DailyAgenda(events: [allA, allB], on: allStart, calendar: calendar)
    require(agenda.items.count == 1 && agenda.items[0].end == allEnd, "All-day copies retain exclusive DST day bounds")
    require(DailyAgenda(events: [allA, allB], on: allEnd, calendar: calendar).items.isEmpty,
        "An exclusive all-day end must not create a next-day agenda row")
    func metadata(_ id: String, _ calendar: String, identity: String? = nil, signature: String = "notes-one", fallback: Bool = true) -> FeatureCalendarEvent {
        FeatureCalendarEvent(sourceID: "fixture", eventID: id, calendarID: calendar, title: "Meeting",
            start: start, end: end, isAllDay: false, location: "Room", duplicateIdentity: identity,
            contentSignature: Data(signature.utf8), allowsContentMatching: fallback)
    }
    require(FeatureCalendarEvent.coalescedForDisplay([metadata("a", "a"), metadata("b", "b", signature: "notes-two")]).count == 2,
        "Copies with changed hidden meaningful content must remain separate")
    require(FeatureCalendarEvent.coalescedForDisplay([metadata("a", "a", fallback: false), metadata("b", "b", fallback: false)]).count == 2,
        "Unknown recurrence identity or unsupported metadata must not use a content-only guess")
    let recurring = [metadata("a", "a", identity: "occurrence:series:1", fallback: false),
                     metadata("b", "b", identity: "occurrence:series:1", fallback: false)]
    require(FeatureCalendarEvent.coalescedForDisplay(recurring).count == 1,
        "A verified recurring occurrence may be collapsed even when content-only matching is unsafe")
    require(FeatureCalendarEvent.coalescedForDisplay([recurring[0], metadata("b", "b", identity: "occurrence:series:2", fallback: false)]).count == 2,
        "Two series occurrences must not collapse because their edited display times happen to coincide")
    require(FeatureCalendarEvent.coalescedForDisplay([metadata("a", "a", identity: "mapping:1"),
        metadata("b", "b", identity: "mapping:1", signature: "changed notes")]).count == 2,
        "Mapping identity must not conceal a diverged peer")
    let firstOccurrence = metadata("a1", "a", identity: "occurrence:series:1", fallback: false)
    let firstCopy = metadata("b1", "b", identity: "occurrence:series:1", fallback: false)
    let movedOccurrence = metadata("a2", "a", identity: "occurrence:series:2", fallback: false)
    let movedCopy = metadata("b2", "b", identity: "occurrence:series:2", fallback: false)
    let overlapping = FeatureCalendarEvent.coalescedForDisplay([firstOccurrence, movedOccurrence, firstCopy])
    require(overlapping.count == 2 && overlapping.filter { $0.duplicateIdentity == "occurrence:series:1" }.count == 1,
        "A verified pair must collapse even when another original occurrence moves to the same visible interval")
    let copiedOccurrences = FeatureCalendarEvent.coalescedForDisplay([movedCopy, firstCopy, movedOccurrence, firstOccurrence])
    require(copiedOccurrences.count == 2 && Set(copiedOccurrences.compactMap(\.duplicateIdentity)) == ["occurrence:series:1", "occurrence:series:2"] &&
        copiedOccurrences.allSatisfy { $0.calendarIDs == ["a", "b"] },
        "Two verified pairs at one displayed time must retain exactly two distinct original occurrences")
    let ambiguousOccurrence = metadata("a1-other", "a", identity: "occurrence:series:1", fallback: false)
    require(FeatureCalendarEvent.coalescedForDisplay([firstOccurrence, firstCopy, ambiguousOccurrence]).count == 3,
        "Multiple candidates for the same identity in one calendar must remain ambiguous")
    let verifiedPairAndOther = [metadata("v1", "a", identity: "verified-pair"),
        metadata("v2", "b", identity: "verified-pair"), metadata("other", "c", identity: "other")]
    let once = FeatureCalendarEvent.coalescedForDisplay(verifiedPairAndOther)
    require(once.count == 2 && FeatureCalendarEvent.coalescedForDisplay(once).count == 2,
        "Reusing the month projection in the daily agenda must not fallback-merge a verified group with an unrelated candidate")
    print("PASS calendar display copies: exact matching, ambiguity, source preservation, deterministic rows, removal, edits, time zones, DST and all-day bounds")
}
