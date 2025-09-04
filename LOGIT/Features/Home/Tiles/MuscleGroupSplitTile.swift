//
//  MuscleGroupSplitTile.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 24.08.24.
//

import Charts
import SwiftUI

struct MuscleGroupSplitTile: View {
    // MARK: - Environment

    @EnvironmentObject private var muscleGroupService: MuscleGroupService

    // MARK: - Parameters

    let workouts: [Workout]

    // MARK: - Body

    var body: some View {
        let workoutsThisWeek = workouts.filter { $0.date ?? .distantPast >= .now.startOfWeek && $0.date ?? .distantFuture <= .now }
        let muscleGroupOccurances = muscleGroupService.getMuscleGroupOccurances(in: workoutsThisWeek)
        VStack(spacing: 20) {
            HStack {
                Text(NSLocalizedString("muscleGroups", comment: ""))
                    .tileHeaderStyle()
                Spacer()
                NavigationChevron()
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .bottom) {
                VStack(alignment: .leading) {
                    Text(NSLocalizedString("focus", comment: ""))
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                        .fontWeight(.semibold)
                    let fucusedMuscleGroups = getFocusedMuscleGroups(muscleGroupOccurances)
                    HStack {
                        if !fucusedMuscleGroups.isEmpty {
                            ForEach(fucusedMuscleGroups) { muscleGroup in
                                Text(muscleGroup.description)
                                    .foregroundStyle(muscleGroup.color.gradient)
                            }
                        } else {
                            Text(NSLocalizedString("none", comment: ""))
                                .foregroundStyle(Color.secondaryLabel.gradient)
                        }
                    }
                    .font(.title3)
                    .fontWeight(.bold)
                    .fontDesign(.rounded)
                }
                Spacer()
                MuscleGroupOccurancesChart(muscleGroupOccurances: muscleGroupOccurances)
                    .frame(width: 70, height: 70)
            }
        }
        .padding(CELL_PADDING)
        .tileStyle()
    }

    // MAKR: - Supporting Methods

    /// Calculates the smallest number of Muscle Groups that combined account for 51% of the overall sets in the timeframe
    /// - Returns: The focused Muscle Groups
    private func getFocusedMuscleGroups(_ muscleGroupOccurances: [(MuscleGroup, Int)]) -> [MuscleGroup] {
        var accumulatedPercetange: Float = 0
        var focusedMuscleGroups = [MuscleGroup]()
        let amountOfOccurances = muscleGroupOccurances.reduce(0) { $0 + $1.1 }
        for muscleGroupOccurance in muscleGroupOccurances {
            accumulatedPercetange += Float(muscleGroupOccurance.1) / Float(amountOfOccurances)
            focusedMuscleGroups.append(muscleGroupOccurance.0)
            if accumulatedPercetange > 0.51 {
                return Array(focusedMuscleGroups.prefix(2))
            }
        }
        return []
    }
}

#Preview {
    FetchRequestWrapper(Workout.self) { workouts in
        MuscleGroupSplitTile(workouts: workouts)
            .padding()
            .previewEnvironmentObjects()
    }
}
