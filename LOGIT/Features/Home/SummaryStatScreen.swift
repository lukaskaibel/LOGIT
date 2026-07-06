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
                    header
                    chart
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

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text(period.currentPeriodLabel)
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                // A period sum is a real value even at zero ("0 sets this week"), clearer than a
                // "––" no-data dash — same rule as the stat tiles.
                UnitView(
                    value: metric.formattedValue(fromRaw: currentRaw),
                    unit: metric.unit,
                    configuration: .large,
                    unitColor: .secondaryLabel
                )
                .foregroundStyle(isDuration ? AnyShapeStyle(Color.label) : AnyShapeStyle(Color.accentColor.gradient))
            }
            Spacer()
            if let percentChange {
                TrendIndicatorView(
                    percentChange: percentChange,
                    positiveColor: isDuration ? .secondary : .accentColor
                )
                .animation(.snappy, value: percentChange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Chart

    private var chart: some View {
        PeriodHistoryChart(
            buckets: buckets,
            period: period,
            valueLabel: metric.title,
            currentBarStyle: AnyShapeStyle(isDuration ? Color.secondary : Color.accentColor),
            unit: metric.unit
        )
    }

    // MARK: - Data

    private var currentRaw: Int { sum(in: period.currentRange()) }
    private var previousRaw: Int { sum(in: period.previousRange()) }

    private var percentChange: Double? {
        PeriodHistoryChart.trendPercentChange(current: currentRaw, previous: previousRaw)
    }

    private func sum(in range: ClosedRange<Date>) -> Int {
        workouts
            .filter { ($0.date).map { range.contains($0) } ?? false }
            .reduce(0) { $0 + metric.rawValue(of: $1) }
    }

    private var buckets: [PeriodHistoryChart.Bucket] {
        PeriodHistoryChart.buckets(
            for: period,
            value: { metric.displayValue(fromRaw: sum(in: $0)) },
            formatted: { metric.formattedValue(fromRaw: sum(in: $0)) }
        )
    }
}
