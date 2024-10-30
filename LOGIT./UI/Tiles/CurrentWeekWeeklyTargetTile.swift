//
//  CurrentWeekWeeklyTargetTile.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 24.08.24.
//

import Charts
import SwiftUI

struct CurrentWeekWeeklyTargetTile: View {
    
    // MARK: - AppStorage
    
    @AppStorage("workoutPerWeekTarget") var targetPerWeek: Int = 3
    
    // MARK: - Environment
    
    @EnvironmentObject private var workoutRepository: WorkoutRepository
    
    // MARK: - Body
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(NSLocalizedString("Workouts per Week", comment: ""))
                    .tileHeaderStyle()
                Spacer()
                NavigationChevron()
                    .foregroundStyle(.secondary)
            }
            
            
//            .frame(maxWidth: .infinity, alignment: .trailing)
//            VStack(alignment: .leading) {
//                Text(NSLocalizedString("goal", comment: ""))
//                    .fontWeight(.semibold)
//                    .foregroundStyle(.secondary)
//                
//                Text(NSLocalizedString("PerWeek", comment: ""))
//                    .fontWeight(.bold)
//                    .fontDesign(.rounded)
//                    .foregroundStyle(.secondary)
//            }
            HStack {
                if #available(iOS 17.0, *) {
                    Chart {
                        ForEach(0..<targetPerWeek, id:\.self) { value in
                            SectorMark(
                                angle: .value("Value", 1),
                                innerRadius: .ratio(0.65),
                                angularInset: 1
                            )
                            .foregroundStyle(value < numberOfWorkoutsInCurrentWeek ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(Color.fill))
                        }
                    }
                    .overlay {
                        if numberOfWorkoutsInCurrentWeek >= targetPerWeek {
                            Image(systemName: "checkmark")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundStyle(Color.accentColor.gradient)
                        } else {
                            VStack(spacing: 0) {
                                Text("\(targetPerWeek - numberOfWorkoutsInCurrentWeek)")
                                    .fontWeight(.semibold)
                                Text(NSLocalizedString("toGo", comment: ""))
                                    .font(.caption)
                                    .textCase(.uppercase)
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 120, height: 120)
                    .padding(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                VStack(alignment: .leading) {
//                    Text(NSLocalizedString("thisWeek", comment: ""))
////                        .fontWeight(.medium)
//                    HStack(alignment: .lastTextBaseline, spacing: 0) {
//                        Text("\(numberOfWorkoutsInCurrentWeek)")
//                            .foregroundStyle(Color.accentColor.gradient)
//                            .fontWeight(.bold)
//                            .fontDesign(.rounded)
//                            .font(.title)
////                        Text("workouts")
////                            .textCase(.uppercase)
////                            .foregroundStyle(.secondary)
////                            .fontWeight(.semibold)
////                            .fontDesign(.rounded)
//                    }
                    HStack(alignment: .firstTextBaseline) {
                        VStack {
                            Text("\(numberOfWorkoutsInCurrentWeek)")
                                .font(.title)
                                .fontDesign(.rounded)
                                .fontWeight(.bold)
                                .foregroundStyle(Color.accentColor.gradient)
                            Text(NSLocalizedString("thisWeek", comment: ""))
                                .textCase(.uppercase)
                                .font(.footnote)
                                .foregroundStyle(Color.accentColor.gradient)
                        }
                        .frame(maxWidth: .infinity)
                        Text("/")
                            .textCase(.uppercase)
                            .font(.title2)
                            .fontDesign(.rounded)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        
                        VStack {
                            Text("\(targetPerWeek)")
                                .font(.title)
                                .fontDesign(.rounded)
                                .fontWeight(.bold)
                            Text(NSLocalizedString("goal", comment: ""))
                                .textCase(.uppercase)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: .infinity)
                
            }
            
//            VStack(spacing: 10) {
//                Divider()
//                HStack {
//                    Text("Goal")
//                    Spacer()
//                    Text("3")
//                        .fontWeight(.medium)
//                }
//            }
           
        }
        .padding(CELL_PADDING)
        .tileStyle()
    }
    
    // MARK: - Computed Properties
    
    private var numberOfWorkoutsInCurrentWeek: Int {
        workoutRepository.getWorkouts(for: [.weekOfYear, .yearForWeekOfYear], including: .now).count
    }
}

#Preview {
    CurrentWeekWeeklyTargetTile()
        .previewEnvironmentObjects()
        .padding()
}
