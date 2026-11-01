// AgeCalc.swift — age computation, captions, milestones.
// Foundation only; exercised by tools/check-pure.swift.
// Grammar law applies: every count string is singular/plural correct.

import Foundation

public struct AgeParts: Equatable {
    public let years: Int
    public let months: Int
    public let days: Int
    public init(years: Int, months: Int, days: Int) {
        self.years = years; self.months = months; self.days = days
    }
}

public func ageParts(birth: Date, at: Date, calendar: Calendar = .current) -> AgeParts {
    let c = calendar.dateComponents([.year, .month, .day], from: birth, to: at)
    return AgeParts(years: max(0, c.year ?? 0),
                    months: max(0, c.month ?? 0),
                    days: max(0, c.day ?? 0))
}

/// Total whole months of age (for the shape prior's age bands).
public func ageInMonths(birth: Date, at: Date, calendar: Calendar = .current) -> Double {
    let p = ageParts(birth: birth, at: at, calendar: calendar)
    return Double(p.years * 12 + p.months) + Double(p.days) / 30.44
}

private func plural(_ n: Int, _ one: String, _ many: String) -> String {
    "\(n) \(n == 1 ? one : many)"
}

/// "3 months, 12 days" / "1 month, 1 day" / "2 weeks, 3 days" /
/// "1 year, 2 months" / "Today" on the birth day itself.
public func ageText(birth: Date, at: Date, calendar: Calendar = .current) -> String {
    let p = ageParts(birth: birth, at: at, calendar: calendar)
    if p.years > 0 {
        if p.months > 0 {
            return "\(plural(p.years, "year", "years")), \(plural(p.months, "month", "months"))"
        }
        return plural(p.years, "year", "years")
    }
    if p.months > 0 {
        if p.days > 0 {
            return "\(plural(p.months, "month", "months")), \(plural(p.days, "day", "days"))"
        }
        return plural(p.months, "month", "months")
    }
    if p.days == 0 { return "Today" }
    let weeks = p.days / 7
    let rem = p.days % 7
    if weeks > 0 {
        if rem > 0 {
            return "\(plural(weeks, "week", "weeks")), \(plural(rem, "day", "days"))"
        }
        return plural(weeks, "week", "weeks")
    }
    return plural(p.days, "day", "days")
}

/// Auto-suggested captions (spec §4): the family's words are offered,
/// never forced — the parent can always type their own.
public func captionSuggestions(name: String, birth: Date, at: Date,
                               calendar: Calendar = .current) -> [String] {
    let trimmed = name.trimmingCharacters(in: .whitespaces)
    let who = trimmed.isEmpty ? "Baby" : trimmed
    var out: [String] = []
    out.append("\(who) — \(ageText(birth: birth, at: at, calendar: calendar))")
    let fmt = DateFormatter()
    fmt.calendar = calendar
    fmt.locale = Locale(identifier: "en_US")
    fmt.dateFormat = "MMMM d, yyyy"
    out.append("\(who) — \(fmt.string(from: at))")
    if let m = milestoneNear(birth: birth, at: at, calendar: calendar) {
        out.append(m.title)
    }
    return out
}

public struct Milestone: Equatable {
    public let id: String
    public let title: String
    public let date: Date
    public init(id: String, title: String, date: Date) {
        self.id = id; self.title = title; self.date = date
    }
}

public func allMilestones(birth: Date, calendar: Calendar = .current) -> [Milestone] {
    var out: [Milestone] = []
    let monthMarks: [(Int, String)] = [
        (1, "One month"), (2, "Two months"), (3, "Three months"),
        (4, "Four months"), (6, "Six months"), (9, "Nine months"),
        (12, "One year"), (18, "Eighteen months"), (24, "Two years"),
    ]
    for (m, title) in monthMarks {
        if let d = calendar.date(byAdding: .month, value: m, to: birth) {
            out.append(Milestone(id: "month-\(m)", title: title, date: d))
        }
    }
    // First Christmas: the first Dec 25 on or after the birth date.
    let y = calendar.component(.year, from: birth)
    for year in [y, y + 1] {
        var dc = DateComponents()
        dc.year = year; dc.month = 12; dc.day = 25
        dc.hour = 12
        if let d = calendar.date(from: dc),
           calendar.startOfDay(for: d) >= calendar.startOfDay(for: birth) {
            out.append(Milestone(id: "first-christmas", title: "First Christmas", date: d))
            break
        }
    }
    // First Thanksgiving: the fourth Thursday of November (US).
    for year in [y, y + 1] {
        if let d = thanksgiving(year: year, calendar: calendar),
           calendar.startOfDay(for: d) >= calendar.startOfDay(for: birth) {
            out.append(Milestone(id: "first-thanksgiving", title: "First Thanksgiving", date: d))
            break
        }
    }
    return out.sorted { $0.date < $1.date }
}

private func thanksgiving(year: Int, calendar: Calendar) -> Date? {
    var dc = DateComponents()
    dc.year = year; dc.month = 11; dc.day = 1; dc.hour = 12
    guard let nov1 = calendar.date(from: dc) else { return nil }
    let weekday = calendar.component(.weekday, from: nov1) // 1 = Sunday … 5 = Thursday
    let toFirstThursday = (5 - weekday + 7) % 7
    return calendar.date(byAdding: .day, value: toFirstThursday + 21, to: nov1)
}

/// A milestone within ±windowDays of `at` (for caption suggestions).
public func milestoneNear(birth: Date, at: Date, windowDays: Int = 10,
                          calendar: Calendar = .current) -> Milestone? {
    let day = 86400.0
    return allMilestones(birth: birth, calendar: calendar)
        .filter { abs($0.date.timeIntervalSince(at)) <= Double(windowDays) * day }
        .min { abs($0.date.timeIntervalSince(at)) < abs($1.date.timeIntervalSince(at)) }
}

/// The next milestone still ahead (for the book's gentle prompt).
public func nextMilestone(birth: Date, at: Date,
                          calendar: Calendar = .current) -> Milestone? {
    allMilestones(birth: birth, calendar: calendar)
        .first { $0.date > at }
}
