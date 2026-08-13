//
//  SummaryStatTiles.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 29.06.26.
//

import Charts
import SwiftUI

// MARK: - Bin Strip

/// The mini bar chart under a Summary stat tile's value: the selected window broken into its days,
/// weeks or months, **every bar in the accent** because every bar is inside the timeframe the picker
/// names. An untrained bin draws no bar, so a strip of days shows the rhythm of a training week for
/// free — three bars, a gap, two bars.
///
/// It replaced a five-slot strip of whole *windows* with only the last one tinted, which meant a tile
/// set to "4 weeks" spent four fifths of its chart on the twenty weeks before them. Sized in ratios
/// rather than points (see `TileBarChartStyle.footerBarWidth`) so twenty-eight bars in a half-width
/// tile stay bars rather than becoming tally marks.
struct SummaryBinStrip: View {
    /// Bin values in display units, oldest → newest. Zero means untrained.
    let bins: [Double]
    let style: AnyShapeStyle

    var body: some View {
        let maxValue = bins.max() ?? 0
        Chart {
            ForEach(Array(bins.enumerated()), id: \.offset) { index, value in
                if value > 0 {
                    BarMark(
                        x: .value("Bin", String(index)),
                        y: .value("Value", value),
                        width: TileBarChartStyle.footerBarWidth
                    )
                    .foregroundStyle(style)
                    .tileBarStyle()
                }
            }
        }
        .chartXScale(domain: (0 ..< max(bins.count, 1)).map(String.init))
        .chartYScale(domain: 0 ... max(maxValue, 1))
        .chartXAxis {}
        .chartYAxis {}
        .overlay {
            if maxValue <= 0 {
                Text(NSLocalizedString("noData", comment: ""))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Summary Stat Tile

/// One window-scoped core stat on the Summary screen — the shared `MetricTile` carrying a Summary
/// value: the *per-workout average* over the screen's selected `TrendWindow` (a typical session,
/// frequency divided out), the change versus the previous window's average, and a strip of that same
/// window's bins underneath. The "per workout" subtitle names the basis right under the number.
/// Parallel to `WorkoutStatTile` (which is hardwired to "this workout vs prior runs"), but reading the
/// Summary's one timeframe instead.
///
/// The tile carries no caption naming its window, deliberately: the picker at the top of the screen
/// names it once for everything below, which is the whole point of there being one picker. Everything
/// on the tile now honours that — the number, the percentage, and every bar are the selected window
/// and nothing else, so reading "10,000 kg" and "+8%" off one tile and "+3.5%" off the Strength tile
/// beside it are statements about the same four weeks.
///
/// There is no "building your trend" placeholder any more. It existed because one lone bar among five
/// windows read as a half-loaded tile; a single bar among twenty-eight days is just a true statement
/// about a window with one workout in it. A window with nothing in it still shows "––" and the shared
/// chart's own no-data treatment.
///
/// Every bar uses the app accent. The trend pill tints with the accent for a genuine gain and mutes to
/// gray for a decline or no change (handled by `TrendIndicatorView`) — the same rule for every metric,
/// duration included.
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
                    // One lone bar in an otherwise empty strip doesn't read as "you trained once" —
                    // it reads as a half-loaded tile, and it sits beside a Strength tile that says
                    // "building your strength trend" in exactly this situation. Show the same hint
                    // until the window holds something to see; the bars return on their own.
                    TrendPlaceholder(progress: data.historyFraction, text: NSLocalizedString("buildingYourTrend", comment: ""))
                } else {
                    // Every bar the accent, even on the duration tile — the bars mark the window, not
                    // a judgement, so they read like the other three tiles.
                    SummaryBinStrip(bins: data.bins, style: AnyShapeStyle(Color.accentColor))
                }
            }
        }
        .buttonStyle(TileButtonStyle())
    }

    /// A single trained bin is a stripe, not a chart. Swap it for the placeholder, but only once the
    /// window itself has a value: an all-empty tile already shows "––" and keeps the strip's own
    /// no-data treatment.
    ///
    /// The threshold is *bins with training*, not windows with data as it was when a bar was a whole
    /// window — the strip is inside one window now, so "is there enough here to draw" is a question
    /// about this window alone.
    private var showsTrendPlaceholder: Bool {
        data.hasData && data.bins.filter { $0 > 0 }.count < 2
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
