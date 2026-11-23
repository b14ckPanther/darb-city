import Foundation

/// Whether a place is open, and the plain words to say it in.
struct Status: Sendable, Equatable {
    enum State: Sendable { case open, closingSoon, appointment, closed }
    let state: State
    /// In full: "פתוח עד 22:00", "סגור, נפתח ב 8:00".
    let text: String
    /// Short form for tight spaces: "עד 22:00", "24 שעות", "נפתח 8:00".
    let short: String
    /// Just the hour of the short form, for the tightest spaces: "22:00".
    var hour: String = ""
    /// Closed, and it does not open again today.
    var closedForToday = false

    var isOpen: Bool { state == .open || state == .closingSoon }
    /// Open first, then by appointment, then closed.
    var rank: Int { isOpen ? 0 : state == .appointment ? 1 : 2 }
}

enum OpenHours {
    static func clock(_ m: Int) -> String {
        let v = ((m % 1440) + 1440) % 1440
        return "\(v / 60):" + String(format: "%02d", v % 60)
    }

    static func weekday(_ date: Date, calendar: Calendar = .current) -> Int { calendar.component(.weekday, from: date) - 1 }
    static func minuteOfDay(_ date: Date, calendar: Calendar = .current) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// A weekday's name in the language in use; 0 is Sunday.
    static func dayName(_ day: Int) -> String {
        L(["ראשון", "שני", "שלישי", "רביעי", "חמישי", "שישי", "שבת"][((day % 7) + 7) % 7])
    }

    /// The spans covering a date, as minutes of that day; a span that ran past midnight yesterday shows up as [0, close].
    static func spans(_ hours: Hours, on date: Date, calendar: Calendar = .current) -> [ClosedRange<Int>]? {
        guard case .weekly(let week) = hours else { return nil }
        let day = weekday(date, calendar: calendar)
        var out: [ClosedRange<Int>] = []
        for s in week[day] ?? [] { out.append(s.open...(s.close <= s.open ? 1440 : s.close)) }
        for s in week[(day + 6) % 7] ?? [] where s.close <= s.open && s.close > 0 { out.append(0...s.close) }
        return out
    }

    static func status(_ hours: Hours, at date: Date, calendar: Calendar = .current) -> Status {
        switch hours {
        case .appointment: return Status(state: .appointment, text: L("בתיאום מראש"), short: L("בתיאום"))
        case .unknown: return Status(state: .closed, text: L("אין שעות פתיחה"), short: L("אין שעות"))
        case .weekly: break
        }
        let sp = spans(hours, on: date, calendar: calendar) ?? []
        let m = minuteOfDay(date, calendar: calendar)
        if sp.contains(where: { $0.lowerBound == 0 && $0.upperBound >= 1440 }) {
            return Status(state: .open, text: L("פתוח 24 שעות"), short: L("24 שעות"), hour: L("24 שעות"))
        }
        if let cur = sp.first(where: { m >= $0.lowerBound && m < $0.upperBound }) {
            let left = cur.upperBound - m
            let until = cur.upperBound >= 1440 ? L("אחרי חצות") : clock(cur.upperBound)
            if left <= 45 { return Status(state: .closingSoon, text: L("נסגר בעוד %lld דק׳", left), short: L("עד %@", until), hour: until) }
            return Status(state: .open, text: L("פתוח עד %@", until), short: L("עד %@", until), hour: until)
        }
        if let next = sp.filter({ $0.lowerBound > m }).min(by: { $0.lowerBound < $1.lowerBound }) {
            let at = clock(next.lowerBound)
            return Status(state: .closed, text: L("סגור, נפתח ב %@", at), short: L("נפתח %@", at), hour: at)
        }
        return Status(state: .closed, text: L("סגור היום"), short: L("סגור"), hour: L("סגור"), closedForToday: true)
    }

    /// How many minutes are left until closing, when the place is open now; nil when it is closed or open all day.
    static func minutesLeft(_ hours: Hours, at date: Date, calendar: Calendar = .current) -> Int? {
        let sp = spans(hours, on: date, calendar: calendar) ?? []
        let m = minuteOfDay(date, calendar: calendar)
        if sp.contains(where: { $0.lowerBound == 0 && $0.upperBound >= 1440 }) { return nil }
        guard let cur = sp.first(where: { m >= $0.lowerBound && m < $0.upperBound }) else { return nil }
        // a span that ends at midnight may carry on into the next day's early hours
        if cur.upperBound >= 1440, let more = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)),
           let tail = spans(hours, on: more, calendar: calendar)?.first(where: { $0.lowerBound == 0 }) {
            return 1440 - m + (tail.upperBound >= 1440 ? 1440 : tail.upperBound)
        }
        return cur.upperBound - m
    }

    /// Whether a place that is open now will still be open after a drive of `minutes`.
    static func openOnArrival(_ hours: Hours, at date: Date, drive minutes: Int, calendar: Calendar = .current) -> Bool {
        guard status(hours, at: date, calendar: calendar).isOpen else { return false }
        guard let left = minutesLeft(hours, at: date, calendar: calendar) else { return true }
        return left > minutes
    }

    /// The next moment the place opens after `date`, looking a week ahead; nil when it has no weekly hours or never opens.
    static func nextOpening(_ hours: Hours, after date: Date, calendar: Calendar = .current) -> Date? {
        guard case .weekly(let week) = hours else { return nil }
        let day = weekday(date, calendar: calendar), m = minuteOfDay(date, calendar: calendar)
        let start = calendar.startOfDay(for: date)
        for off in 0..<8 {
            let opens = (week[(day + off) % 7] ?? []).map(\.open).filter { off > 0 || $0 > m }
            guard let o = opens.min(), let d = calendar.date(byAdding: .day, value: off, to: start) else { continue }
            return calendar.date(bySettingHour: o / 60, minute: o % 60, second: 0, of: d)
        }
        return nil
    }

    /// One weekday's hours in plain words: "8:00 עד 17:00", "24 שעות", "סגור".
    static func dayText(_ hours: Hours, day: Int) -> String {
        switch hours {
        case .appointment: return L("בתיאום")
        case .unknown: return L("לא ידוע")
        case .weekly(let w):
            let s = w[day] ?? []
            if s.isEmpty { return L("סגור") }
            return s.map { sp in
                if sp.open == 0 && (sp.close == 0 || sp.close >= 1440) { return L("24 שעות") }
                return L("%@ עד %@", clock(sp.open), clock(sp.close))
            }.joined(separator: ", ")
        }
    }
}
