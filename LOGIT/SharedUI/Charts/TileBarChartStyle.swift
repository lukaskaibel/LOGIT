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
    /// Bar width as a fraction of each slot — wide bars with a small gap between them.
    static let barWidth: MarkDimension = .ratio(0.8)

    /// Corner radius of the rounded bar caps.
    static let cornerRadius: CGFloat = 9
}

extension ChartContent {
    /// Rounds a tile bar chart's bars to the shared corner radius. Use together with
    /// `width: TileBarChartStyle.barWidth` on the `BarMark` for the full shared look.
    func tileBarStyle() -> some ChartContent {
        clipShape(RoundedRectangle(cornerRadius: TileBarChartStyle.cornerRadius, style: .continuous))
    }
}
