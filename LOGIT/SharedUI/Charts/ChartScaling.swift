//
//  ChartScaling.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 04.07.26.
//

import Foundation

/// Y-axis ceiling for the stat charts: the largest value currently on screen plus ~1/5 headroom,
/// so the tallest bar or line peak never touches the top of the plot and the scale re-fits the
/// data as the user scrolls the visible window. `fallbackMax` (typically the series' overall max)
/// keeps the scale sane when the window holds no data at all.
func chartYScaleCap(visibleMax: Double?, fallbackMax: Double? = nil) -> Double {
    let reference = [visibleMax, fallbackMax].compactMap { $0 }.first { $0 > 0 } ?? 0
    guard reference > 0 else { return 10 }
    return reference * 1.2
}

/// The largest plotted value inside the visible window. Bars are positioned by their bucket's
/// start date, so pass the bucket's length as `bucketLength` to also count a bar that starts
/// before the window but reaches into it.
func chartVisibleMax(
    of points: [(date: Date, value: Double)],
    from windowStart: Date,
    to windowEnd: Date,
    bucketLength: TimeInterval = 0
) -> Double? {
    points
        .filter { $0.date >= windowStart.addingTimeInterval(-bucketLength) && $0.date <= windowEnd }
        .map(\.value)
        .max()
}

/// `chartVisibleMax` for line charts, where the line runs on between and beyond data points: a
/// window with no point inside still shows the segment spanning it (or the flat run-out before the
/// first / after the last point), so the nearest points just outside the window bound what's
/// visible there.
func chartVisibleLineMax(
    of points: [(date: Date, value: Double)],
    from windowStart: Date,
    to windowEnd: Date
) -> Double? {
    if let inWindow = chartVisibleMax(of: points, from: windowStart, to: windowEnd) {
        return inWindow
    }
    let before = points.filter { $0.date < windowStart }.max { $0.date < $1.date }?.value
    let after = points.filter { $0.date > windowEnd }.min { $0.date < $1.date }?.value
    return [before, after].compactMap { $0 }.max()
}
