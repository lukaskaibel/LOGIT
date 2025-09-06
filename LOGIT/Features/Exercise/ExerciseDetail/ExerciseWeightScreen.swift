//
//  ExerciseWeightScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 12.11.24.
//

import Charts
import SwiftUI

struct ExerciseWeightScreen: View {
    private enum ChartGranularity {
        case month, year
    }
    
    private let yAxisMaxValuesKG = [10, 25, 50, 100, 150, 200, 300, 400, 500, 600, 700, 800, 900, 1000]
    private let yAxisMaxValuesLBS = [25, 55, 110, 225, 335, 445, 665, 885, 1105, 1325, 1545, 1765, 1985, 2205]

    let exercise: Exercise
    let workoutSets: [WorkoutSet]

    @State private var chartGranularity: ChartGranularity = .month
    @State private var isShowingCurrentBestInfo = false
    @State private var chartScrollPosition: Date = .now

    var body: some View {
        let allDailyMaxSets = allDailyMaxWeightSets(in: workoutSets)
        let bestVisibleWeight = bestWeightInGranularity(workoutSets)
        VStack {
            Picker("Select Chart Granularity", selection: $chartGranularity) {
                Text(NSLocalizedString("month", comment: ""))
                    .tag(ChartGranularity.month)
                Text(NSLocalizedString("year", comment: ""))
                    .tag(ChartGranularity.year)
            }
            .pickerStyle(.segmented)
            .padding(.vertical)
            .padding(.horizontal)
            VStack(alignment: .leading) {
                Text(NSLocalizedString("monthlyBest", comment: ""))
                    .font(.footnote)
                    .fontWeight(.medium)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                UnitView(
                    value: "\(bestVisibleWeight != nil ? String(convertWeightForDisplaying(bestVisibleWeight!)) : "––")",
                    unit: WeightUnit.used.rawValue
                )
                .foregroundStyle(exerciseMuscleGroupColor.gradient)
                Text(chartHeaderTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            Chart {
                if let firstEntry = workoutSets.last {
                    LineMark(
                        x: .value("Date", Date.distantPast, unit: .day),
                        y: .value("Max repetitions on day", convertWeightForDisplaying(firstEntry.maximum(.weight, for: exercise)))
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(exerciseMuscleGroupColor.gradient)
                    .lineStyle(StrokeStyle(lineWidth: 5))
                    AreaMark(
                        x: .value("Date", Date.distantPast, unit: .day),
                        y: .value("Max repetitions on day", convertWeightForDisplaying(firstEntry.maximum(.weight, for: exercise)))
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Gradient(colors: [
                        exerciseMuscleGroupColor.opacity(0.5),
                        exerciseMuscleGroupColor.opacity(0.2),
                        exerciseMuscleGroupColor.opacity(0.05),
                    ]))
                }
                ForEach(allDailyMaxSets) { workoutSet in
                    LineMark(
                        x: .value("Date", workoutSet.workout?.date ?? .now, unit: .day),
                        y: .value("Max weight on day", convertWeightForDisplaying(workoutSet.maximum(.weight, for: exercise)))
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(exerciseMuscleGroupColor.gradient)
                    .lineStyle(StrokeStyle(lineWidth: 5))
                    .symbol {
                        Circle()
                            .frame(width: 10, height: 10)
                            .foregroundStyle(exerciseMuscleGroupColor.gradient)
                            .overlay {
                                Circle()
                                    .frame(width: 4, height: 4)
                                    .foregroundStyle(Color.black)
                            }
                    }
                    AreaMark(
                        x: .value("Date", workoutSet.workout?.date ?? .now, unit: .day),
                        y: .value("Max weight on day", convertWeightForDisplaying(workoutSet.maximum(.weight, for: exercise)))
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Gradient(colors: [
                        exerciseMuscleGroupColor.opacity(0.5),
                        exerciseMuscleGroupColor.opacity(0.2),
                        exerciseMuscleGroupColor.opacity(0.05),
                    ]))
                }
                if let lastSet = allDailyMaxSets.last, let lastDate = lastSet.workout?.date, !Calendar.current.isDateInToday(lastDate) {
                    let weightDisplayed = convertWeightForDisplaying(lastSet.maximum(.weight, for: exercise))
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
            .chartXScale(domain: xDomain(for: workoutSets))
            .chartYScale(domain: 0 ... chartYScaleMax(maxYValue: allTimeWeightPR(in: workoutSets)))
            .chartScrollableAxes(.horizontal)
            .chartScrollPosition(x: $chartScrollPosition)
            .chartScrollTargetBehavior(
                .valueAligned(
                    matching: chartGranularity == .month ? DateComponents(weekday: 2) : DateComponents(month: 1, day: 1)
                )
            )
            .chartXVisibleDomain(length: visibleChartDomainInSeconds)
            .chartXAxis {
                AxisMarks(
                    position: .bottom,
                    values: .stride(by: chartGranularity == .month ? .weekOfYear : .month)
                ) { value in
                    if let date = value.as(Date.self) {
                        AxisGridLine()
                            .foregroundStyle(Color.gray.opacity(0.5))
                        AxisValueLabel(xAxisDateString(for: date))
                            .foregroundStyle(isDateNow(date, for: chartGranularity) ? Color.primary : .secondary)
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
            Spacer()
        }
        .isBlockedWithoutPro()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack {
                    Text("\(NSLocalizedString("weight", comment: ""))")
                        .font(.headline)
                    Text(exercise.name ?? "")
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }
            }
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

    private var visibleChartDomainInSeconds: Int {
        3600 * 24 * (chartGranularity == .month ? 35 : 365)
    }

    private func xDomain(for workoutSets: [WorkoutSet]) -> some ScaleDomain {
        let maxStartDate = Calendar.current.date(
            byAdding: chartGranularity == .month ? .month : .year,
            value: -1,
            to: .now
        )!
        let endDate = chartGranularity == .month ? Date.now.endOfWeek : Date.now.endOfYear
        guard let firstSetDate = allDailyMaxWeightSets(in: workoutSets).first?.workout?.date, firstSetDate < maxStartDate
        else { return maxStartDate ... endDate }
        let startDate = chartGranularity == .month ? firstSetDate.startOfMonth : firstSetDate.startOfYear
        return startDate ... endDate
    }

    private var exerciseMuscleGroupColor: Color {
        exercise.muscleGroup?.color ?? Color.accentColor
    }

    private func xAxisDateString(for date: Date) -> String {
        switch chartGranularity {
        case .month:
            return date.formatted(.dateTime.day().month(.defaultDigits))
        case .year:
            return date.formatted(Date.FormatStyle().month(.narrow))
        }
    }

    private func isDateNow(_ date: Date, for _: ChartGranularity) -> Bool {
        switch chartGranularity {
        case .month:
            return Calendar.current.isDate(date, equalTo: .now, toGranularity: [.weekOfYear, .yearForWeekOfYear])
        case .year:
            return Calendar.current.isDate(date, equalTo: .now, toGranularity: [.month, .year])
        }
    }

    private var chartHeaderTitle: String {
        let endDate = Calendar.current.date(byAdding: .second, value: visibleChartDomainInSeconds, to: chartScrollPosition)!
        switch chartGranularity {
        case .month:
            return "\(chartScrollPosition.isInCurrentYear ? chartScrollPosition.formatted(.dateTime.day().month()) : chartScrollPosition.formatted(.dateTime.day().month().year())) - \(endDate.isInCurrentYear ? endDate.formatted(.dateTime.day().month()) : endDate.formatted(.dateTime.day().month().year()))"
        case .year:
            return "\(chartScrollPosition.formatted(.dateTime.month().year())) - \(endDate.formatted(.dateTime.month().year()))"
        }
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

    private func bestWeightInGranularity(_ workoutSets: [WorkoutSet]) -> Int? {
        let endDate = Calendar.current.date(byAdding: .second, value: visibleChartDomainInSeconds, to: chartScrollPosition)!
        let setsInTimeFrame = workoutSets.filter { $0.workout?.date ?? .distantPast >= chartScrollPosition && $0.workout?.date ?? .distantFuture <= endDate }

        guard !setsInTimeFrame.isEmpty else {
            return workoutSets.first?.maximum(.weight, for: exercise)
        }

        return setsInTimeFrame
            .map { $0.maximum(.weight, for: exercise) }
            .max()
    }
    
    private func chartYScaleMax(maxYValue: Int) -> Int {
        let values = WeightUnit.used == .kg ? yAxisMaxValuesKG : yAxisMaxValuesLBS
        let nextBiggerYAxisMaxValue = values.filter { $0 > maxYValue }.min()
        return nextBiggerYAxisMaxValue ?? maxYValue
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
