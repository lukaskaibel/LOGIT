//
//  SummaryStatTiles.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 29.06.26.
//

import SwiftUI

// MARK: - Summary Stat Tile

/// One period-scoped core stat on the Summary screen — the shared `MetricTile` carrying a Summary
/// value: the *per-workout average* over the selected period (a typical session, frequency divided
/// out), the change versus the prior period's average, and a five-bucket history bar chart with the
/// current period highlighted. The "per workout" subtitle names the basis right under the number.
/// Parallel to `WorkoutStatTile` (which is hardwired to "this workout vs prior runs"), but reading
/// the period block's window instead.
///
/// The highlighted bar always uses the app accent — it marks "this week" (the current period). The
/// trend pill tints with the accent for a genuine gain and mutes to gray for a decline or no change
/// (handled by `TrendIndicatorView`) — the same rule for every metric, duration included.
struct SummaryStatTile: View {
    let metric: WorkoutStatMetric
    let data: SummaryViewModel.StatData
    /// The scoped period — the placeholder ring reads how far through it we are.
    let period: StatPeriod
    let onOpen: () -> Void

    /// Positive trends carry the app accent; `TrendIndicatorView` mutes declines and flat weeks to
    /// gray on its own, so the pill just supplies the accent as the "up" tint.
    private var pillColor: Color { .accentColor }

    var body: some View {
        Button(action: onOpen) {
            MetricTile(
                title: metric.title,
                // "per workout" as a quiet qualifier under the title — a soft annotation on the value,
                // deliberately lighter than the title so the number stays the tile's focus.
                label: .caption(NSLocalizedString("perWorkout", comment: "")),
                // A per-workout average needs a session to exist: with no workout in the period there
                // is nothing to average, so show the "––" no-data dash rather than a misleading "0",
                // and suppress the trend pill (also nil'd upstream when either period is empty).
                value: data.hasData ? metric.formattedAverage(rawAverage: data.rawAverage, compact: true) : nil,
                unit: metric.unit,
                accent: AnyShapeStyle(pillColor),
                accentColor: pillColor,
                percentChange: data.hasData ? data.percentChange : nil,
                requiresPro: metric.requiresPro,
                chartBleeds: false
            ) {
                if showsTrendPlaceholder {
                    // One lone bar (or none) isn't a trend — it just reads as a half-loaded tile. Until
                    // a second period has data, show a quiet "building your trend" hint instead; the real
                    // bars return on their own once there's something to compare.
                    SummaryTrendPlaceholder(progress: trendProgress)
                } else {
                    // The highlighted "this week" bar always uses the accent, even for duration — it
                    // marks the current period, not a judgement, so it reads the same as the other tiles.
                    WorkoutRunsBarChart(bars: bars, currentStyle: AnyShapeStyle(Color.accentColor))
                }
            }
        }
        .buttonStyle(TileButtonStyle())
    }

    /// Fewer than two periods with data means there's no trend to plot yet — a single bar, or none.
    /// Swap the bar chart for the placeholder, but only once this period itself has a value: an
    /// all-empty tile already shows "––" and keeps the shared chart's own no-data treatment.
    private var showsTrendPlaceholder: Bool {
        data.hasData && periodsWithData < 2
    }

    /// Periods in the five-bucket window that have data — gates the placeholder (a lone period isn't
    /// a trend).
    private var periodsWithData: Int {
        data.buckets.filter { $0 > 0 }.count
    }

    /// The placeholder ring's fill — how far through the current period we are, so it creeps forward
    /// as the week (or month / year) goes on rather than sitting at a fixed mark.
    private var trendProgress: Double {
        period.elapsedFraction()
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

// MARK: - Trend Placeholder

/// The chart-slot placeholder a core-stat tile shows before it has a trend to draw — a quiet gray
/// progress ring (around a small bar-chart glyph) beside "Building your trend", sitting where the
/// bars would, so a brand-new week reads as *in progress* rather than an empty tile. All gray, no
/// accent: it's a nudge, not data — the honest answer to "there's nothing to chart yet" without
/// faking bars. The ring tracks how far through the current period the tile is, so it creeps forward
/// as the week goes on.
private struct SummaryTrendPlaceholder: View {
    /// How far through the current period we are (0…1) — the ring's fill.
    let progress: Double

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                Circle()
                    .stroke(Color.fill, lineWidth: 3)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.secondaryLabel, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    // Start at 12 o'clock and fill clockwise, like every other progress ring.
                    .rotationEffect(.degrees(-90))
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 30, height: 30)
            Text(NSLocalizedString("buildingYourTrend", comment: ""))
                .font(.caption.weight(.medium))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
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
            period: period,
            onOpen: { onOpenDetail(metric) }
        )
    }
}
