//
//  ExerciseHistoryScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 12.11.24.
//

import SwiftUI

struct ExerciseHistoryScreen: View {
    
    @EnvironmentObject private var workoutSetGroupRepository: WorkoutSetGroupRepository
    
    let exercise: Exercise
    
    var body: some View {
        ScrollView {
            VStack(spacing: SECTION_SPACING) {
                ForEach(groupedWorkoutSetGroups.indices, id: \.self) { index in
                    VStack(spacing: SECTION_HEADER_SPACING) {
                        Text(setGroupGroupHeaderTitle(for: index))
                            .sectionHeaderStyle2()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        VStack(spacing: CELL_SPACING) {
                            ForEach(groupedWorkoutSetGroups[index]) { setGroup in
                                WorkoutSetGroupCell(
                                    setGroup: setGroup,
                                    focusedIntegerFieldIndex: .constant(nil),
                                    sheetType: .constant(nil),
                                    isReordering: .constant(false),
                                    supplementaryText:
                                        "\(setGroup.workout?.date?.description(.short) ?? "")  ·  \(setGroup.workout?.name ?? "")"
                                )
                                .padding(CELL_PADDING)
                                .tileStyle()
                                .canEdit(false)
                                .allowsHitTesting(false)
                            }
                        }
                    }
                }
                .emptyPlaceholder(workoutSetGroupRepository.getWorkoutSetGroups(with: exercise)) {
                    Text(NSLocalizedString("noHistory", comment: ""))
                        .frame(maxWidth: .infinity)
                        .frame(height: 150)
                }
            }
            .padding([.top, .horizontal])
            .padding(.bottom, SCROLLVIEW_BOTTOM_PADDING)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack {
                    Text("\(NSLocalizedString("history", comment: ""))")
                        .font(.headline)
                    Text(exercise.name ?? "")
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }
            }
            
        }
    }
    
    private var groupedWorkoutSetGroups: [[WorkoutSetGroup]] {
        workoutSetGroupRepository.getGroupedWorkoutSetGroups(with: exercise)
    }

    private func setGroupGroupHeaderTitle(for index: Int) -> String {
        guard let date = groupedWorkoutSetGroups.value(at: index)?.first?.workout?.date else {
            return ""
        }
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }
    
}

private struct PreviewWrapperView: View {
    @EnvironmentObject private var database: Database
    
    var body: some View {
        NavigationView {
            ExerciseHistoryScreen(exercise: database.getExercises().first!)
        }
    }
}

struct ExerciseHistoryScreen_Previews: PreviewProvider {
    static var previews: some View {
        PreviewWrapperView()
            .previewEnvironmentObjects()
    }
}
