//
//  TrendWindowHistoryChart.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 07.08.26.
//

import Charts
import SwiftUI

// MARK: - Bucket

/// One rolling window in a stat detail screen's history strip: the span it covers, the labels that
/// name it, and the value trained in it. The `TrendWindow` sibling of `PeriodHistoryChart.Bucket`,
/// which is built on calendar periods.
///
/// The x-axis is **categorical** — the bar's x-value is `id`, a stable epoch string, not a date. A
/// rolling window has no calendar unit for `BarMark` to bin by (four weeks is not a month), so
/// binning by one would either merge two windows into a bar or split one across two. It also drops
/// the scroll-and-snap machinery `StatPeriod` charts carry, which needs a calendar component to snap
/// to: this strip shows a fixed `historyBucketCount` of windows and stays put.
struct TrendWindowBucket: Identifiable {
    /// Stable, unique key — the window start's epoch seconds. The chart's x-category and its
    /// selection value; the human labels aren't guaranteed unique across a strip.
    let id: String
    let range: ClosedRange<Date>
    /// Short label under the bar, naming where the window *ends* ("6 Aug", "Aug", "2026").
    let axisLabel: String
    /// Full name for the inspect card — "Last 4 weeks" for the current window, the date span for
    /// every older one.
    let title: String
    /// The newest window, the one ending now.
    let isCurrent: Bool
    /// Bar height, in display units.
    let value: Double
    /// The window's value in raw storage units — what the average is taken over, so "average" reads
    /// in the same units the header formats.
    let rawValue: Double
    /// The value as printed in the inspect card ("1,234", "12.5", "8").
    let formattedValue: String
}

extension TrendWindowBucket {
    /// The history strip for `window`, oldest first, the current window last. One builder for every
    /// consumer, so "recent history" can't quietly mean different runs of windows on different
    /// screens. `raw` reduces one window's span to a value in storage units, `display` maps that to
    /// the bar's height, and `formatted` to the inspect card's string.
    static func history(
        for window: TrendWindow,
        now: Date = .now,
        raw: (ClosedRange<Date>) -> Double,
        display: (Double) -> Double,
        formatted: (Double) -> String
    ) -> [TrendWindowBucket] {
        (0 ..< window.historyBucketCount).reversed().map { windowsAgo in
            let range = window.range(windowsAgo: windowsAgo, from: now)
            let rawValue = raw(range)
            return TrendWindowBucket(
                id: String(Int(range.lowerBound.timeIntervalSince1970)),
                range: range,
                axisLabel: window.axisLabel(forWindowEnding: range.upperBound),
                title: window.windowTitle(windowsAgo: windowsAgo, from: now),
                isCurrent: windowsAgo == 0,
                value: display(rawValue),
                rawValue: rawValue,
                formattedValue: formatted(rawValue)
            )
        }
    }
}

// MARK: - Chart

/// The shared rolling-window bar chart behind the Summary's four stat detail screens: one bar per
/// `TrendWindow`, the current window highlighted, every bar labelled by where its window ends.
///
/// Tap or press-and-hold a bar to inspect it — a value card names the exact value and which window
/// it belongs to, the touched bar lights up and the rest dim, the same gesture the calendar-period
/// charts use. The y-axis keeps ~1/6 headroom above the tallest bar so a peak never touches the
/// ceiling, matching the stat tiles.
///
/// Every bar carries its own label, unlike the scrollable calendar charts which label every second
/// mark: the strip is only six to eight bars wide and each label is short by construction (see
/// `TrendWindow.historyBucketCount`, which is capped by exactly this).
struct TrendWindowHistoryChart: View {
    let buckets: [TrendWindowBucket]
    /// Series name for the y-values ("Volume", "Sets", …) — accessibility, not rendered.
    let valueLabel: String
    /// Fill of the current window's bar; past bars stay the quiet `Color.fill`.
    let currentBarStyle: AnyShapeStyle
    /// Unit shown after the value in the inspect card ("kg", "sets", "" for a bare count).
    var unit: String = ""
    var height: CGFloat = 260
    /// An optional reference value drawn as a dashed horizontal rule — the average of the completed
    /// windows. Nil draws nothing. In the buckets' display units, so it lands where the bars are.
    var averageLine: Double? = nil

    @State private var selectedID: String?

    private var selectedBucket: TrendWindowBucket? {
        selectedID.flatMap { id in buckets.first { $0.id == id } }
    }

    var body: some View {
        let maxValue = buckets.map(\.value).max() ?? 0
        let selected = selectedBucket
        Chart {
            ForEach(buckets) { bucket in
                BarMark(
                    x: .value("Window", bucket.id),
                    y: .value(valueLabel, bucket.value),
                    width: .ratio(0.6)
                )
                .foregroundStyle(barStyle(for: bucket, selected: selected))
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                // A tapped bar stays lit; every other bar goes quiet while one is inspected.
                .opacity(selected == nil || selected?.id == bucket.id ? 1.0 : 0.4)
                .annotation(
                    position: annotationPosition(for: bucket),
                    overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                ) {
                    if selected?.id == bucket.id {
                        annotationCard(for: bucket)
                    }
                }
            }
            // The completed windows' average, as a dashed reference the current bar reads against.
            // Drawn last so it sits above the bars.
            if let averageLine {
                RuleMark(y: .value(NSLocalizedString("average", comment: ""), averageLine))
                    .averageLineStyle()
            }
        }
        .chartXScale(domain: buckets.map(\.id))
        // ~1/6 headroom above the tallest bar so a peak never touches the ceiling (matches tiles).
        .chartYScale(domain: 0 ... max(maxValue * 1.15, 1))
        .chartXSelection(value: $selectedID)
        .chartXAxis {
            AxisMarks(values: buckets.map(\.id)) { value in
                if let id = value.as(String.self), let bucket = buckets.first(where: { $0.id == id }) {
                    AxisGridLine()
                        .foregroundStyle(Color.gray.opacity(0.4))
                    // Styling lives on the Text inside the label closure — hierarchical styles on the
                    // AxisMark resolve against the chart's accent on iOS 26 (labels turned lime).
                    AxisValueLabel {
                        Text(bucket.axisLabel)
                            .font(.caption.weight(bucket.isCurrent ? .bold : .semibold))
                            .foregroundStyle(bucket.isCurrent ? Color.label : Color.secondaryLabel)
                            .fixedSize()
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3))
        }
        .animation(.easeInOut(duration: 0.3), value: maxValue)
        .animation(.easeInOut(duration: 0.3), value: averageLine)
        .frame(height: height)
    }

    // MARK: - Selection

    /// The current bar keeps its highlight; the inspected past bar lights up white, the rest stay the
    /// quiet fill — the opacity dim (applied on the mark) does the rest.
    private func barStyle(for bucket: TrendWindowBucket, selected: TrendWindowBucket?) -> AnyShapeStyle {
        if bucket.isCurrent { return currentBarStyle }
        if selected?.id == bucket.id { return AnyShapeStyle(Color.label) }
        return AnyShapeStyle(Color.fill)
    }

    /// Hang the card leading when the inspected bar sits in the right third, trailing in the left
    /// third, centred otherwise — so an edge bar's card never lays out past the plot.
    private func annotationPosition(for bucket: TrendWindowBucket) -> AnnotationPosition {
        guard buckets.count > 1, let index = buckets.firstIndex(where: { $0.id == bucket.id }) else {
            return .top
        }
        let fraction = Double(index) / Double(buckets.count - 1)
        if fraction > 0.66 { return .topLeading }
        if fraction < 0.33 { return .topTrailing }
        return .top
    }

    private func annotationCard(for bucket: TrendWindowBucket) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            UnitView(value: bucket.formattedValue, unit: unit, unitColor: .secondaryLabel)
                .foregroundStyle(Color.label)
            Text(bucket.title)
                .font(.caption)
                .fontWeight(.bold)
                .fontDesign(.rounded)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondaryBackground))
    }
}

// MARK: - Header + chart

/// The shared header-plus-chart for the Summary's four stat detail screens — the `TrendWindow`
/// sibling of `PeriodStatChartView`, which the calendar-period exercise screens still use.
///
/// The scoreboard reads the current window against the average of the completed windows behind it on
/// the strip: the neutral "Average" side, the trend pill, then the tinted current window. The dashed
/// line on the chart is that same average, so the header and the plot state one fact twice rather
/// than two facts once.
///
/// The average excludes the current window and untrained ones. Excluding the current window is what
/// makes the comparison mean anything — averaging a value into its own baseline drags the baseline
/// toward it — and excluding untrained windows keeps a training break from reading as a collapse in
/// output rather than an absence of it.
struct TrendWindowStatChartView: View {
    let window: TrendWindow
    let buckets: [TrendWindowBucket]
    let valueLabel: String
    let unit: String
    let currentBarStyle: AnyShapeStyle
    /// Trailing (subject) side: the current window's formatted value and its raw counterpart, which
    /// the trend pill is computed from.
    let currentValue: String
    let currentRaw: Double
    let trailingValueStyle: AnyShapeStyle
    let positiveColor: Color
    var positiveStyle: AnyShapeStyle? = nil
    /// Raw average → the header string (each screen rounds / formats in its own units).
    let formatAverage: (Double) -> String
    /// Raw average → the dashed line's height in display units.
    let displayAverage: (Double) -> Double
    var explanation: String? = nil

    var body: some View {
        let average = completedAverage
        let percentChange = PeriodHistoryChart.trendPercentChange(current: currentRaw, previous: average ?? 0)
        VStack(spacing: 16) {
            MetricComparisonView(
                leading: .init(
                    label: NSLocalizedString("average", comment: ""),
                    value: average.map(formatAverage) ?? "––",
                    unit: unit,
                    caption: completedSpanCaption
                ),
                trailing: .init(
                    label: window.currentWindowLabel,
                    value: currentValue,
                    unit: unit,
                    caption: window.dateSpan(window.currentRange())
                ),
                trailingValueStyle: trailingValueStyle,
                percentChange: percentChange,
                positiveColor: positiveColor,
                positiveStyle: positiveStyle,
                explanation: explanation
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            TrendWindowHistoryChart(
                buckets: buckets,
                valueLabel: valueLabel,
                currentBarStyle: currentBarStyle,
                unit: unit,
                averageLine: average.map(displayAverage)
            )
            // A fresh chart per window: the x-categories change wholesale when the window does, and
            // a stale selection would otherwise point at a bucket id that no longer exists.
            .id(window)
        }
    }

    /// The completed windows' average in raw units — nil when none of them holds training, which is
    /// what makes the header show "––" instead of a zero it can't stand behind.
    private var completedAverage: Double? {
        let completed = buckets.filter { !$0.isCurrent && $0.rawValue > 0 }
        guard !completed.isEmpty else { return nil }
        return completed.reduce(0) { $0 + $1.rawValue } / Double(completed.count)
    }

    /// The span the average covers: the oldest window on the strip through the last completed one.
    private var completedSpanCaption: String? {
        guard let oldest = buckets.first, let lastCompleted = buckets.last(where: { !$0.isCurrent })
        else { return nil }
        return window.dateSpan(oldest.range.lowerBound ... lastCompleted.range.upperBound)
    }
}

#Preview {
    TrendWindowHistoryChart(
        buckets: TrendWindowBucket.history(
            for: .fourWeeks,
            raw: { range in Double(Calendar.current.component(.day, from: range.upperBound) * 300) },
            display: { $0 },
            formatted: { String(Int($0)) }
        ),
        valueLabel: "Volume",
        currentBarStyle: AnyShapeStyle(Color.accentColor),
        unit: "kg"
    )
    .padding()
}
