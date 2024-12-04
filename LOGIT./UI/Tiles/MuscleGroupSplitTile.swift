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
    
    @EnvironmentObject private var workoutRepository: WorkoutRepository
    @EnvironmentObject private var muscleGroupService: MuscleGroupService
    
    // MARK: - Body
    
    var body: some View {
        if #available(iOS 17.0, *) {
            let muscleGroupOccurances = getMuscleGroupOccurancesThisWeek()
            VStack(spacing: 20) {
                HStack {
                    Text(NSLocalizedString("muscleGroups", comment: ""))
                        .tileHeaderStyle()
                    Spacer()
                    NavigationChevron()
                        .foregroundStyle(.secondary)
                }
                HStack {
                    VStack(alignment: .leading) {
                        Text(NSLocalizedString("focusThisWeek", comment: ""))
                        HStack {
                            ForEach(getFocusedMuscleGroups()) { muscleGroup in
                                Text(muscleGroup.description)
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .fontDesign(.rounded)
                                    .foregroundStyle(muscleGroup.color.gradient)
                            }
                        }
                    }
                    .emptyPlaceholder(muscleGroupOccurances) {
                        Text(NSLocalizedString("noWorkoutsThisWeek", comment: ""))
                            .font(.body)
                            .multilineTextAlignment(.center)
                    }
                    Spacer()
                    MuscleGroupOccurancesChart(muscleGroupOccurances: muscleGroupOccurances)
                    .frame(width: 120, height: 80)
                }
            }
            .padding(CELL_PADDING)
            .tileStyle()
        } else {
            // Fallback on earlier versions
        }
        
    }
    
    // MAKR: - Supporting Methods
    
    func getMuscleGroupOccurancesThisWeek() -> [(MuscleGroup, Int)] {
        let workoutsThisWeek = workoutRepository.getWorkouts(
            for: [.weekOfYear, .yearForWeekOfYear],
            including: .now
        )
        return muscleGroupService.getMuscleGroupOccurances(in: workoutsThisWeek)
    }
    
    private var amountOfOccurances: Int {
        getMuscleGroupOccurancesThisWeek().reduce(0, { $0 + $1.1 })
    }
    
    /// Calculates the smallest number of Muscle Groups that combined account for 51% of the overall sets in the timeframe
    /// - Returns: The focused Muscle Groups
    private func getFocusedMuscleGroups() -> [MuscleGroup] {
        var accumulatedPercetange: Float = 0
        var focusedMuscleGroups = [MuscleGroup]()
        for muscleGroupOccurance in getMuscleGroupOccurancesThisWeek() {
            accumulatedPercetange += Float(muscleGroupOccurance.1) / Float(amountOfOccurances)
            focusedMuscleGroups.append(muscleGroupOccurance.0)
            if accumulatedPercetange > 0.51 {
                return focusedMuscleGroups
            }
        }
        return []
    }
    
}

#Preview {
    MuscleGroupSplitTile()
        .padding()
        .previewEnvironmentObjects()
}
