//
//  TileSparklineStyle.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 23.06.26.
//

import Charts
import SwiftUI

// MARK: - Point

/// One point on a tile sparkline — a single day's best for an exercise metric, or one measurement
/// entry — oldest → newest. Shared so every tile sparkline plots the same shape of data.
struct TileSparklinePoint: Identifiable {
    let date: Date
    let value: Double
    var id: Date { date }
}

// MARK: - Style

/// The shared look of the small line charts (sparklines) that live inside tiles across the app —
/// the home pinned-exercise tiles, the exercise-detail metric tiles, the measurement tiles, the
/// personal-record cards, and the in-workout set-group cell. They all draw the same thing: a smooth
/// tinted line with daily-best dots, a translucent area fill beneath, a dashed carry-forward to
/// today, and a faded leading edge. Centralising the line, area, symbol, carry-forward, and fade
/// here keeps every tile's sparkline identical instead of each chart re-deriving the recipe inline.
///
/// Build the marks with `tileSparklineMarks(...)` inside the chart, and apply `.tileSparklineFadeMask()`
/// for the leading fade. Each tile still owns its own x/y scales and frame — the *style* is shared,
/// the *scaling* (which legitimately differs per tile) is not.
enum TileSparklineStyle {
    /// Stroke width of the line (and the carry-forward rule).
    static let lineWidth: CGFloat = 3
    /// Smoothing of the line — a soft curve through the daily points.
    static let interpolation: InterpolationMethod = .catmullRom
    /// Diameter of a daily-best dot.
    static let pointDiameter: CGFloat = 6
    /// Dash pattern of the carry-forward line from the last point to today.
    static let carryForwardDash: [CGFloat] = [3, 6]
    /// Opacity of the carry-forward line — quieter than the solid line behind it.
    static let carryForwardOpacity: CGFloat = 0.45
    /// Fraction of the width over which the leading edge fades in.
    static let leadingFadeLocation: CGFloat = 0.12

    /// The translucent fill under the line — a top-heavy tint. Swift Charts won't reliably fade an
    /// `AreaMark` to clear at the baseline on its own (the fill gradient maps to a range far taller
    /// than the area, so its bottom never reaches transparent), so the real fade to transparent is the
    /// vertical pass in `tileSparklineFadeMask()`; this just supplies the colour.
    static func areaGradient(_ color: Color) -> LinearGradient {
        LinearGradient(
            colors: [color.opacity(0.38), color.opacity(0.18)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// A daily-best dot: a filled circle in the tint with a punched-out black center so it reads as
    /// a marker on top of the line.
    @ViewBuilder
    static func pointSymbol(_ color: Color) -> some View {
        Circle()
            .frame(width: pointDiameter, height: pointDiameter)
            .foregroundStyle(color.gradient)
            .overlay {
                Circle()
                    .frame(width: pointDiameter / 3, height: pointDiameter / 3)
                    .foregroundStyle(Color.black)
            }
    }
}

// MARK: - Marks

/// The shared marks of a tile sparkline: a leading segment pinned to the far past so the line enters
/// from the left edge, the tinted line with daily-best dots, the area fill beneath, and the dashed
/// carry-forward from the last point to `carryForwardEnd`. Wrap this in a `Chart { … }` and add the
/// chart's own scales/frame/fade.
///
/// - Parameters:
///   - showsSymbols: per-point dots; off for the all-time line, which draws one clean dotless curve.
///   - showsCarryForward: the dashed flat line from the last point to `carryForwardEnd` when the
///     last point predates that anchor (an exercise untrained since, or the recorder's live anchor).
///   - carryForwardEnd: where the carry-forward reaches — today (`.now`) for finished history, or the
///     workout being recorded for the in-workout cell.
@ChartContentBuilder
func tileSparklineMarks(
    points: [TileSparklinePoint],
    color: Color,
    interpolation: InterpolationMethod = TileSparklineStyle.interpolation,
    showsSymbols: Bool = true,
    showsCarryForward: Bool = true,
    carryForwardEnd: Date = .now
) -> some ChartContent {
    // Leading entry pinned to the far past so the line and area enter from the left edge instead of
    // starting mid-chart (the domain clips it).
    if let first = points.first {
        LineMark(x: .value("Date", Date.distantPast, unit: .day), y: .value("Value", first.value))
            .interpolationMethod(interpolation)
            .foregroundStyle(color.gradient)
            .lineStyle(StrokeStyle(lineWidth: TileSparklineStyle.lineWidth, lineCap: .round))
        AreaMark(x: .value("Date", Date.distantPast, unit: .day), y: .value("Value", first.value))
            .interpolationMethod(interpolation)
            .foregroundStyle(TileSparklineStyle.areaGradient(color))
    }
    ForEach(points) { point in
        if showsSymbols {
            LineMark(x: .value("Date", point.date, unit: .day), y: .value("Value", point.value))
                .interpolationMethod(interpolation)
                .foregroundStyle(color.gradient)
                .lineStyle(StrokeStyle(lineWidth: TileSparklineStyle.lineWidth))
                .symbol { TileSparklineStyle.pointSymbol(color) }
        } else {
            LineMark(x: .value("Date", point.date, unit: .day), y: .value("Value", point.value))
                .interpolationMethod(interpolation)
                .foregroundStyle(color.gradient)
                .lineStyle(StrokeStyle(lineWidth: TileSparklineStyle.lineWidth))
        }
        AreaMark(x: .value("Date", point.date, unit: .day), y: .value("Value", point.value))
            .interpolationMethod(interpolation)
            .foregroundStyle(TileSparklineStyle.areaGradient(color))
    }
    if showsCarryForward, let last = points.last,
       last.date < carryForwardEnd,
       !Calendar.current.isDate(last.date, inSameDayAs: carryForwardEnd) {
        RuleMark(
            xStart: .value("Start", last.date),
            xEnd: .value("End", carryForwardEnd),
            y: .value("Value", last.value)
        )
        .foregroundStyle(color.opacity(TileSparklineStyle.carryForwardOpacity))
        .lineStyle(
            StrokeStyle(
                lineWidth: TileSparklineStyle.lineWidth,
                lineCap: .round,
                dash: TileSparklineStyle.carryForwardDash
            )
        )
    }
}

// MARK: - Fade Mask

extension View {
    /// Fades a tile sparkline in from its leading edge (so the clipped line dissolves into the tile
    /// rather than starting on a hard vertical) AND out toward the bottom. Two stacked masks compose
    /// to "visible where both are opaque". Shared by the windowed tile sparklines' frame treatment;
    /// the all-time line wants only the bottom half and applies `tileSparklineBottomFadeMask()` alone.
    func tileSparklineFadeMask() -> some View {
        mask(
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .black, location: TileSparklineStyle.leadingFadeLocation),
                    .init(color: .black, location: 1.0),
                ]),
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .tileSparklineBottomFadeMask()
    }

    /// Fades a tile sparkline out toward its BOTTOM edge so the area fill melts into the surface
    /// instead of ending on a hard horizontal at the baseline (Swift Charts can't fade the `AreaMark`
    /// itself reliably — left alone it gets clipped while still tinted). The line and the band just
    /// under it stay opaque; only the lower fill dissolves. Used on its own by the all-time line,
    /// which bleeds to the card's bottom border and wants this fade but not the leading one.
    func tileSparklineBottomFadeMask() -> some View {
        mask(
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: .black, location: 0.0),
                    .init(color: .black, location: 0.4),
                    .init(color: .clear, location: 1.0),
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}
