//
//  SummaryStatScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 29.06.26.
//

import SwiftUI

/// Detail screen behind a Summary core-stat tile: the stat across recent history, scoped by the
/// shared `TrendWindowPicker` and read either **per workout** (the default, matching the tile — a
/// typical session with frequency divided out) or as the window's running **total**, flipped with the
/// basis menu. The tile shows the current window; the screen zooms out to a strip of them, the current
/// one highlighted at the trailing edge, and scrolls back through the whole logged history — the
/// header's average and the chart's dashed line following whatever is on screen. One screen serves all
/// four stats — `WorkoutStatMetric` supplies values, formatting, and the about text. Pro, like the
/// other stat detail screens (the tile is the free hook).
///
/// It opens on whatever window the Summary was showing, and offers the same three options as every
/// other scoped screen. It used to carry a calendar Week / Month / Year picker instead, which made it
/// the odd one out among the six detail screens and meant tapping a four-week tile opened a screen
/// reporting calendar months — a different measurement, presented as the same one.
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
                        buckets: history.buckets,
                        valueLabel: metric.title,
                        unit: metric.unit,
                        currentBarStyle: AnyShapeStyle(isDuration ? Color.secondary : Color.accentColor),
                        currentValue: currentValue(history.current),
                        currentRaw: currentRaw(history.current),
                        trailingValueStyle: isDuration ? AnyShapeStyle(Color.label) : AnyShapeStyle(Color.accentColor.gradient),
                        positiveColor: isDuration ? .secondary : .accentColor,
                        formatAverage: { metric.formattedAverage(rawAverage: $0) },
                        displayAverage: { metric.displayValue(fromRaw: Int($0.rounded())) },
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

    /// The metric summed and the non-empty workouts counted per window. The count is the per-workout
    /// divisor — matching the "N workouts" the weekly-goal pill counts — and empty workouts are left
    /// out: they add nothing to the sum yet would inflate the count and drag an average down.
    private struct Aggregate {
        var sum = 0
        var count = 0
    }

    /// The scrollable strip plus the current window's aggregate, built in **one pass** over the
    /// workouts. The strip now reaches back to the first logged workout rather than showing a fixed
    /// handful of windows, so a per-window filter would re-scan every workout dozens of times — and
    /// `metric.rawValue(of:)` faults a workout's whole set list, which makes that the most expensive
    /// scan on the screen. Instead each workout is placed in its window once, by binary search
    /// (`TrendWindow.bucketIndex`, whose half-open lower edge is the same membership rule
    /// `TrendWindow.contains` applies everywhere else).
    private var history: (buckets: [TrendWindowBucket], current: Aggregate) {
        let ranges = window.historyRanges(firstDataDate: firstDataDate)
        var aggregates = [Aggregate](repeating: Aggregate(), count: ranges.count)
        for workout in workouts where !workout.isEmpty {
            guard let date = workout.date,
                  let index = TrendWindow.bucketIndex(of: date, in: ranges) else { continue }
            aggregates[index].sum += metric.rawValue(of: workout)
            aggregates[index].count += 1
        }
        let buckets = TrendWindowBucket.history(
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
        // The strip's newest bucket *is* the current window — the header reads it straight off rather
        // than aggregating the same span a second time.
        return (buckets, aggregates.last ?? Aggregate())
    }

    /// Earliest logged workout — how far back the strip scrolls.
    private var firstDataDate: Date? {
        workouts.compactMap(\.date).min()
    }

    /// The current window's value in raw units for the chosen basis — the per-workout average or the
    /// running total. Drives the header's trend against the visible windows' average.
    private func currentRaw(_ aggregate: Aggregate) -> Double {
        basis.aggregate(sum: aggregate.sum, count: aggregate.count)
    }

    /// The current window's headline string: the total formatted whole, or the per-workout average
    /// with its fractional precision kept (for the small set / rep counts). "––" when nothing was
    /// logged — there is no session to average, and a "0" total would read as a decline.
    private func currentValue(_ aggregate: Aggregate) -> String {
        switch basis {
        case .total:
            return metric.formattedValue(fromRaw: aggregate.sum)
        case .perWorkout:
            return aggregate.count > 0 ? metric.formattedAverage(rawAverage: currentRaw(aggregate)) : "––"
        }
    }
}
