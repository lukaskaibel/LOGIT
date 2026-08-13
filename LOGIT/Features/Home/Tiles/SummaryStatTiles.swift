//
//  SummaryStatTiles.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 29.06.26.
//

import Charts
import SwiftUI

// MARK: - Bin Strip Grid

/// The reference grid behind a Summary bin strip: a hairline at **every** bin boundary — a day
/// across four weeks, a week across a quarter, a month across a year — the way the Fitness app's
/// tiles rule their day into hours. It is what turns a row of bars into a timeline: an untrained
/// stretch becomes a countable number of days rather than a vague space.
///
/// The grid **starts and ends on a rule**. The outermost two sit on the strip's first and last bin
/// boundary, clamped *into* the plot by their own width rather than centred on it, so neither loses
/// half of itself to the edge. A strip that faded out into open space would leave the reader
/// guessing where the window it draws actually stops.
///
/// Drawn straight rather than through `AxisMarks`: the strip's x-scale is categorical, so its plot
/// divides into exactly `binCount` equal slots and boundary `i` lands at `i / binCount` of the width
/// — arithmetic simple enough that owning it costs nothing and buys the edge rules an axis would
/// have clipped.
private struct SummaryBinGrid: View {
    let binCount: Int

    @Environment(\.displayScale) private var displayScale

    /// Two device pixels — the weight the Fitness app's ruling reads at. A whole point would put a
    /// fifth of the strip's width in grid lines once there are twenty-nine of them.
    private var hairline: CGFloat { 2 / displayScale }

    var body: some View {
        GeometryReader { geometry in
            let count = max(binCount, 1)
            let width = hairline
            ZStack(alignment: .topLeading) {
                ForEach(0 ... count, id: \.self) { index in
                    Rectangle()
                        .fill(Color.separator)
                        .frame(width: width, height: geometry.size.height)
                        .offset(
                            x: min(
                                max(CGFloat(index) / CGFloat(count) * geometry.size.width - width / 2, 0),
                                max(geometry.size.width - width, 0)
                            )
                        )
                }
            }
        }
    }
}

/// The dates written under a bin strip, left-aligned on the boundary each one names — the same
/// anchoring the Fitness app's hour marks use, and the only one that keeps an edge label whole (a
/// centred date on the leading boundary would hang half of itself off the tile).
private struct SummaryBinGridLabels: View {
    /// One date and the bin boundary it names.
    struct Label: Identifiable {
        let index: Int
        let text: String
        var id: Int { index }
    }

    let binCount: Int
    let labels: [Label]

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ForEach(labels) { label in
                    Text(label.text)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.tertiaryLabel)
                        .fixedSize()
                        .offset(x: CGFloat(label.index) / CGFloat(max(binCount, 1)) * geometry.size.width + 2)
                }
            }
        }
        .frame(height: Self.height)
    }

    /// A flat height for the row: it is read off the bars above it, so it must cost the same on
    /// every tile whatever dates land in it.
    static let height: CGFloat = 13
}

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
///
/// The bars stand on a **ruled grid** with dates under it (see `SummaryBinGrid`), which is what turns
/// a row of bars into a timeline: a gap in the strip becomes "the four days after the 17th" rather
/// than an unplaceable space, and the two edge rules say where the window the picker names begins and
/// ends. The grid is drawn even when the window holds nothing — an empty ruled strip still says which
/// days it is empty *for*.
struct SummaryBinStrip: View {
    /// Bin values in display units, oldest → newest. Zero means untrained.
    let bins: [Double]
    let style: AnyShapeStyle
    /// The window the bins slice, and the span each bin covers — what the grid writes its dates
    /// from. Nil (or a mismatched count) draws bars alone, as the strip did before.
    var window: TrendWindow? = nil
    var binRanges: [ClosedRange<Date>] = []

    var body: some View {
        let maxValue = bins.max() ?? 0
        VStack(spacing: 3) {
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
            .background {
                if hasGrid {
                    SummaryBinGrid(binCount: bins.count)
                }
            }
            .overlay {
                if maxValue <= 0 {
                    Text(NSLocalizedString("noData", comment: ""))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            if !gridLabels.isEmpty {
                SummaryBinGridLabels(binCount: bins.count, labels: gridLabels)
            }
        }
    }

    /// The grid needs one span per bar to date its rules; anything else and the strip falls back to
    /// bars alone rather than ruling a timeline it can't name.
    private var hasGrid: Bool {
        window != nil && binRanges.count == bins.count && !bins.isEmpty
    }

    /// Which bin boundaries carry a date — counted forward from the leading edge, every
    /// `tileAxisStride`-th, and never the trailing edge (a label there has nowhere to sit).
    private var gridLabels: [SummaryBinGridLabels.Label] {
        guard hasGrid, let window else { return [] }
        return Swift.stride(from: 0, to: bins.count, by: max(window.tileAxisStride, 1)).map { index in
            SummaryBinGridLabels.Label(index: index, text: window.tileAxisLabel(for: binRanges[index]))
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
    /// The Summary's one timeframe — the strip's grid writes its dates from it.
    let window: TrendWindow
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
                    SummaryBinStrip(
                        bins: data.bins,
                        style: AnyShapeStyle(Color.accentColor),
                        window: window,
                        binRanges: data.binRanges
                    )
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
            window: window,
            onOpen: { onOpenDetail(metric) }
        )
    }
}
