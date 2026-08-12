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
/// The x-axis is an **index** axis — the bar's x-value is `index`, its position in the strip, not a
/// date. A rolling window has no calendar unit for `BarMark` to bin by (four weeks is not a month), so
/// binning by one would either merge two windows into a bar or split one across two. Plain indices
/// give evenly spaced bars whatever the window, and give the scroll machinery something to snap to:
/// one unit is one window (see `TrendWindow.historyRanges` and its neighbours).
struct TrendWindowBucket: Identifiable {
    /// Stable, unique key — the window start's epoch seconds. The human labels aren't guaranteed
    /// unique across a strip, so `Identifiable` rides on this rather than on them.
    let id: String
    /// Position in the strip, oldest window `0`.
    let index: Int
    /// Where the bar sits on the chart's synthetic one-window-per-day timeline — `index` as an x-value
    /// the date machinery can bin, snap and scroll (see `TrendWindow.stripDate(forIndex:)`). Never
    /// shown: the axis labels come from `axisLabel`.
    let stripDate: Date
    /// The real dates the window covers.
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
    /// screens.
    ///
    /// `ranges` comes from `window.historyRanges(firstDataDate:)` and `raw` holds one value per range,
    /// in the same order. The values are handed over already reduced rather than pulled through a
    /// per-window closure: the strip now runs back to the first logged workout — dozens of windows —
    /// and a closure re-scanning the whole dataset per window would make building it quadratic on the
    /// screen's hottest path. `TrendWindow.bucketIndex(of:in:)` is how a screen fills that array in one
    /// pass. `display` maps a raw value to the bar's height and `formatted` to the inspect card's
    /// string.
    static func history(
        for window: TrendWindow,
        ranges: [ClosedRange<Date>],
        raw: [Double],
        now: Date = .now,
        display: (Double) -> Double,
        formatted: (Double) -> String
    ) -> [TrendWindowBucket] {
        ranges.enumerated().map { index, range in
            let rawValue = index < raw.count ? raw[index] : 0
            let windowsAgo = ranges.count - 1 - index
            return TrendWindowBucket(
                id: String(Int(range.lowerBound.timeIntervalSince1970)),
                index: index,
                stripDate: TrendWindow.stripDate(forIndex: index),
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

    /// What the visible slice of a strip says: the average of the completed windows on screen (in raw
    /// units) and the tallest bar on screen (in display units).
    ///
    /// The average excludes the current, still-growing window and untrained ones — averaging a window
    /// into its own baseline drags the baseline toward it, and a training break should read as an
    /// absence of output rather than a collapse in it. The max includes every visible bar, the current
    /// one too, because the axis has to fit what it draws.
    struct VisibleStats {
        var averageRaw: Double?
        var displayMax: Double
        /// The dates the visible windows cover — the header's "average over…" caption.
        var span: ClosedRange<Date>?
    }

    static func visibleStats(
        buckets: [TrendWindowBucket],
        window: TrendWindow,
        scrollPosition: Date
    ) -> VisibleStats {
        let visible = buckets[window.visibleIndices(scrollPosition: scrollPosition, bucketCount: buckets.count)]
        var sum = 0.0
        var count = 0
        var maxDisplay = 0.0
        for bucket in visible {
            if bucket.value > maxDisplay { maxDisplay = bucket.value }
            if !bucket.isCurrent, bucket.rawValue > 0 {
                sum += bucket.rawValue
                count += 1
            }
        }
        var span: ClosedRange<Date>?
        if let first = visible.first, let last = visible.last {
            span = first.range.lowerBound ... last.range.upperBound
        }
        return VisibleStats(
            averageRaw: count > 0 ? sum / Double(count) : nil,
            displayMax: maxDisplay,
            span: span
        )
    }
}

// MARK: - Chart

/// The shared rolling-window bar chart behind the Summary's detail screens: one bar per `TrendWindow`,
/// the current window highlighted, every bar labelled by where its window ends.
///
/// It **scrolls** through the whole logged history, `historyBucketCount` windows at a time, opening on
/// the most recent ones with the current window at the trailing edge — the same timeline gesture the
/// exercise-detail charts have. A scroll settles on whole windows, and the y-scale and the dashed
/// average retarget to what is on screen, easing rather than snapping (see `PeriodHistoryChart`, whose
/// calendar-period sibling this mirrors).
///
/// Tap or press-and-hold a bar to inspect it — a value card names the exact value and which window it
/// belongs to, the touched bar lights up and the rest dim, the same gesture the calendar-period charts
/// use. The y-axis tops out on a round `chartAxisTop` above the tallest visible bar, so a peak never
/// touches the ceiling and the plot is closed by a labelled grid line.
///
/// Every bar carries its own label, unlike the scrollable calendar charts which label every second
/// mark: only `historyBucketCount` bars are ever on screen and each label is short by construction
/// (see `TrendWindow.historyBucketCount`, which is capped by exactly this).
struct TrendWindowHistoryChart: View {
    let window: TrendWindow
    let buckets: [TrendWindowBucket]
    /// Series name for the y-values ("Volume", "Sets", …) — accessibility, not rendered.
    let valueLabel: String
    /// Fill of the current window's bar; past bars stay the quiet `Color.fill`.
    let currentBarStyle: AnyShapeStyle
    /// Unit shown after the value in the inspect card ("kg", "sets", "" for a bare count).
    var unit: String = ""
    var height: CGFloat = 260
    /// An optional reference value drawn as a dashed horizontal rule — the average of the completed
    /// windows in view. Nil draws nothing. In the buckets' display units, so it lands where the bars
    /// are, and it eases to its new height as the strip scrolls.
    var averageLine: Double? = nil
    /// Bound by an owner that reads the visible window itself, so its header can move with the chart
    /// (the stat detail screens). Nil lets the chart keep its own position — the muscle detail's
    /// compact tile, which has no header to keep in step.
    var scrollPosition: Binding<Date>? = nil

    @State private var ownScrollPosition: Date
    @State private var selectedDate: Date?

    init(
        window: TrendWindow,
        buckets: [TrendWindowBucket],
        valueLabel: String,
        currentBarStyle: AnyShapeStyle,
        unit: String = "",
        height: CGFloat = 260,
        averageLine: Double? = nil,
        scrollPosition: Binding<Date>? = nil
    ) {
        self.window = window
        self.buckets = buckets
        self.valueLabel = valueLabel
        self.currentBarStyle = currentBarStyle
        self.unit = unit
        self.height = height
        self.averageLine = averageLine
        self.scrollPosition = scrollPosition
        _ownScrollPosition = State(initialValue: window.trailingScrollPosition(bucketCount: buckets.count))
    }

    private var scrollBinding: Binding<Date> { scrollPosition ?? $ownScrollPosition }

    /// The bucket whose slot the raw selection point lands in — snaps the tap onto a bar.
    private var selectedBucket: TrendWindowBucket? {
        guard let selectedDate else { return nil }
        let index = TrendWindow.stripIndex(for: selectedDate)
        guard index >= 0, index < buckets.count else { return nil }
        return buckets[index]
    }

    var body: some View {
        let visible = TrendWindowBucket.visibleStats(
            buckets: buckets,
            window: window,
            scrollPosition: scrollBinding.wrappedValue
        )
        let axisTop = chartAxisTop(above: visible.displayMax)
        let selected = selectedBucket
        Chart {
            ForEach(buckets) { bucket in
                bar(for: bucket, selected: selected)
            }
            // The visible windows' average, as a dashed reference the current bar reads against.
            // Drawn last so it sits above the bars.
            if let averageLine {
                RuleMark(y: .value(NSLocalizedString("average", comment: ""), averageLine))
                    .averageLineStyle()
            }
        }
        .chartXScale(domain: TrendWindow.stripEpoch ... TrendWindow.stripDate(forIndex: buckets.count))
        // A round ceiling just above the tallest bar in view, so the plot closes on a labelled grid
        // line instead of open space (see `chartAxisTop`).
        .chartYScale(domain: 0 ... axisTop)
        .chartXSelection(value: $selectedDate)
        .chartXAxis {
            AxisMarks(values: buckets.map(\.stripDate)) { value in
                if let date = value.as(Date.self),
                   let bucket = buckets.first(where: { $0.index == TrendWindow.stripIndex(for: date) }) {
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
            // Zero, the midpoint and the ceiling — the top mark is the point: it closes the plot.
            AxisMarks(values: [0, axisTop / 2, axisTop])
        }
        // Ease the y-scale and the dashed average to their new values as bars scroll in and out, so the
        // axis rescales and the line glides instead of snapping. Applied to the chart's marks and scale
        // here, *inside* the scroll modifiers below — the horizontal scroll must stay outside this
        // animation's scope so it keeps tracking the finger.
        .animation(.easeInOut(duration: 0.3), value: axisTop)
        .animation(.easeInOut(duration: 0.3), value: averageLine)
        .chartScrollableAxes(.horizontal)
        .chartScrollPosition(x: scrollBinding)
        .chartXVisibleDomain(length: window.historyBucketCount * TrendWindow.stripDaySeconds)
        // Midnight is a window boundary on the synthetic timeline, so a scroll comes to rest on whole
        // bars rather than mid-window — the same snap the calendar-period charts get from their own
        // components.
        .chartScrollTargetBehavior(.valueAligned(matching: DateComponents(hour: 0)))
        .frame(height: height)
    }

    // MARK: - Marks

    /// One window's bar, binned to its day on the synthetic timeline so `width` reads as a fraction of
    /// the slot. Split out of the `Chart` builder to keep that builder inside what the type checker
    /// will chew through in reasonable time.
    private func bar(for bucket: TrendWindowBucket, selected: TrendWindowBucket?) -> some ChartContent {
        BarMark(
            x: .value("Window", bucket.stripDate, unit: .day),
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

    // MARK: - Selection

    /// The current bar keeps its highlight; the inspected past bar lights up white, the rest stay the
    /// quiet fill — the opacity dim (applied on the mark) does the rest.
    private func barStyle(for bucket: TrendWindowBucket, selected: TrendWindowBucket?) -> AnyShapeStyle {
        if bucket.isCurrent { return currentBarStyle }
        if selected?.id == bucket.id { return AnyShapeStyle(Color.label) }
        return AnyShapeStyle(Color.fill)
    }

    /// Hang the card leading when the inspected bar sits in the right third of the *viewport*, trailing
    /// in the left third, centred otherwise — so an edge bar's card never lays out past the plot. The
    /// thirds are measured within the visible window rather than across the whole strip: the plot
    /// scrolls, so `fit(to: .chart)` alone would let an edge card lay out into off-screen windows and
    /// clip.
    private func annotationPosition(for bucket: TrendWindowBucket) -> AnnotationPosition {
        let length = Double(window.historyBucketCount)
        guard length > 0 else { return .top }
        let leadingIndex = Double(TrendWindow.stripIndex(for: scrollBinding.wrappedValue))
        let fraction = (Double(bucket.index) + 0.5 - leadingIndex) / length
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
/// The scoreboard reads the current window against the average of the completed windows **in view**:
/// the neutral "Average" side, the trend pill, then the tinted current window. The dashed line on the
/// chart is that same average, so the header and the plot state one fact twice rather than two facts
/// once — and both retarget together as the strip scrolls back through the history.
///
/// It owns the scroll position deliberately, exactly as `PeriodStatChartView` does: scrolling and
/// inspecting then re-evaluate only *this* view, never the screen that builds `buckets`, so the whole
/// history is bucketed once per window rather than on every scroll frame.
///
/// One known rough edge, shared with every `chartScrollPosition`-driven chart in the app: Swift Charts
/// stops reporting the position part-way through a hard flick's deceleration, so a fling that coasts
/// several windows can leave the header describing a window or two off from the bars that came to
/// rest. Anything that moves the chart again — a further scroll, a tap on a bar, switching the window
/// — re-syncs it, and a drag that the finger actually carries to a stop is reported exactly.
struct TrendWindowStatChartView: View {
    let window: TrendWindow
    let buckets: [TrendWindowBucket]
    let valueLabel: String
    let unit: String
    let currentBarStyle: AnyShapeStyle
    /// Trailing (subject) side: the current window's formatted value and its raw counterpart, which
    /// the trend pill is computed from. Fixed as the chart scrolls.
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

    @State private var scrollPosition: Date

    init(
        window: TrendWindow,
        buckets: [TrendWindowBucket],
        valueLabel: String,
        unit: String,
        currentBarStyle: AnyShapeStyle,
        currentValue: String,
        currentRaw: Double,
        trailingValueStyle: AnyShapeStyle,
        positiveColor: Color,
        positiveStyle: AnyShapeStyle? = nil,
        formatAverage: @escaping (Double) -> String,
        displayAverage: @escaping (Double) -> Double,
        explanation: String? = nil
    ) {
        self.window = window
        self.buckets = buckets
        self.valueLabel = valueLabel
        self.unit = unit
        self.currentBarStyle = currentBarStyle
        self.currentValue = currentValue
        self.currentRaw = currentRaw
        self.trailingValueStyle = trailingValueStyle
        self.positiveColor = positiveColor
        self.positiveStyle = positiveStyle
        self.formatAverage = formatAverage
        self.displayAverage = displayAverage
        self.explanation = explanation
        _scrollPosition = State(initialValue: window.trailingScrollPosition(bucketCount: buckets.count))
    }

    var body: some View {
        let visible = TrendWindowBucket.visibleStats(buckets: buckets, window: window, scrollPosition: scrollPosition)
        let average = visible.averageRaw
        let percentChange = PeriodHistoryChart.trendPercentChange(current: currentRaw, previous: average ?? 0)
        VStack(spacing: 16) {
            MetricComparisonView(
                leading: .init(
                    label: NSLocalizedString("average", comment: ""),
                    value: average.map(formatAverage) ?? "––",
                    unit: unit,
                    caption: visible.span.map(window.dateSpan)
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
                window: window,
                buckets: buckets,
                valueLabel: valueLabel,
                currentBarStyle: currentBarStyle,
                unit: unit,
                averageLine: average.map(displayAverage),
                scrollPosition: $scrollPosition
            )
            // A fresh chart per window: the strip is re-tiled wholesale when the window changes, and a
            // stale selection or scroll offset would otherwise point into a strip that no longer
            // exists.
            .id(window)
        }
        .onChange(of: window) {
            scrollPosition = window.trailingScrollPosition(bucketCount: buckets.count)
        }
    }
}

#Preview {
    let window = TrendWindow.fourWeeks
    let ranges = window.historyRanges(firstDataDate: Calendar.current.date(byAdding: .year, value: -2, to: .now))
    return TrendWindowHistoryChart(
        window: window,
        buckets: TrendWindowBucket.history(
            for: window,
            ranges: ranges,
            raw: ranges.map { Double(Calendar.current.component(.day, from: $0.upperBound) * 300) },
            display: { $0 },
            formatted: { String(Int($0)) }
        ),
        valueLabel: "Volume",
        currentBarStyle: AnyShapeStyle(Color.accentColor),
        unit: "kg"
    )
    .padding()
}
