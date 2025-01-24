//
//  ExerciseWeightTile.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 03.12.24.
//

import Charts
import SwiftUI

struct ExerciseWeightTile: View {
    
    @EnvironmentObject private var workoutSetRepository: WorkoutSetRepository
    
    let exercise: Exercise
    
    var body: some View {
        VStack {
            HStack {
                Text(NSLocalizedString("weight", comment: ""))
                    .tileHeaderStyle()
                Spacer()
                NavigationChevron()
                    .foregroundStyle(.secondary)
            }
            HStack {
                VStack(alignment: .leading) {
                    VStack(alignment: .leading) {
                        Text(NSLocalizedString("bestThisMonth", comment: ""))
                        HStack(alignment: .lastTextBaseline, spacing: 0) {
                            Text(bestWeightThisMonth != nil ? String(convertWeightForDisplaying(bestWeightThisMonth!)) : "––")
                                .font(.title)
                                .foregroundStyle((exercise.muscleGroup?.color ?? .label).gradient)
                            Text(WeightUnit.used.rawValue)
                                .textCase(.uppercase)
                                .foregroundStyle((exercise.muscleGroup?.color ?? .label).gradient)
                        }
                        .fontWeight(.bold)
                        .fontDesign(.rounded)
                    }
                }
                Spacer()
                Chart {
                    if let firstEntry = maxWeightDailySets.first {
                        LineMark(
                            x: .value("Date", Date.distantPast, unit: .day),
                            y: .value("Max weight on day", convertWeightForDisplaying(firstEntry.maximum(.weight, for: exercise)))
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(exerciseMuscleGroupColor.gradient)
                        .lineStyle(StrokeStyle(lineWidth: 6))
                        AreaMark(
                            x: .value("Date", Date.distantPast, unit: .day),
                            y: .value("Max weight on day", convertWeightForDisplaying(firstEntry.maximum(.weight, for: exercise)))
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Gradient(colors: [
                            exerciseMuscleGroupColor.opacity(0.5),
                            exerciseMuscleGroupColor.opacity(0.2),
                            exerciseMuscleGroupColor.opacity(0)
                        ]))
                    }
                    ForEach(maxWeightDailySets) { workoutSet in
                        LineMark(
                            x: .value("Date", workoutSet.workout?.date ?? .now, unit: .day),
                            y: .value("Max weight on day", convertWeightForDisplaying(workoutSet.maximum(.weight, for: exercise)))
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(exerciseMuscleGroupColor.gradient)
                        .lineStyle(StrokeStyle(lineWidth: 6))
                        AreaMark(
                            x: .value("Date", workoutSet.workout?.date ?? .now, unit: .day),
                            y: .value("Max weight on day", convertWeightForDisplaying(workoutSet.maximum(.weight, for: exercise)))
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Gradient(colors: [
                            exerciseMuscleGroupColor.opacity(0.5),
                            exerciseMuscleGroupColor.opacity(0.2),
                            exerciseMuscleGroupColor.opacity(0)
                        ]))
                    }
                }
                .chartXScale(domain: xDomain)
                .chartXAxis {}
                .chartYAxis {}
                .frame(width: 120, height: 80)
                .clipped()
                .padding(.horizontal)
            }
        }
        .padding(CELL_PADDING)
        .tileStyle()
    }
    
    // MARK: - Private Methods
    
    private var xDomain: some ScaleDomain {
        let startDate = Calendar.current.date(byAdding: .second, value: -visibleChartDomainInSeconds, to: .now)!
        return startDate...Date.now
    }
    
    private var maxWeightDailySets: [WorkoutSet] {
        let startDate = Calendar.current.date(byAdding: .second, value: -visibleChartDomainInSeconds, to: .now)!
        let groupedSets = workoutSetRepository.getGroupedWorkoutSets(
            with: exercise,
            groupedBy: [.day, .month, .year],
            from: startDate,
            to: .now
        )
        let maxSetsPerDay = groupedSets.compactMap { setsPerDay -> WorkoutSet? in
            return setsPerDay.max(by: { $0.maximum(.weight, for: exercise) < $1.maximum(.weight, for: exercise) })
        }
        return maxSetsPerDay
    }
    
    private var exerciseMuscleGroupColor: Color {
        exercise.muscleGroup?.color ?? Color.accentColor
    }
    
    private var visibleChartDomainInSeconds: Int {
        3600 * 24 * 35
    }
    
    private var bestWeightThisMonth: Int? {
        let startDate = Calendar.current.date(byAdding: .second, value: -visibleChartDomainInSeconds, to: .now)!
        let setsThisMonth = workoutSetRepository.getWorkoutSets(
            with: exercise,
            from: startDate,
            to: .now
        )
        guard !setsThisMonth.isEmpty else {
            return 0
        }
        return setsThisMonth
            .map({ $0.maximum(.weight, for: exercise) })
            .max()
    }
}

private struct PreviewWrapperView: View {
    @EnvironmentObject private var database: Database
    
    var body: some View {
        NavigationStack {
            ExerciseWeightTile(exercise: database.getExercises().first!)
        }
    }
}

struct ExerciseWeightTileView_Previews: PreviewProvider {
    static var previews: some View {
        PreviewWrapperView()
            .previewEnvironmentObjects()
            .padding()
    }
}
