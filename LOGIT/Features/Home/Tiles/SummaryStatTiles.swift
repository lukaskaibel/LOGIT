//
//  SummaryStatTiles.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 29.06.26.
//

import SwiftUI

// MARK: - Summary Stat Tile

/// One window-scoped core stat on the Summary screen — the shared `MetricTile` carrying a Summary
/// value: the *per-workout average* over the screen's selected `TrendWindow` (a typical session,
/// frequency divided out), the change versus the prior window's average, and a five-bucket history
/// bar chart with the current window highlighted. The "per workout" subtitle names the basis right
/// under the number. Parallel to `WorkoutStatTile` (which is hardwired to "this workout vs prior
/// runs"), but reading the Summary's one timeframe instead.
///
/// The tile carries no caption naming its window, deliberately: the picker at the top of the screen
/// names it once for everything below, which is the whole point of there being one picker.
///
/// The highlighted bar always uses the app accent — it marks the current window. The trend pill
/// tints with the accent for a genuine gain and mutes to gray for a decline or no change (handled by
/// `TrendIndicatorView`) — the same rule for every metric, duration included.
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
                    // a second window has data, show a quiet "building your trend" hint instead; the real
                    // bars return on their own once there's something to compare.
                    TrendPlaceholder(progress: data.historyFraction, text: NSLocalizedString("buildingYourTrend", comment: ""))
                } else {
                    // The highlighted current-window bar always uses the accent, even for duration —
                    // it marks the window, not a judgement, so it reads like the other tiles.
                    WorkoutRunsBarChart(bars: bars, currentStyle: AnyShapeStyle(Color.accentColor))
                }
            }
        }
        .buttonStyle(TileButtonStyle())
    }

    /// Fewer than two windows with data means there's no trend to plot yet — a single bar, or none.
    /// Swap the bar chart for the placeholder, but only once this window itself has a value: an
    /// all-empty tile already shows "––" and keeps the shared chart's own no-data treatment.
    private var showsTrendPlaceholder: Bool {
        data.hasData && windowsWithData < 2
    }

    /// Windows in the five-bucket strip that have data — gates the placeholder (a lone window isn't
    /// a trend).
    private var windowsWithData: Int {
        data.buckets.filter { $0 > 0 }.count
    }

    /// The five history buckets right-aligned into the fixed five-slot chart, newest (current window)
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
/// screen's selected `TrendWindow`, each tile a button into its `SummaryStatScreen` on that same
/// window. Collapses to one column at accessibility type sizes, like the workout-detail grid.
struct SummaryStatTileGrid: View {
    @ObservedObject var viewModel: SummaryViewModel
    let workouts: [Workout]
    /// The Summary's one timeframe, owned by the screen and passed down — see `TrendWindow`.
    let window: TrendWindow
    let onOpenDetail: (WorkoutStatMetric) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The gap between tiles. Exposed because the Strength + Balance pair above the grid sits on the
    /// same rhythm — the six tiles are one block reading one window, not two sections.
    static let tileSpacing: CGFloat = 10

    private var spacing: CGFloat { Self.tileSpacing }

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: spacing) {
                ForEach(WorkoutStatMetric.allCases) { metric in
                    tile(metric)
                }
            }
        } else {
            VStack(spacing: spacing) {
                HStack(alignment: .top, spacing: spacing) {
                    tile(.volume)
                    tile(.duration)
                }
                HStack(alignment: .top, spacing: spacing) {
                    tile(.sets)
                    tile(.repetitions)
                }
            }
        }
    }

    private func tile(_ metric: WorkoutStatMetric) -> some View {
        SummaryStatTile(
            metric: metric,
            data: viewModel.statData(for: metric, window: window, workouts: workouts),
            onOpen: { onOpenDetail(metric) }
        )
    }
}
