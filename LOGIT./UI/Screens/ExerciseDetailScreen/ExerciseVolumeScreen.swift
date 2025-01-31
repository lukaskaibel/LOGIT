//
//  ExerciseVolumeScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 03.12.24.
//

import Charts
import SwiftUI

struct ExerciseVolumeScreen: View {
    
    private enum ChartGranularity {
        case month, year
    }
        
    @StateObject var exercise: Exercise
    
    @State private var chartGranularity: ChartGranularity = .month
    @State private var chartScrollPosition: Date = .now
    
    var body: some View {
        let workoutSets = exercise.sets
        let groupedWorkoutSets = Dictionary(grouping: workoutSets) { $0.workout?.date?.startOfWeek ?? .now }.sorted { $0.key < $1.key }
        ScrollView {
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
                    Text(NSLocalizedString("total", comment: ""))
                        .font(.footnote)
                        .fontWeight(.semibold)
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                    UnitView(
                        value: "\(totalVolumeInTimeFrame(workoutSets))",
                        unit: WeightUnit.used.rawValue
                    )
                    .foregroundStyle((exercise.muscleGroup?.color ?? .label).gradient)
                    Text("\(visibleDomainDescription)")
                        .fontWeight(.bold)
                        .fontDesign(.rounded)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Chart {
                    ForEach(groupedWorkoutSets, id:\.0) { key, workoutSets in
                        BarMark(
                            x: .value("Day", workoutSets.first?.workout?.date ?? .now, unit: .weekOfYear),
                            y: .value("Volume", volume(for: workoutSets)),
                            width: .ratio(0.5)
                        )
                        .foregroundStyle((exercise.muscleGroup?.color ?? Color.label).gradient)
                    }
                }
                .chartXScale(domain: xDomain(for: groupedWorkoutSets.map({ $0.1 })))
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
                }
                .emptyPlaceholder(groupedWorkoutSets) {
                    Text(NSLocalizedString("noData", comment: ""))
                }
                .frame(height: 300)
                
            }
            .padding(.horizontal)
            .padding(.top)
        }
        .isBlockedWithoutPro()
        .onAppear {
            let firstDayOfNextWeek = Calendar.current.date(byAdding: .day, value: 1, to: .now.endOfWeek)!
            chartScrollPosition = Calendar.current.date(byAdding: .second, value: -visibleChartDomainInSeconds, to: firstDayOfNextWeek)!
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack {
                    Text("\(NSLocalizedString("volume", comment: ""))")
                        .font(.headline)
                    Text(exercise.name ?? "")
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }
            }
            
        }
    }
    
    // MARK: - Private Methods
    
    private var visibleChartDomainInSeconds: Int {
        3600 * 24 * (chartGranularity == .month ? 35 : 365)
    }
    
    private func xDomain(for groupedWorkoutSets: [[WorkoutSet]]) -> some ScaleDomain {
        let maxStartDate = Calendar.current.date(
            byAdding: chartGranularity == .month ? .month : .year,
            value: -1,
            to: .now
        )!
        let endDate = chartGranularity == .month ? Date.now.endOfWeek : Date.now.endOfYear
        guard let firstSetDate = groupedWorkoutSets.first?.first?.workout?.date, firstSetDate < maxStartDate
        else { return maxStartDate...endDate }
        let startDate = chartGranularity == .month ? firstSetDate.startOfMonth : firstSetDate.startOfYear
        return startDate...endDate
    }
    
    private func totalVolumeInTimeFrame(_ workoutSets: [WorkoutSet]) -> Int {
        let endDate = Calendar.current.date(byAdding: .second, value: visibleChartDomainInSeconds, to: chartScrollPosition)!
        let setsInTimeFrame = workoutSets.filter { $0.workout?.date ?? .distantPast >= chartScrollPosition && $0.workout?.date ?? .distantFuture <= endDate }
        return volume(for: setsInTimeFrame)
    }
    
    private func volume(for sets: [WorkoutSet]) -> Int {
        convertWeightForDisplaying(getVolume(of: sets, for: exercise))
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
    
    private var visibleDomainDescription: String {
        let endDate = Calendar.current.date(byAdding: .second, value: visibleChartDomainInSeconds, to: chartScrollPosition)!
        switch chartGranularity {
        case .month:
            return "\(chartScrollPosition.formatted(.dateTime.day().month())) - \(endDate.formatted(.dateTime.day().month()))"
        case .year:
            return "\(chartScrollPosition.formatted(.dateTime.month().year())) - \(endDate.formatted(.dateTime.month().year()))"
        }
    }

}

private struct PreviewWrapperView: View {
    @EnvironmentObject private var database: Database
    
    var body: some View {
        NavigationView {
            ExerciseVolumeScreen(exercise: database.getExercises().first!)
        }
    }
}

struct ExerciseVolumeScreen_Previews: PreviewProvider {
    static var previews: some View {
        PreviewWrapperView()
            .previewEnvironmentObjects()
    }
}
