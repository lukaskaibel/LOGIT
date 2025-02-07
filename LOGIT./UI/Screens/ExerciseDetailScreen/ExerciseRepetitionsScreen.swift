//
//  ExerciseRepetitionsScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 12.11.24.
//

import Charts
import SwiftUI

struct ExerciseRepetitionsScreen: View {
    
    private enum ChartGranularity {
        case month, year
    }
        
    @StateObject var exercise: Exercise
    
    @State private var chartGranularity: ChartGranularity = .month
    @State private var isShowingCurrentBestInfo = false
    @State private var chartScrollPosition: Date = .now
    
    var body: some View {
        let workoutSets = exercise.sets.sorted { $0.workout?.date ?? .now < $1.workout?.date ?? .now }
        let allDailyMaxRepsSets = allDailyMaxRepetitionsSets(in: workoutSets)
        let bestRepsInGranularity: Int? = bestRepetitionsInGranularity(in: workoutSets)
        VStack {
            Picker("Select Chart Granularity", selection: $chartGranularity) {
                Text(NSLocalizedString("month", comment: ""))
                    .tag(ChartGranularity.month)
                Text(NSLocalizedString("year", comment: ""))
                    .tag(ChartGranularity.year)
            }
            .pickerStyle(.segmented)
            .padding(.vertical)
            
            
            VStack(alignment: .leading) {
                Text("Monthly best")
                    .font(.footnote)
                    .fontWeight(.medium)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                UnitView(
                    value: "\(bestRepsInGranularity != nil ? String(bestRepsInGranularity!) : "––")",
                    unit: NSLocalizedString("rps", comment: "")
                )
                .foregroundStyle(exerciseMuscleGroupColor.gradient)
                Text(chartHeaderTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Chart {
                if let firstEntry = allDailyMaxRepsSets.first {
                    LineMark(
                        x: .value("Date", Date.distantPast, unit: .day),
                        y: .value("Max repetitions on day", firstEntry.maximum(.repetitions, for: exercise))
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(exerciseMuscleGroupColor.gradient)
                    .lineStyle(StrokeStyle(lineWidth: 5))
                    AreaMark(
                        x: .value("Date", Date.distantPast, unit: .day),
                        y: .value("Max repetitions on day", firstEntry.maximum(.repetitions, for: exercise))
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Gradient(colors: [
                        exerciseMuscleGroupColor.opacity(0.5),
                        exerciseMuscleGroupColor.opacity(0.2),
                        exerciseMuscleGroupColor.opacity(0.05)
                    ]))
                }
                ForEach(allDailyMaxRepsSets) { workoutSet in
                    LineMark(
                        x: .value("Date", workoutSet.workout?.date ?? .now, unit: .day),
                        y: .value("Max repetitions on day", workoutSet.maximum(.repetitions, for: exercise))
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
                        y: .value("Max repetitions on day", workoutSet.maximum(.repetitions, for: exercise))
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Gradient(colors: [
                        exerciseMuscleGroupColor.opacity(0.5),
                        exerciseMuscleGroupColor.opacity(0.2),
                        exerciseMuscleGroupColor.opacity(0.05)
                    ]))
                }
            }
            .chartXScale(domain: xDomain(for: workoutSets))
            .chartYScale(domain: 0...(Double(allTimeRepetitionsPR(in: workoutSets)) * 1.1))
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
                AxisMarks(values: .automatic(desiredCount: 4))
                if let currentBestRepetitions = bestRepsInGranularity {
                    AxisMarks(values: [currentBestRepetitions]) {
                        AxisValueLabel()
                            .foregroundStyle(exerciseMuscleGroupColor.gradient)
                            .font(.system(.caption, design: .rounded, weight: .bold))
                    }
                }
            }
            .emptyPlaceholder(allDailyMaxRepsSets) {
                Text(NSLocalizedString("noData", comment: ""))
            }
            .frame(height: 300)
            Spacer()
        }
        .isBlockedWithoutPro()
        .padding(.horizontal)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack {
                    Text("\(NSLocalizedString("repetitions", comment: ""))")
                        .font(.headline)
                    Text(exercise.name ?? "")
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }
            }
            
        }
    }
    
    // MARK: - Private Methods
    
    private func allDailyMaxRepetitionsSets(in workoutSets: [WorkoutSet]) -> [WorkoutSet] {
        let groupedSets = Dictionary(grouping: workoutSets) {
            Calendar.current.startOfDay(for: $0.workout?.date ?? .now)
        }.sorted { $0.key < $1.key }
            .map({ $0.1 })
        let maxSetsPerDay = groupedSets
            .compactMap { setsPerDay -> WorkoutSet? in
                return setsPerDay.max(by: { $0.maximum(.repetitions, for: exercise) < $1.maximum(.repetitions, for: exercise) })
            }
            .filter { $0.maximum(.repetitions, for: exercise) > 0 }
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
        guard let firstSetDate = allDailyMaxRepetitionsSets(in: workoutSets).first?.workout?.date, firstSetDate < maxStartDate
        else { return maxStartDate...endDate }
        let startDate = chartGranularity == .month ? firstSetDate.startOfMonth : firstSetDate.startOfYear
        return startDate...endDate
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
    
    private func isDateNow(_ date: Date, for granularity: ChartGranularity) -> Bool {
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
            return "\(chartScrollPosition.formatted(.dateTime.day().month())) - \(endDate.formatted(.dateTime.day().month()))"
        case .year:
            return "\(chartScrollPosition.formatted(.dateTime.month().year())) - \(endDate.formatted(.dateTime.month().year()))"
        }
    }
    
    private func allTimeRepetitionsPR(in workoutSets: [WorkoutSet]) -> Int {
        workoutSets
            .map {
                $0.maximum(.repetitions, for: exercise)
            }
            .max() ?? 0
    }
    
    private func bestRepetitionsInGranularity(in workoutSets: [WorkoutSet]) -> Int? {
        let endDate = Calendar.current.date(byAdding: .second, value: visibleChartDomainInSeconds, to: chartScrollPosition)!
        let setsInTimeFrame = workoutSets
            .filter {
                guard let date = $0.workout?.date else { return false }
                return date >= chartScrollPosition && date <= endDate
            }

        guard !setsInTimeFrame.isEmpty else {
            return workoutSets.first?.maximum(.repetitions, for: exercise)
        }
        
        return setsInTimeFrame
            .map({ $0.maximum(.repetitions, for: exercise) })
            .max()
    }
    
}

private struct PreviewWrapperView: View {
    @EnvironmentObject private var database: Database
    
    var body: some View {
        NavigationView {
            ExerciseRepetitionsScreen(exercise: database.getExercises().first!)
        }
    }
}

struct ExerciseRepetitionsScreen_Previews: PreviewProvider {
    static var previews: some View {
        PreviewWrapperView()
            .previewEnvironmentObjects()
    }
}
