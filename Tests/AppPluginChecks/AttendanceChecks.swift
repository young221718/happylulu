import Foundation
import AppPluginCore
import DaouOfficePlugin

func checkDaouAttendance() async throws {
    let now = try DaouOfficeAPIParser.date("2026-11-17T10:00:00+09:00")
    let valid = Data(#"{"data":{"startWorkTime":"2026-11-17T08:31:23+09:00","endWorkTime":null,"zoneId":"Asia/Seoul"}}"#.utf8)
    let arrival = try DaouOfficeAPIParser.todayAttendance(valid, now: now)
    require(arrival.arrival == ISO8601DateFormatter().date(from: "2026-11-16T23:31:23Z"), "Source offset must preserve the actual instant")
    require(arrival.day == "2026-11-17" && arrival.timeZoneID == "Asia/Seoul", "Source civil date and timezone must survive")
    let empty = try DaouOfficeAPIParser.todayAttendance(Data(#"{"data":{"startWorkTime":null,"endWorkTime":null,"zoneId":"Asia/Seoul"}}"#.utf8), now: now)
    require(empty.arrival == nil, "No record must not become midnight")
    for json in [#"{"data":null}"#, #"{"data":{}}"#,
                 #"{"data":{"startWorkTime":"2026-11-16T08:00:00+09:00","zoneId":"Asia/Seoul"}}"#,
                 #"{"data":{"startWorkTime":"2026-11-17T11:00:00+09:00","zoneId":"Asia/Seoul"}}"#,
                 #"{"data":{"startWorkTime":"08:00","zoneId":"Asia/Seoul"}}"#,
                 #"{"data":{"startWorkTime":"2026-11-17 08:00:00","zoneId":"Asia/Seoul"}}"#,
                 #"{"data":{"startWorkTime":"2026-11-17T08:00:00+09:00","zoneId":"unknown"}}"#] {
        do { _ = try DaouOfficeAPIParser.todayAttendance(Data(json.utf8), now: now); fatalError("Unverified attendance accepted") }
        catch PluginFailure.unsupportedResponse {}
    }
    let config = try DaouOfficeConfiguration(enabled: true, address: "https://example.daouoffice.com", loginID: "employee")
    let bootstrap = [APIStep(path: "/api/portal/public/auth/company", json: #"{"data":{"companyList":[{"companyId":12}]}}"#),
        APIStep(path: "/api/portal/public/auth/login", json: #"{"data":{}}"#, method: "POST")]
    let reads = [APIStep(path: "/api/leave/normal/my/annual/summary", json: #"{"data":{"totalDays":7,"usedDays":1,"formattedRemain":"6d"}}"#),
        APIStep(path: "/api/leave/normal/my/upcoming", json: #"{"data":{"elements":[]}}"#),
        APIStep(path: "/api/leave/normal/my/past/2026", json: #"{"data":{"elements":[]}}"#),
        APIStep(path: "/gw/api/user/session", json: #"{"data":{"id":900}}"#),
        APIStep(path: "/gw/api/calendar/user/900/calendar", json: #"{"data":[]}"#)]
    for step in [APIStep(path: "/api/attend/normal/gadget/today", json: String(decoding: valid, as: UTF8.self)),
                 APIStep(path: "/api/attend/normal/gadget/today", json: #"{"data":null}"#),
                 APIStep(path: "/api/attend/normal/gadget/today", json: "{}", status: 404),
                 APIStep(path: "/api/attend/normal/gadget/today", json: "{}", status: 401),
                 APIStep(path: "/api/attend/normal/gadget/today", json: "{}", status: 500)] {
        let transport = FixtureTransport(bootstrap + reads + [step])
        let client = DaouOfficeAPIClient(configuration: config, secrets: FixtureSecrets(password: "fixture"), transport: transport)
        let value = try await client.refresh(now: now)
        require(value.leave?.remainingDays == 6, "Optional attendance failure must preserve valid leave/calendar")
        require((value.todayAttendance != nil) == (step.json == String(decoding: valid, as: UTF8.self)), "Only verified attendance may be published")
        let remaining = await transport.remaining()
        require(remaining == 0, "The personal attendance GET was not performed")
        let requests = await transport.captured()
        require(requests.last?.httpMethod == "GET" && requests.last?.url?.host == "example.daouoffice.com", "Attendance must reuse the same personal session origin")
        require(requests.filter { $0.httpMethod != "GET" }.count == 1, "Only personal login may write; no attendance mutation or admin API")
    }
    print("PASS personal Daou attendance: exact read route, ISO/timezone/date validation, no-record and optional 401/404/500 preservation")
}
