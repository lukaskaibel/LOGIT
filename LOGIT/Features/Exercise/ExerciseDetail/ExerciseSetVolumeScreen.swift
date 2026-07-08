//
//  ExerciseSetVolumeScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 11.06.26.
//

import Charts
import SwiftUI

struct ExerciseSetVolumeScreen: View {
    let exercise: Exercise
    let workoutSets: [WorkoutSet]
    /// Daily-max sets, grouped once at init. The chart, the header baseline, the y-scale, the domain
    /// and the selection all read from this — so scrolling or inspecting never regroups every set
    /// again. (The selection lag came from `firstDataDate` re-grouping all sets once per axis mark,
    /// every frame.)
    private let dailyMaxSets: [WorkoutSet]
    /// Earliest day with data — anchors the scrollable domain and the All range. Derived once from
    /// `dailyMaxSets`, not recomputed on every scroll/selection frame.
    private let firstDataDate: Date?

    @State private var chartRange: ChartRange = .threeMonths
    @State private var chartScrollPosition: Date = .now
    @State private var selectedDate: Date?

    init(exercise: Exercise, workoutSets: [WorkoutSet]) {
        self.exercise = exercise
        self.workoutSets = workoutSets
        let daily = Self.dailyMaxSetVolumeSets(in: workoutSets, for: exercise)
        self.dailyMaxSets = daily
        self.firstDataDate = daily.first?.workout?.date
    }

    var body: some View {
        let allDailyMaxSets = dailyMaxSets
        // Determine the snapped selected set only when a selection exists; snap to the nearest datapoint (prefer visible)
        let snappedSelectedSet: WorkoutSet? = selectedDate != nil ? nearestSet(to: selectedDate, in: allDailyMaxSets) : nil
        let bestVisibleSetVolume = bestSetVolumeInVisibleWindow()
        ScrollView {
            VStack(spacing: SECTION_SPACING) {
                VStack {
                    RangePicker(selection: $chartRange)
                    .padding(.vertical)
                    .padding(.horizontal)
                    MetricComparisonView(
                        leading: .init(
                            label: NSLocalizedString("previousBest", comment: ""),
                            value: bestVisibleSetVolume.map(formatWeightForDisplay) ?? "––",
                            unit: WeightUnit.used.rawValue,
                            caption: chartRange.visibleWindowDescription(from: chartScrollPosition, firstDataDate: firstDataDate)
                        ),
                        trailing: .init(
                            label: NSLocalizedString(bestAnchor?.isLapsed == true ? "lastBest" : "currentBest", comment: ""),
                            value: bestAnchor.map { formatWeightForDisplay($0.value) } ?? "––",
                            unit: WeightUnit.used.rawValue,
                            caption: bestAnchor?.date.map { $0.formatted(.dateTime.day().month()) }
                        ),
                        trailingValueStyle: AnyShapeStyle(exerciseMuscleGroupColor.gradient),
                        percentChange: bestAnchor?.isLapsed == true ? nil : headerTrendPercentage(visibleBest: bestVisibleSetVolume),
                        positiveColor: exerciseMuscleGroupColor,
                        explanation: NSLocalizedString("currentBestComparisonInfo", comment: "")
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    Chart {
                        // Show selection only when a selection exists, snapped to the nearest datapoint
                        if selectedDate != nil, let selectedSet = snappedSelectedSet, let sDate = selectedSet.workout?.date {
                            let snapped = Calendar.current.startOfDay(for: sDate)
                            let valueDisplayed = formatWeightForDisplay(selectedSet.volume(for: exercise))
                            RuleMark(x: .value("Selected", snapped, unit: .day))
                                .foregroundStyle(exerciseMuscleGroupColor.opacity(0.35))
                                .lineStyle(StrokeStyle(lineWidth: 2))
                                .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                                    VStack(alignment: .leading) {
                                        UnitView(
                                            value: "\(valueDisplayed)",
                                            unit: WeightUnit.used.rawValue
                                        )
                                        .foregroundStyle(exerciseMuscleGroupColor.gradient)
                                        Text(snapped.formatted(.dateTime.day().month()))
                                            .fontWeight(.bold)
                                            .fontDesign(.rounded)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondaryBackground))
                                }
                        }
                        if let firstEntry = allDailyMaxSets.first {
                            LineMark(
                                x: .value("Date", Date.distantPast, unit: .day),
                                y: .value("Max set volume on day", convertWeightForDisplayingDecimal(firstEntry.volume(for: exercise)))
                            )
                            .interpolationMethod(.monotone)
                            .foregroundStyle(exerciseMuscleGroupColor.gradient)
                            .lineStyle(StrokeStyle(lineWidth: 5))
                            .opacity(snappedSelectedSet == nil ? 1.0 : 0.3)
                            AreaMark(
                                x: .value("Date", Date.distantPast, unit: .day),
                                y: .value("Max set volume on day", convertWeightForDisplayingDecimal(firstEntry.volume(for: exercise)))
                            )
                            .interpolationMethod(.monotone)
                            .foregroundStyle(Gradient(colors: [
                                exerciseMuscleGroupColor.opacity(0.5),
                                exerciseMuscleGroupColor.opacity(0.2),
                                exerciseMuscleGroupColor.opacity(0.05),
                            ]))
                            .opacity(snappedSelectedSet == nil ? 1.0 : 0.3)
                        }
                        ForEach(allDailyMaxSets) { workoutSet in
                            LineMark(
                                x: .value("Date", workoutSet.workout?.date ?? .now, unit: .day),
                                y: .value("Max set volume on day", convertWeightForDisplayingDecimal(workoutSet.volume(for: exercise)))
                            )
                            .interpolationMethod(.monotone)
                            .foregroundStyle(exerciseMuscleGroupColor.gradient)
                            .lineStyle(StrokeStyle(lineWidth: 5))
                            .symbol {
                                Circle()
                                    .frame(width: 10, height: 10)
                                    .foregroundStyle(
                                        exerciseMuscleGroupColor.gradient
                                            .opacity({
                                                guard let s = snappedSelectedSet?.workout?.date else { return 1.0 }
                                                return Calendar.current.isDate(workoutSet.workout?.date ?? .distantPast, inSameDayAs: s) ? 1.0 : 0.3
                                            }())
                                    )
                                    .overlay {
                                        Circle()
                                            .frame(width: 4, height: 4)
                                            .foregroundStyle(Color.black)
                                    }
                                    .background(Circle().fill(Color.black))
                            }
                            .opacity({
                                guard let s = snappedSelectedSet?.workout?.date else { return 1.0 }
                                return Calendar.current.isDate(workoutSet.workout?.date ?? .distantPast, inSameDayAs: s) ? 1.0 : 0.3
                            }())
                            AreaMark(
                                x: .value("Date", workoutSet.workout?.date ?? .now, unit: .day),
                                y: .value("Max set volume on day", convertWeightForDisplayingDecimal(workoutSet.volume(for: exercise)))
                            )
                            .interpolationMethod(.monotone)
                            .foregroundStyle(Gradient(colors: [
                                exerciseMuscleGroupColor.opacity(0.5),
                                exerciseMuscleGroupColor.opacity(0.2),
                                exerciseMuscleGroupColor.opacity(0.05),
                            ]))
                            .opacity(selectedDate == nil ? 1.0 : 0.0)
                        }
                        if selectedDate == nil, let lastSet = allDailyMaxSets.last, let lastDate = lastSet.workout?.date, !Calendar.current.isDateInToday(lastDate) {
                            let setVolumeDisplayed = convertWeightForDisplayingDecimal(lastSet.volume(for: exercise))
                            RuleMark(
                                xStart: .value("Start", lastDate),
                                xEnd: .value("End", Date()),
                                y: .value("Max set volume on day", setVolumeDisplayed)
                            )
                            .foregroundStyle(exerciseMuscleGroupColor.opacity(0.45))
                            .lineStyle(
                                StrokeStyle(
                                    lineWidth: 5,
                                    lineCap: .round,
                                    dash: [5, 10]
                                )
                            )
                        }
                    }
                    .chartXScale(domain: chartRange.xDomain(firstDataDate: firstDataDate))
                    .chartYScale(domain: 0 ... chartYScaleMax(maxYValue: allTimeSetVolumePR))
                    .chartScrollableAxes(.horizontal)
                    .chartScrollPosition(x: $chartScrollPosition)
                    .chartScrollTargetBehavior(
                        .valueAligned(matching: chartRange.scrollSnapComponents)
                    )
                    .chartXSelection(value: $selectedDate)
                    .chartXVisibleDomain(length: visibleChartDomainInSeconds)
                    .chartXAxis {
                        let axisStride = chartRange.axisStride(firstDataDate: firstDataDate)
                        AxisMarks(
                            position: .bottom,
                            values: .stride(by: axisStride.component, count: axisStride.count)
                        ) { value in
                            if let date = value.as(Date.self) {
                                AxisGridLine()
                                    .foregroundStyle(Color.gray.opacity(0.5))
                                AxisValueLabel(chartRange.axisLabel(for: date, firstDataDate: firstDataDate))
                                    .foregroundStyle(chartRange.isCurrentAxisMark(date, firstDataDate: firstDataDate) ? Color.primary : .secondary)
                                    .font(.caption.weight(.bold))
                            }
                        }
                    }
                    .chartYAxis {
                        let chartYScaleMax = chartYScaleMax(maxYValue: allTimeSetVolumePR)
                        AxisMarks(values: [0, chartYScaleMax / 2, chartYScaleMax])
                    }
                    .emptyPlaceholder(allDailyMaxSets) {
                        Text(NSLocalizedString("noData", comment: ""))
                    }
                    .frame(height: 300)
                    .padding(.leading)
                    .padding(.trailing, 5)
                }

                // MARK: - About Section
                AboutSection(
                    metricTitle: NSLocalizedString("setVolume", comment: ""),
                    text: NSLocalizedString("setVolumeInfo", comment: "")
                )
                .padding(.horizontal)
            }
            .padding(.top)
            .padding(.bottom, SCROLLVIEW_BOTTOM_PADDING)
        }
        .isBlockedWithoutPro()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack {
                    Text("\(NSLocalizedString("setVolume", comment: ""))")
                        .font(.headline)
                    Text(exercise.displayName)
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }
            }
        }
        .onAppear {
            chartScrollPosition = chartRange.initialScrollPosition(firstDataDate: firstDataDate)
        }
        .onChange(of: chartRange) {
            // Re-initialize scroll position when switching ranges to avoid desync with visible window
            chartScrollPosition = chartRange.initialScrollPosition(firstDataDate: firstDataDate)
        }
    }

    private static func dailyMaxSetVolumeSets(in workoutSets: [WorkoutSet], for exercise: Exercise) -> [WorkoutSet] {
        let groupedSets = Dictionary(grouping: workoutSets) {
            Calendar.current.startOfDay(for: $0.workout?.date ?? .now)
        }.sorted { $0.key < $1.key }
            .map { $0.1 }
        let maxSetsPerDay = groupedSets
            .compactMap { setsPerDay -> WorkoutSet? in
                return setsPerDay.max(by: { $0.volume(for: exercise) < $1.volume(for: exercise) })
            }
            .filter { $0.volume(for: exercise) > 0 }
        return maxSetsPerDay
    }

    private var visibleChartDomainInSeconds: Int {
        chartRange.visibleDomainSeconds(firstDataDate: firstDataDate)
    }


    private var exerciseMuscleGroupColor: Color {
        exercise.muscleGroup?.color ?? Color.accentColor
    }




    private var allTimeSetVolumePR: Int {
        convertWeightForDisplaying(
            dailyMaxSets
                .map {
                    $0.volume(for: exercise)
                }
                .max() ?? 0
        )
    }

    /// The header's left value and the comparison baseline: the best single-set volume in the visible
    /// window *other than* the current best, falling back to the most recent day's best before the
    /// window when it holds no other value (see `exerciseOtherBestBaseline`).
    private func bestSetVolumeInVisibleWindow() -> Int? {
        exerciseOtherBestBaseline(
            sets: dailyMaxSets,
            windowStart: chartScrollPosition,
            windowEnd: visibleEndDate,
            currentBestDay: bestAnchor?.date
        ) { $0.volume(for: exercise) }
    }

    /// Set volume has no practical upper bound, so unlike the weight and e1RM screens (which pick
    /// from a fixed list of axis caps) the cap is the PR rounded up to a clean half-magnitude step
    /// — keeping the mid axis mark (cap / 2) a round number too.
    private func chartYScaleMax(maxYValue: Int) -> Int {
        guard maxYValue > 0 else { return 10 }
        let magnitude = pow(10.0, floor(log10(Double(maxYValue))))
        let step = magnitude / 2
        return Int((Double(maxYValue) / step).rounded(.up) * step)
    }

    /// The fixed right-hand anchor of the header scoreboard, independent of scroll: the current best
    /// (highest single-set volume in the last four weeks) and the day it was reached. When the
    /// current-best window is empty (untrained for over a month) it falls back to the "last best" —
    /// the best on the most recent session — which flips the label to "Last Best" and drops the pill.
    private var bestAnchor: (value: Int, date: Date?, isLapsed: Bool)? {
        if let best = exercise.currentBestSetVolumeSet(in: workoutSets) {
            return (best.volume(for: exercise), best.workout?.date, false)
        }
        if let last = exercise.lastBestSetVolumeSet(in: workoutSets) {
            return (last.volume(for: exercise), last.workout?.date, true)
        }
        return nil
    }

    /// The header pill: the current best measured against the best in the shown window. Nil when
    /// either side is empty, so the pill drops out only when there is genuinely nothing to compare.
    private func headerTrendPercentage(visibleBest: Int?) -> Double? {
        guard let current = bestAnchor?.value, current > 0,
              let visible = visibleBest, visible > 0 else { return nil }
        return (Double(current) - Double(visible)) / Double(visible) * 100
    }

    // MARK: - Selection helpers

    private var visibleEndDate: Date {
        Calendar.current.date(byAdding: .second, value: visibleChartDomainInSeconds, to: chartScrollPosition)!
    }

    private func nearestSet(to date: Date?, in sets: [WorkoutSet]) -> WorkoutSet? {
        let visibleSets = sets.filter {
            guard let d = $0.workout?.date else { return false }
            return d >= chartScrollPosition && d <= visibleEndDate
        }
        let candidates = visibleSets.isEmpty ? sets : visibleSets
        guard !candidates.isEmpty else { return nil }
        guard let target = date else { return nil }
        return candidates.min { a, b in
            let ad = a.workout?.date ?? .distantPast
            let bd = b.workout?.date ?? .distantPast
            return abs(ad.timeIntervalSince(target)) < abs(bd.timeIntervalSince(target))
        }
    }

}

private struct PreviewWrapperView: View {
    @EnvironmentObject private var database: Database

    var body: some View {
        let exercise = database.getExercises().first!
        NavigationView {
            ExerciseSetVolumeScreen(exercise: exercise, workoutSets: exercise.sets)
        }
    }
}

struct ExerciseSetVolumeScreen_Previews: PreviewProvider {
    static var previews: some View {
        PreviewWrapperView()
            .previewEnvironmentObjects()
    }
}
