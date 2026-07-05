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
    /// The workout being added via the editor sheet. Created once on button tap — creating it
    /// inside the sheet's ViewBuilder inserts a fresh orphan workout into the context on every
    /// re-evaluation of the builder, and they all get persisted by the next save.
    @State private var workoutToAdd: Workout?
    @State private var selectedWorkout: Workout?

    // MARK: - Body

    var body: some View {
        FetchRequestWrapper(
            Workout.self,
            sortDescriptors: [SortDescriptor(\Workout.date, order: .reverse)],
            predicate: WorkoutPredicateFactory.getWorkouts(
                nameIncluding: "",
                withMuscleGroup: selectedMuscleGroup
            )
        ) { allWorkouts in
            let workouts = FuzzySearchService.shared.searchWorkouts(searchedText, in: allWorkouts)
            let groupedWorkouts = Dictionary(grouping: workouts, by: { workout in
                workout.date?.startOfMonth ?? .now
            }).sorted { $0.key > $1.key }
            let isSearching = !searchedText.isEmpty

            ScrollView {
                LazyVStack(spacing: SECTION_SPACING) {
                    MuscleGroupSelector(selectedMuscleGroup: $selectedMuscleGroup)
                    if isSearching {
                        // Flat list when searching - results ordered by relevance
                        VStack(spacing: 8) {
                            ForEach(workouts) { workout in
                                Button {
                                    selectedWorkout = workout
                                } label: {
                                    WorkoutCell(workout: workout)
                                }
                                .buttonStyle(TileButtonStyle())
                            }
                        }
                        .padding(.horizontal)
                    } else {
                        // Grouped by month when not searching
                        ForEach(groupedWorkouts, id: \.0) { key, workouts in
                            VStack(spacing: SECTION_HEADER_SPACING) {
                                Text(key.monthDescription)
                                    .sectionHeaderStyle2()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                VStack(spacing: 8) {
                                    ForEach(workouts) {
                                        workout in
                                        Button {
                                            selectedWorkout = workout
                                        } label: {
                                            WorkoutCell(workout: workout)
                                        }
                                        .buttonStyle(TileButtonStyle())
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    EmptyView()
                        .emptyPlaceholder(workouts) {
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
                        workoutToAdd = database.newWorkout()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $workoutToAdd) { workout in
                WorkoutEditorScreen(workout: workout, isAddingNewWorkout: true)
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
