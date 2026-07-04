//
//  ExerciseWeightScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 12.11.24.
//

import Charts
import SwiftUI

struct ExerciseWeightScreen: View {
    private let yAxisMaxValuesKG = [10, 25, 50, 100, 150, 200, 300, 400, 500, 600, 700, 800, 900, 1000]
    private let yAxisMaxValuesLBS = [25, 55, 110, 225, 335, 445, 665, 885, 1105, 1325, 1545, 1765, 1985, 2205]

    let exercise: Exercise
    let workoutSets: [WorkoutSet]

    @State private var chartRange: ChartRange = .threeMonths
    @State private var chartScrollPosition: Date = .now
    @State private var selectedDate: Date?

    var body: some View {
        let allDailyMaxSets = allDailyMaxWeightSets(in: workoutSets)
        // Determine the snapped selected set only when a selection exists; snap to the nearest datapoint (prefer visible)
        let snappedSelectedSet: WorkoutSet? = selectedDate != nil ? nearestSet(to: selectedDate, in: allDailyMaxSets) : nil
        let bestVisibleWeight = bestWeightInVisibleWindow(workoutSets)
        ScrollView {
            VStack(spacing: SECTION_SPACING) {
                VStack {
                    RangePicker(selection: $chartRange)
            .padding(.vertical)
            .padding(.horizontal)
            MetricComparisonView(
                leading: .init(
                    label: NSLocalizedString("previousBest", comment: ""),
                    value: bestVisibleWeight.map(formatWeightForDisplay) ?? "––",
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
                percentChange: bestAnchor?.isLapsed == true ? nil : headerTrendPercentage(visibleBest: bestVisibleWeight),
                positiveColor: exerciseMuscleGroupColor,
                explanation: NSLocalizedString("currentBestComparisonInfo", comment: "")
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            Chart {
                // Show selection only when a selection exists, snapped to the nearest datapoint
                if selectedDate != nil, let selectedSet = snappedSelectedSet, let sDate = selectedSet.workout?.date {
                    let snapped = Calendar.current.startOfDay(for: sDate)
                    let valueDisplayed = formatWeightForDisplay(selectedSet.maximum(.weight, for: exercise))
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
                        y: .value("Max repetitions on day", convertWeightForDisplayingDecimal(firstEntry.maximum(.weight, for: exercise)))
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(exerciseMuscleGroupColor.gradient)
                    .lineStyle(StrokeStyle(lineWidth: 5))
                    .opacity(snappedSelectedSet == nil ? 1.0 : 0.3)
                    AreaMark(
                        x: .value("Date", Date.distantPast, unit: .day),
                        y: .value("Max repetitions on day", convertWeightForDisplayingDecimal(firstEntry.maximum(.weight, for: exercise)))
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
                        y: .value("Max weight on day", convertWeightForDisplayingDecimal(workoutSet.maximum(.weight, for: exercise)))
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
                        y: .value("Max weight on day", convertWeightForDisplayingDecimal(workoutSet.maximum(.weight, for: exercise)))
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
                    let weightDisplayed = convertWeightForDisplayingDecimal(lastSet.maximum(.weight, for: exercise))
                    RuleMark(
                        xStart: .value("Start", lastDate),
                        xEnd: .value("End", Date()),
                        y: .value("Max weight on day", weightDisplayed)
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
            .chartYScale(domain: 0 ... chartYScaleMax(maxYValue: allTimeWeightPR(in: workoutSets)))
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
                let chartYScaleMax = chartYScaleMax(maxYValue: allTimeWeightPR(in: workoutSets))
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
                    metricTitle: NSLocalizedString("weight", comment: ""),
                    text: NSLocalizedString("weightInfo", comment: "")
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
                    Text("\(NSLocalizedString("weight", comment: ""))")
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

    private func allDailyMaxWeightSets(in workoutSets: [WorkoutSet]) -> [WorkoutSet] {
        let groupedSets = Dictionary(grouping: workoutSets) {
            Calendar.current.startOfDay(for: $0.workout?.date ?? .now)
        }.sorted { $0.key < $1.key }
            .map { $0.1 }
        let maxSetsPerDay = groupedSets
            .compactMap { setsPerDay -> WorkoutSet? in
                return setsPerDay.max(by: { $0.maximum(.weight, for: exercise) < $1.maximum(.weight, for: exercise) })
            }
            .filter { $0.maximum(.weight, for: exercise) > 0 }
        return maxSetsPerDay
    }

    /// Earliest day with a recorded weight — anchors the scrollable domain and the All range.
    private var firstDataDate: Date? {
        allDailyMaxWeightSets(in: workoutSets).first?.workout?.date
    }

    private var visibleChartDomainInSeconds: Int {
        chartRange.visibleDomainSeconds(firstDataDate: firstDataDate)
    }

    private var exerciseMuscleGroupColor: Color {
        exercise.muscleGroup?.color ?? Color.accentColor
    }

    private func allTimeWeightPR(in workoutSets: [WorkoutSet]) -> Int {
        convertWeightForDisplaying(
            workoutSets
                .map {
                    $0.maximum(.weight, for: exercise)
                }
                .max() ?? 0
        )
    }

    /// The header's left value and the comparison baseline: the best max-weight in the visible window
    /// *other than* the current best, so the pill measures the current best against the rest of the
    /// shown period rather than itself when the peak is in view. Falls back to the most recent day's
    /// best before the window when it holds no other value (see `exerciseOtherBestBaseline`).
    private func bestWeightInVisibleWindow(_ workoutSets: [WorkoutSet]) -> Int? {
        exerciseOtherBestBaseline(
            sets: workoutSets,
            windowStart: chartScrollPosition,
            windowEnd: visibleEndDate,
            currentBestDay: bestAnchor?.date
        ) { $0.maximum(.weight, for: exercise) }
    }

    private func chartYScaleMax(maxYValue: Int) -> Int {
        let values = WeightUnit.used == .kg ? yAxisMaxValuesKG : yAxisMaxValuesLBS
        let nextBiggerYAxisMaxValue = values.filter { $0 > maxYValue }.min()
        return nextBiggerYAxisMaxValue ?? maxYValue
    }

    /// The fixed right-hand anchor of the header scoreboard, independent of scroll: the current best
    /// (highest max-weight in the last four weeks) and the day it was reached. When the current-best
    /// window is empty (untrained for over a month) it falls back to the "last best" — the best on
    /// the most recent session — which flips the label to "Last Best" and drops the comparison pill.
    private var bestAnchor: (value: Int, date: Date?, isLapsed: Bool)? {
        if let best = exercise.currentBestSet(for: .weight, in: workoutSets) {
            return (best.maximum(.weight, for: exercise), best.workout?.date, false)
        }
        if let last = exercise.lastBestSet(for: .weight, in: workoutSets) {
            return (last.maximum(.weight, for: exercise), last.workout?.date, true)
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
            ExerciseWeightScreen(exercise: exercise, workoutSets: exercise.sets)
        }
    }
}

struct PersonalBestScreen_Previews: PreviewProvider {
    static var previews: some View {
        PreviewWrapperView()
            .previewEnvironmentObjects()
    }
}
