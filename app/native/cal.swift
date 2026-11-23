// 37FRHG 캘린더 도우미(EventKit). build_mac.sh 가 swiftc 로 Contents/MacOS/frhgcal 로 만들어 넣는다.
// 앱(37FRHG)이 자식 프로세스로 부르므로 캘린더 권한은 앱 이름으로 묻고 앱에 붙는다
// (Info.plist NSCalendarsFullAccessUsageDescription). 결과는 표준 출력에 JSON 한 줄.
//
//   frhgcal day YYYY-MM-DD   그날(지역 시각 0시~24시)에 걸친 일정
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
        ]
        if let loc = e.location, !loc.isEmpty { d["location"] = loc }
        if let n = e.notes, !n.isEmpty { d["notes"] = String(n.prefix(300)) }
        list.append(d)
    }
    out(["events": list])
default:
    out(["error": "unknown command"], 1)
}
