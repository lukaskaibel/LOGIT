//
//  SearchQuery.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 18.09.25.
//

import Foundation

/// A search query after parsing: the free text that is left over, plus the date
/// constraints that were lifted out of it.
///
/// "bench" parses to text "bench" with no tokens, "dezember 2024" to no text and
/// one `.month(12, year: 2024)` token, "bench dezember" to both. Several tokens
/// are combined with AND, so "dezember montag" means every Monday in December.
struct SearchQuery: Equatable {
    /// What the user typed with every recognised date word removed.
    let text: String
    /// The date constraints, in the order they were recognised.
    let dateTokens: [SearchDateToken]

    var isEmpty: Bool { text.isEmpty && dateTokens.isEmpty }
    var hasDateConstraint: Bool { !dateTokens.isEmpty }

    /// Whether `date` satisfies every date token. A query without tokens matches
    /// any date.
    func matchesDate(_ date: Date?, calendar: Calendar = .current) -> Bool {
        guard !dateTokens.isEmpty else { return true }
        guard let date = date else { return false }
        return dateTokens.allSatisfy { $0.matches(date, calendar: calendar) }
    }
}

/// One date constraint lifted out of a search query.
enum SearchDateToken: Hashable, Identifiable {
    /// A single calendar day — "today", "yesterday", "15.09.2025".
    case day(Date)
    /// A calendar month, optionally pinned to a year. Without a year it means
    /// *every* December in the history, not the most recent one.
    case month(Int, year: Int?)
    /// A whole calendar year.
    case year(Int)
    /// Every Monday, every Tuesday … in `Calendar`'s 1-based weekday numbering.
    case weekday(Int)
    /// A span that already carries its own name — this week, last week.
    case span(DateInterval, name: String)

    var id: String {
        switch self {
        case let .day(date): return "day-\(date.timeIntervalSinceReferenceDate)"
        case let .month(month, year): return "month-\(month)-\(year.map(String.init) ?? "any")"
        case let .year(year): return "year-\(year)"
        case let .weekday(weekday): return "weekday-\(weekday)"
        case let .span(interval, name): return "span-\(name)-\(interval.start.timeIntervalSinceReferenceDate)"
        }
    }

    func matches(_ date: Date, calendar: Calendar = .current) -> Bool {
        switch self {
        case let .day(day):
            return calendar.isDate(date, inSameDayAs: day)
        case let .month(month, year):
            let components = calendar.dateComponents([.month, .year], from: date)
            guard components.month == month else { return false }
            guard let year = year else { return true }
            return components.year == year
        case let .year(year):
            return calendar.component(.year, from: date) == year
        case let .weekday(weekday):
            return calendar.component(.weekday, from: date) == weekday
        case let .span(interval, _):
            // Half-open on purpose. `DateInterval.contains` includes its end
            // instant, and a week's end *is* the next week's first midnight —
            // which is exactly when a workout logged at 00:00 sits, so "last
            // week" would quietly pull in this week's Monday.
            return date >= interval.start && date < interval.end
        }
    }

    /// The text of the chip shown above the results, so it is always visible what
    /// the app understood the query to mean.
    func label(calendar: Calendar = .current, locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        switch self {
        case let .day(date):
            if calendar.isDateInToday(date) { return NSLocalizedString("today", comment: "") }
            if calendar.isDateInYesterday(date) { return NSLocalizedString("yesterday", comment: "") }
            formatter.dateStyle = .medium
            return formatter.string(from: date)
        case let .month(month, year):
            formatter.setLocalizedDateFormatFromTemplate(year == nil ? "MMMM" : "MMMMy")
            let components = DateComponents(year: year ?? 2000, month: month, day: 1)
            guard let date = calendar.date(from: components) else { return "" }
            return formatter.string(from: date)
        case let .year(year):
            formatter.setLocalizedDateFormatFromTemplate("y")
            guard let date = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) else { return "" }
            return formatter.string(from: date)
        case let .weekday(weekday):
            let symbols = formatter.standaloneWeekdaySymbols ?? formatter.weekdaySymbols ?? []
            guard symbols.indices.contains(weekday - 1) else { return "" }
            return symbols[weekday - 1]
        case let .span(_, name):
            return name
        }
    }
}
