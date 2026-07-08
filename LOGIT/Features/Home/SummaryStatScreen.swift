//
//  SummaryStatScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 29.06.26.
//

import SwiftUI

/// Detail screen behind a Summary core-stat tile: the stat summed per period across recent history,
/// scoped by the shared `PeriodPicker`. The tile shows the current period; the screen zooms out to the
/// last several periods, the current one highlighted. One screen serves all four stats —
/// `WorkoutStatMetric` supplies values, formatting, and the about text. Pro, like the other stat
/// detail screens (the tile is the free hook).
struct SummaryStatScreen: View {
    let metric: WorkoutStatMetric
    let workouts: [Workout]

    @State private var period: StatPeriod

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
                        currentValue: metric.formattedValue(fromRaw: currentRaw),
                        currentRaw: currentRaw,
                        trailingValueStyle: isDuration ? AnyShapeStyle(Color.label) : AnyShapeStyle(Color.accentColor.gradient),
                        positiveColor: isDuration ? .secondary : .accentColor,
                        formatAverage: { metric.formattedAverage(rawAverage: Double($0)) },
                        displayAverage: { metric.displayValue(fromRaw: $0) },
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
        }
    }

    // MARK: - Data

    private var currentRaw: Int { sum(in: period.currentRange()) }

    /// Earliest recorded workout — the left end of the scrollable domain.
    private var firstDataDate: Date? {
        workouts.compactMap { $0.date }.min()
    }

    /// The metric summed per period start, in one pass over the workouts so the scrollable chart looks
    /// each period up instead of re-summing per bar. Keyed the same way `scrollableBuckets` keys its
    /// lookups — `currentRange(containing:).lowerBound`.
    private var rawByPeriodStart: [Date: Int] {
        var dict: [Date: Int] = [:]
        for workout in workouts {
            guard let date = workout.date else { continue }
            let start = period.currentRange(containing: date).lowerBound
            dict[start, default: 0] += metric.rawValue(of: workout)
        }
        return dict
    }

    private func sum(in range: ClosedRange<Date>) -> Int {
        workouts
            .filter { ($0.date).map { range.contains($0) } ?? false }
            .reduce(0) { $0 + metric.rawValue(of: $1) }
    }

    private var buckets: [PeriodHistoryChart.Bucket] {
        PeriodHistoryChart.scrollableBuckets(
            for: period,
            rawByPeriodStart: rawByPeriodStart,
            firstDataDate: firstDataDate,
            display: { metric.displayValue(fromRaw: $0) },
            formatted: { metric.formattedValue(fromRaw: $0) }
        )
    }
}
