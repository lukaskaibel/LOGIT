//
//  MuscleGroupOccurancesChart.swift
//  LOGIT
//
//  Created by Volker Kaibel on 02.10.24.
//

import Charts
import SwiftUI

struct MuscleGroupOccurancesChart: View {
    let muscleGroupOccurances: [(MuscleGroup, Int)]
    let selectedMuscleGroup: MuscleGroup?

    init(muscleGroupOccurances: [(MuscleGroup, Int)], selectedMuscleGroup: MuscleGroup? = nil) {
        self.muscleGroupOccurances = muscleGroupOccurances
        self.selectedMuscleGroup = selectedMuscleGroup
    }

    var body: some View {
        Chart {
            if muscleGroupOccurances.isEmpty {
                SectorMark(
                    angle: .value("Value", 1),
                    innerRadius: .ratio(0.65)
                )
                .foregroundStyle(Color.fill.gradient)
            } else {
                ForEach(muscleGroupOccurances, id: \.0) { muscleGroupOccurance in
                    SectorMark(
                        angle: .value("Value", muscleGroupOccurance.1),
                        innerRadius: .ratio(0.65),
                        angularInset: 1
                    )
                    .foregroundStyle(foregroundStyle(for: muscleGroupOccurance.0))
                }
            }
        }
    }

    private func foregroundStyle(for muscleGroup: MuscleGroup) -> some ShapeStyle {
        if selectedMuscleGroup == nil || muscleGroup == selectedMuscleGroup {
            return AnyShapeStyle(muscleGroup.color.gradient)
        } else {
            return AnyShapeStyle(muscleGroup.color.secondaryTranslucentBackground)
        }
    }
}

private struct MuscleGroupOccurancesChartPreviewView: View {
    var body: some View {
        MuscleGroupOccurancesChart(muscleGroupOccurances: getMuscleGroupOccurances(in: []))
    }

    private func getMuscleGroupOccurances(in workouts: [Workout]) -> [(MuscleGroup, Int)] {
        let sets = workouts.map { $0.sets }.joined()
        return Array(
            sets
                .reduce(into: [MuscleGroup: Int]()) {
                    if let muscleGroup = $1.setGroup?.exercise?.muscleGroup {
                        $0[muscleGroup, default: 0] += 1
                    }
                    if let muscleGroup = $1.setGroup?.secondaryExercise?.muscleGroup {
                        $0[muscleGroup, default: 0] += 1
                    }
                }
        )
        .sorted {
            MuscleGroup.allCases.firstIndex(of: $0.key)! < MuscleGroup.allCases.firstIndex(
                of: $1.key
            )!
        }
    }
}

#Preview {
    MuscleGroupOccurancesChartPreviewView()
        .previewEnvironmentObjects()
}
