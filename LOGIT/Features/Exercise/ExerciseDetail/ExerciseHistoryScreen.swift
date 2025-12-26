//
//  ExerciseHistoryScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 12.11.24.
//

import SwiftUI

struct ExerciseHistoryScreen: View {
    let exercise: Exercise

    var body: some View {
        FetchRequestWrapper(
            WorkoutSetGroup.self,
            sortDescriptors: [SortDescriptor(\.workout?.date, order: .reverse)],
            predicate: WorkoutSetGroupPredicateFactory.getWorkoutSetGroups(withExercise: exercise)
        ) { workoutSetGroups in
            let groupedWorkoutSetGroups = Dictionary(grouping: workoutSetGroups, by: {
                $0.workout?.date?.startOfMonth ?? .now
            }).sorted { $0.key > $1.key }
            ScrollView {
                VStack(spacing: SECTION_SPACING) {
                    ForEach(groupedWorkoutSetGroups, id: \.0) { key, workoutSetGroups in
                        VStack(spacing: SECTION_HEADER_SPACING) {
                            Text(key.monthDescription)
                                .sectionHeaderStyle2()
                                .frame(maxWidth: .infinity, alignment: .leading)
                            VStack(spacing: CELL_SPACING) {
                                ForEach(workoutSetGroups) { setGroup in
                                    WorkoutSetGroupCell(
                                        setGroup: setGroup,
                                        focusedIntegerFieldIndex: .constant(nil),
                                        isReordering: .constant(false),
                                        supplementaryText:
                                        "\(setGroup.workout?.date?.description(.short) ?? "")"
                                    )
                                    .tileStyle()
                                    .canEdit(false)
                                    .allowsHitTesting(false)
                                }
                            }
                        }
                    }
                    .emptyPlaceholder(groupedWorkoutSetGroups) {
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
                        Text(exercise.displayName)
                            .foregroundStyle(.secondary)
                            .font(.footnote)
                    }
                }
            }
        }
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
