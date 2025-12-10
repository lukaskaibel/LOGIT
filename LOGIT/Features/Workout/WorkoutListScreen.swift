//
//  WorkoutListScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 12.12.21.
//

import SwiftUI

struct WorkoutListScreen: View {
    // MARK: - Environment

    @EnvironmentObject private var database: Database

    // MARK: - State

    @State private var searchedText: String = ""
    @State private var selectedMuscleGroup: MuscleGroup? = nil
    @State private var isShowingAddWorkout = false
    @State private var selectedWorkout: Workout?

    // MARK: - Body

    var body: some View {
        FetchRequestWrapper(
            Workout.self,
            sortDescriptors: [SortDescriptor(\Workout.date, order: .reverse)],
            predicate: WorkoutPredicateFactory.getWorkouts(
                nameIncluding: searchedText,
                withMuscleGroup: selectedMuscleGroup
            )
        ) { workouts in
            let groupedWorkouts = Dictionary(grouping: workouts, by: { workout in
                workout.date?.startOfMonth ?? .now
            }).sorted { $0.key > $1.key }

            ScrollView {
                LazyVStack(spacing: SECTION_SPACING) {
                    MuscleGroupSelector(selectedMuscleGroup: $selectedMuscleGroup)
                    ForEach(groupedWorkouts, id: \.0) { key, workouts in
                        VStack(spacing: SECTION_HEADER_SPACING) {
                            Text(key.monthDescription)
                                .sectionHeaderStyle2()
                                .frame(maxWidth: .infinity, alignment: .leading)
                            VStack(spacing: CELL_SPACING) {
                                ForEach(workouts) {
                                    workout in
                                    Button {
                                        selectedWorkout = workout
                                    } label: {
                                        WorkoutCell(workout: workout)
                                            .padding(CELL_PADDING)
                                            .tileStyle()
                                    }
                                    .buttonStyle(TileButtonStyle())
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .emptyPlaceholder(groupedWorkouts) {
                        Text(NSLocalizedString("noWorkouts", comment: ""))
                    }
                }
                .padding(.bottom, SCROLLVIEW_BOTTOM_PADDING)
            }
            .searchable(
                text: $searchedText,
                prompt: NSLocalizedString("searchWorkouts", comment: "")
            )
            .navigationTitle(NSLocalizedString("workoutHistory", comment: ""))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        isShowingAddWorkout = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $isShowingAddWorkout) {
                WorkoutEditorScreen(workout: database.newWorkout(), isAddingNewWorkout: true)
            }
        }
        .navigationDestination(item: $selectedWorkout) { workout in
            WorkoutDetailScreen(workout: workout, canNavigateToTemplate: true)
        }
    }
}

struct AllWorkoutsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            WorkoutListScreen()
        }
        .previewEnvironmentObjects()
    }
}
