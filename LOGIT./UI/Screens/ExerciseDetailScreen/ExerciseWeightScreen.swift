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
        case month, year, allTime
    }
    
    @EnvironmentObject private var workoutSetRepository: WorkoutSetRepository
    
    let exercise: Exercise
    
    @State private var chartGranularity: ChartGranularity = .month
    
    var body: some View {
        VStack {
//            Text(exercise.name ?? "")
//                .screenHeaderSecondaryStyle()
//                .foregroundStyle(exerciseMuscleGroupColor.gradient)
//                .frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                VStack(alignment: .leading) {
                    Text(NSLocalizedString("currentBest", comment: ""))
                    HStack(alignment: .lastTextBaseline, spacing: 0) {
                        Text("\(currentBestWeight != nil ? String(convertWeightForDisplaying(currentBestWeight!)) : "––")")
                            .font(.title)
                            .foregroundStyle((exercise.muscleGroup?.color ?? .label).gradient)
                        Text(WeightUnit.used.rawValue)
                            .textCase(.uppercase)
                            .foregroundStyle((exercise.muscleGroup?.color ?? .label).gradient)
                    }
                    .fontWeight(.bold)
                    .fontDesign(.rounded)
                    .foregroundStyle(exerciseMuscleGroupColor.gradient)
                }
                .frame(maxWidth: .infinity)
                VStack(alignment: .leading) {
                    Text(NSLocalizedString("personalBest", comment: ""))
                    HStack(alignment: .lastTextBaseline, spacing: 0) {
                        Text("\(String(allTimeWeightPR))")
                            .font(.title)
                            .foregroundStyle((exercise.muscleGroup?.color ?? .label).gradient)
                        Text(WeightUnit.used.rawValue)
                            .textCase(.uppercase)
                            .foregroundStyle((exercise.muscleGroup?.color ?? .label).gradient)
                    }
                    .fontWeight(.bold)
                    .fontDesign(.rounded)
                    .foregroundStyle(exerciseMuscleGroupColor.gradient)
                }
                .frame(maxWidth: .infinity)
            }
            .padding()
            .padding(.vertical)
            
            VStack(spacing: SECTION_HEADER_SPACING) {
                Text(chartHeaderTitle)
                    .sectionHeaderStyle2()
                    .frame(maxWidth: .infinity, alignment: .leading)
                VStack {
                    if #available(iOS 17.0, *) {
                        Chart {
                            ForEach(maxWeightDailySets) { workoutSet in
                                LineMark(
                                    x: .value("Date", workoutSet.workout?.date ?? .now, unit: .day),
                                    y: .value("Max weight on day", convertWeightForDisplaying(workoutSet.max(.weight)))
                                )
                                .interpolationMethod(.catmullRom)
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
                                    y: .value("Max weight on day", convertWeightForDisplaying(workoutSet.max(.weight)))
                                )
                                .interpolationMethod(.catmullRom)
                                .foregroundStyle(Gradient(colors: [
                                    exerciseMuscleGroupColor.opacity(0.5),
                                    exerciseMuscleGroupColor.opacity(0.2),
                                    exerciseMuscleGroupColor.opacity(0.05)
                                ]))
                            }
                        }
                        .chartXScale(domain: xDomain)
                        .frame(height: 300)
                    }
                    Picker("Select Chart Granularity", selection: $chartGranularity) {
                        Text(NSLocalizedString("month", comment: ""))
                            .tag(ChartGranularity.month)
                        Text(NSLocalizedString("year", comment: ""))
                            .tag(ChartGranularity.year)
                        Text(NSLocalizedString("allTime", comment: ""))
                            .tag(ChartGranularity.allTime)
                    }
                    .pickerStyle(.segmented)
                    .padding(.top)
                }
            }
            Spacer()
        }
        .padding(.horizontal)
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
    
    private var maxWeightDailySets: [WorkoutSet] {
        let components: [Calendar.Component] = (chartGranularity == .month ? [.month, .year] : chartGranularity == .year ? [.year] : [])

        let groupedSets = workoutSetRepository.getGroupedWorkoutsSets(
            with: exercise,
            for: components,
            inclusing: .now,
            groupedBy: [.day, .year]
        )

        let maxSetsPerDay = groupedSets.compactMap { setsPerDay -> WorkoutSet? in
            return setsPerDay.max(by: { $0.max(.weight) < $1.max(.weight) })
        }
        
        return maxSetsPerDay
    }
    
    private var exerciseMuscleGroupColor: Color {
        exercise.muscleGroup?.color ?? Color.accentColor
    }
    
    private var xDomain: some ScaleDomain {
        switch chartGranularity {
        case .month:
            return Date.now.startOfMonth ... Date.now.endOfMonth
        case .year:
            return Date.now.startOfYear ... Date.now.endOfYear
        default:
            guard let firstDate = maxWeightDailySets.sorted(by: {
                ($0.workout?.date ?? .distantPast) < ($1.workout?.date ?? .distantPast)
            }).first?.workout?.date else {
                return Date.now.startOfYear ... Date.now.endOfYear // Default to this year if no data exists
            }
            
            let endDate = Date.now.endOfYear
            let oneYearAgo = Calendar.current.date(byAdding: .year, value: -1, to: endDate) ?? Date.distantPast

            // If the range is shorter than a year, extend it to a full year
            if firstDate > oneYearAgo {
                return Date.now.startOfYear ... endDate
            } else {
                return firstDate ... endDate
            }
        }
    }

    private var chartHeaderTitle: String {
        switch chartGranularity {
        case .month:
            return "\(NSLocalizedString("thisMonth", comment: ""))"
        case .year:
            return "\(NSLocalizedString("thisYear", comment: ""))"
        case .allTime:
            return NSLocalizedString("allTime", comment: "")
        }
    }
    
    private var allTimeWeightPR: Int {
        workoutSetRepository.getWorkoutSets(with: exercise)
            .map {
                convertWeightForDisplaying($0.max(.weight))
            }
            .max() ?? 0
    }
    
    private var currentBestWeight: Int? {
        let setsThisMonth = workoutSetRepository.getWorkoutSets(
            with: exercise,
            for: [.month, .year],
            including: .now
        )
        
        guard !setsThisMonth.isEmpty else {
            return workoutSetRepository.getWorkoutSets(with: exercise).first?.max(.weight)
        }
        
        return setsThisMonth
            .map({ $0.max(.weight) })
            .max()
    }
    
}

private struct PreviewWrapperView: View {
    @EnvironmentObject private var database: Database
    
    var body: some View {
        NavigationView {
            ExerciseWeightScreen(exercise: database.getExercises().first!)
        }
    }
}

struct PersonalBestScreen_Previews: PreviewProvider {
    static var previews: some View {
        PreviewWrapperView()
            .previewEnvironmentObjects()
    }
}
