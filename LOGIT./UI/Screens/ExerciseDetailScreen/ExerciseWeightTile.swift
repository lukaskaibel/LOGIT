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
                        Text(NSLocalizedString("currentBest", comment: ""))
                        HStack(alignment: .lastTextBaseline, spacing: 0) {
                            Text(currentBestWeight != nil ? String(convertWeightForDisplaying(currentBestWeight!)) : "––")
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
                    ForEach(maxWeightDailySets) { workoutSet in
                        LineMark(
                            x: .value("Date", workoutSet.workout?.date ?? .now, unit: .day),
                            y: .value("Max weight on day", convertWeightForDisplaying(workoutSet.max(.weight)))
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(exerciseMuscleGroupColor.gradient)
                        .lineStyle(StrokeStyle(lineWidth: 3))
                        AreaMark(
                            x: .value("Date", workoutSet.workout?.date ?? .now, unit: .day),
                            y: .value("Max weight on day", convertWeightForDisplaying(workoutSet.max(.weight)))
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Gradient(colors: [
                            exerciseMuscleGroupColor.opacity(0.5),
                            exerciseMuscleGroupColor.opacity(0.2),
                            exerciseMuscleGroupColor.opacity(0)
                        ]))
                    }
                }
                .chartXAxis {}
                .chartYAxis {}
                .frame(width: 120, height: 80)
                .padding(.horizontal)
            }
        }
        .padding(CELL_PADDING)
        .tileStyle()
    }
    
    private var maxWeightDailySets: [WorkoutSet] {
        let groupedSets = workoutSetRepository.getGroupedWorkoutsSets(
            with: exercise,
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
