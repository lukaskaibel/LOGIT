//
//  SummaryStatScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 29.06.26.
//

import SwiftUI

/// Detail screen behind a Summary core-stat tile: the stat across recent history, scoped by the
/// shared `PeriodPicker` and read either **per workout** (the default, matching the tile — a typical
/// session with frequency divided out) or as the period's running **total**, flipped with the
/// `StatBasisPicker`. The tile shows the current period; the screen zooms out to the last several
/// periods, the current one highlighted. One screen serves all four stats — `WorkoutStatMetric`
/// supplies values, formatting, and the about text. Pro, like the other stat detail screens (the tile
/// is the free hook).
struct SummaryStatScreen: View {
    let metric: WorkoutStatMetric
    let workouts: [Workout]

    @State private var period: StatPeriod
    /// The tiles are always per-workout (a typical session); the screen opens the same way but lets
    /// the reader flip to the period's running total.
    @State private var basis: StatBasis = .perWorkout

    init(metric: WorkoutStatMetric, workouts: [Workout], initialPeriod: StatPeriod = .week) {
        self.metric = metric
        self.workouts = workouts
        _period = State(initialValue: initialPeriod)
    }

    private var isDuration: Bool { metric == .duration }

    var body: some View {
        ScrollView {
            VStack(spacing: SECTION_SPACING) {
                VStack(spacing: 16) {
                    PeriodPicker(selection: $period)
                    PeriodStatChartView(
                        period: period,
                        buckets: buckets,
                        firstDataDate: firstDataDate,
                        valueLabel: metric.title,
                        unit: metric.unit,
                        currentBarStyle: AnyShapeStyle(isDuration ? Color.secondary : Color.accentColor),
                        currentLabel: period.currentPeriodLabel,
                        currentValue: currentValue,
                        currentRaw: currentRaw,
                        trailingValueStyle: isDuration ? AnyShapeStyle(Color.label) : AnyShapeStyle(Color.accentColor.gradient),
                        positiveColor: isDuration ? .secondary : .accentColor,
                        formatAverage: { metric.formattedAverage(rawAverage: $0) },
                        displayAverage: { metric.displayValue(fromRaw: Int($0.rounded())) },
                        explanation: NSLocalizedString("averageComparisonInfo", comment: "")
                    )
                }
                .padding(.horizontal)
                AboutSection(metricTitle: metric.title, text: metric.aboutText)
                    .padding(.horizontal)
            }
            .padding(.top)
            .padding(.bottom, SCROLLVIEW_BOTTOM_PADDING)
        }
        .isBlockedWithoutPro()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(metric.title)
                    .font(.headline)
            }
            // The Per Workout / Total switch lives in the nav bar — a menu keeps the chart area to the
            // single Week / Month / Year scope, and the checkmarked options say which basis is showing.
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker(NSLocalizedString("basis", comment: ""), selection: $basis) {
                        ForEach(StatBasis.allCases) { basis in
                            Text(basis.title).tag(basis)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .accessibilityLabel(NSLocalizedString("basis", comment: ""))
                }
            }
        }
    }

    // MARK: - Data

    /// Sum of the metric and the non-empty workout count per period start, built in one pass so the
    /// scrollable chart looks each period up instead of re-scanning per bar. The count is the
    /// per-workout divisor — matching the "N workouts" the weekly-goal hero counts — and empty
    /// workouts are left out: they add nothing to the sum yet would inflate the count and drag an
    /// average down. Keyed the way `scrollableBuckets` looks periods up: `currentRange(containing:).lowerBound`.
    private var aggregatesByPeriodStart: [Date: (sum: Int, count: Int)] {
        var dict: [Date: (sum: Int, count: Int)] = [:]
        for workout in workouts where !workout.isEmpty {
            guard let date = workout.date else { continue }
            let start = period.currentRange(containing: date).lowerBound
            var entry = dict[start] ?? (sum: 0, count: 0)
            entry.sum += metric.rawValue(of: workout)
            entry.count += 1
            dict[start] = entry
        }
        return dict
    }

    /// The current period's sum and workout count.
    private var currentAggregate: (sum: Int, count: Int) {
        aggregatesByPeriodStart[period.currentRange().lowerBound] ?? (sum: 0, count: 0)
    }

    /// The current period's value in raw units for the chosen basis — the per-workout average or the
    /// running total. Drives the header's trend against the visible-window average.
    private var currentRaw: Double {
        basis.aggregate(sum: currentAggregate.sum, count: currentAggregate.count)
    }

    /// The current period's headline string: the total formatted whole, or the per-workout average
    /// with its fractional precision kept (for the small set / rep counts). "––" when nothing was
    /// logged — there is no session to average, and a "0" total would read as a decline.
    private var currentValue: String {
        switch basis {
        case .total:
            return metric.formattedValue(fromRaw: currentAggregate.sum)
        case .perWorkout:
            return currentAggregate.count > 0 ? metric.formattedAverage(rawAverage: currentRaw) : "––"
        }
    }

    /// Earliest recorded workout — the left end of the scrollable domain.
    private var firstDataDate: Date? {
        workouts.compactMap { $0.date }.min()
    }

    /// Each period start mapped to its basis value — the per-workout average or the total — for the
    /// scrollable history bars.
    private var rawByPeriodStart: [Date: Double] {
        aggregatesByPeriodStart.mapValues { basis.aggregate(sum: $0.sum, count: $0.count) }
    }

    private var buckets: [PeriodHistoryChart.Bucket] {
        PeriodHistoryChart.scrollableBuckets(
            for: period,
            rawByPeriodStart: rawByPeriodStart,
            firstDataDate: firstDataDate,
            display: { metric.displayValue(fromRaw: Int($0.rounded())) },
            formatted: {
                basis == .total
                    ? metric.formattedValue(fromRaw: Int($0.rounded()))
                    : metric.formattedAverage(rawAverage: $0)
            }
        )
    }
}
