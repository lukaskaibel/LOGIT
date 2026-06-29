//
//  StatPeriod.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 29.06.26.
//

import Foundation

/// The Week / Month / Year scope shared by the Summary screen's period selector and the stat detail
/// screens. The single source of truth for "the current period", "the equivalent prior period", and
/// the localized segment titles — replacing the per-screen private `ChartGranularity` enums every
/// detail screen used to declare on its own.
enum StatPeriod: String, CaseIterable, Identifiable {
    case week, month, year

    var id: String { rawValue }

    /// Localized segment title ("Week" / "Month" / "Year"), reusing the keys the detail-screen
    /// granularity pickers already ship.
    var title: String { NSLocalizedString(rawValue, comment: "") }

    /// The closed date range of the period containing `date` — this calendar week, month, or year.
    /// Built on the `Date.startOf…`/`endOf…` helpers so the week boundary respects the user's locale.
    func currentRange(containing date: Date = .now) -> ClosedRange<Date> {
        switch self {
        case .week: return date.startOfWeek ... date.endOfWeek
        case .month: return date.startOfMonth ... date.endOfMonth
        case .year: return date.startOfYear ... date.endOfYear
        }
    }

    /// The equivalent prior period before the one containing `date` — last week / last month / last
    /// year. Load-bearing for every "vs last period" trend pill in the stats grid: the trend compares
    /// `currentRange` against this.
    func previousRange(before date: Date = .now) -> ClosedRange<Date> {
        range(periodsAgo: 1, from: date)
    }

    /// The closed range of the period `n` periods before the one containing `date` — `n == 0` is the
    /// current period, `n == 1` the previous. Powers the stats grid's 5-bucket history bars and the
    /// detail screen's recent-periods chart.
    func range(periodsAgo n: Int, from date: Date = .now) -> ClosedRange<Date> {
        let component: Calendar.Component
        switch self {
        case .week: component = .weekOfYear
        case .month: component = .month
        case .year: component = .year
        }
        let shifted = Calendar.current.date(byAdding: component, value: -n, to: date) ?? date
        return currentRange(containing: shifted)
    }
}
