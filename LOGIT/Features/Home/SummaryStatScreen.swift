//
//  SummaryStatScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 29.06.26.
//

import SwiftUI

/// Detail screen behind a Summary core-stat tile: the selected window broken into its days, weeks or
/// months, read either **per workout** (the default, matching the tile — a typical session with
/// frequency divided out) or as the window's running **total**, flipped with the basis menu. The tile
/// shows the same window's bars in miniature; the screen adds the axis, the inspect card, the
/// comparison against the window before, and a scroll back through the whole logged history a window
/// at a time. One screen serves all four stats — `WorkoutStatMetric` supplies values, formatting, and
/// the about text. Pro, like the other stat detail screens (the tile is the free hook).
///
/// It opens on whatever window the Summary was showing, and offers the same three options as every
/// other scoped screen. Two earlier readings are worth not going back to: a calendar Week / Month /
/// Year picker, which meant tapping a four-week tile opened a screen reporting calendar months; and a
/// strip of whole windows, which meant picking "4 weeks" drew twenty-eight weeks of bars and compared
/// the current one against an average of six windows the picker never named.
struct SummaryStatScreen: View {
    let metric: WorkoutStatMetric
    let workouts: [Workout]

    @State private var window: TrendWindow
    /// The tiles are always per-workout (a typical session); the screen opens the same way but lets
    /// the reader flip to the window's running total.
    @State private var basis: StatBasis = .perWorkout

    init(metric: WorkoutStatMetric, workouts: [Workout], initialWindow: TrendWindow = .default) {
        self.metric = metric
        self.workouts = workouts
        _window = State(initialValue: initialWindow)
    }

    private var isDuration: Bool { metric == .duration }

    var body: some View {
        let history = self.history
        ScrollView {
            VStack(spacing: SECTION_SPACING) {
                VStack(spacing: 16) {
                    TrendWindowPicker(selection: $window)
                    TrendWindowStatChartView(
                        window: window,
                        bins: history.bins,
                        valueLabel: metric.title,
                        unit: metric.unit,
                        barStyle: AnyShapeStyle(isDuration ? Color.secondary : Color.accentColor),
                        value: { indices in windowValue(over: indices, aggregates: history.aggregates) },
                        trailingValueStyle: isDuration ? AnyShapeStyle(Color.label) : AnyShapeStyle(Color.accentColor.gradient),
                        positiveColor: isDuration ? .secondary : .accentColor,
                        explanation: NSLocalizedString("averageComparisonInfo", comment: "")
                    )
                }
                .padding(.horizontal)
                AboutSection(metricTitle: metric.title, text: metric.aboutText)
                    .padding(.horizontal)
            }
            .padding(.top)
            .padding(.bottom, SCROLLVIEW_BOTTOM_PADDING)
        }
        .isBlockedWithoutPro()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(metric.title)
                    .font(.headline)
            }
            // The Per Workout / Total switch lives in the nav bar — a menu keeps the chart area to the
            // single 4 weeks / 3 months / 1 year scope, and the checkmarked options say which basis is
            // showing.
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker(NSLocalizedString("basis", comment: ""), selection: $basis) {
                        ForEach(StatBasis.allCases) { basis in
                            Text(basis.title).tag(basis)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .accessibilityLabel(NSLocalizedString("basis", comment: ""))
                }
            }
        }
    }

    // MARK: - Data

    /// The metric summed and the non-empty workouts counted for one bin. The count is the per-workout
    /// divisor — matching the "N workouts" the weekly-goal pill counts — and empty workouts are left
    /// out: they add nothing to the sum yet would inflate the count and drag an average down.
    ///
    /// Sums and counts are kept **per bin rather than pre-collapsed**, because a window's per-workout
    /// average is its total over its workout count, which is not the mean of its days' averages once a
    /// day holds two sessions. Keeping both halves lets any run of bins be collapsed correctly.
    private struct Aggregate {
        var sum = 0
        var count = 0
    }

    /// The scrollable strip of bins plus the per-bin aggregates behind it, built in **one pass** over
    /// the workouts. The strip reaches back to the first logged workout, so a per-bin filter would
    /// re-scan every workout hundreds of times — and `metric.rawValue(of:)` faults a workout's whole
    /// set list, which makes that the most expensive scan on the screen. Instead each workout is placed
    /// in its bin once, by binary search (`TrendWindow.binIndex`, whose half-open lower edge is the
    /// same membership rule `TrendWindow.contains` applies everywhere else).
    private var history: (bins: [TrendWindowBin], aggregates: [Aggregate]) {
        let ranges = window.binRanges(firstDataDate: firstDataDate)
        var aggregates = [Aggregate](repeating: Aggregate(), count: ranges.count)
        for workout in workouts where !workout.isEmpty {
            guard let date = workout.date,
                  let index = TrendWindow.binIndex(of: date, in: ranges) else { continue }
            aggregates[index].sum += metric.rawValue(of: workout)
            aggregates[index].count += 1
        }
        let bins = TrendWindowBin.strip(
            for: window,
            ranges: ranges,
            raw: aggregates.map { basis.aggregate(sum: $0.sum, count: $0.count) },
            display: { metric.displayValue(fromRaw: Int($0.rounded())) },
            formatted: {
                basis == .total
                    ? metric.formattedValue(fromRaw: Int($0.rounded()))
                    : metric.formattedAverage(rawAverage: $0)
            }
        )
        return (bins, aggregates)
    }

    /// Earliest logged workout — how far back the strip scrolls.
    private var firstDataDate: Date? {
        workouts.compactMap(\.date).min()
    }

    /// A run of bins collapsed to the header's number: the window's running total, or its per-workout
    /// average — the summed metric over the sessions that produced it, never the mean of the bars.
    ///
    /// "––" when the span held no workout: there is no session to average, and a "0" total would read
    /// as a collapse in output rather than an absence of it.
    private func windowValue(over indices: Range<Int>, aggregates: [Aggregate]) -> TrendWindowValue {
        guard !indices.isEmpty, indices.upperBound <= aggregates.count else { return .none }
        var total = Aggregate()
        for aggregate in aggregates[indices] {
            total.sum += aggregate.sum
            total.count += aggregate.count
        }
        guard total.count > 0 else { return .none }
        let raw = basis.aggregate(sum: total.sum, count: total.count)
        let formatted = basis == .total
            ? metric.formattedValue(fromRaw: total.sum)
            : metric.formattedAverage(rawAverage: raw)
        return TrendWindowValue(raw: raw, formatted: formatted, hasData: true)
    }
}
