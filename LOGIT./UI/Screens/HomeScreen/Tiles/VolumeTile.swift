//
//  VolumeTile.swift
//  LOGIT
//
//  Created by Volker Kaibel on 06.10.24.
//

import Charts
import SwiftUI

struct VolumeTile: View {
    
    let workouts: [Workout]
        
    var body: some View {
        let workoutsLastMonth = workouts.filter({ $0.date ?? .distantPast >= Calendar.current.date(byAdding: .month, value: -1, to: .now)! && $0.date ?? .distantFuture <= .now })
        let workoutSets = workoutsLastMonth.flatMap({ $0.sets })
        VStack(spacing: 20) {
            HStack {
                VStack(alignment: .leading) {
                    Text(NSLocalizedString("volume", comment: ""))
                        .tileHeaderStyle()
                    
                }
                Spacer()
                NavigationChevron()
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                VStack(alignment: .leading) {
                    Text(NSLocalizedString("thisWeek", comment: ""))
                    let setsThisWeek = workoutSets.filter({ Calendar.current.isDate($0.workout?.date ?? .distantPast, equalTo: .now, toGranularity: [.weekOfYear, .year]) })
                    UnitView(
                        value: "\(convertWeightForDisplaying(getVolume(of: setsThisWeek)))",
                        unit: WeightUnit.used.rawValue,
                        configuration: .large
                    )
                    .foregroundStyle(Color.accentColor.gradient)
                }
                Spacer()
                Chart {
                    ForEach(setsGroupedByGranularity(workoutSets), id:\.0) { key, workoutSets in
                        let volume = convertWeightForDisplaying(getVolume(of: workoutSets))
                        BarMark(
                            x: .value("Weeks before now", key, unit: .weekOfYear),
                            y: .value("Volume in week", volume),
                            width: .ratio(0.5)
                        )
                        .foregroundStyle((Calendar.current.isDate(key, equalTo: .now, toGranularity: .weekOfYear) ? Color.accentColor : Color.fill).gradient)
                    }
                }
                .chartXAxis {}
                .chartYAxis {}
                .frame(width: 120, height: 80)
                .padding(.trailing)
            }
        }
        .padding(CELL_PADDING)
        .tileStyle()
    }
    
    private func getPeriodStart(for date: Date) -> Date? {
        let calendar = Calendar.current
        return calendar.dateInterval(of: .weekOfYear, for: date)?.start
    }
    
    private func setsGroupedByGranularity(_ workoutSets: [WorkoutSet]) -> [(date: Date, workoutSets: [WorkoutSet])] {
        var result = [(date: Date, workoutSets: [WorkoutSet])]()
        let allPeriods = last5Weeks
        var groupedByPeriod: [Date: [WorkoutSet]] = [:]

        workoutSets
            .forEach { workoutSet in
                if let setDate = workoutSet.workout?.date,
                   let periodStart = getPeriodStart(for: setDate) {
                    groupedByPeriod[periodStart, default: []].append(workoutSet)
                }
            }

        allPeriods.forEach { periodStart in
            let setsForPeriod = groupedByPeriod[periodStart] ?? []
            result.append((date: periodStart, workoutSets: setsForPeriod))
        }

        return result
    }
    
    private var last5Weeks: [Date] {
        let calendar = Calendar.current
        let today = Date()
        var periods = [Date]()
        
        guard let monthInterval = calendar.dateInterval(of: .month, for: today),
              let firstWeekStart = getPeriodStart(for: monthInterval.start) else { return [] }
        var periodStart = firstWeekStart
        while periodStart < monthInterval.end {
            periods.append(periodStart)
            guard let nextPeriodStart = calendar.date(byAdding: .weekOfYear, value: 1, to: periodStart) else { break }
            periodStart = nextPeriodStart
        }
        return periods
    }

}

#Preview {
    FetchRequestWrapper(Workout.self) { workouts in
        VolumeTile(workouts: workouts)
            .previewEnvironmentObjects()
            .padding()
    }
}
