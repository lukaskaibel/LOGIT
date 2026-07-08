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
        /// The period's value in raw storage units — what the moving visible-window average is taken
        /// over (so "average" reads in the same units the header formats). Zero for the compact tile,
        /// which shows no average.
        var rawValue: Double = 0
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
    /// An optional reference value drawn as a dashed horizontal rule across the plot — the average of
    /// the visible periods, excluding the current, still-growing one. Nil draws nothing. In the
    /// buckets' own value units, so it moves with the header as the chart scrolls.
    var averageLine: Double? = nil
    /// When bound, the chart scrolls horizontally: `buckets` span the full history, a window of
    /// `historyBucketCount` periods shows at a time, and this is its left edge (owned by the screen so
    /// its header can read the visible window). Nil keeps the chart static — the compact muscle tile.
    var scrollPosition: Binding<Date>? = nil
    /// The earliest data date — the left end of the scrollable domain. Ignored when static.
    var firstDataDate: Date? = nil

    @State private var selectedDate: Date?

    var body: some View {
        let maxValue = buckets.map(\.value).max() ?? 0
        let selectedBucket = selectedDate.flatMap { nearestBucket(to: $0) }
        scrollableIfNeeded(
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
                // The visible window's average, as a dashed reference the current bar reads against —
                // moving with the header as the chart scrolls. Drawn last so it sits above the bars.
                if let averageLine {
                    RuleMark(y: .value(NSLocalizedString("average", comment: ""), averageLine))
                        .averageLineStyle()
                }
            }
            // ~1/6 headroom above the tallest bar so a peak never touches the ceiling (matches tiles).
            .chartYScale(domain: 0 ... max(maxValue * 1.15, 1))
            .chartXSelection(value: $selectedDate)
            .chartXAxis {
                if showsXAxisLabels {
                    let axisStride = period.scrollAxisStride
                    AxisMarks(values: .stride(by: axisStride.component, count: axisStride.count)) { value in
                        if let date = value.as(Date.self) {
                            let isCurrent = period.currentRange().contains(date)
                            AxisGridLine()
                                .foregroundStyle(Color.gray.opacity(0.4))
                            // Styling lives on the Text inside the label closure — hierarchical styles
                            // on the AxisMark resolve against the chart's accent on iOS 26 (labels
                            // turned lime). The current period hugs the right edge on first load, so
                            // hang its label trailing off the mark to keep the edge from clipping it.
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
        )
        .frame(height: height)
    }

    /// Wraps the chart in the scrollable-timeline modifiers when a `scrollPosition` is bound — the
    /// full-detail charts scroll a `historyBucketCount`-wide window through the whole history; the
    /// compact muscle tile, with no binding, stays static on its fixed recent window.
    @ViewBuilder
    private func scrollableIfNeeded(_ chart: some View) -> some View {
        if let scrollPosition {
            chart
                .chartXScale(domain: period.scrollableXDomain(firstDataDate: firstDataDate))
                .chartScrollableAxes(.horizontal)
                .chartScrollPosition(x: scrollPosition)
                .chartXVisibleDomain(length: period.visibleDomainSeconds())
                .chartScrollTargetBehavior(.valueAligned(matching: period.scrollSnapComponents))
        } else {
            chart
        }
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

    /// Hang the card leading when the inspected bar sits in the right third, trailing in the left
    /// third, centred otherwise — so an edge bar's card never lays out past the plot. On the
    /// scrollable charts the thirds are measured within the visible window (the plot scrolls, so
    /// `fit(to: .chart)` alone would let an edge card lay out into off-viewport periods and clip).
    private func annotationPosition(for bucket: Bucket) -> AnnotationPosition {
        let fraction: Double
        if let scrollPosition {
            let windowSeconds = Double(period.visibleDomainSeconds())
            guard windowSeconds > 0 else { return .top }
            fraction = bucket.date.timeIntervalSince(scrollPosition.wrappedValue) / windowSeconds
        } else {
            guard buckets.count > 1, let index = buckets.firstIndex(where: { $0.id == bucket.id }) else { return .top }
            fraction = Double(index) / Double(buckets.count - 1)
        }
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

    /// Buckets for the whole scrollable history — one per period from the first data point through
    /// the current period. `rawByPeriodStart` is the data pre-grouped by period start (built in one
    /// pass by the screen), looked up per period so building N bars stays O(periods) rather than
    /// re-filtering the data per bar; keys must be `period.currentRange(containing:).lowerBound`, the
    /// same canonical period start this uses. `display` maps a raw sum to the bar's height, `formatted`
    /// to its tooltip, and the raw sum rides along for the moving visible-window average.
    static func scrollableBuckets(
        for period: StatPeriod,
        rawByPeriodStart: [Date: Int],
        firstDataDate: Date?,
        now: Date = .now,
        display: (Int) -> Double,
        formatted: (Int) -> String
    ) -> [Bucket] {
        let domain = period.scrollableXDomain(firstDataDate: firstDataDate, now: now)
        let currentStart = period.currentRange(containing: now).lowerBound
        var buckets: [Bucket] = []
        var start = period.currentRange(containing: domain.lowerBound).lowerBound
        var index = 0
        while start <= currentStart {
            let raw = rawByPeriodStart[start] ?? 0
            buckets.append(Bucket(
                id: index,
                date: start,
                value: display(raw),
                isCurrent: start == currentStart,
                formattedValue: formatted(raw),
                rawValue: Double(raw)
            ))
            guard let next = Calendar.current.date(byAdding: period.calendarComponent, value: 1, to: start) else { break }
            start = period.currentRange(containing: next).lowerBound
            index += 1
        }
        return buckets
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

/// The shared scrollable header-plus-chart for the period-scoped stat detail screens (exercise
/// Volume / Sets, the Summary stats). It owns the scroll position — deliberately, so that scrolling
/// and inspecting re-evaluate only *this* view, never the screen that builds `buckets`; the whole
/// history is bucketed once per period up in the parent, not on every scroll frame. As the window
/// scrolls, the header's neutral "Average" side and the dashed line both retarget to the average of
/// the visible, completed periods, while the tinted "this period" side stays the fixed subject — the
/// same scoreboard the workout stat screen uses, at week / month / year granularity.
struct PeriodStatChartView: View {
    let period: StatPeriod
    /// The whole history, one bucket per period, built once by the parent.
    let buckets: [PeriodHistoryChart.Bucket]
    let firstDataDate: Date?
    let valueLabel: String
    let unit: String
    let currentBarStyle: AnyShapeStyle
    /// Trailing (subject) side: "This Week" and the current period's value, fixed as the chart scrolls.
    let currentLabel: String
    let currentValue: String
    let currentRaw: Int
    let trailingValueStyle: AnyShapeStyle
    let positiveColor: Color
    var positiveStyle: AnyShapeStyle? = nil
    /// Raw visible-window average → the header string (each screen rounds / formats in its own units).
    let formatAverage: (Int) -> String
    /// Raw visible-window average → the dashed line's height in display units.
    let displayAverage: (Int) -> Double
    var explanation: String? = nil

    @State private var scrollPosition: Date

    init(
        period: StatPeriod,
        buckets: [PeriodHistoryChart.Bucket],
        firstDataDate: Date?,
        valueLabel: String,
        unit: String,
        currentBarStyle: AnyShapeStyle,
        currentLabel: String,
        currentValue: String,
        currentRaw: Int,
        trailingValueStyle: AnyShapeStyle,
        positiveColor: Color,
        positiveStyle: AnyShapeStyle? = nil,
        formatAverage: @escaping (Int) -> String,
        displayAverage: @escaping (Int) -> Double,
        explanation: String? = nil
    ) {
        self.period = period
        self.buckets = buckets
        self.firstDataDate = firstDataDate
        self.valueLabel = valueLabel
        self.unit = unit
        self.currentBarStyle = currentBarStyle
        self.currentLabel = currentLabel
        self.currentValue = currentValue
        self.currentRaw = currentRaw
        self.trailingValueStyle = trailingValueStyle
        self.positiveColor = positiveColor
        self.positiveStyle = positiveStyle
        self.formatAverage = formatAverage
        self.displayAverage = displayAverage
        self.explanation = explanation
        _scrollPosition = State(initialValue: period.initialScrollPosition())
    }

    var body: some View {
        // The completed periods on screen — the current, still-growing one and untrained periods left
        // out, matching the pill's "both sides need data" rule. O(buckets) per scroll frame; the
        // buckets themselves are the parent's, unchanged by scrolling.
        let window = period.visibleWindowRange(from: scrollPosition)
        let visible = buckets.filter { !$0.isCurrent && $0.rawValue > 0 && window.contains($0.date) }
        let averageRaw: Int? = visible.isEmpty
            ? nil
            : Int((visible.map(\.rawValue).reduce(0, +) / Double(visible.count)).rounded())
        let percentChange = PeriodHistoryChart.trendPercentChange(current: currentRaw, previous: averageRaw ?? 0)
        return VStack(spacing: 16) {
            MetricComparisonView(
                leading: .init(
                    label: NSLocalizedString("average", comment: ""),
                    value: averageRaw.map(formatAverage) ?? "––",
                    unit: unit,
                    caption: period.rangeCaption(window)
                ),
                trailing: .init(
                    label: currentLabel,
                    value: currentValue,
                    unit: unit,
                    caption: period.rangeCaption(period.currentRange())
                ),
                trailingValueStyle: trailingValueStyle,
                percentChange: percentChange,
                positiveColor: positiveColor,
                positiveStyle: positiveStyle,
                explanation: explanation
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            PeriodHistoryChart(
                buckets: buckets,
                period: period,
                valueLabel: valueLabel,
                currentBarStyle: currentBarStyle,
                unit: unit,
                averageLine: averageRaw.map(displayAverage),
                scrollPosition: $scrollPosition,
                firstDataDate: firstDataDate
            )
            // A fresh chart per granularity: switching week/month/year changes the visible-domain
            // length, which otherwise leaves the scroll offset stale (see the capability charts).
            .id(period)
        }
        .onChange(of: period) {
            scrollPosition = period.initialScrollPosition()
        }
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
