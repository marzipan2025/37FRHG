// 37FRHG 캘린더 도우미(EventKit). build_mac.sh 가 swiftc 로 Contents/MacOS/frhgcal 로 만들어 넣는다.
// 앱(37FRHG)이 자식 프로세스로 부르므로 캘린더 권한은 앱 이름으로 묻고 앱에 붙는다
// (Info.plist NSCalendarsFullAccessUsageDescription). 결과는 표준 출력에 JSON 한 줄.
//
//   frhgcal day YYYY-MM-DD   그날(지역 시각 0시~24시)에 걸친 일정
//   frhgcal calendars        일정을 넣을 수 있는 캘린더 이름들과 기본 캘린더
//   frhgcal add '<JSON>'     {title, start "YYYY-MM-DD HH:mm", end?, all_day?, location?, notes?, calendar?} 새 일정
//   frhgcal update '<JSON>'  {id, at "그 회차 시작", span "this"|"future", title?, start?, end?, all_day?, location?, notes?}
//   frhgcal delete '<JSON>'  {id, at, span}
//   (2026-11-25 추가: 만들기·바꾸기·지우기. 반복 일정은 span this = 그 회차만, future = 이 회차부터 앞으로 모두.)
//
// 종료 코드: 0 성공, 2 권한 없음, 1 그 밖의 오류. 오류도 {"error": "..."} 로 찍는다.
import EventKit
import Foundation

let store = EKEventStore()

func out(_ obj: Any, _ code: Int32 = 0) -> Never {
    let data = try! JSONSerialization.data(withJSONObject: obj, options: [])
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write("\n".data(using: .utf8)!)
    exit(code)
}

func requestAccess() -> Bool {
    switch EKEventStore.authorizationStatus(for: .event) {
    case .fullAccess:
        return true
    case .notDetermined:
        let sem = DispatchSemaphore(value: 0)
        var ok = false
        store.requestFullAccessToEvents { granted, _ in
            ok = granted
            sem.signal()
        }
        sem.wait()
        return ok
    default:
        return false
    }
}

let args = CommandLine.arguments
guard args.count >= 2 else { out(["error": "usage"], 1) }
guard requestAccess() else { out(["error": "denied"], 2) }

let local = DateFormatter()
local.locale = Locale(identifier: "en_US_POSIX")
local.dateFormat = "yyyy-MM-dd HH:mm"
let dayFmt = DateFormatter()
dayFmt.locale = Locale(identifier: "en_US_POSIX")
dayFmt.dateFormat = "yyyy-MM-dd"

switch args[1] {
case "day":
    guard args.count >= 3, let day = dayFmt.date(from: args[2]) else { out(["error": "bad date"], 1) }
    let cal = Calendar.current
    let start = cal.startOfDay(for: day)
    let end = cal.date(byAdding: .day, value: 1, to: start)!
    let pred = store.predicateForEvents(withStart: start, end: end, calendars: nil)
    let events = store.events(matching: pred).sorted {
        ($0.isAllDay ? 0 : 1, $0.startDate) < ($1.isAllDay ? 0 : 1, $1.startDate)
    }
    var list: [[String: Any]] = []
    for e in events {
        var d: [String: Any] = [
            "id": e.calendarItemIdentifier,
            "title": e.title ?? "",
            "all_day": e.isAllDay,
            "start": local.string(from: e.startDate),
            "end": local.string(from: e.endDate),
            "calendar": e.calendar?.title ?? "",
            "recurring": e.hasRecurrenceRules,
            "readonly": !(e.calendar?.allowsContentModifications ?? false),
        ]
        if let loc = e.location, !loc.isEmpty { d["location"] = loc }
        if let n = e.notes, !n.isEmpty { d["notes"] = String(n.prefix(300)) }
        list.append(d)
    }
    out(["events": list])
case "calendars":
    let cals = store.calendars(for: .event).filter { $0.allowsContentModifications }.map { $0.title }
    out(["calendars": cals, "default": store.defaultCalendarForNewEvents?.title ?? ""])
case "add", "update", "delete":
    guard args.count >= 3, let data = args[2].data(using: .utf8),
          let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { out(["error": "bad json"], 1) }
    func str(_ k: String) -> String? { (j[k] as? String).map { $0.trimmingCharacters(in: .whitespaces) } }
    func date(_ k: String) -> Date? {
        guard let v = str(k), !v.isEmpty else { return nil }
        return local.date(from: v) ?? dayFmt.date(from: v)
    }
    func info(_ e: EKEvent) -> [String: Any] {
        ["id": e.calendarItemIdentifier, "title": e.title ?? "", "all_day": e.isAllDay,
         "start": local.string(from: e.startDate), "end": local.string(from: e.endDate), "calendar": e.calendar?.title ?? ""]
    }
    // 바꾸기·지우기: id 와 그 회차 시작(at)으로 정확히 그 일정(반복이면 그 회차)을 찾는다.
    func find() -> EKEvent {
        guard let id = str("id"), let at = date("at") else { out(["error": "need id and at"], 1) }
        let pred = store.predicateForEvents(withStart: at.addingTimeInterval(-86400), end: at.addingTimeInterval(86400), calendars: nil)
        guard let e = store.events(matching: pred).first(where: {
            $0.calendarItemIdentifier == id && abs($0.startDate.timeIntervalSince(at)) < 60
        }) else { out(["error": "not found"], 1) }
        if !(e.calendar?.allowsContentModifications ?? false) { out(["error": "readonly"], 1) }
        return e
    }
    func apply(_ e: EKEvent) {
        if let t = str("title"), !t.isEmpty { e.title = t }
        if let a = j["all_day"] as? Bool { e.isAllDay = a }
        let oldLen = e.endDate.timeIntervalSince(e.startDate)
        if let s = date("start") {
            e.startDate = s
            if date("end") == nil { e.endDate = s.addingTimeInterval(e.isAllDay ? 86400 : max(oldLen, 1800)) }
        }
        if let en = date("end") { e.endDate = en }
        if let l = str("location") { e.location = l.isEmpty ? nil : l }
        if let n = str("notes") { e.notes = n.isEmpty ? nil : n }
    }
    let span: EKSpan = str("span") == "future" ? .futureEvents : .thisEvent
    do {
        switch args[1] {
        case "add":
            guard let t = str("title"), !t.isEmpty, let s = date("start") else { out(["error": "need title and start"], 1) }
            let e = EKEvent(eventStore: store)
            e.title = t
            e.isAllDay = (j["all_day"] as? Bool) ?? false
            e.startDate = s
            e.endDate = s.addingTimeInterval(e.isAllDay ? 86400 : 3600)
            apply(e)
            if let name = str("calendar"), !name.isEmpty {
                guard let c = store.calendars(for: .event).first(where: { $0.title == name && $0.allowsContentModifications })
                else { out(["error": "no calendar"], 1) }
                e.calendar = c
            } else {
                guard let c = store.defaultCalendarForNewEvents else { out(["error": "no default calendar"], 1) }
                e.calendar = c
            }
            try store.save(e, span: .thisEvent, commit: true)
            out(["ok": true, "event": info(e)])
        case "update":
            let e = find()
            apply(e)
            if e.endDate <= e.startDate { out(["error": "end before start"], 1) }
            try store.save(e, span: span, commit: true)
            out(["ok": true, "event": info(e)])
        default:
            let e = find()
            let before = info(e)
            try store.remove(e, span: span, commit: true)
            out(["ok": true, "event": before])
        }
    } catch {
        out(["error": error.localizedDescription], 1)
    }
default:
    out(["error": "unknown command"], 1)
}
