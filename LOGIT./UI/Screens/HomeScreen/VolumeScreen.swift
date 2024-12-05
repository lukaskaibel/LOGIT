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
    
    @EnvironmentObject private var workoutSetRepository: WorkoutSetRepository
    
    @State private var chartGranularity: ChartGranularity = .month
    @State private var selectedMuscleGroup: MuscleGroup?
    
    var body: some View {
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
                                value: "\(volumeInThisChartGranularity)",
                                unit: WeightUnit.used.rawValue
                            )
                            .foregroundStyle(selectedMuscleGroup.color.gradient)
                        } else {
                            UnitView(
                                value: "\(volumeInThisChartGranularity)",
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
                        ForEach(setsGroupedByGranularity, id: \.date) { data in
                            if let selectedMuscleGroup = selectedMuscleGroup {
                                BarMark(
                                    x: .value("Day", data.date, unit: chartGranularity == .month ? .weekOfYear : .month),
                                    y: .value("Volume", volume(for: data.workoutSets, muscleGroup: selectedMuscleGroup)),
                                    width: .ratio(0.5)
                                )
                                .foregroundStyle(selectedMuscleGroup.color.gradient)
                            }
                            let volume: Int = volume(for: data.workoutSets) - (selectedMuscleGroup != nil ? volume(for: data.workoutSets, muscleGroup: selectedMuscleGroup) : 0)
                            BarMark(
                                x: .value("Day", data.date, unit: chartGranularity == .month ? .weekOfYear : .month),
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
                    .chartYScale(domain: [0, maxTotalVolumePerPeriod])
                    .frame(height: 300)
                }
                .padding(.horizontal)
                MuscleGroupSelector(selectedMuscleGroup: $selectedMuscleGroup)
                    .padding(.top)
            }
            .padding(.top)
        }
        .navigationBarTitle(NSLocalizedString("volume", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private var workoutSetsInSelectedGranularity: [WorkoutSet] {
        workoutSetRepository.getWorkoutSets(
            for: chartGranularity == .month ? [.month, .year] : [.year],
            including: .now
        )
    }
    
    private var volumeInThisChartGranularity: Int {
        if let selectedMuscleGroup = selectedMuscleGroup {
            volume(for: workoutSetsInSelectedGranularity, muscleGroup: selectedMuscleGroup)
        } else {
            volume(for: workoutSetsInSelectedGranularity)
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
    
    private var setsGroupedByGranularity: [(date: Date, workoutSets: [WorkoutSet])] {
        var result = [(date: Date, workoutSets: [WorkoutSet])]()
        let allPeriods = allPeriodsInSelectedGranularity
        var groupedByPeriod: [Date: [WorkoutSet]] = [:]

        workoutSetsInSelectedGranularity
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
    
    private var maxTotalVolumePerPeriod: Int {
        setsGroupedByGranularity.map { totalVolume(for: $0.workoutSets) }.max() ?? 0
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
