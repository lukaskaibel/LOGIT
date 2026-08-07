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
/// basis menu. The tile shows the current window; the screen zooms out to the last several windows,
/// the current one highlighted. One screen serves all four stats — `WorkoutStatMetric` supplies
/// values, formatting, and the about text. Pro, like the other stat detail screens (the tile is the
/// free hook).
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
        ScrollView {
            VStack(spacing: SECTION_SPACING) {
                VStack(spacing: 16) {
                    TrendWindowPicker(selection: $window)
                    TrendWindowStatChartView(
                        window: window,
                        buckets: buckets,
                        valueLabel: metric.title,
                        unit: metric.unit,
                        currentBarStyle: AnyShapeStyle(isDuration ? Color.secondary : Color.accentColor),
                        currentValue: currentValue,
                        currentRaw: currentRaw,
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

    /// The metric summed and the non-empty workouts counted over one window. The count is the
    /// per-workout divisor — matching the "N workouts" the weekly-goal pill counts — and empty
    /// workouts are left out: they add nothing to the sum yet would inflate the count and drag an
    /// average down.
    ///
    /// Membership goes through `TrendWindow.contains`, whose lower edge is half-open, so a workout
    /// landing exactly on the instant two windows share counts in the newer one only.
    private func aggregate(in range: ClosedRange<Date>) -> (sum: Int, count: Int) {
        var sum = 0
        var count = 0
        for workout in workouts where !workout.isEmpty {
            guard let date = workout.date, date > range.lowerBound, date <= range.upperBound else { continue }
            sum += metric.rawValue(of: workout)
            count += 1
        }
        return (sum, count)
    }

    private var currentAggregate: (sum: Int, count: Int) {
        aggregate(in: window.currentRange())
    }

    /// The current window's value in raw units for the chosen basis — the per-workout average or the
    /// running total. Drives the header's trend against the completed windows' average.
    private var currentRaw: Double {
        basis.aggregate(sum: currentAggregate.sum, count: currentAggregate.count)
    }

    /// The current window's headline string: the total formatted whole, or the per-workout average
    /// with its fractional precision kept (for the small set / rep counts). "––" when nothing was
    /// logged — there is no session to average, and a "0" total would read as a decline.
    private var currentValue: String {
        switch basis {
        case .total:
            return metric.formattedValue(fromRaw: currentAggregate.sum)
        case .perWorkout:
            return currentAggregate.count > 0 ? metric.formattedAverage(rawAverage: currentRaw) : "––"
        }
    }

    private var buckets: [TrendWindowBucket] {
        TrendWindowBucket.history(
            for: window,
            raw: { range in
                let aggregate = self.aggregate(in: range)
                return basis.aggregate(sum: aggregate.sum, count: aggregate.count)
            },
            display: { metric.displayValue(fromRaw: Int($0.rounded())) },
            formatted: {
                basis == .total
                    ? metric.formattedValue(fromRaw: Int($0.rounded()))
                    : metric.formattedAverage(rawAverage: $0)
            }
        )
    }
}
