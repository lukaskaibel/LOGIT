//
//  VolumeScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 03.12.24.
//

import Charts
import SwiftUI

struct VolumeScreen: View {
    
    private enum ChartGranularity {
        case month, year
    }
        
    @State private var chartGranularity: ChartGranularity = .month
    @State private var selectedMuscleGroup: MuscleGroup?
    
    var body: some View {
        FetchRequestWrapper(
            Workout.self,
            sortDescriptors: [SortDescriptor(\.date, order: .reverse)],
            predicate: WorkoutPredicateFactory.getWorkouts(
                from: Calendar.current.date(
                    byAdding: chartGranularity == .month ? .month : .year,
                    value: -1,
                    to: .now
                ),
                to: .now
            )
        ) { workouts in
            let workoutSets = workouts.flatMap({ $0.sets })
            ScrollView {
                VStack(spacing: SECTION_SPACING) {
                    VStack {
                        Picker("Select Chart Granularity", selection: $chartGranularity) {
                            Text(NSLocalizedString("month", comment: ""))
                                .tag(ChartGranularity.month)
                            Text(NSLocalizedString("year", comment: ""))
                                .tag(ChartGranularity.year)
                        }
                        .pickerStyle(.segmented)
                        .padding(.bottom)
                        VStack(alignment: .leading) {
                            Text(NSLocalizedString("total", comment: ""))
                                .font(.footnote)
                                .fontWeight(.semibold)
                                .textCase(.uppercase)
                                .foregroundStyle(.secondary)
                            if let selectedMuscleGroup = selectedMuscleGroup {
                                UnitView(
                                    value: "\(volumeInThisChartGranularity(workoutSets))",
                                    unit: WeightUnit.used.rawValue
                                )
                                .foregroundStyle(selectedMuscleGroup.color.gradient)
                            } else {
                                UnitView(
                                    value: "\(volumeInThisChartGranularity(workoutSets))",
                                    unit: WeightUnit.used.rawValue
                                )
                                .foregroundStyle(Color.accentColor.gradient)
                            }
                            Text("\(NSLocalizedString("this", comment: "")) \(NSLocalizedString(chartGranularity == .month ? "month" : "year", comment: ""))")
                                .fontWeight(.bold)
                                .fontDesign(.rounded)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Chart {
                            ForEach(setsGroupedByGranularity(workoutSets), id: \.0) { key, workoutSets in
                                if let selectedMuscleGroup = selectedMuscleGroup {
                                    BarMark(
                                        x: .value("Day", key, unit: chartGranularity == .month ? .weekOfYear : .month),
                                        y: .value("Volume", volume(for: workoutSets, muscleGroup: selectedMuscleGroup)),
                                        width: .ratio(0.5)
                                    )
                                    .foregroundStyle(selectedMuscleGroup.color.gradient)
                                }
                                let volume: Int = volume(for: workoutSets) - (selectedMuscleGroup != nil ? volume(for: workoutSets, muscleGroup: selectedMuscleGroup) : 0)
                                BarMark(
                                    x: .value("Day", key, unit: chartGranularity == .month ? .weekOfYear : .month),
                                    y: .value("Volume", volume),
                                    width: .ratio(0.5)
                                )
                                .foregroundStyle((selectedMuscleGroup == nil ? Color.accentColor : Color.placeholder).gradient)
                            }
                        }
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
                        .chartYScale(domain: [0, maxTotalVolume(setsGroupedByGranularity(workoutSets).map({ $0.1 }))])
                        .frame(height: 300)
                    }
                    .padding(.horizontal)
                    MuscleGroupSelector(selectedMuscleGroup: $selectedMuscleGroup)
                        .padding(.top)
                }
                .padding(.top)
            }
            .isBlockedWithoutPro()
            .navigationBarTitle(NSLocalizedString("volume", comment: ""))
            .navigationBarTitleDisplayMode(.inline)

        }
    }
    
    private func volumeInThisChartGranularity(_ workoutSets: [WorkoutSet]) -> Int {
        if let selectedMuscleGroup = selectedMuscleGroup {
            volume(for: workoutSets, muscleGroup: selectedMuscleGroup)
        } else {
            volume(for: workoutSets)
        }
    }
    
    private func volume(for sets: [WorkoutSet], muscleGroup: MuscleGroup? = nil) -> Int {
        if let muscleGroup = muscleGroup {
            return convertWeightForDisplaying(getVolume(of: sets, for: muscleGroup))
        } else {
            return convertWeightForDisplaying(getVolume(of: sets))
        }
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
    
    private func getPeriodStart(for date: Date, granularity: ChartGranularity) -> Date? {
        let calendar = Calendar.current
        switch granularity {
        case .month:
            return calendar.dateInterval(of: .weekOfYear, for: date)?.start
        case .year:
            return calendar.dateInterval(of: .month, for: date)?.start
        }
    }
    
    private func setsGroupedByGranularity(_ workoutSets: [WorkoutSet]) -> [(date: Date, workoutSets: [WorkoutSet])] {
        var result = [(date: Date, workoutSets: [WorkoutSet])]()
        let allPeriods = allPeriodsInSelectedGranularity
        var groupedByPeriod: [Date: [WorkoutSet]] = [:]

        workoutSets
            .forEach { workoutSet in
                if let setDate = workoutSet.workout?.date,
                   let periodStart = getPeriodStart(for: setDate, granularity: chartGranularity) {
                    groupedByPeriod[periodStart, default: []].append(workoutSet)
                }
            }

        allPeriods.forEach { periodStart in
            let setsForPeriod = groupedByPeriod[periodStart] ?? []
            result.append((date: periodStart, workoutSets: setsForPeriod))
        }

        return result
    }
    
    private var allPeriodsInSelectedGranularity: [Date] {
        let calendar = Calendar.current
        let today = Date()
        var periods = [Date]()

        switch chartGranularity {
        case .month:
            guard let monthInterval = calendar.dateInterval(of: .month, for: today),
                  let firstWeekStart = getPeriodStart(for: monthInterval.start, granularity: .month) else { return [] }
            var periodStart = firstWeekStart
            while periodStart < monthInterval.end {
                periods.append(periodStart)
                guard let nextPeriodStart = calendar.date(byAdding: .weekOfYear, value: 1, to: periodStart) else { break }
                periodStart = nextPeriodStart
            }
        case .year:
            guard let yearStart = calendar.dateInterval(of: .year, for: today)?.start else { return [] }
            periods = (0..<12).compactMap { calendar.date(byAdding: .month, value: $0, to: yearStart) }
        }
        return periods
    }
    
    private func maxTotalVolume(_ groupedWorkoutSets: [[WorkoutSet]]) -> Int {
        groupedWorkoutSets.map { totalVolume(for: $0) }.max() ?? 0
    }

    private func totalVolume(for sets: [WorkoutSet]) -> Int {
        return convertWeightForDisplaying(getVolume(of: sets))
    }


}

private struct PreviewWrapperView: View {
    @EnvironmentObject private var database: Database
    
    var body: some View {
        NavigationView {
            VolumeScreen()
        }
    }
}

struct VolumeScreen_Previews: PreviewProvider {
    static var previews: some View {
        PreviewWrapperView()
            .previewEnvironmentObjects()
    }
}
