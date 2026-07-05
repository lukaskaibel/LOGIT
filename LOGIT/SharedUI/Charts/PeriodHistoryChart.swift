//
//  PeriodHistoryChart.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 05.07.26.
//

import Charts
import SwiftUI

/// The shared recent-periods bar chart behind every period-scoped stat detail — the Summary stat
/// screens and the exercise Sets / Volume screens. One bar per period (`StatPeriod.historyBucketCount`
/// of them, current highlighted), at most ~4 axis labels counted back from the current bucket so
/// "now" is always labeled. The newest label is anchored trailing so it renders fully instead of
/// truncating at the plot edge ("Jul 4", not "J…"). One component, so the history charts can't
/// drift apart again.
struct PeriodHistoryChart: View {
    struct Bucket: Identifiable {
        let id: Int
        let date: Date
        let value: Double
        let isCurrent: Bool
    }

    let buckets: [Bucket]
    let period: StatPeriod
    /// Series name for the y-values ("Volume", "Sets", …) — accessibility, not rendered.
    let valueLabel: String
    /// Fill of the current period's bar; past bars stay the quiet `Color.fill`.
    let currentBarStyle: AnyShapeStyle

    var body: some View {
        let maxValue = buckets.map(\.value).max() ?? 0
        // At most ~4 axis labels, counted back from the current bucket so "now" is always labeled —
        // one label per bucket sat shoulder-to-shoulder on the week view.
        let labelStride = max(1, Int((Double(buckets.count) / 4.0).rounded(.up)))
        let labeledDates = stride(from: buckets.count - 1, through: 0, by: -labelStride).map { buckets[$0].date }
        Chart {
            ForEach(buckets) { bucket in
                BarMark(
                    x: .value("Period", bucket.date, unit: period.calendarComponent),
                    y: .value(valueLabel, bucket.value),
                    width: .ratio(0.6)
                )
                .foregroundStyle(bucket.isCurrent ? currentBarStyle : AnyShapeStyle(Color.fill))
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            }
        }
        .chartYScale(domain: 0 ... max(maxValue, 1))
        .chartXAxis {
            AxisMarks(values: labeledDates) { value in
                if let date = value.as(Date.self) {
                    let isCurrent = period.currentRange().contains(date)
                    AxisGridLine()
                        .foregroundStyle(Color.gray.opacity(0.4))
                    // Styling lives on the Text inside the label closure — hierarchical styles on the
                    // AxisMark itself resolve against the chart's accent on iOS 26 (labels turned lime).
                    // The current period's label is always the newest (labels stride back from it) and
                    // sits at the plot edge — hang it trailing off its mark so the edge can't clip it.
                    AxisValueLabel(anchor: isCurrent ? .topTrailing : nil) {
                        Text(period.axisLabel(for: date))
                            .font(.caption.weight(isCurrent ? .bold : .semibold))
                            .foregroundStyle(isCurrent ? Color.label : Color.secondaryLabel)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3))
        }
        .frame(height: 260)
    }
}

extension PeriodHistoryChart {
    /// The standard history buckets for `period` — one per recent period
    /// (`StatPeriod.historyBucketCount`), oldest first, the current period last — with each
    /// period's value pulled from `value`. The one bucket-building loop for every consumer, so
    /// "recent history" can't quietly mean different windows on different screens.
    static func buckets(for period: StatPeriod, value: (ClosedRange<Date>) -> Double) -> [Bucket] {
        let count = period.historyBucketCount
        return (0 ..< count).map { index in
            let periodsAgo = count - 1 - index
            let range = period.range(periodsAgo: periodsAgo)
            return Bucket(
                id: index,
                date: range.lowerBound,
                value: value(range),
                isCurrent: periodsAgo == 0
            )
        }
    }

    /// The period-over-period trend for a stat header, or nil unless both periods have data — a
    /// freshly started week must not read as a "−100%" collapse (the same suppression rule as the
    /// stat tiles).
    static func trendPercentChange(current: Int, previous: Int) -> Double? {
        guard current > 0, previous > 0 else { return nil }
        return (Double(current) - Double(previous)) / Double(previous) * 100
    }
}

#Preview {
    PeriodHistoryChart(
        buckets: (0 ..< 12).map { index in
            PeriodHistoryChart.Bucket(
                id: index,
                date: StatPeriod.week.range(periodsAgo: 11 - index).lowerBound,
                value: Double((index * 37) % 90) + 10,
                isCurrent: index == 11
            )
        },
        period: .week,
        valueLabel: "Volume",
        currentBarStyle: AnyShapeStyle(Color.accentColor)
    )
    .padding()
}
