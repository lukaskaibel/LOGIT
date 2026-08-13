//
//  TrendWindowHistoryChart.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 07.08.26.
//

import Charts
import SwiftUI

// MARK: - Bin

/// One bar of a rolling-window history strip: a **bin** inside the window — a day, a week or a month,
/// whichever `TrendWindow.bin` says — the span it covers, the labels that name it, and the value
/// trained in it. The `TrendWindow` sibling of `PeriodHistoryChart.Bucket`, which is built on calendar
/// periods.
///
/// Bars used to be whole windows: picking "4 weeks" drew five four-week blocks and tinted one, so four
/// fifths of the chart lay outside the timeframe the screen said it was reporting, and the header's
/// baseline was an average of windows the picker never mentioned. A bar is now a slice *of* the
/// selected window, every bar is in scope, and the viewport is exactly one window wide.
///
/// The x-axis is a **synthetic one-bin-per-day timeline** (`stripDate`), not the bin's real dates: bins
/// are days, weeks or months depending on the window, and Swift Charts needs one fixed unit to bin,
/// snap and scroll by. See the doc on `TrendWindow`'s strip geometry.
struct TrendWindowBin: Identifiable {
    /// Stable, unique key — the bin start's epoch seconds. The human labels aren't guaranteed unique
    /// across a strip, so `Identifiable` rides on this rather than on them.
    let id: String
    /// Position in the strip, oldest bin `0`.
    let index: Int
    /// Where the bar sits on the chart's synthetic one-bin-per-day timeline — `index` as an x-value the
    /// date machinery can bin, snap and scroll (see `TrendWindow.stripDate(forIndex:)`). Never shown.
    let stripDate: Date
    /// The real dates the bin covers. Half-open at the lower edge, tiling its neighbours exactly.
    let range: ClosedRange<Date>
    /// Short label under the bar — nil on the bins between labelled ones. Twenty-eight day bars cannot
    /// each carry a date without running together, so only every `TrendWindow.binAxisStride`-th bin is
    /// named, counted back from the newest so the most recent bin always carries one.
    let axisLabel: String?
    /// Full name for the inspect card — "Mon, 9 Aug" / "9 - 15 Aug" / "Aug 2026".
    let title: String
    /// Bar height, in display units. Zero draws no bar: an untrained bin is a gap in the strip, which
    /// is how the rhythm of training reads off a chart of days.
    let value: Double
    /// The bin's value in raw storage units.
    let rawValue: Double
    /// The value as printed in the inspect card ("1,234", "12.5", "8").
    let formattedValue: String
}

extension TrendWindowBin {
    /// The strip for `window`, oldest bin first, the one holding "now" last.
    ///
    /// `ranges` comes from `window.binRanges(firstDataDate:)` and `raw` holds one value per range, in
    /// the same order. The values are handed over already reduced rather than pulled through a
    /// per-bin closure: a strip runs to hundreds of bins, and a closure re-scanning the whole dataset
    /// per bin would make building it quadratic on the screen's hottest path.
    /// `TrendWindow.binIndex(of:in:)` is how a screen fills that array in one pass. `display` maps a
    /// raw value to the bar's height and `formatted` to the inspect card's string.
    static func strip(
        for window: TrendWindow,
        ranges: [ClosedRange<Date>],
        raw: [Double],
        display: (Double) -> Double,
        formatted: (Double) -> String
    ) -> [TrendWindowBin] {
        let stride = max(window.binAxisStride, 1)
        let newest = ranges.count - 1
        return ranges.enumerated().map { index, range in
            let rawValue = index < raw.count ? raw[index] : 0
            // Counted back from the newest bin so it is always labelled, whatever the strip's length —
            // the same anchoring the calendar-period charts use for their axis marks.
            let isLabelled = (newest - index) % stride == 0
            return TrendWindowBin(
                id: String(Int(range.lowerBound.timeIntervalSince1970)),
                index: index,
                stripDate: TrendWindow.stripDate(forIndex: index),
                range: range,
                axisLabel: isLabelled ? window.binAxisLabel(for: range) : nil,
                title: window.binTitle(for: range),
                value: display(rawValue),
                rawValue: rawValue,
                formattedValue: formatted(rawValue)
            )
        }
    }

    /// What the visible slice of a strip looks like: the tallest bar on screen (so the axis can fit
    /// what it draws) and the mean of the bins that hold training (the dashed reference line).
    ///
    /// The mean skips untrained bins deliberately. A strip of days is mostly gaps for anyone training
    /// three times a week, and averaging the rest days in would drag the line to a third of the bars
    /// it is meant to sit among — it reads "a typical session", not "output per calendar day".
    struct VisibleStats {
        var displayMax: Double
        var trainedMean: Double?
    }

    static func visibleStats(bins: [TrendWindowBin], indices: Range<Int>) -> VisibleStats {
        guard !indices.isEmpty, indices.upperBound <= bins.count else {
            return VisibleStats(displayMax: 0, trainedMean: nil)
        }
        var sum = 0.0
        var count = 0
        var maxDisplay = 0.0
        for bin in bins[indices] {
            if bin.value > maxDisplay { maxDisplay = bin.value }
            if bin.value > 0 {
                sum += bin.value
                count += 1
            }
        }
        return VisibleStats(
            displayMax: maxDisplay,
            trainedMean: count > 0 ? sum / Double(count) : nil
        )
    }
}

// MARK: - Chart

/// The shared bin bar chart behind the Summary's detail screens: one bar per day / week / month of the
/// selected window, **every bar in the same tint** because every bar is in scope. Untrained bins are
/// gaps.
///
/// It **scrolls** through the whole logged history one window at a time, opening on the current window
/// at the trailing edge — the same timeline gesture the exercise-detail charts have. A scroll settles
/// on whole bins, and the y-scale and the dashed mean retarget to what is on screen, easing rather
/// than snapping (see `PeriodHistoryChart`, whose calendar-period sibling this mirrors). Because the
/// viewport is exactly one window wide, scrolling back a screenful is scrolling back one window: the
/// header beside it keeps describing "a window", just an earlier one.
///
/// Tap or press-and-hold a bar to inspect it — a value card names the exact value and which day, week
/// or month it belongs to, the touched bar lights up and the rest dim. The y-axis tops out on a round
/// `chartAxisTop` above the tallest visible bar, so a peak never touches the ceiling and the plot is
/// closed by a labelled grid line.
struct TrendWindowHistoryChart: View {
    let window: TrendWindow
    let bins: [TrendWindowBin]
    /// Series name for the y-values ("Volume", "Sets", …) — accessibility, not rendered.
    let valueLabel: String
    /// Fill of every bar. One style, not a current-vs-past split: the whole strip is the timeframe the
    /// picker names, so there is no "rest" to grey out.
    let barStyle: AnyShapeStyle
    /// Unit shown after the value in the inspect card ("kg", "sets", "" for a bare count).
    var unit: String = ""
    var height: CGFloat = 260
    /// An optional reference value drawn as a dashed horizontal rule — the mean of the trained bins in
    /// view. Nil draws nothing. In the bins' display units, so it lands where the bars are, and it
    /// eases to its new height as the strip scrolls.
    var averageLine: Double? = nil
    /// Bound by an owner that reads the visible window itself, so its header can move with the chart
    /// (the stat detail screens). Nil lets the chart keep its own position — the muscle detail's
    /// compact tile, which has no header to keep in step.
    var scrollPosition: Binding<Date>? = nil

    @State private var ownScrollPosition: Date
    @State private var selectedDate: Date?

    init(
        window: TrendWindow,
        bins: [TrendWindowBin],
        valueLabel: String,
        barStyle: AnyShapeStyle,
        unit: String = "",
        height: CGFloat = 260,
        averageLine: Double? = nil,
        scrollPosition: Binding<Date>? = nil
    ) {
        self.window = window
        self.bins = bins
        self.valueLabel = valueLabel
        self.barStyle = barStyle
        self.unit = unit
        self.height = height
        self.averageLine = averageLine
        self.scrollPosition = scrollPosition
        _ownScrollPosition = State(initialValue: window.trailingScrollPosition(binCount: bins.count))
    }

    private var scrollBinding: Binding<Date> { scrollPosition ?? $ownScrollPosition }

    /// The bin whose slot the raw selection point lands in — snaps the tap onto a bar.
    private var selectedBin: TrendWindowBin? {
        guard let selectedDate else { return nil }
        let index = TrendWindow.stripIndex(for: selectedDate)
        guard index >= 0, index < bins.count else { return nil }
        return bins[index]
    }

    var body: some View {
        let visible = TrendWindowBin.visibleStats(
            bins: bins,
            indices: window.visibleIndices(scrollPosition: scrollBinding.wrappedValue, binCount: bins.count)
        )
        let axisTop = chartAxisTop(above: visible.displayMax)
        let selected = selectedBin
        Chart {
            ForEach(bins) { bin in
                bar(for: bin, selected: selected)
            }
            // The visible window's typical bar, as a dashed reference. Drawn last so it sits above the
            // bars.
            if let averageLine {
                RuleMark(y: .value(NSLocalizedString("average", comment: ""), averageLine))
                    .averageLineStyle()
            }
        }
        .chartXScale(domain: TrendWindow.stripEpoch ... TrendWindow.stripDate(forIndex: bins.count))
        // A round ceiling just above the tallest bar in view, so the plot closes on a labelled grid
        // line instead of open space (see `chartAxisTop`).
        .chartYScale(domain: 0 ... axisTop)
        .chartXSelection(value: $selectedDate)
        .chartXAxis {
            // Only the labelled bins get a mark — a grid line under all twenty-eight bars of a
            // four-week strip would read as hatching, and their labels would collide outright.
            AxisMarks(values: bins.filter { $0.axisLabel != nil }.map(\.stripDate)) { value in
                if let date = value.as(Date.self),
                   let bin = bins.first(where: { $0.index == TrendWindow.stripIndex(for: date) }),
                   let label = bin.axisLabel {
                    AxisGridLine()
                        .foregroundStyle(Color.gray.opacity(0.4))
                    // The newest bin hugs the right edge on first load, where a centred label is
                    // silently clipped to half a date ("Au"). Hang that one trailing off its mark so
                    // it renders whole; every other label centres under the bar it names. Styling
                    // lives on the Text inside the closure — hierarchical styles on the AxisMark
                    // resolve against the chart's accent on iOS 26 (labels turned lime).
                    AxisValueLabel(anchor: bin.index == bins.count - 1 ? .topTrailing : nil) {
                        Text(label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.secondaryLabel)
                            .fixedSize()
                    }
                }
            }
        }
        .chartYAxis {
            // Zero, the midpoint and the ceiling — the top mark is the point: it closes the plot.
            AxisMarks(values: [0, axisTop / 2, axisTop])
        }
        // Ease the y-scale and the dashed mean to their new values as bars scroll in and out, so the
        // axis rescales and the line glides instead of snapping. Applied to the chart's marks and scale
        // here, *inside* the scroll modifiers below — the horizontal scroll must stay outside this
        // animation's scope so it keeps tracking the finger.
        .animation(.easeInOut(duration: 0.3), value: axisTop)
        .animation(.easeInOut(duration: 0.3), value: averageLine)
        .chartScrollableAxes(.horizontal)
        .chartScrollPosition(x: scrollBinding)
        // Exactly one window wide — the picker names the viewport.
        .chartXVisibleDomain(length: window.binsPerWindow * TrendWindow.stripDaySeconds)
        // Midnight is a bin boundary on the synthetic timeline, so a scroll comes to rest on whole
        // bars rather than mid-bin — the same snap the calendar-period charts get from their own
        // components.
        .chartScrollTargetBehavior(.valueAligned(matching: DateComponents(hour: 0)))
        .frame(height: height)
    }

    // MARK: - Marks

    /// One bin's bar, binned to its day on the synthetic timeline so `width` reads as a fraction of the
    /// slot. Split out of the `Chart` builder to keep that builder inside what the type checker will
    /// chew through in reasonable time.
    private func bar(for bin: TrendWindowBin, selected: TrendWindowBin?) -> some ChartContent {
        BarMark(
            x: .value("Bin", bin.stripDate, unit: .day),
            y: .value(valueLabel, bin.value),
            width: .ratio(0.6)
        )
        .foregroundStyle(selected?.id == bin.id ? AnyShapeStyle(Color.label) : barStyle)
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        // A tapped bar stays lit; every other bar goes quiet while one is inspected.
        .opacity(selected == nil || selected?.id == bin.id ? 1.0 : 0.4)
        .annotation(
            position: annotationPosition(for: bin),
            overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
        ) {
            if selected?.id == bin.id {
                annotationCard(for: bin)
            }
        }
    }

    // MARK: - Selection

    /// Hang the card leading when the inspected bar sits in the right third of the *viewport*, trailing
    /// in the left third, centred otherwise — so an edge bar's card never lays out past the plot. The
    /// thirds are measured within the visible window rather than across the whole strip: the plot
    /// scrolls, so `fit(to: .chart)` alone would let an edge card lay out into off-screen bins and
    /// clip.
    private func annotationPosition(for bin: TrendWindowBin) -> AnnotationPosition {
        let length = Double(window.binsPerWindow)
        guard length > 0 else { return .top }
        let leadingIndex = Double(TrendWindow.stripIndex(for: scrollBinding.wrappedValue))
        let fraction = (Double(bin.index) + 0.5 - leadingIndex) / length
        if fraction > 0.66 { return .topLeading }
        if fraction < 0.33 { return .topTrailing }
        return .top
    }

    private func annotationCard(for bin: TrendWindowBin) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            UnitView(value: bin.formattedValue, unit: unit, unitColor: .secondaryLabel)
                .foregroundStyle(Color.label)
            Text(bin.title)
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

// MARK: - Window value

/// One window's worth of bins collapsed to the single number a header shows — whatever "collapsed"
/// means for the screen asking (a per-workout average, a running total, a set count).
///
/// The screen supplies this rather than the chart deriving it from the bars, because the honest
/// answer is not always a function of the bars: a per-workout average over a window is its total
/// divided by the workouts in it, which is not the mean of the daily averages once a day holds two
/// sessions.
struct TrendWindowValue {
    let raw: Double
    let formatted: String
    /// False when the span held no training — the header shows "––" rather than a zero it can't stand
    /// behind, and the trend pill disappears.
    let hasData: Bool

    static let none = TrendWindowValue(raw: 0, formatted: "––", hasData: false)
}

// MARK: - Header + chart

/// The shared header-plus-chart for the Summary's four stat detail screens — the `TrendWindow` sibling
/// of `PeriodStatChartView`, which the calendar-period exercise screens still use.
///
/// The scoreboard reads **the window on screen against the window immediately before it**: the neutral
/// "Previous 4 weeks" side, the trend pill, then the tinted current one. That is the whole point of the
/// screen having one picker — pick "4 weeks" and every number on it, the percentage included, is about
/// those four weeks and the four before them. It used to compare the current window against the average
/// of the six completed windows on the strip, which not only reached far outside the timeframe the
/// picker named but disagreed with the tile that had just been tapped: the tile compares against the
/// single previous window, so the same metric showed two different percentages either side of a tap.
///
/// Scrolling moves both sides together — the strip's viewport is exactly one window wide, so a
/// screenful back is a window back, and the header re-reads as that earlier window against the one
/// before *it*. The dashed line on the chart is the typical trained bin in view, so the header says
/// what the window did and the line says what a session in it looked like.
///
/// It owns the scroll position deliberately, exactly as `PeriodStatChartView` does: scrolling and
/// inspecting then re-evaluate only *this* view, never the screen that builds the bins, so the whole
/// history is binned once per window rather than on every scroll frame.
///
/// One known rough edge, shared with every `chartScrollPosition`-driven chart in the app: Swift Charts
/// stops reporting the position part-way through a hard flick's deceleration, so a fling that coasts
/// several windows can leave the header describing a window or two off from the bars that came to rest.
/// Anything that moves the chart again — a further scroll, a tap on a bar, switching the window —
/// re-syncs it, and a drag that the finger actually carries to a stop is reported exactly.
struct TrendWindowStatChartView: View {
    let window: TrendWindow
    let bins: [TrendWindowBin]
    let valueLabel: String
    let unit: String
    let barStyle: AnyShapeStyle
    /// Collapses a run of bins into the number the header shows. Called for the visible window and for
    /// the one before it, so both sides are computed the same way by construction.
    let value: (Range<Int>) -> TrendWindowValue
    let trailingValueStyle: AnyShapeStyle
    let positiveColor: Color
    var positiveStyle: AnyShapeStyle? = nil
    var explanation: String? = nil

    @State private var scrollPosition: Date

    init(
        window: TrendWindow,
        bins: [TrendWindowBin],
        valueLabel: String,
        unit: String,
        barStyle: AnyShapeStyle,
        value: @escaping (Range<Int>) -> TrendWindowValue,
        trailingValueStyle: AnyShapeStyle,
        positiveColor: Color,
        positiveStyle: AnyShapeStyle? = nil,
        explanation: String? = nil
    ) {
        self.window = window
        self.bins = bins
        self.valueLabel = valueLabel
        self.unit = unit
        self.barStyle = barStyle
        self.value = value
        self.trailingValueStyle = trailingValueStyle
        self.positiveColor = positiveColor
        self.positiveStyle = positiveStyle
        self.explanation = explanation
        _scrollPosition = State(initialValue: window.trailingScrollPosition(binCount: bins.count))
    }

    var body: some View {
        let visibleIndices = window.visibleIndices(scrollPosition: scrollPosition, binCount: bins.count)
        let precedingIndices = window.precedingIndices(before: visibleIndices)
        let current = value(visibleIndices)
        let previous = value(precedingIndices)
        let stats = TrendWindowBin.visibleStats(bins: bins, indices: visibleIndices)
        let percentChange = (current.hasData && previous.hasData)
            ? PeriodHistoryChart.trendPercentChange(current: current.raw, previous: previous.raw)
            : nil
        VStack(spacing: 16) {
            MetricComparisonView(
                leading: .init(
                    label: window.previousWindowLabel,
                    value: previous.formatted,
                    unit: unit,
                    caption: caption(for: precedingIndices)
                ),
                trailing: .init(
                    // At the trailing edge the visible window *is* the current one and can be named
                    // "Last 4 weeks"; scrolled back it is simply a four-week window, and the date
                    // caption underneath is what says which.
                    label: isAtTrailingEdge ? window.currentWindowLabel : window.title,
                    value: current.formatted,
                    unit: unit,
                    caption: caption(for: visibleIndices)
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
                bins: bins,
                valueLabel: valueLabel,
                barStyle: barStyle,
                unit: unit,
                averageLine: stats.trainedMean,
                scrollPosition: $scrollPosition
            )
            // A fresh chart per window: the strip is re-binned wholesale when the window changes, and a
            // stale selection or scroll offset would otherwise point into a strip that no longer
            // exists.
            .id(window)
        }
        .onChange(of: window) {
            scrollPosition = window.trailingScrollPosition(binCount: bins.count)
        }
    }

    private var isAtTrailingEdge: Bool {
        window.visibleIndices(scrollPosition: scrollPosition, binCount: bins.count).upperBound >= bins.count
    }

    /// The dates a run of bins covers. The upper bound is the *next* bin's first instant (bins tile the
    /// timeline), so it steps back an instant before formatting — otherwise a window ending today would
    /// caption itself with tomorrow's date.
    private func caption(for indices: Range<Int>) -> String? {
        guard !indices.isEmpty, indices.upperBound <= bins.count else { return nil }
        let run = bins[indices]
        guard let first = run.first, let last = run.last else { return nil }
        return window.dateSpan(first.range.lowerBound ... last.range.upperBound.addingTimeInterval(-1))
    }
}

#Preview {
    let window = TrendWindow.fourWeeks
    let ranges = window.binRanges(firstDataDate: Calendar.current.date(byAdding: .month, value: -3, to: .now))
    return TrendWindowHistoryChart(
        window: window,
        bins: TrendWindowBin.strip(
            for: window,
            ranges: ranges,
            // A plausible rhythm: trained on most days, resting on others.
            raw: ranges.enumerated().map { index, _ in index % 3 == 0 ? 0 : Double(2000 + (index % 7) * 400) },
            display: { $0 },
            formatted: { String(Int($0)) }
        ),
        valueLabel: "Volume",
        barStyle: AnyShapeStyle(Color.accentColor),
        unit: "kg"
    )
    .padding()
}
