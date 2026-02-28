import EventKit
import Foundation

// MARK: - Authorization
func authorize(store: EKEventStore) -> Bool {
    let status = EKEventStore.authorizationStatus(for: .event)
    if status == .fullAccess { return true }
    if status == .denied || status == .restricted { return false }

    nonisolated(unsafe) var granted = false
    let sema = DispatchSemaphore(value: 0)
    store.requestFullAccessToEvents { g, _ in granted = g; sema.signal() }
    sema.wait()
    return granted
}

// MARK: - Date helpers
func parseDateTime(_ s: String) -> Date? {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = .current
    f.dateFormat = "yyyy-MM-dd HH:mm"
    return f.date(from: s)
}
func parseDate(_ s: String) -> Date? {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = .current
    f.dateFormat = "yyyy-MM-dd"
    return f.date(from: s)
}
func fmt(_ d: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = .current
    f.dateFormat = "yyyy-MM-dd HH:mm"
    return f.string(from: d)
}

// MARK: - Tool implementations
func getUpcomingEvents(store: EKEventStore, days: Int, calendarName: String?) -> String {
    let start = Date()
    let end = Calendar.current.date(byAdding: .day, value: days, to: start)!
    let cals: [EKCalendar]? = calendarName.map { name in
        store.calendars(for: .event).filter { $0.title == name }
    }
    if let cals, cals.isEmpty { return "No upcoming events found." }
    let pred = store.predicateForEvents(withStart: start, end: end, calendars: cals)
    let events = store.events(matching: pred).sorted { $0.startDate < $1.startDate }
    if events.isEmpty { return "No upcoming events found." }
    return events.map { "\(fmt($0.startDate)) | \(fmt($0.endDate)) | \($0.title ?? "") [\($0.calendar.title)]" }
               .joined(separator: "\n")
}

func searchEvents(store: EKEventStore, query: String, days: Int) -> String {
    let now = Date()
    let start = Calendar.current.date(byAdding: .day, value: -days, to: now)!
    let end   = Calendar.current.date(byAdding: .day, value:  days, to: now)!
    let pred  = store.predicateForEvents(withStart: start, end: end, calendars: nil)
    let events = store.events(matching: pred)
        .filter { ($0.title ?? "").localizedCaseInsensitiveContains(query) }
        .sorted { $0.startDate < $1.startDate }
    if events.isEmpty { return "No events found matching '\(query)'." }
    return events.map { "\(fmt($0.startDate)) | \($0.title ?? "") [\($0.calendar.title)]" }
               .joined(separator: "\n")
}

func createEvent(store: EKEventStore, title: String, startStr: String, endStr: String,
                 calendarName: String?, notes: String?) -> String {
    guard let startDate = parseDateTime(startStr) else { return "ERROR: Invalid start: \(startStr)" }
    guard let endDate   = parseDateTime(endStr)   else { return "ERROR: Invalid end: \(endStr)" }
    let cal: EKCalendar
    if let name = calendarName {
        guard let found = store.calendars(for: .event).first(where: { $0.title == name }) else {
            return "ERROR: Calendar '\(name)' not found."
        }
        cal = found
    } else {
        if let preferred = store.calendars(for: .event).first(where: { $0.title == "roxana@rocksgy.com" }) {
            cal = preferred
        } else {
            guard let def = store.defaultCalendarForNewEvents else { return "ERROR: No default calendar." }
            cal = def
        }
    }
    let event = EKEvent(eventStore: store)
    event.title = title; event.startDate = startDate; event.endDate = endDate
    event.calendar = cal; event.notes = notes
    do {
        try store.save(event, span: .thisEvent, commit: true)
        return "Event '\(title)' created successfully."
    } catch { return "ERROR: \(error.localizedDescription)" }
}

func deleteEvent(store: EKEventStore, title: String, dateStr: String) -> String {
    guard let d = parseDate(dateStr) else { return "ERROR: Invalid date: \(dateStr)" }
    let start = Calendar.current.startOfDay(for: d)
    let end   = Calendar.current.date(byAdding: .day, value: 1, to: start)!
    let pred  = store.predicateForEvents(withStart: start, end: end, calendars: nil)
    let matches = store.events(matching: pred).filter { ($0.title ?? "") == title }
    do {
        for e in matches { try store.remove(e, span: .thisEvent, commit: false) }
        if !matches.isEmpty { try store.commit() }
        return "Event '\(title)' deleted."
    } catch { return "ERROR: \(error.localizedDescription)" }
}

// MARK: - Entry point
guard CommandLine.arguments.count == 3 else {
    fputs("Usage: calendar_helper <subcommand> <json>\n", stderr); exit(1)
}
let subcommand = CommandLine.arguments[1]
guard let data = CommandLine.arguments[2].data(using: .utf8),
      let args = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
    fputs("ERROR: Invalid JSON\n", stderr); exit(1)
}

let store = EKEventStore()
guard authorize(store: store) else {
    print("ERROR: Calendar access not authorized."); exit(1)
}

switch subcommand {
case "get_upcoming_events":
    print(getUpcomingEvents(store: store,
        days: (args["days"] as? Int) ?? 7,
        calendarName: args["calendar"] as? String))
case "search_events":
    print(searchEvents(store: store,
        query: (args["query"] as? String) ?? "",
        days:  (args["days"] as? Int) ?? 30))
case "create_event":
    print(createEvent(store: store,
        title:       (args["title"]    as? String) ?? "",
        startStr:    (args["start"]    as? String) ?? "",
        endStr:      (args["end_time"] as? String) ?? "",
        calendarName: args["calendar"] as? String,
        notes:        args["notes"]    as? String))
case "delete_event":
    print(deleteEvent(store: store,
        title:   (args["title"] as? String) ?? "",
        dateStr: (args["date"]  as? String) ?? ""))
default:
    fputs("ERROR: Unknown subcommand '\(subcommand)'\n", stderr); exit(1)
}
