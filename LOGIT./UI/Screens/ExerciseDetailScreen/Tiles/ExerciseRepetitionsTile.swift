//
//  ExerciseRepetitionsTile.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 03.12.24.
//

import Charts
import SwiftUI

struct ExerciseRepetitionsTile: View {
        
    @StateObject var exercise: Exercise
    
    var body: some View {
        let workoutSets = exercise.sets
        let groupedWorkoutSets = Dictionary(grouping: workoutSets) {
            Calendar.current.startOfDay(for: $0.workout?.date ?? .now)
        }.sorted { $0.key < $1.key }
        let maxDailySets = maxRepetitionsDailySets(in: groupedWorkoutSets.map({ $0.1 }))
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
                        Text(NSLocalizedString("bestThisMonth", comment: ""))
                        HStack(alignment: .lastTextBaseline, spacing: 0) {
                            Text(bestRepetitionsThisMonth(workoutSets) != nil ? String(bestRepetitionsThisMonth(workoutSets)!) : "––")
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
                    if let firstEntry = maxDailySets.first {
                        LineMark(
                            x: .value("Date", Date.distantPast, unit: .day),
                            y: .value("Max repetitions on day", firstEntry.maximum(.repetitions, for: exercise))
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(exerciseMuscleGroupColor.gradient)
                        .lineStyle(StrokeStyle(lineWidth: 6))
                        AreaMark(
                            x: .value("Date", Date.distantPast, unit: .day),
                            y: .value("Max repetitions on day", firstEntry.maximum(.repetitions, for: exercise))
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Gradient(colors: [
                            exerciseMuscleGroupColor.opacity(0.5),
                            exerciseMuscleGroupColor.opacity(0.2),
                            exerciseMuscleGroupColor.opacity(0)
                        ]))
                    }
                    ForEach(maxDailySets) { workoutSet in
                        LineMark(
                            x: .value("Date", workoutSet.workout?.date ?? .now, unit: .day),
                            y: .value("Max repetitions on day", workoutSet.maximum(.repetitions, for: exercise))
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(exerciseMuscleGroupColor.gradient)
                        .lineStyle(StrokeStyle(lineWidth: 6))
                        AreaMark(
                            x: .value("Date", workoutSet.workout?.date ?? .now, unit: .day),
                            y: .value("Max repetitions on day", workoutSet.maximum(.repetitions, for: exercise))
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
    
    private func maxRepetitionsDailySets(in groupedWorkoutSets: [[WorkoutSet]]) -> [WorkoutSet] {
        let startDate = Calendar.current.date(byAdding: .second, value: -visibleChartDomainInSeconds, to: .now)!
        let maxSetsPerDay = groupedWorkoutSets.compactMap { setsPerDay -> WorkoutSet? in
            return setsPerDay.max(by: { $0.maximum(.repetitions, for: exercise) < $1.maximum(.repetitions, for: exercise) })
        }
        return maxSetsPerDay
    }
    
    private var exerciseMuscleGroupColor: Color {
        exercise.muscleGroup?.color ?? Color.accentColor
    }
    
    private var visibleChartDomainInSeconds: Int {
        3600 * 24 * 35
    }
    
    private func bestRepetitionsThisMonth(_ workoutSets: [WorkoutSet]) -> Int? {
        let startDate = Calendar.current.date(byAdding: .second, value: -visibleChartDomainInSeconds, to: .now)!
        let setsInTimeFrame = workoutSets.filter { $0.workout?.date ?? .distantPast >= startDate }
        guard !setsInTimeFrame.isEmpty else {
            return 0
        }
        return setsInTimeFrame
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
