//
//  TileBarChartStyle.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 23.06.26.
//

import Charts
import SwiftUI

/// The shared look of the small bar charts that live inside tiles across the app — the home Volume
/// and Sets tiles, the exercise-detail Volume and Sets tiles, and the workout-detail stat tiles.
/// They all draw the same thing: a handful of short, wide, softly-rounded bars with the current
/// period highlighted and the rest in quiet gray. Centralising the bar width and corner radius here
/// keeps every tile's bars identical instead of each chart picking its own ratio and rounding (the
/// workout stat tiles set the reference look; the rest used to render thinner, square bars).
///
/// Pair the two pieces on each `BarMark`: pass `width: TileBarChartStyle.barWidth` to the
/// initializer and chain `.tileBarStyle()` after the bar's `.foregroundStyle(...)`. The larger
/// detail-screen charts (axes, selection, gradients) are deliberately *not* part of this and keep
/// their own styling.
enum TileBarChartStyle {
    /// Bar width as a fraction of each slot — wide bars with a small gap between them. The home tiles
    /// keep this; the metric-tile footer charts take the slimmer ratio below.
    static let barWidth: MarkDimension = .ratio(0.8)
    /// Bar width for the metric-tile footer charts (Summary stat tiles, exercise Volume/Sets, workout
    /// stat tiles) — the same fraction-of-slot the full detail charts use, so a tile's bars read as a
    /// small copy of the chart behind them rather than a different chart with the same numbers.
    ///
    /// It was a fixed 10pt while the trend pill occupied the footer's leading corner and the bars had
    /// roughly half the tile to live in. Now that the chart spans the full width, a fixed width no
    /// longer tracks the slots: five 10pt bars across 144pt read as tally marks in a mostly empty
    /// field. A ratio widens with the slot instead, and stays right whatever bar count a tile ends up
    /// showing.
    static let footerBarWidth: MarkDimension = .ratio(0.6)

    /// Corner radius of the bar caps — the app's one bar radius, shared with every full chart
    /// (`PeriodHistoryChart`, `TrendWindowHistoryChart`, `WorkoutStatScreen`, the Strength and
    /// muscle-balance bars). A tile's bars are meant to read as a small copy of the chart they tap
    /// into, and at the old 9pt they didn't: on a bar this narrow that radius rounds the whole cap
    /// into a capsule, so the tile drew lozenges where the detail screen draws columns.
    static let cornerRadius: CGFloat = 3
}

extension ChartContent {
    /// Rounds a tile bar chart's bars to the shared corner radius. Use together with
    /// `width: TileBarChartStyle.barWidth` on the `BarMark` for the full shared look.
    func tileBarStyle() -> some ChartContent {
        clipShape(RoundedRectangle(cornerRadius: TileBarChartStyle.cornerRadius, style: .continuous))
    }
}
