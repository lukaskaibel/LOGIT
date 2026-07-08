//
//  SummaryStatTiles.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 29.06.26.
//

import SwiftUI

// MARK: - Summary Stat Tile

/// One period-scoped core stat on the Summary screen — the shared `MetricTile` carrying a Summary
/// value: the sum over the selected period, the change versus the prior period, and a five-bucket
/// history bar chart with the current period highlighted. Parallel to `WorkoutStatTile` (which is
/// hardwired to "this workout vs prior runs"), but reading the period block's window instead.
///
/// The highlighted bar always uses the app accent — it marks "this week" (the current period). The
/// trend pill tints with the accent for a genuine gain and mutes to gray for a decline or no change
/// (handled by `TrendIndicatorView`) — the same rule for every metric, duration included.
struct SummaryStatTile: View {
    let metric: WorkoutStatMetric
    let data: SummaryViewModel.StatData
    let onOpen: () -> Void

    /// Positive trends carry the app accent; `TrendIndicatorView` mutes declines and flat weeks to
    /// gray on its own, so the pill just supplies the accent as the "up" tint.
    private var pillColor: Color { .accentColor }

    var body: some View {
        Button(action: onOpen) {
            MetricTile(
                title: metric.title,
                label: .none,
                // A period sum is a real value even at zero ("0 sets this week"), clearer than the
                // "––" no-data dash; the trend pill is suppressed when empty so a blank week never
                // reads as a misleading "100 % decline".
                value: metric.formattedValue(fromRaw: data.rawValue),
                unit: metric.unit,
                accent: AnyShapeStyle(pillColor),
                accentColor: pillColor,
                percentChange: data.rawValue > 0 ? data.percentChange : nil,
                requiresPro: metric.requiresPro,
                chartBleeds: false
            ) {
                // The highlighted "this week" bar always uses the accent, even for duration — it marks
                // the current period, not a judgement, so it reads the same as the other tiles.
                WorkoutRunsBarChart(bars: bars, currentStyle: AnyShapeStyle(Color.accentColor))
            }
        }
        .buttonStyle(TileButtonStyle())
    }

    /// The five history buckets right-aligned into the fixed five-slot chart, newest (current period)
    /// last and highlighted.
    private var bars: [WorkoutRunsBarChart.Bar] {
        let count = data.buckets.count
        return data.buckets.enumerated().map { index, value in
            WorkoutRunsBarChart.Bar(slot: index, value: value, isCurrent: index == count - 1)
        }
    }
}

// MARK: - Summary Stat Grid

/// The Summary screen's 2×2 core-stats grid — volume and duration, then sets and reps — scoped to the
/// view model's selected period, each tile a button into its `SummaryStatScreen`. Collapses to one
/// column at accessibility type sizes, like the workout-detail grid.
struct SummaryStatTileGrid: View {
    @ObservedObject var viewModel: SummaryViewModel
    let workouts: [Workout]
    let onOpenDetail: (WorkoutStatMetric) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let spacing: CGFloat = 10

    var body: some View {
        let period = viewModel.selectedPeriod
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: spacing) {
                ForEach(WorkoutStatMetric.allCases) { metric in
                    tile(metric, period: period)
                }
            }
        } else {
            VStack(spacing: spacing) {
                HStack(alignment: .top, spacing: spacing) {
                    tile(.volume, period: period)
                    tile(.duration, period: period)
                }
                HStack(alignment: .top, spacing: spacing) {
                    tile(.sets, period: period)
                    tile(.repetitions, period: period)
                }
            }
        }
    }

    private func tile(_ metric: WorkoutStatMetric, period: StatPeriod) -> some View {
        SummaryStatTile(
            metric: metric,
            data: viewModel.statData(for: metric, period: period, workouts: workouts),
            onOpen: { onOpenDetail(metric) }
        )
    }
}
