//
//  ExerciseWeightTile.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 03.12.24.
//

import Charts
import SwiftUI

struct ExerciseRepetitionsTile: View {
    
    @EnvironmentObject private var workoutSetRepository: WorkoutSetRepository
    
    let exercise: Exercise
    
    var body: some View {
        VStack {
            HStack {
                Text(NSLocalizedString("repetitions", comment: ""))
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
                            Text(currentBestRepetitions != nil ? String(currentBestRepetitions!) : "––")
                                .font(.title)
                                .foregroundStyle((exercise.muscleGroup?.color ?? .label).gradient)
                            Text(NSLocalizedString("rps", comment: ""))
                                .textCase(.uppercase)
                                .foregroundStyle((exercise.muscleGroup?.color ?? .label).gradient)
                        }
                        .fontWeight(.bold)
                        .fontDesign(.rounded)
                    }
                }
                Spacer()
                Chart {
                    ForEach(maxRepetitionsDailySets) { workoutSet in
                        LineMark(
                            x: .value("Date", workoutSet.workout?.date ?? .now, unit: .day),
                            y: .value("Max weight on day", workoutSet.maximum(.repetitions, for: exercise))
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(exerciseMuscleGroupColor.gradient)
                        .lineStyle(StrokeStyle(lineWidth: 3))
                        AreaMark(
                            x: .value("Date", workoutSet.workout?.date ?? .now, unit: .day),
                            y: .value("Max weight on day", workoutSet.maximum(.repetitions, for: exercise))
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
    
    private var maxRepetitionsDailySets: [WorkoutSet] {
        let groupedSets = workoutSetRepository.getGroupedWorkoutsSets(
            with: exercise,
            groupedBy: [.day, .year]
        )

        let maxSetsPerDay = groupedSets.compactMap { setsPerDay -> WorkoutSet? in
            return setsPerDay.max(by: { $0.maximum(.repetitions, for: exercise) < $1.maximum(.repetitions, for: exercise) })
        }
        
        return maxSetsPerDay
    }
    
    private var exerciseMuscleGroupColor: Color {
        exercise.muscleGroup?.color ?? Color.accentColor
    }
    
    private var currentBestRepetitions: Int? {
        let setsThisMonth = workoutSetRepository.getWorkoutSets(
            with: exercise,
            for: [.month, .year],
            including: .now
        )
        
        guard !setsThisMonth.isEmpty else {
            return workoutSetRepository.getWorkoutSets(with: exercise).first?.maximum(.repetitions, for: exercise)
        }
        
        return setsThisMonth
            .map({ $0.maximum(.repetitions, for: exercise) })
            .max()
    }
}

private struct PreviewWrapperView: View {
    @EnvironmentObject private var database: Database
    
    var body: some View {
        NavigationStack {
            ExerciseRepetitionsTile(exercise: database.getExercises().first!)
        }
    }
}

struct ExerciseRepetitionsTileView_Previews: PreviewProvider {
    static var previews: some View {
        PreviewWrapperView()
            .previewEnvironmentObjects()
            .padding()
    }
}
