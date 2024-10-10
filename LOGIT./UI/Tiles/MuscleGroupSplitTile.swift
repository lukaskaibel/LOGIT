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
                    VStack(alignment: .leading) {
                        Text(NSLocalizedString("muscleGroupSplit", comment: ""))
                            .tileHeaderStyle()
                        Text(NSLocalizedString("ThisWeek", comment: ""))
                            .tileHeaderSecondaryStyle()
                    }
                    Spacer()
                    NavigationChevron()
                        .foregroundStyle(.secondary)
                }
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading) {
                        Spacer()
                        Text(NSLocalizedString("focusedOn", comment: ""))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        HStack {
                            ForEach(getFocusedMuscleGroups()) { muscleGroup in
                                Text(muscleGroup.description)
                                    .fontWeight(.bold)
                                    .fontDesign(.rounded)
                                    .foregroundStyle(muscleGroup.color)
                            }
                        }
                    }
                    .emptyPlaceholder(muscleGroupOccurances) {
                        Text(NSLocalizedString("noWorkoutsThisWeek", comment: ""))
                            .font(.body)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxHeight: 150)
                    Spacer()
                    MuscleGroupOccurancesChart(muscleGroupOccurances: muscleGroupOccurances)
                    .frame(width: 150, height: 150)
                }
                // MARK: Legend, maybe needed in future...
//                Grid(alignment: .leading) {
//                    GridRow {
//                        ForEach(muscleGroupOccurances.prefix(upTo: muscleGroupOccurances.count / 2 + 1), id:\.0) { muscleGroupOccurance in
//                            HStack {
//                                Circle()
//                                    .frame(width: 5, height: 5)
//                                    .foregroundStyle(muscleGroupOccurance.0.color.gradient)
//                                Text(muscleGroupOccurance.0.description)
//                                    .font(.footnote)
//                            }
//                            .frame(maxWidth: .infinity, alignment: .leading)
//                        }
//                    }
//                    GridRow {
//                        ForEach(muscleGroupOccurances.suffix(from: muscleGroupOccurances.count / 2 + 1), id:\.0) { muscleGroupOccurance in
//                            HStack {
//                                Circle()
//                                    .frame(width: 5, height: 5)
//                                    .foregroundStyle(muscleGroupOccurance.0.color.gradient)
//                                Text(muscleGroupOccurance.0.description)
//                                    .font(.footnote)
//                            }
//                            .frame(maxWidth: .infinity, alignment: .leading)
//                        }
//                    }
//                }
                
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
