//
//  PeriodHistoryChart.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 05.07.26.
//

import Charts
import SwiftUI

/// The shared recent-periods bar chart behind every period-scoped stat detail — the Summary stat
/// screens, the exercise Sets / Volume screens, and the muscle-group detail's sets tile. One bar per
/// period (`StatPeriod.historyBucketCount` of them, current highlighted), at most ~4 axis labels
/// counted back from the current bucket so "now" is always labeled. The newest label is anchored
/// trailing so it renders fully instead of truncating at the plot edge ("Jul 4", not "J…").
///
/// Tap or press-and-hold any bar to inspect it: a rule mark and a value card name the exact value and
/// period, the touched bar lights up and the rest dim — the same gesture the scrollable capability
/// charts use. The y-axis keeps ~1/6 headroom above the tallest bar so a peak never touches the
/// ceiling (matching the stat tiles). One component, so the history charts can't drift apart again —
/// the compact muscle tile is this same chart with `height` / `showsXAxisLabels` turned down, not a
/// hand-rolled copy.
struct PeriodHistoryChart: View {
    struct Bucket: Identifiable {
        let id: Int
        let date: Date
        let value: Double
        let isCurrent: Bool
        /// The value as printed in the selection tooltip ("1,234", "12.5", "8"). Kept apart from
        /// `value` (which only sets the bar's height) so each screen formats it in its own units.
        var formattedValue: String
    }

    let buckets: [Bucket]
    let period: StatPeriod
    /// Series name for the y-values ("Volume", "Sets", …) — accessibility, not rendered.
    let valueLabel: String
    /// Fill of the current period's bar; past bars stay the quiet `Color.fill`.
    let currentBarStyle: AnyShapeStyle
    /// Unit shown after the value in the selection tooltip ("kg", "sets", "" for a bare count).
    var unit: String = ""
    /// Plot height — the full detail charts stand tall; the muscle tile turns it down.
    var height: CGFloat = 260
    /// Whether the x-axis draws its period labels. Off for the compact tile, whose surrounding
    /// header already names the window it shows.
    var showsXAxisLabels: Bool = true
    /// An optional reference value drawn as a dashed horizontal rule across the plot — the average
    /// of the periods shown, excluding the current, still-growing one. Nil draws nothing, so the
    /// Summary stat chart that doesn't pass it is unchanged. In the buckets' own value units.
    var averageLine: Double? = nil

    @State private var selectedDate: Date?

    var body: some View {
        let maxValue = buckets.map(\.value).max() ?? 0
        // At most ~4 axis labels, counted back from the current bucket so "now" is always labeled —
        // one label per bucket sat shoulder-to-shoulder on the week view.
        let labelStride = max(1, Int((Double(buckets.count) / 4.0).rounded(.up)))
        let labeledDates = stride(from: buckets.count - 1, through: 0, by: -labelStride).map { buckets[$0].date }
        let selectedBucket = selectedDate.flatMap { nearestBucket(to: $0) }
        Chart {
            if let selectedBucket {
                RuleMark(x: .value("Selected", selectedBucket.date, unit: period.calendarComponent))
                    .foregroundStyle(Color.label.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .annotation(
                        position: annotationPosition(for: selectedBucket),
                        overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                    ) {
                        annotationCard(for: selectedBucket)
                    }
            }
            ForEach(buckets) { bucket in
                BarMark(
                    x: .value("Period", bucket.date, unit: period.calendarComponent),
                    y: .value(valueLabel, bucket.value),
                    width: .ratio(0.6)
                )
                .foregroundStyle(barStyle(for: bucket, selected: selectedBucket))
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                // A tapped bar stays lit; every other bar goes quiet while one is inspected.
                .opacity(selectedBucket == nil || selectedBucket?.id == bucket.id ? 1.0 : 0.4)
            }
            // The average of the completed periods shown, as a dashed reference the current bar can
            // be read against. Drawn after the bars so it sits on top; only when a value is supplied.
            if let averageLine {
                RuleMark(y: .value(NSLocalizedString("average", comment: ""), averageLine))
                    .averageLineStyle()
            }
        }
        // ~1/6 headroom above the tallest bar so a peak never touches the ceiling (matches the tiles).
        .chartYScale(domain: 0 ... max(maxValue * 1.15, 1))
        .chartXSelection(value: $selectedDate)
        .chartXAxis {
            if showsXAxisLabels {
                AxisMarks(values: labeledDates) { value in
                    if let date = value.as(Date.self) {
                        let isCurrent = period.currentRange().contains(date)
                        AxisGridLine()
                            .foregroundStyle(Color.gray.opacity(0.4))
                        // Styling lives on the Text inside the label closure — hierarchical styles on
                        // the AxisMark itself resolve against the chart's accent on iOS 26 (labels
                        // turned lime). The current period's label is always the newest (labels stride
                        // back from it) and sits at the plot edge — hang it trailing off its mark so
                        // the edge can't clip it.
                        AxisValueLabel(anchor: isCurrent ? .topTrailing : nil) {
                            Text(period.axisLabel(for: date))
                                .font(.caption.weight(isCurrent ? .bold : .semibold))
                                .foregroundStyle(isCurrent ? Color.label : Color.secondaryLabel)
                        }
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3))
        }
        .frame(height: height)
    }

    // MARK: - Selection

    /// The bucket whose bar sits nearest the raw selection point — snaps the tap/drag onto a bar.
    private func nearestBucket(to date: Date) -> Bucket? {
        buckets.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    /// The current bar keeps its highlight; the inspected past bar lights up white, the rest stay the
    /// quiet fill — the opacity dim (applied on the mark) does the rest. Matches the workout stat
    /// screen's bars so the inspect gesture reads the same everywhere.
    private func barStyle(for bucket: Bucket, selected: Bucket?) -> AnyShapeStyle {
        if bucket.isCurrent { return currentBarStyle }
        if selected?.id == bucket.id { return AnyShapeStyle(Color.label) }
        return AnyShapeStyle(Color.fill)
    }

    /// Hang the card leading when the inspected bar sits in the right third of the chart, trailing in
    /// the left third, centred otherwise — so an edge bar's card never lays out past the plot.
    private func annotationPosition(for bucket: Bucket) -> AnnotationPosition {
        guard buckets.count > 1, let index = buckets.firstIndex(where: { $0.id == bucket.id }) else { return .top }
        let fraction = Double(index) / Double(buckets.count - 1)
        if fraction > 0.66 { return .topLeading }
        if fraction < 0.33 { return .topTrailing }
        return .top
    }

    private func annotationCard(for bucket: Bucket) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            UnitView(value: bucket.formattedValue, unit: unit, unitColor: .secondaryLabel)
                .foregroundStyle(Color.label)
            Text(periodDescription(for: bucket.date))
                .font(.caption)
                .fontWeight(.bold)
                .fontDesign(.rounded)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondaryBackground))
    }

    /// The inspected period spelled out for the card: the week's span, the month, or the year.
    private func periodDescription(for date: Date) -> String {
        switch period {
        case .week:
            let start = date.startOfWeek.formatted(.dateTime.day().month())
            let end = date.endOfWeek.formatted(.dateTime.day().month())
            return "\(start) – \(end)"
        case .month:
            return date.formatted(.dateTime.month(.abbreviated).year())
        case .year:
            return date.formatted(.dateTime.year())
        }
    }
}

extension PeriodHistoryChart {
    /// The standard history buckets for `period` — one per recent period
    /// (`StatPeriod.historyBucketCount`), oldest first, the current period last — with each
    /// period's value pulled from `value`. `formatted` supplies the tooltip string for a period
    /// (defaulting to the rounded value) so a screen can print it in its own units. The one
    /// bucket-building loop for every consumer, so "recent history" can't quietly mean different
    /// windows on different screens.
    static func buckets(
        for period: StatPeriod,
        value: (ClosedRange<Date>) -> Double,
        formatted: ((ClosedRange<Date>) -> String)? = nil
    ) -> [Bucket] {
        let count = period.historyBucketCount
        return (0 ..< count).map { index in
            let periodsAgo = count - 1 - index
            let range = period.range(periodsAgo: periodsAgo)
            let bucketValue = value(range)
            return Bucket(
                id: index,
                date: range.lowerBound,
                value: bucketValue,
                isCurrent: periodsAgo == 0,
                formattedValue: formatted?(range) ?? defaultFormattedValue(bucketValue)
            )
        }
    }

    /// Tooltip text when a screen doesn't supply its own formatter: the value as a plain rounded
    /// integer, right for the bare set counts the muscle tile and the exercise Sets screen show.
    static func defaultFormattedValue(_ value: Double) -> String {
        String(Int(value.rounded()))
    }

    /// The period-over-period trend for a stat header, or nil unless both periods have data — a
    /// freshly started week must not read as a "−100%" collapse (the same suppression rule as the
    /// stat tiles).
    static func trendPercentChange(current: Int, previous: Int) -> Double? {
        guard current > 0, previous > 0 else { return nil }
        return (Double(current) - Double(previous)) / Double(previous) * 100
    }
}

extension ChartContent {
    /// The one shared look of the dashed "average" reference line drawn across the stat charts — a
    /// neutral, slightly wide rule with rounded dashes, set apart from the bars it sits over. Defined
    /// once so every average line matches wherever it appears (the exercise Volume / Sets charts
    /// today, the Summary stat charts next).
    func averageLineStyle() -> some ChartContent {
        foregroundStyle(Color.secondaryLabel)
            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, dash: [5, 10]))
    }
}

#Preview {
    PeriodHistoryChart(
        buckets: (0 ..< 12).map { index in
            let value = Double((index * 37) % 90) + 10
            return PeriodHistoryChart.Bucket(
                id: index,
                date: StatPeriod.week.range(periodsAgo: 11 - index).lowerBound,
                value: value,
                isCurrent: index == 11,
                formattedValue: String(Int(value))
            )
        },
        period: .week,
        valueLabel: "Volume",
        currentBarStyle: AnyShapeStyle(Color.accentColor),
        unit: "kg"
    )
    .padding()
}
