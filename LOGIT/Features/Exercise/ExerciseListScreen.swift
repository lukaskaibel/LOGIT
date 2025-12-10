//
//  ExerciseListScreen.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 19.03.22.
//

import SwiftUI

struct ExerciseListScreen: View {

    // MARK: - State

    @State private var searchedText = ""
    @State private var selectedMuscleGroup: MuscleGroup? = nil
    @State private var showingAddExercise = false
    @State private var isShowingNoExercisesTip = false
    @State private var selectedExercise: Exercise?

    // MARK: - Body

    var body: some View {
        FetchRequestWrapper(
            Exercise.self,
            sortDescriptors: [SortDescriptor(\.firstLetterOfName), SortDescriptor(\.name)],
            predicate: ExercisePredicateFactory.getExercises(
                nameIncluding: "",
                withMuscleGroup: selectedMuscleGroup
            )
        ) { allExercises in
            let exercises = searchedText.isEmpty ? allExercises : allExercises.filter { exercise in
                exercise.displayName.localizedCaseInsensitiveContains(searchedText)
            }
            let groupedExercises = Dictionary(grouping: exercises, by: {
                $0.displayNameFirstLetter
            }).sorted { $0.key < $1.key }
            ScrollView {
                LazyVStack(spacing: SECTION_SPACING) {
                    MuscleGroupSelector(selectedMuscleGroup: $selectedMuscleGroup)
                    if isShowingNoExercisesTip {
                        TipView(title: NSLocalizedString("noExercisesTip", comment: ""),
                                description: NSLocalizedString("noExercisesTipDescription", comment: ""),
                                buttonAction: .init(title: NSLocalizedString("createExercise", comment: ""), action: { showingAddExercise = true }),
                                isShown: $isShowingNoExercisesTip)
                            .padding(CELL_PADDING)
                            .tileStyle()
                            .padding(.horizontal)
                    }
                    ForEach(groupedExercises, id: \.0) { key, exercises in
                        VStack(spacing: SECTION_HEADER_SPACING) {
                            Text(key)
                                .sectionHeaderStyle2()
                                .frame(maxWidth: .infinity, alignment: .leading)
                            VStack(spacing: CELL_SPACING) {
                                ForEach(exercises) { exercise in
                                    Button {
                                        selectedExercise = exercise
                                    } label: {
                                        HStack {
                                            ExerciseCell(exercise: exercise)
                                            Spacer()
                                            NavigationChevron()
                                                .foregroundColor(
                                                    exercise.muscleGroup?.color ?? .secondaryLabel
                                                )
                                        }
                                        .padding(CELL_PADDING)
                                        .tileStyle()
                                    }
                                    .buttonStyle(TileButtonStyle())
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .emptyPlaceholder(exercises) {
                        Text(NSLocalizedString("noExercises", comment: ""))
                    }
                }
                .padding(.bottom, SCROLLVIEW_BOTTOM_PADDING)
            }
            .searchable(text: $searchedText)
            .onAppear {
                isShowingNoExercisesTip = exercises.isEmpty
            }
            .navigationTitle(NSLocalizedString("exercises", comment: "sports activity"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingAddExercise.toggle() }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddExercise) {
                ExerciseEditScreen(initialMuscleGroup: selectedMuscleGroup ?? .chest)
            }
            .navigationDestination(item: $selectedExercise) { exercise in
                ExerciseDetailScreen(exercise: exercise)
            }
        }
    }

    // MARK: - Methods / Computed Properties

    private func getLetter(for group: [Exercise]) -> String {
        String(group.first?.name?.first ?? Character(" "))
    }
}

struct AllExercisesView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            ExerciseListScreen()
        }
        .previewEnvironmentObjects()
    }
}
